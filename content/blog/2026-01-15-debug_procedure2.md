+++
title = '段错误(SEGV)故障定位排查文档'
date = 2026-01-15T10:18:16+08:00
draft = false
+++

## 📋 问题概述

**故障现象**：`panda_strategy-1.0.0` 程序在运行过程中发生段错误(Segmentation Fault)，进程崩溃。

**崩溃时间**：2026-01-15 01:04:11 CST  
**崩溃进程**：PID 2312019  
**崩溃线程**：`adapter-poller[2312082]`  
**信号类型**：SIGSEGV (Signal 11)

---

## 🔍 排查步骤

### 1. 确认崩溃信息

#### 1.1 使用 coredumpctl 获取崩溃基本信息

```bash
coredumpctl info 2312019
```

**输出结果**：
```
           PID: 2312019 (panda_strategy-)
           UID: 1000 (jason)
           GID: 1000 (jason)
        Signal: 11 (SEGV)
     Timestamp: Thu 2026-01-15 01:04:11 CST (7h ago)
  Command Line: ./panda_strategy-1.0.0
    Executable: /home/jason/panda/panda-strategy/Strategy/out/build/wsl-profile/panda_strategy-1.0.0
       Storage: none
       Message: Process 2312019 (panda_strategy-) of user 1000 dumped core.
```

**关键信息**：
- ✅ 确认崩溃时间：`2026-01-15 01:04:11 CST`
- ⚠️ **Storage: none** - 核心转储文件未保存，但可以尝试其他方法分析

#### 1.2 尝试使用 coredumpctl 获取更多信息

即使显示 `Storage: none`，也应该尝试使用 `coredumpctl` 的各种命令：

##### 1.2.1 尝试 coredumpctl gdb（需要 core 文件）

```bash
# 方法1：使用 heredoc 传递 gdb 命令
coredumpctl gdb 2312019 <<'EOF'
bt
info registers
info threads
quit
EOF

# 方法2：使用管道传递命令
echo -e "bt\ninfo registers\nquit" | coredumpctl gdb 2312019
```

**实际执行结果**（本例中）：
```
Coredump entry has no core attached (neither internally in the journal nor externally on disk).
```

**说明**：
- ❌ **如果没有 core 文件，`coredumpctl gdb` 无法提供任何调试信息**
- `coredumpctl gdb` 会直接报错退出，无法进入 gdb 会话
- 无法获取堆栈（`bt`）、寄存器（`info registers`）等调试信息

##### 1.2.2 使用 coredumpctl list 查看所有崩溃记录

```bash
coredumpctl list 2312019
```

**输出结果**：
```
TIME                            PID   UID   GID SIG COREFILE  EXE
Thu 2026-01-15 01:04:11 CST  2312019  1000  1000  11 none      /home/jason/panda/panda-strategy/Strategy/out/build/wsl-profile/panda_strategy-1.0.0
```

**可获取信息**：
- ✅ 崩溃时间戳
- ✅ 进程 ID、用户 ID、组 ID
- ✅ 信号类型（SIG 11 = SEGV）
- ✅ 可执行文件路径
- ❌ 无法获取堆栈、寄存器等运行时信息

##### 1.2.3 使用 coredumpctl dump 尝试提取 core 文件

```bash
coredumpctl dump 2312019 > core.dump
```

**实际结果**：
- 如果 core 文件不存在，命令会失败
- 但如果 systemd 在 journal 中保存了 core 数据，可以提取出来

**结论**：
- **在没有 core dump 文件的情况下，`coredumpctl` 只能提供元数据信息**（时间、PID、信号等）
- **无法获取运行时调试信息**（堆栈、寄存器、内存内容等）
- 这些元数据信息在 `coredumpctl info` 中已经包含，`coredumpctl gdb` 不会提供额外信息
- **建议**：仍然应该尝试，因为某些系统配置可能将 core 文件保存在非标准位置，尝试成本低

##### 1.2.4 如果有 Core Dump 文件时的分析方法

> **重要**：以下方法仅在 core dump 文件存在时有效。如果 `Storage: none`，这些方法无法使用。

**对比表：有/无 Core Dump 文件的情况**

| 操作 | 有 Core Dump | 无 Core Dump (Storage: none) |
|------|-------------|---------------------------|
| `coredumpctl info` | ✅ 获取元数据 | ✅ 获取元数据（相同） |
| `coredumpctl gdb` | ✅ 进入 gdb，可查看堆栈 | ❌ 直接报错退出 |
| `bt` (backtrace) | ✅ 完整调用栈 | ❌ 无法使用 |
| `info registers` | ✅ 寄存器状态 | ❌ 无法使用 |
| `info threads` | ✅ 所有线程信息 | ❌ 无法使用 |
| `print variable` | ✅ 变量值 | ❌ 无法使用 |
| 内存分析 | ✅ 完整内存内容 | ❌ 无法使用 |

> **注意**：以下方法仅在 core dump 文件存在时有效。如果 `Storage: none`，这些方法无法使用。

**方法 A：使用 coredumpctl gdb（推荐）**

```bash
# 交互式调试
coredumpctl gdb <PID>

# 或使用命令脚本
coredumpctl gdb <PID> <<'EOF'
bt
info registers
info threads
info proc mappings
quit
EOF
```

**方法 B：手动加载 core 文件**

```bash
# 先提取 core 文件
coredumpctl dump <PID> > core.dump

# 然后使用 gdb 加载
gdb /path/to/executable core.dump
```

**方法 C：在 GDB 中加载**

```bash
gdb /path/to/executable
(gdb) core /path/to/core.dump
```

**查看调用栈：**

```bash
(gdb) bt
# 或
(gdb) backtrace
```

**输出示例**：
```
#0  0x0000000000537cd8 in std::_Hashtable<...>::_M_find_before_node(...) const
    at /usr/include/c++/11/bits/hashtable.h:1234
#1  0x000000000053b440 in pandas::SHMOrderGateway::publishCancelOrder(...)
    at SHMOrderGateway.cpp:228
#2  0x00000000004e9bd0 in pandas::Adapter::cancelOrder(...)
    at Adapter.cpp:536
#3  0x0000000000554ff0 in pandas::Strategy::cancelOrders(...)
    at Strategy.cpp:1557
#4  0x0000000000558df0 in pandas::Strategy::onSignal(...)
    at Strategy.cpp:148
#5  0x00000000004e3560 in pandas::Adapter::pollSignals()
    at Adapter.cpp:359
```

**其他有用的 GDB 命令**：

```bash
(gdb) info registers    # 查看寄存器状态
(gdb) info threads      # 查看所有线程
(gdb) thread apply all bt  # 查看所有线程的堆栈
(gdb) info proc mappings # 查看内存映射
(gdb) print variable     # 打印变量值
(gdb) x/10x $rsp         # 查看栈内存内容
```

**在本案例中**：
- ❌ core dump 文件不存在（`Storage: none`）
- ❌ 无法使用上述方法获取堆栈信息
- ✅ 需要使用后续的静态分析方法（addr2line、objdump 等）

#### 1.3 从系统日志获取详细崩溃信息

```bash
dmesg | grep "2312082\|2312019"
```

**输出结果**：
```
[3507552.855142] adapter-poller[2312082]: segfault at 7fb2ab6f76e0 ip 0000000000537cd8 sp 00007fb57c842410 error 4 in panda_strategy-1.0.0[4c3000+26d000]
```

**关键信息**：
- **崩溃线程**：`adapter-poller[2312082]`
- **崩溃地址**：`ip 0000000000537cd8` - 指令指针
- **无效内存**：`segfault at 7fb2ab6f76e0` - 访问的无效内存地址
- **错误码**：`error 4` - 用户态访问无效内存

---

### 2. 在没有 Core Dump 的情况下定位崩溃位置

> **提示**：如果 `coredumpctl gdb` 失败（如本例），可以使用以下静态分析方法继续排查。

#### 2.1 使用 addr2line 定位崩溃代码

```bash
addr2line -e panda_strategy-1.0.0 -f -C -i 0x537cd8
```

**输出结果**：
```
std::_Hashtable<...>::_M_find_before_node(...) const [clone .isra.0]
SHMOrderGateway.cpp:?
```

**分析**：
- 崩溃发生在 `std::_Hashtable` 的 `_M_find_before_node` 函数中
- 这是 `std::unordered_map` 的内部实现函数
- 文件位置：`SHMOrderGateway.cpp`

#### 2.2 使用 objdump 分析汇编代码

```bash
objdump -d panda_strategy-1.0.0 | grep -A 20 "537cd8:"
```

**关键汇编指令**：
```asm
537cd8:	48 8b 4e 38          	mov    0x38(%rsi),%rcx
```

**分析**：
- 指令：从 `%rsi + 0x38` 读取到 `%rcx`
- `%rsi` 应该是哈希表节点的指针
- 访问 `0x38(%rsi)` 时发生段错误，说明 `%rsi` 指向无效内存

#### 2.3 使用 nm 确认函数符号

```bash
nm panda_strategy-1.0.0 | grep -E "onSignal|pollSignals|publishCancelOrder"
```

**输出结果**：
```
00000000004e3560 T _ZN6pandas7Adapter11pollSignalsEv
0000000000558df0 T _ZN6pandas8Strategy8onSignalERN7pandadt6SignalE
000000000053b440 T _ZN6pandas15SHMOrderGateway18publishCancelOrderERKN7pandadt18CancelOrderRequestE
```

**确认调用链**：
- `Adapter::pollSignals()` → `Strategy::onSignal()` → `SHMOrderGateway::publishCancelOrder()`

---

### 3. 分析崩溃时间点的日志

#### 3.1 查看崩溃前的最后日志

```bash
grep -E "01:04:1[0-2]" main.log | tail -30
```

**最后一条成功日志**：
```
[01:04:11.153427][2312080][info][shm-order-gateway] [OrderACKLatency] acc=278, CANCEL, clOrdId=CGW2002780017684102511508174870, latency_ms=1.263
```

**关键发现**：
- 最后日志时间：`01:04:11.153427`
- 崩溃发生在该时间点之后
- 日志显示正在处理订单取消操作

#### 3.2 分析崩溃前的调用序列

从日志可以重建崩溃前的调用链：

```
[01:04:11.153400] Strategy::onSignal() - 处理 Signal
[01:04:11.153424] Signal triggered 4 immediate cancels
[01:04:11.153427] SHMOrderGateway::pollLoop() - 处理 OrderACK
[崩溃发生] ← 在 adapter-poller 线程调用 publishCancelOrder 时
```

---

## 🎯 根本原因分析

### 问题定位：多线程竞态条件导致哈希表损坏

#### 证据链

1. **崩溃位置确认**
   - 崩溃发生在 `std::unordered_map::find()` 操作中
   - 文件：`SHMOrderGateway.cpp`
   - 对象：`m_order_send_time_map`

2. **多线程访问冲突**

   **线程1：`SHMOrderGateway::pollLoop` (PID 2312080)**
   ```cpp
   // 在 pollLoop 线程中读取
   auto it_create = m_order_send_time_map.find(create_key);
   auto it_cancel = m_order_send_time_map.find(cancel_key);
   ```

   **线程2：`adapter-poller` (PID 2312082)**
   ```cpp
   // 通过 Strategy::onSignal() → cancelOrders() → publishCancelOrder()
   m_order_send_time_map[key] = info;  // 写入操作
   ```

3. **代码注释与实际不符**

   ```cpp
   // 注意：无锁设计，pollLoop线程负责读写，publishOrder/publishCancelOrder只写
   // 由于统计信息不是关键业务，偶发的竞态条件导致的统计丢失可以接受
   std::unordered_map<std::string, OrderSendTimeInfo> m_order_send_time_map;
   ```

   **问题**：
   - 注释声称"无锁设计"，但实际上 `publishCancelOrder` 在 `adapter-poller` 线程中调用
   - 两个不同线程同时访问同一个 `unordered_map`
   - `std::unordered_map` 不是线程安全的

#### 崩溃机制详解

**时序图**：

```
时间线：
T1: adapter-poller 线程执行 publishCancelOrder()
    → m_order_send_time_map[key] = info;
    → 触发哈希表 rehash（如果负载因子过高）
    
T2: pollLoop 线程同时执行 find()
    → auto it = m_order_send_time_map.find(key);
    → 遍历哈希表 bucket 链表
    
T3: 【竞态条件】
    - publishCancelOrder 正在 rehash（移动/重建 bucket）
    - find() 访问到已被移动或释放的节点
    - 访问无效内存地址 7fb2ab6f76e0
    
T4: ❌ SEGV at 0x537cd8
    - mov 0x38(%rsi),%rcx  ← %rsi 指向已失效的节点
```

**技术细节**：

1. **哈希表 rehash 过程**：
   - `unordered_map` 在插入元素时，如果负载因子超过阈值会触发 rehash
   - rehash 会重新分配 bucket 数组，移动所有元素
   - 这是一个非原子操作，需要时间完成

2. **并发访问问题**：
   - 写入线程（`adapter-poller`）触发 rehash
   - 读取线程（`pollLoop`）同时遍历旧的 bucket 结构
   - 读取线程访问到已被移动的节点指针
   - 导致访问无效内存

3. **为什么崩溃在 find() 而不是写入**：
   - `find()` 需要遍历 bucket 链表
   - 如果链表节点在遍历过程中被移动，后续访问会失败
   - `operator[]` 写入操作可能触发 rehash，但写入本身可能已经完成

---

## 📊 调用链完整分析

### 崩溃时的完整调用栈（重建）

```
adapter-poller 线程 (PID 2312082)
  │
  ├─ Adapter::pollSignals()
  │   └─ for (const auto& listener : m_signalListeners)
  │       └─ listener(signal)  // 调用 Strategy::onSignal
  │
  ├─ Strategy::onSignal(pandadt::Signal& signal)
  │   ├─ m_quoter->setSignalSpreadAdjustments(signal)
  │   └─ cancelOrders(cancelResult.m_cancelOrders, ...)
  │
  ├─ Strategy::cancelOrders(...)
  │   └─ m_adapter->cancelOrder(cancelOrder)
  │
  ├─ Adapter::cancelOrder(CancelOrderRequest&)
  │   └─ gatewayIt->second->publishCancelOrder(cancelRequest)
  │
  └─ SHMOrderGateway::publishCancelOrder(...)
      └─ m_order_send_time_map[key] = info;  ← 写入，可能触发 rehash
          │
          └─ 【同时】pollLoop 线程执行 find()
              └─ ❌ 访问到已移动的节点 → SEGV
```

### 并发执行时间线

```
时间轴：
01:04:11.153400  adapter-poller: Strategy::onSignal() 开始
01:04:11.153424  adapter-poller: cancelOrders() 开始
01:04:11.153427  pollLoop: 正在执行 find() 操作
                  adapter-poller: publishCancelOrder() 写入 map
                  → 触发 rehash
                  pollLoop: find() 访问到已移动的节点
                  → ❌ SEGV at 0x537cd8
```

---

## 🔧 修复方案

### 方案1：添加互斥锁保护（推荐）

**修改位置**：`SHMOrderGateway.h` 和 `SHMOrderGateway.cpp`

```cpp
// 在 SHMOrderGateway.h 中添加
#include <mutex>

private:
    mutable std::mutex m_mapMutex;  // 保护 m_order_send_time_map
    std::unordered_map<std::string, OrderSendTimeInfo> m_order_send_time_map;
```

```cpp
// 在 SHMOrderGateway.cpp 中修改所有访问点

// publishCancelOrder() 中
{
    std::lock_guard<std::mutex> lock(m_mapMutex);
    m_order_send_time_map[key] = info;
}

// pollLoop() 中的 find() 操作
{
    std::lock_guard<std::mutex> lock(m_mapMutex);
    auto it_create = m_order_send_time_map.find(create_key);
    auto it_cancel = m_order_send_time_map.find(cancel_key);
    // ... 使用迭代器
}
```

**优点**：
- 彻底解决竞态条件
- 保证数据一致性
- 实现简单

**缺点**：
- 增加锁竞争，可能影响性能
- 需要仔细设计锁粒度

### 方案2：使用线程安全的哈希表

使用 `concurrent_unordered_map` 或类似的数据结构。

**优点**：
- 无锁设计，性能更好
- 线程安全

**缺点**：
- 需要引入额外依赖（如 Intel TBB）
- 可能增加编译复杂度

### 方案3：分离读写操作到单线程

将 `publishCancelOrder` 的写入操作通过队列发送到 `pollLoop` 线程执行。

**优点**：
- 保持无锁设计
- 单线程访问，无竞态条件

**缺点**：
- 需要额外的队列和同步机制
- 增加延迟

---

## 📝 经验总结

### 在没有 Core Dump 的情况下如何排查

1. **使用 coredumpctl 获取基本信息**
   - 确认崩溃时间和进程信息
   - 即使没有 core 文件，也能获取关键元数据

2. **利用系统日志 (dmesg/journalctl)**
   - 获取崩溃时的寄存器状态
   - 确认崩溃线程和内存地址

3. **使用 addr2line 定位代码位置**
   - 将指令地址转换为函数名和文件
   - 即使没有行号，也能定位到函数

4. **结合应用日志分析**
   - 查看崩溃时间点的日志
   - 重建调用链和时序

5. **静态代码分析**
   - 检查多线程访问模式
   - 识别潜在的竞态条件

### 关键教训

1. **代码注释必须准确**
   - 注释说"无锁设计"，但实际存在多线程访问
   - 误导了代码审查和维护

2. **std::unordered_map 不是线程安全的**
   - 即使只是"统计信息"，并发访问也会导致崩溃
   - 需要显式的同步机制

3. **多线程代码需要仔细审查**
   - 所有共享数据结构的访问路径
   - 确认是否有并发访问的可能

4. **日志是排查的关键**
   - 详细的日志帮助重建调用链
   - 时间戳帮助分析并发时序

---

## 📚 参考资料

- [std::unordered_map 线程安全性](https://en.cppreference.com/w/cpp/container/unordered_map)
- [Linux 段错误分析](https://man7.org/linux/man-pages/man5/core.5.html)
- [coredumpctl 使用指南](https://www.freedesktop.org/software/systemd/man/coredumpctl.html)
- [addr2line 工具说明](https://sourceware.org/binutils/docs/binutils/addr2line.html)

---

**文档版本**：v1.0  
**创建时间**：2026-01-15  
**作者**：故障排查团队
