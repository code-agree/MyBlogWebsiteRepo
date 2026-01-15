+++
title = 'Linux Coredump 调试完整指南'
date = 2026-01-15T10:05:34+08:00
draft = false
+++

## 目录
1. [概述](#概述)
2. [Coredump 生成机制](#coredump-生成机制)
3. [环境检查与配置](#环境检查与配置)
4. [Coredump 文件定位](#coredump-文件定位)
5. [使用 GDB 分析 Coredump](#使用-gdb-分析-coredump)
6. [实战案例分析](#实战案例分析)
7. [最佳实践与故障排查](#最佳实践与故障排查)

---

## 概述

当 Linux 进程因段错误（SIGSEGV）、总线错误（SIGBUS）等信号异常终止时，系统可以生成 coredump 文件，记录进程崩溃时的完整内存状态。通过分析 coredump，我们可以准确定位崩溃原因，包括：

- 崩溃时的函数调用栈（Stack Trace）
- 局部变量和全局变量的值
- 内存布局和寄存器状态
- 崩溃发生的精确代码位置

本文档提供一套完整的 coredump 调试流程，从环境配置到深度分析，帮助开发者快速定位和解决程序崩溃问题。

---

## Coredump 生成机制

### 2.1 系统级配置：core_pattern

Linux 内核通过 `/proc/sys/kernel/core_pattern` 控制 coredump 的生成方式：

```bash
# 查看当前配置
cat /proc/sys/kernel/core_pattern
```

**常见配置模式：**

1. **传统模式**：直接生成 core 文件
   ```
   core
   ```
   在当前工作目录生成名为 `core` 的文件。

2. **Systemd-coredump 模式**（现代 Linux 发行版默认）：
   ```
   |/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h %e
   ```
   由 systemd-coredump 服务统一管理，提供压缩、存储和查询功能。

3. **自定义路径模式**：
   ```
   /var/crash/core.%e.%p.%t
   ```
   生成到指定目录，文件名包含可执行文件名、PID 和时间戳。

### 2.2 进程级限制：ulimit

即使系统配置允许生成 coredump，进程仍需通过 `ulimit -c` 检查是否被允许：

```bash
# 查看当前 shell 的 coredump 限制
ulimit -c

# 输出示例：
# 0        # 表示禁止生成 coredump
# unlimited # 表示允许生成任意大小的 coredump
# 1024     # 表示允许生成最大 1024KB 的 coredump
```

**关键点：**
- `ulimit -c` 是**进程级限制**，由父进程继承给子进程
- 如果父进程的 `ulimit -c` 为 0，即使子进程设置 `ulimit -c unlimited` 也无法生成 coredump
- 必须在**程序启动前**设置，崩溃后设置无效

---

## 环境检查与配置

### 3.1 检查 Coredump 生成能力

**步骤 1：检查 ulimit 设置**

```bash
ulimit -c
```

**结果判断：**
- `0`：当前 shell 禁止生成 coredump，需要启用
- `unlimited` 或数字：已启用，可以继续

**步骤 2：检查系统 core_pattern**

```bash
cat /proc/sys/kernel/core_pattern
```

**结果判断：**
- 如果包含 `systemd-coredump`：使用 systemd 管理，需要配置存储
- 如果是路径模式：检查该路径是否存在且可写
- 如果是 `core`：会在程序运行目录生成

**步骤 3：验证 systemd-coredump 服务状态**

```bash
systemctl status systemd-coredump
# 或
systemctl is-enabled systemd-coredump
```

### 3.2 启用 Coredump 生成

#### 方法 A：在启动脚本中设置（推荐）

```bash
#!/bin/bash
# 启用 coredump
ulimit -c unlimited

# 启动程序
./RT_Launcher /path/to/lib.so /path/to/config.json
```

**优点：**
- 简单直接
- 不影响系统其他进程
- 不需要 root 权限

#### 方法 B：在代码中设置（永久生效）

```cpp
#include <sys/resource.h>
#include <unistd.h>

void enable_coredump() {
    struct rlimit rlim;
    rlim.rlim_cur = RLIM_INFINITY;  // 软限制：当前进程
    rlim.rlim_max = RLIM_INFINITY;  // 硬限制：最大可设置值
    if (setrlimit(RLIMIT_CORE, &rlim) != 0) {
        perror("setrlimit failed");
    }
}

int main() {
    enable_coredump();
    // ... 程序逻辑
}
```

**优点：**
- 不依赖启动环境
- 程序自身控制，更可靠

#### 方法 C：系统级配置（需要 root 权限）

编辑 `/etc/security/limits.conf`：

```
* soft core unlimited
* hard core unlimited
```

或针对特定用户：

```
jason soft core unlimited
jason hard core unlimited
```

### 3.3 配置 Systemd-Coredump 存储

如果系统使用 systemd-coredump，需要配置保存 coredump 文件：

**步骤 1：编辑配置文件**

```bash
sudo vim /etc/systemd/coredump.conf
```

**步骤 2：修改配置**

```ini
[Coredump]
# 存储模式：external=保存到磁盘, journal=仅保存到日志, none=不保存
Storage=external

# 是否压缩
Compress=yes

# 单个 coredump 最大大小
ExternalSizeMax=2G

# 所有 coredump 总大小限制
MaxUse=10G

# 保留至少多少磁盘空间
KeepFree=5G
```

**步骤 3：重启服务**

```bash
sudo systemctl daemon-reload
sudo systemctl restart systemd-coredump
```

**验证配置：**

```bash
# 查看配置是否生效
systemd-analyze cat-config systemd/coredump.conf
```

---

## Coredump 文件定位

### 4.1 使用 coredumpctl 查询（Systemd 系统）

**列出所有 coredump 记录：**

```bash
coredumpctl list
```

**输出格式：**
```
TIME                            PID   UID   GID SIG COREFILE  EXE
Wed 2026-01-14 03:53:08 CST  2088685  1000  1000  11 none      /home/jason/panda-md-infra/release/RT_Launcher
```

**字段说明：**
- `TIME`：崩溃时间
- `PID`：进程 ID
- `UID/GID`：用户/组 ID
- `SIG`：导致崩溃的信号（11=SIGSEGV, 6=SIGABRT, 7=SIGBUS 等）
- `COREFILE`：coredump 文件状态（`none`=未保存，`present`=已保存）
- `EXE`：可执行文件路径

**按条件过滤：**

```bash
# 按程序名过滤
coredumpctl list RT_Launcher

# 按 PID 过滤
coredumpctl list 2088685

# 按时间范围过滤
coredumpctl list --since "2026-01-14 00:00:00" --until "2026-01-14 23:59:59"
```

### 4.2 查看详细信息

**查看特定 coredump 的详细信息：**

```bash
coredumpctl info <PID>
# 或
coredumpctl info <程序名>
```

**输出示例：**
```
           PID: 2088685 (RT_Launcher)
           UID: 1000 (jason)
           GID: 1000 (jason)
        Signal: 11 (SEGV)
     Timestamp: Wed 2026-01-14 03:53:08 CST
  Command Line: /home/jason/panda-md-infra/release/RT_Launcher /path/to/lib.so /path/to/config.json
    Executable: /home/jason/panda-md-infra/release/RT_Launcher
       Storage: external
       Message: Process 2088685 (RT_Launcher) of user 1000 dumped core.
```

**关键信息解读：**
- `Signal: 11 (SEGV)`：段错误，通常由空指针解引用、缓冲区溢出等引起
- `Command Line`：崩溃时的完整命令行参数，有助于复现问题
- `Storage: external`：coredump 已保存到磁盘
- `Storage: none`：coredump 未保存（可能已被清理或配置未启用）

### 4.3 导出 Coredump 文件

**导出到指定文件：**

```bash
coredumpctl dump <PID> -o /path/to/core.dump
```

**直接使用 GDB 打开：**

```bash
coredumpctl gdb <PID>
```

### 4.4 查找传统 Core 文件

如果系统未使用 systemd-coredump，coredump 可能生成在以下位置：

```bash
# 在程序运行目录查找
find . -name "core*" -type f

# 在系统常见目录查找
find /var/crash /tmp /home -name "core*" -type f -newer /path/to/program 2>/dev/null

# 全局查找（可能较慢）
find / -name "core" -o -name "core.*" -o -name "*.core" 2>/dev/null
```

**根据时间戳定位：**

```bash
# 查找最近生成的 core 文件
find / -name "core*" -type f -mtime -1 2>/dev/null

# 查找特定时间后生成的文件
find / -name "core*" -type f -newermt "2026-01-14 03:50:00" 2>/dev/null
```

---

## 使用 GDB 分析 Coredump

### 5.1 加载 Coredump

**方法 A：使用 coredumpctl（推荐）**

```bash
coredumpctl gdb <PID>
```

**方法 B：手动加载**

```bash
gdb /path/to/executable /path/to/core.dump
```

**方法 C：在 GDB 中加载**

```bash
gdb /path/to/executable
(gdb) core /path/to/core.dump
```

### 5.2 查看调用栈

**基本堆栈信息：**

```bash
(gdb) bt
# 或
(gdb) backtrace
```

**输出示例：**
```
#0  0x00007f8b4c5a1234 in std::string::operator[] (this=0x0, __pos=0) at /usr/include/c++/11/bits/basic_string.h:1234
#1  0x000055f8b1a2b567 in RT_CryptoTDBase::on_rtn_trade (this=0x7f8b4c123456, trade_update=...) at RT_CryptoTDBase.cpp:367
#2  0x00007f8b4c5a7890 in callback_wrapper (data=0x7f8b4c123456) at wrapper.cpp:45
#3  0x00007f8b4c5a9012 in thread_func (arg=0x0) at thread.cpp:78
```

**详细堆栈信息（包含局部变量）：**

```bash
(gdb) bt full
```

**查看所有线程的堆栈：**

```bash
(gdb) thread apply all bt
```

**切换到特定线程：**

```bash
(gdb) info threads        # 列出所有线程
(gdb) thread <thread_id>   # 切换到指定线程
(gdb) bt                   # 查看该线程堆栈
```

### 5.3 分析崩溃位置

**查看当前帧信息：**

```bash
(gdb) frame 0              # 切换到崩溃帧（最顶层）
(gdb) info frame           # 查看帧详细信息
(gdb) info locals          # 查看局部变量
(gdb) info args            # 查看函数参数
(gdb) list                 # 查看源代码上下文
```

**查看寄存器状态：**

```bash
(gdb) info registers       # 查看所有寄存器
(gdb) print $pc            # 查看程序计数器
(gdb) print $sp            # 查看栈指针
(gdb) print $rbp           # 查看基址指针（x86_64）
```

**查看内存内容：**

```bash
(gdb) x/20x $sp            # 以16进制查看栈内容（20个单元）
(gdb) x/s <address>        # 以字符串查看内存
(gdb) x/10i $pc            # 以指令查看内存（反汇编）
(gdb) disassemble          # 反汇编当前函数
```

### 5.4 分析变量和对象

**打印变量值：**

```bash
(gdb) print variable_name
(gdb) print *pointer
(gdb) print object.member
(gdb) print array[0]@10    # 打印数组前10个元素
```

**查看对象内容（C++）：**

```bash
(gdb) print *this          # 如果是成员函数，查看 this 指针
(gdb) print this->member
(gdb) print object->method()  # 注意：只能调用 const 方法
```

**查看内存映射：**

```bash
(gdb) info proc mappings    # 查看进程内存映射
(gdb) info sharedlibrary    # 查看加载的共享库
```

### 5.5 高级分析技巧

**条件断点和观察点（用于分析崩溃前的状态）：**

```bash
# 虽然 coredump 是静态快照，但可以分析内存布局
(gdb) print &variable       # 查看变量地址
(gdb) x/100x &variable      # 查看变量周围内存
```

**分析指针有效性：**

```bash
(gdb) print pointer
(gdb) print (void*)pointer  # 查看指针值
(gdb) info proc mappings    # 检查指针是否在有效地址范围内
```

**查看字符串内容：**

```bash
(gdb) print (char*)string_ptr
(gdb) x/s string_ptr
(gdb) print std::string(string_ptr)  # C++ string
```

---

## 实战案例分析

### 6.1 案例：RT_Launcher 段错误分析

**场景：** RT_Launcher 进程在 2026-01-14 03:53:08 崩溃，信号为 SIGSEGV (11)

**步骤 1：检查环境配置**

```bash
# 检查 ulimit
$ ulimit -c
0  # 未启用，需要配置

# 检查 core_pattern
$ cat /proc/sys/kernel/core_pattern
|/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h %e
# 使用 systemd-coredump
```

**步骤 2：查询 coredump 记录**

```bash
$ coredumpctl list | grep RT_Launcher
Wed 2026-01-14 03:53:08 CST  2088685  1000  1000  11 none      /home/jason/panda-md-infra/release/RT_Launcher
```

**步骤 3：查看详细信息**

```bash
$ coredumpctl info 2088685
           PID: 2088685 (RT_Launcher)
           UID: 1000 (jason)
           GID: 1000 (jason)
        Signal: 11 (SEGV)
     Timestamp: Wed 2026-01-14 03:53:08 CST
  Command Line: /home/jason/panda-md-infra/release/RT_Launcher /home/jason/panda-md-infra/release/libokex_td.so /home/jason/panda-md-infra/config/prod_td/account/okex_278.json
    Executable: /home/jason/panda-md-infra/release/RT_Launcher
       Storage: none
       Message: Process 2088685 (RT_Launcher) of user 1000 dumped core.
```

**问题诊断：**
- `Storage: none` 表示 coredump 文件未保存，无法进行深度分析
- 需要配置 systemd-coredump 保存文件，或确保程序启动时设置了 `ulimit -c unlimited`

**步骤 4：如果 coredump 已保存，使用 GDB 分析**

```bash
$ coredumpctl gdb 2088685
```

在 GDB 中：

```bash
(gdb) bt full
#0  0x00007f8b4c5a1234 in std::string::operator[] (this=0x0, __pos=0) at /usr/include/c++/11/bits/basic_string.h:1234
    this = 0x0  # 空指针！
    __pos = 0
#1  0x000055f8b1a2b567 in RT_CryptoTDBase::on_rtn_trade (this=0x7f8b4c123456, trade_update=...) at RT_CryptoTDBase.cpp:367
    this = 0x7f8b4c123456
    trade_update = {...}

(gdb) frame 1
(gdb) list
362|    int RT_CryptoTDBase::on_rtn_trade(TradeUpdate& trade_update) {
363|        m_trade_update_pub->push(trade_update, true);
364|        return 1;
365|    }
366|
367|    // 查看第367行附近的代码
(gdb) print trade_update
$1 = {...}
(gdb) print trade_update.m_clientOrderId
$2 = {<std::string> = {_M_dataplus = {<std::allocator<char>> = {<No data fields>}, _M_p = 0x0}, <No data fields>}
```

**分析结果：**
- 崩溃发生在 `std::string::operator[]`，`this` 指针为 `0x0`（空指针）
- 调用链：`on_rtn_trade` → `std::string::operator[]`
- 可能原因：`trade_update` 中的某个字符串成员未正确初始化

### 6.2 常见崩溃模式分析

**模式 1：空指针解引用**

```bash
(gdb) bt
#0  0x00007f8b4c5a1234 in function (ptr=0x0) at file.cpp:123
(gdb) print ptr
$1 = 0x0
```

**模式 2：缓冲区溢出**

```bash
(gdb) bt
#0  0x00007f8b4c5a1234 in memcpy (dest=0x7fff12345678, src=0x7fff12345000, len=1024) at memcpy.c:45
(gdb) x/20x $sp
# 查看栈内容，可能发现被覆盖的数据
```

**模式 3：使用已释放内存**

```bash
(gdb) bt
#0  0x00007f8b4c5a1234 in free (ptr=0x7f8b4c123456) at malloc.c:1234
(gdb) info proc mappings
# 检查指针是否在已释放区域
```

---

## 最佳实践与故障排查

### 7.1 预防性配置检查清单

在部署生产环境前，确保：

- [ ] `ulimit -c unlimited` 已在启动脚本中设置
- [ ] 或代码中已调用 `setrlimit(RLIMIT_CORE, ...)`
- [ ] systemd-coredump 已配置 `Storage=external`
- [ ] 磁盘空间充足（至少保留 10GB 用于 coredump）
- [ ] 程序编译时包含调试符号（`-g` 选项）
- [ ] 可执行文件未 strip（保留符号表）

### 7.2 编译时注意事项

**保留调试信息：**

```bash
# CMake
set(CMAKE_BUILD_TYPE RelWithDebInfo)  # 或 Debug
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g")

# 或直接编译
g++ -g -O2 -o program program.cpp
```

**检查是否包含调试信息：**

```bash
file program
# 输出应包含 "with debug_info"
readelf -S program | grep debug
```

### 7.3 故障排查

**问题 1：coredumpctl list 显示 Storage: none**

**可能原因：**
- systemd-coredump 配置未启用存储
- coredump 文件已被自动清理（超过 MaxUse 或 KeepFree 限制）
- 磁盘空间不足

**解决方法：**
```bash
# 检查配置
cat /etc/systemd/coredump.conf | grep Storage

# 检查磁盘空间
df -h /var/lib/systemd/coredump

# 检查服务日志
journalctl -u systemd-coredump -n 50
```

**问题 2：ulimit -c 显示 unlimited，但仍无 coredump**

**可能原因：**
- 父进程的 ulimit -c 为 0
- 程序以 systemd 服务运行，需要在 service 文件中设置
- core_pattern 配置错误

**解决方法：**
```bash
# 检查父进程
ps aux | grep <program_name>
cat /proc/<parent_pid>/limits | grep core

# 对于 systemd 服务，编辑 .service 文件
[Service]
LimitCORE=infinity
```

**问题 3：GDB 显示 "No symbol table"**

**解决方法：**
```bash
# 确保使用带调试信息的可执行文件
file program
# 应显示 "with debug_info"

# 如果使用 strip 后的文件，需要原始文件
gdb /path/to/original/program /path/to/core.dump
```

### 7.4 自动化分析脚本

创建脚本 `analyze_coredump.sh`：

```bash
#!/bin/bash
# analyze_coredump.sh - 自动化 coredump 分析脚本

PROGRAM_NAME=$1
CORE_PID=$2

if [ -z "$PROGRAM_NAME" ] || [ -z "$CORE_PID" ]; then
    echo "用法: $0 <程序名> <PID>"
    echo "示例: $0 RT_Launcher 2088685"
    exit 1
fi

echo "=== 1. 查找 Coredump 记录 ==="
coredumpctl list | grep "$PROGRAM_NAME" | grep "$CORE_PID"

echo -e "\n=== 2. 查看详细信息 ==="
coredumpctl info "$CORE_PID"

echo -e "\n=== 3. 导出 Coredump ==="
CORE_FILE="/tmp/core_${CORE_PID}.dump"
coredumpctl dump "$CORE_PID" -o "$CORE_FILE"

if [ -f "$CORE_FILE" ]; then
    echo "Coredump 已导出到: $CORE_FILE"
    
    echo -e "\n=== 4. 使用 GDB 分析 ==="
    EXECUTABLE=$(coredumpctl info "$CORE_PID" | grep "Executable:" | awk '{print $2}')
    
    if [ -f "$EXECUTABLE" ]; then
        echo "运行: gdb $EXECUTABLE $CORE_FILE"
        echo "然后在 GDB 中执行: bt full"
        
        # 可选：自动生成堆栈报告
        gdb -batch -ex "bt full" -ex "quit" "$EXECUTABLE" "$CORE_FILE" > "/tmp/stacktrace_${CORE_PID}.txt"
        echo "堆栈信息已保存到: /tmp/stacktrace_${CORE_PID}.txt"
    else
        echo "警告: 找不到可执行文件 $EXECUTABLE"
    fi
else
    echo "错误: 无法导出 coredump（可能 Storage=none）"
fi
```

**使用方法：**

```bash
chmod +x analyze_coredump.sh
./analyze_coredump.sh RT_Launcher 2088685
```

### 7.5 性能考虑

**Coredump 文件大小：**
- 通常等于进程的虚拟内存大小
- 对于大型程序（如 1GB+ 内存），coredump 可能很大
- 建议设置 `ExternalSizeMax` 限制，避免填满磁盘

**压缩存储：**
```ini
[Coredump]
Compress=yes  # 启用压缩，可节省 50-90% 空间
```

**定期清理：**
```bash
# 清理 7 天前的 coredump
find /var/lib/systemd/coredump -type f -mtime +7 -delete

# 或使用 systemd-coredump 的自动清理机制
# 配置 MaxUse 和 KeepFree
```

---

## 总结

完整的 coredump 调试流程包括：

1. **环境检查**：`ulimit -c` 和 `core_pattern` 配置
2. **启用生成**：在启动脚本或代码中设置
3. **定位文件**：使用 `coredumpctl list` 和 `coredumpctl info`
4. **加载分析**：使用 `coredumpctl gdb` 或 `gdb program core`
5. **深度调试**：查看堆栈、变量、内存和寄存器状态

遵循本指南，可以系统化地定位和解决程序崩溃问题，提高调试效率。

---

## 参考资源

- `man coredumpctl` - coredumpctl 命令手册
- `man coredump.conf` - systemd-coredump 配置手册
- `man gdb` - GDB 调试器手册
- `man setrlimit` - 资源限制设置
- [Systemd Coredump 官方文档](https://www.freedesktop.org/software/systemd/man/systemd-coredump.html)
