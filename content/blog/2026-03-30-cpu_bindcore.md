---
title: "低延迟系统的 CPU 核心规划：从 isolcpus 到 Busy Poll 的内核级实战"
date: 2026-03-30
draft: false
description: "以 192 核 Graviton3 + 加密货币行情系统为背景，深入讲解 CPU 隔离、Housekeeping 规划、中断与用户进程的核心分配、中断抢占机制，以及 Busy Poll 的内核实现原理。"
tags: ["Linux", "Performance", "Network"]
---

> 上一篇文章[《从网线到策略引擎：Linux 网络收包全路径深度解析》](/blog/2026-03-17-net_proc/)解决的是"数据包怎么走"的问题——从物理层到用户态的七个阶段。本文解决的是"CPU 核心怎么分"的问题——在一个多核系统上，哪些核跑内核家务活、哪些核处理网卡中断、哪些核跑行情线程，以及为什么这样分配。

---

## 一、问题的起点：能不能把所有核都 isolate 掉？

在低延迟系统中，`isolcpus` 是最常见的核心隔离手段。它的作用是将指定的 CPU 从内核调度器的默认调度域中移除，使得普通进程不会被自动调度到这些核上，从而为延迟敏感的用户线程提供"干净"的执行环境。

一个自然的想法是：既然隔离能减少干扰，那把所有核都隔离了，再手动把用户线程绑上去，岂不是最干净？

**这样做不合理，甚至可能导致系统无法正常运行。**

### 1.1 内核的"家务活"必须有人干

Linux 系统的正常运行依赖大量内核线程和基础设施：

```
ksoftirqd/N     — 每个 CPU 上的软中断处理线程
kworker/N:M     — 工作队列线程（延迟工作、异步 I/O 等）
rcu_preempt     — RCU 回调处理
migration/N     — 进程迁移
watchdog/N      — CPU 死锁检测
systemd (PID 1) — 用户空间初始化
sshd / journald — 基础系统服务
```

当你用 `isolcpus=0-191` 把所有 192 个核都隔离后，这些内核线程和系统服务没有任何核可以正常调度。较新的内核在启动早期会检查是否至少存在一个 housekeeping CPU，如果全部隔离，系统可能直接启动失败或行为异常。

### 1.2 CPU 0 的特殊地位

即使不全部隔离，把 CPU 0 隔离也需要格外小心。在 Linux 内核中，CPU 0 承担着特殊职责：

**Boot CPU**：系统启动阶段的大量初始化逻辑绑定在 CPU 0 上执行，部分内核子系统硬编码依赖它。`start_kernel()` → `rest_init()` → `kernel_init()` 这条初始化链路始终在 CPU 0 上运行。

**时钟基础设施**：很多平台上 tick 广播（tick broadcast）和 clockevent 的校准默认在 CPU 0 上处理。ARM64 平台上，arch timer 的初始化与 CPU 0 绑定。

**不可迁移的内核线程**：部分 per-cpu workqueue（`WQ_UNBOUND` 除外）、`ksoftirqd/0`、`migration/0` 等内核线程天然固定在 CPU 0 上，无法迁移到其他核。

**硬件中断的默认亲和性**：很多中断在 `/proc/irq/*/smp_affinity` 中默认指向 CPU 0。如果 CPU 0 被用户线程占满，中断响应延迟会剧增。

### 1.3 正确做法：保留 Housekeeping 核

正确的实践是保留至少一个核（通常是 CPU 0）作为 housekeeping CPU，让内核线程、中断和系统服务运行在上面：

```bash
# 假设 4 核系统 (CPU 0-3)
# 保留 CPU 0 做 housekeeping，隔离 1-3 给用户线程
isolcpus=1-3

# 更精细的控制（内核 4.15+）
isolcpus=managed_irq,domain,1-3
```

然后将用户线程绑到隔离核上：

```bash
taskset -c 1 ./your_thread_1
taskset -c 2 ./your_thread_2
taskset -c 3 ./your_thread_3
```

---

## 二、Housekeeping CPU 的负载规划

保留了 housekeeping 核之后，一个常见的追问是：能不能把一些普通的用户进程也绑到 housekeeping 核上？

可以，但要看量级。Housekeeping 核同时承载四类负载：

1. **内核线程**：`ksoftirqd`、`kworker`、`rcu`、`migration` 等
2. **系统服务**：`systemd`、`sshd`、`journald`、`rsyslogd` 等
3. **硬件中断处理**：默认的 IRQ affinity 通常指向 housekeeping 核
4. **你额外绑上去的用户进程**

如果绑上去的用户进程是轻量级的（监控脚本、日志收集器），完全没问题。但如果是 CPU 密集型任务，就会和内核线程互相抢占：你的用户进程被 `ksoftirqd`、中断打断导致延迟抖动；内核线程得不到及时调度，可能引发网络收包延迟、RCU 回调积压甚至 watchdog 告警。

**评估 housekeeping 核余量的方法**：

```bash
# 查看 CPU 0 的实时负载
mpstat -P 0 1

# 如果 idle 还有 70% 以上，说明还有余量
# 如果中断和内核线程已经吃掉 30%+，就别再往上加了
```

**核心数量与策略的关系**：

- **核少（4 核）**：CPU 0 一个核做 housekeeping 勉强够用，但别堆重负载。
- **核多（8 核以上）**：建议留 2 个核做 housekeeping（比如 CPU 0 和 CPU 1），一个不够时另一个能分担。
- **极多（192 核）**：留 2-4 个核做 housekeeping 绰绰有余，剩余的核资源丰富到可以按业务功能精细划分。

---

## 三、网卡中断与用户进程：两套独立的选核机制

理解了 housekeeping 核的规划后，下一个核心问题是：网卡中断和行情接收线程，各自在哪个核上运行？它们之间是什么关系？

### 3.1 网卡中断的选核：硬件决定

网卡通过 MSI-X 机制向特定 CPU 投递中断。选哪个核由两层决定：

```
第一层：硬件 RSS（Receive Side Scaling）
  网卡根据数据包的五元组 (src_ip, dst_ip, src_port, dst_port, protocol)
  做哈希 → 映射到某个 RX 队列 → 每个队列绑定一个 MSI-X 中断号

第二层：中断亲和性
  /proc/irq/<IRQ>/smp_affinity 决定这个中断号投递到哪个 CPU
```

数据包在哪个核上被处理，由网卡硬件哈希和中断亲和性配置共同决定，和用户进程在哪个核上运行没有任何关系。

### 3.2 用户进程的选核：调度器决定

用户进程跑在哪个核，由 CFS 调度器根据负载均衡决定，或者你用 `taskset` / `sched_setaffinity` 手动绑定。

**两者默认没有任何协调机制。** 网卡中断可能在 CPU 5 上处理，而你的 WebSocket 行情线程可能在 CPU 80 上跑。这是一个很常见但往往被忽视的问题。

### 3.3 网卡中断跟用户进程的关系

从数据依赖角度看，它们是**生产者-消费者关系**：

```
网卡中断 (生产者)                    用户进程 (消费者)
────────────────                    ────────────────
硬中断 → 触发 NAPI
NAPI poll → 从网卡 DMA ring
读取数据包 → 分配 skb
→ 走协议栈 (IP/TCP)
→ 把数据放入 socket recv queue
→ 唤醒阻塞在 recv/epoll 上的进程 ──→ 被唤醒，调用 recv() 取数据
```

没有中断处理完成，用户进程拿不到数据。中断是数据进入用户态的必经之路（除非使用 busy poll 或 kernel bypass，后文详述）。

### 3.4 为什么同核不会 cache miss

一个关键的优化决策是：中断处理和行情线程是放在同一个核上，还是分开放？

先看**不同核**的情况：

```
CPU 5 (处理中断)                          CPU 80 (用户线程)
┌─────────────────┐                      ┌─────────────────┐
│ 硬中断触发       │                      │                 │
│ NAPI poll 收包   │                      │                 │
│ skb 分配并填充   │                      │                 │
│ 协议栈处理       │                      │                 │
│ 数据写入 socket  │                      │                 │
│ buffer          │                      │                 │
│                 │   ── 跨核访问 ──→     │ recv() 读取数据  │
│ 此时 skb 数据    │   cache-to-cache     │ 数据不在本地cache│
│ 在 CPU 5 的      │   transfer 延迟      │ 触发 cache miss  │
│ L1/L2 cache 中  │                      │                 │
└─────────────────┘                      └─────────────────┘
```

跨核访问的代价，在 Graviton3（192 核，2 NUMA node）上：

- **同 NUMA node 内跨核**：L2 miss → 走 L3 或 mesh interconnect，约 30-50ns
- **跨 NUMA node**：走 NUMA 互联，约 80-150ns

再看**同核**的情况：

```
CPU 5 (中断 + 用户线程都在这里)
┌─────────────────────────────────┐
│ 硬中断触发                       │
│ NAPI poll → skb 数据写入 L1/L2  │
│ 协议栈处理 → socket buffer      │
│                                 │
│ ... 中断返回 ...                 │
│                                 │
│ 用户线程 recv()                  │
│ 读取 socket buffer              │
│ 数据还在 L1/L2 cache 里         │  ← 命中，0 额外延迟
│ 直接 cache hit                  │
└─────────────────────────────────┘
```

本质原因：**中断处理和用户线程操作的是同一块内存**——`struct sk_buff` 和 socket 的 receive queue。中断处理时把数据写进了这个核的 cache，用户线程紧接着读，数据还"热"在 cache 里。这不是巧合，而是因为它们是同一个数据结构的生产者和消费者。

### 3.5 同核 vs 分离的取舍

两种方案各有适用场景：

**同核方案**（中断和行情线程绑同一个核）：
- 优势：cache 局部性最优，数据零延迟传递
- 代价：中断处理会抢占用户线程的 CPU 时间
- 适用：中断频率不高（几千次/秒级别）、行情数据量不大的场景

**分离方案**（中断和行情线程绑不同核，但在同 NUMA / 同 L3 域内）：
- 优势：用户线程不会被中断打断，执行更确定
- 代价：数据需要跨核传递，有 cache miss 代价（同 L3 域约 30ns）
- 适用：中断频率高、行情 burst 量大的场景

**绝对不要做的事**：中断核在 NUMA node 0，行情线程在 NUMA node 1。跨 NUMA 的 cache miss 代价远大于同 node 内的跨核传递。

---

## 四、中断优先级与抢占机制

上一节提到"中断处理会抢占用户线程"，这里深入解释这个机制。

### 4.1 Linux 的中断优先级模型

```
优先级从高到低：

1. 硬中断 (hardirq)     ← 网卡中断在这里
   无条件抢占一切，包括内核代码
   不可被调度器控制
   即使你的进程是 SCHED_FIFO 优先级 99 也会被打断

2. 软中断 (softirq)     ← NAPI 收包在这里 (NET_RX_SOFTIRQ)
   在硬中断返回时执行
   或由 ksoftirqd 内核线程执行

3. 内核态进程            ← 系统调用期间
   可被中断抢占

4. 用户态进程            ← 你的行情线程在这里
   优先级最低
```

### 4.2 一次中断打断用户进程的完整过程

```
你的行情线程正在 CPU 2 上执行策略计算
          │
          ▼
网卡收到行情数据包，DMA 写入 Ring Buffer
          │
          ▼
网卡通过 MSI-X 向 CPU 2 投递中断
          │
          ▼
CPU 2 硬件级别响应：
  1. 保存当前寄存器状态（用户线程的上下文）
  2. 跳转到中断向量表
  3. 执行网卡驱动的 hardirq handler
     - 关闭该队列的中断（防止中断风暴）
     - 调用 napi_schedule()，将 NAPI 挂到 softirq 待处理列表
     - 整个过程约 1μs
  4. 硬中断返回
          │
          ▼
检查是否有 pending softirq → 有 (NET_RX_SOFTIRQ)
  执行 NAPI poll：
  - 从网卡 DMA ring 批量收包
  - 每次最多收 budget 个包（默认 64）
  - 走 IP/TCP 协议栈处理
  - 将数据放入 socket recv queue
  - 可能持续 几十μs 到几ms
          │
          ▼
softirq 处理完毕
恢复你的行情线程继续执行
```

**你的线程被打断的时间 = hardirq 时间 + softirq 时间**，通常在 5-100μs 级别，取决于一次收了多少包。需要注意的是，这个打断对用户线程而言是完全不可见、不可控的——你无法用 `SCHED_FIFO` 或任何调度策略来阻止硬中断。

---

## 五、Busy Poll 深度解析

上文提到，中断是数据进入用户态的必经之路——"除非使用 busy poll 或 kernel bypass"。Busy poll 是低延迟系统中性价比最高的优化手段之一，但也是最容易被误解的概念。

### 5.1 它不是 C++ 里的 busy loop

先澄清一个常见的混淆：**内核 busy poll 和你在 C++ 代码里写的 busy loop 不是一回事。**

C++ 里的 busy loop 通常长这样：

```cpp
// 典型的用户态 busy loop
while (true) {
    int n = epoll_wait(epfd, events, MAX_EVENTS, 0);  // 超时设为 0，非阻塞
    if (n > 0) {
        for (int i = 0; i < n; i++) {
            recv(events[i].data.fd, buf, sizeof(buf), 0);
            process(buf);
        }
    }
    // 没数据也不睡觉，继续循环
}
```

这段代码在干什么？

```
循环迭代 1：用户态 → syscall 进内核 → 检查 socket queue → 没数据 → 返回用户态 (EAGAIN)
循环迭代 2：用户态 → syscall 进内核 → 检查 socket queue → 没数据 → 返回用户态 (EAGAIN)
循环迭代 3：用户态 → syscall 进内核 → 检查 socket queue → 没数据 → 返回用户态 (EAGAIN)
......
循环迭代 N：用户态 → syscall 进内核 → 检查 socket queue → 有数据！→ 拷贝 → 返回用户态
```

每次循环都经历一次完整的系统调用开销（用户态 → 内核态 → 用户态）。在 aarch64 上，一次 syscall 的开销约 0.5-1μs。

**最关键的问题是：数据是怎么进入 socket queue 的？** 用户态 busy loop 只是不停地"查看"有没有数据，但数据从网卡到 socket queue 的过程**仍然完全依赖中断驱动**。你的 busy loop 对"网卡 → 内核协议栈 → socket queue"这段路径没有任何加速作用，它只是让你的线程不睡觉，能更快地发现"数据到了"。

### 5.2 内核 busy poll 做了什么

内核 busy poll 的本质完全不同：**它让用户线程在调用 `recv()` / `epoll_wait()` 时，不睡眠等中断唤醒，而是在内核态主动轮询网卡收包。**

#### 没有 busy poll 时的数据路径

```
用户线程调用 recv()
      │
      ▼
内核检查 socket recv queue 有没有数据
      │
      ├── 有数据 → 拷贝到用户 buffer，返回
      │
      └── 没数据 → 把线程标记为 TASK_INTERRUPTIBLE
                   放入 socket 的等待队列
                   调用 schedule() 让出 CPU
                   线程睡眠 💤
                        │
                   ......等待......
                        │
                   网卡收到数据包
                   → 硬中断触发
                   → softirq 执行 NAPI poll
                   → 协议栈处理
                   → 数据放入 socket recv queue
                   → wake_up() 唤醒线程
                        │
                   调度器重新调度线程到某个 CPU
                   线程醒来，读取数据，返回用户态
```

这条路径的延迟分布：

```
数据到达网卡 → 硬中断投递延迟        ~1-5μs
→ softirq 调度延迟                   ~1-3μs
→ 协议栈处理                         ~2-5μs
→ wake_up 唤醒线程                   ~1-3μs
→ 调度器选核 + 上下文切换             ~3-10μs
→ 线程恢复执行                       ~1-2μs
                               总计：约 10-30μs
```

其中 **"睡眠 → 中断唤醒 → 重新调度"** 是最大的延迟来源。

#### 开启 busy poll 后的数据路径

```
用户线程调用 recv()
      │
      ▼
内核检查 socket recv queue 有没有数据
      │
      ├── 有数据 → 拷贝到用户 buffer，返回
      │
      └── 没数据 → 【关键区别】不睡眠！进入 busy poll 循环
                        │
                  ┌──── 循环体 ────────────────────────────┐
                  │                                        │
                  │  直接调用 napi_busy_loop()              │
                  │  （跟 softirq 里调用的是同一个函数）      │
                  │  主动从网卡 DMA ring 拉数据              │
                  │       │                                │
                  │       ├── 拉到了 → 走协议栈处理          │
                  │       │   数据放入 socket recv queue     │
                  │       │   跳出循环                      │
                  │       │                                │
                  │       └── 没拉到 → cpu_relax()          │
                  │                   检查时间是否超限       │
                  │                   没超 → 继续循环       │
                  │                   超了 → 退出，走传统    │
                  │                          睡眠路径       │
                  └────────────────────────────────────────┘
                        │
                  拷贝数据到用户 buffer，返回用户态
```

延迟对比：

```
数据到达网卡 DMA ring
→ busy poll 循环检测到数据              ~1-5μs（取决于轮询间隔）
→ 直接在当前 CPU 上走协议栈处理         ~2-5μs
→ 数据放入 socket recv queue
→ 当前线程立刻读取，不需要唤醒          ~0μs
→ 返回用户态
                               总计：约 3-10μs
```

省掉的就是"睡眠 → 中断 → 唤醒 → 重新调度"整个链路。

### 5.3 Busy poll 在哪一层运行

```
┌─────────────────────────────────────────┐
│           用户态 (User Space)            │
│                                         │
│   your_app:                             │
│     fd = socket(...)                    │
│     setsockopt(fd, SO_BUSY_POLL, 50)    │
│     recv(fd, buf, len, 0)  ──────────┐  │
│                                      │  │
├──────────────── syscall ─────────────┼──┤
│                                      │  │
│           内核态 (Kernel Space)       │  │
│                                      ▼  │
│   sys_recvfrom()                        │
│     → sock_recvmsg()                    │
│       → tcp_recvmsg()                   │
│         → sk_busy_loop()  ◄── 在这里spin│
│           → napi_busy_loop()            │
│             → 网卡驱动 poll 函数         │
│               → 从 DMA ring 读数据      │
│                                         │
│   线程状态：TASK_RUNNING                 │
│   位置：内核态                           │
│   CPU：没有让出去                        │
│   中断：没有关闭，但不需要中断来收包了     │
└─────────────────────────────────────────┘
```

**结论：busy poll 运行在内核态，但由用户线程的系统调用触发。** 用户线程 `recv()` 进入内核后，不睡眠，而是在内核态 spin 调用 NAPI poll 主动收包。

### 5.4 内核代码路径

简化后的核心逻辑（`net/core/dev.c`）：

```c
// 用户调 recv() 最终会走到这里
int sk_busy_loop(struct sock *sk, int nonblock)
{
    unsigned long end_time = busy_loop_end_time();

    while (!skb_queue_empty_lockless(&sk->sk_receive_queue) == false) {

        // 关键：直接调用 NAPI 的 poll 函数
        // 这跟 softirq 里收包调用的是同一个函数
        // 本质：用户线程替代了 ksoftirqd 的工作
        napi_busy_loop(sk->sk_napi_id);

        if (skb_queue_empty_lockless(&sk->sk_receive_queue) == false)
            break;  // 收到了，跳出

        if (busy_loop_timeout(end_time))
            break;  // 超时了，退出 busy poll

        // 让出一点 CPU 资源（aarch64 上是 yield 指令）
        // 但不会让出 CPU 给调度器，线程还在跑
        cpu_relax();
    }
}
```

注意 `napi_busy_loop()` 这个调用——它直接调用了网卡驱动注册的 poll 函数，效果等同于 softirq 里的收包操作：

```
没有 busy poll：
  网卡中断 → softirq → napi_poll() → 收包 → 唤醒用户线程

有 busy poll：
  用户线程自己调 napi_poll() → 收包 → 直接拿到数据

  中间没有中断，没有 softirq，没有睡眠唤醒
```

### 5.5 Busy poll 期间中断来了怎么办

Busy poll 期间 CPU 没有关闭中断。如果此时网卡硬中断到达：

```
你的线程在 busy poll（内核态 spin）
          │
          ▼
网卡中断到达
          │
          ▼
CPU 硬件：保存状态 → 执行 hardirq handler
  但是 NAPI 已经在 poll 模式了
  hardirq handler 发现 NAPI 已经被调度
  → 几乎什么都不做就返回（< 1μs）
          │
          ▼
恢复 busy poll 循环继续
```

这就是 NAPI 的精髓：busy poll **不是阻塞中断，而是让中断变得没有必要**。NAPI 的状态机保证了同一个队列不会同时被中断和轮询两条路径处理。

### 5.6 与 C++ busy loop 的本质对比

```
                   C++ busy loop              内核 busy poll
                   ──────────────             ──────────────
代码位置            用户态 while 循环          内核态 sk_busy_loop()

谁触发收包          网卡中断 → softirq         用户线程在内核态
                   → NAPI poll               直接调 NAPI poll

syscall 次数        每次循环一次 syscall        一次 syscall 内完成
                   没数据就白跑一趟            spin 等到数据再返回

是否依赖中断         完全依赖                   不依赖
                   中断把数据送到 queue         自己主动去网卡拉

空转时在干嘛         用户态空转                  内核态轮询网卡
                   什么有用的事都没干            在主动拉数据

延迟                中断延迟 + 轮询间隔          只有轮询间隔
                   ~10-30μs                   ~3-10μs
```

用一个生活比喻来说明区别：

- **C++ busy loop**：你每隔一秒跑到门口看快递到了没。快递员什么时候送到跟你无关，你只是反复检查。包裹到了放在门口（socket queue），你发现了就拿走。
- **内核 busy poll**：你直接站在快递分拣中心的传送带旁边。包裹一出现你就自己拿走，快递员（中断）都不需要上门了。

### 5.7 两者结合的正确姿势

C++ busy loop 和内核 busy poll 并不互斥，实际上最常见的低延迟写法是两者叠加：

```cpp
// 先开启内核 busy poll
int busy_poll_us = 50;
setsockopt(fd, SOL_SOCKET, SO_BUSY_POLL, &busy_poll_us, sizeof(busy_poll_us));

// 然后用户态也 busy loop
while (true) {
    // 这次 recv 进内核后，内核会先 busy poll 50μs
    // 如果 50μs 内网卡有数据，直接在内核态收完再返回
    int ret = recv(fd, buf, sizeof(buf), 0);  // 可以用阻塞模式
    if (ret > 0) {
        process(buf);
    }
}
```

这样就是两层加速叠加：内核层面绕过中断主动收包，用户层面不做无谓的睡眠等待。

### 5.8 配置方法

```bash
# 全局启用（影响所有 socket）
sysctl -w net.core.busy_poll=50        # epoll_wait 时轮询 50μs
sysctl -w net.core.busy_read=50        # recv 时轮询 50μs

# 或每个 socket 单独设置（更灵活）
int val = 50;
setsockopt(fd, SOL_SOCKET, SO_BUSY_POLL, &val, sizeof(val));
```

代价是 CPU 使用率会升高（空转期间也在轮询），但对于隔离出来的专用核来说这不是问题——那个核反正也不给别人用。

### 5.9 延迟阶梯：从传统中断到 Kernel Bypass

```
传统中断模式    ~10-30μs    什么都不配置
Busy Poll      ~3-10μs     sysctl 一行搞定，不改应用代码
AF_XDP         ~1-3μs      需要改代码，使用 XDP socket
DPDK           ~0.5-1μs    重写网络栈，完全接管网卡
```

- **Busy Poll**：不改代码架构，socket API 不变，性价比最高
- **AF_XDP**：内核创建共享内存 ring（UMEM），用户态和网卡驱动共享，绕过协议栈但不完全绕过内核
- **DPDK**：网卡 DMA 直接映射到用户态内存，用户线程在用户态直接读 DMA ring，完全绕过内核，自己在用户态实现 TCP/IP

对于 WebSocket 行情接收场景，busy poll 通常就够了。如果需要更极致的延迟，才考虑 AF_XDP 或 DPDK，但那意味着重写整个网络层。

---

## 六、192 核 Graviton3 的推荐核心分配方案

结合以上所有分析，给出针对 192 核 Graviton3 + 加密货币行情系统的具体核心分配方案。

### 6.1 硬件拓扑回顾

```
Architecture:     aarch64
CPU(s):           192 (Thread per core: 1, 无超线程)
Socket(s):        2, 每 Socket 96 核
NUMA node 0:      CPU 0-95
NUMA node 1:      CPU 96-191
L1d/L1i:          64KB per core
L2:               2MB per core（私有）
L3:               36MB per socket（共享）
```

### 6.2 确定网卡的 NUMA 亲和性

首先确认网卡属于哪个 NUMA node，这决定了所有行情相关的核心必须分配在哪个 node 上：

```bash
cat /sys/class/net/enP11p4s0/device/numa_node
```

如果输出是 `0`，则行情相关的一切（网卡中断核、行情线程核）都必须在 CPU 0-95 范围内，避免跨 NUMA 访问。

### 6.3 核心分配方案

假设主行情网卡（enP11p4s0）在 NUMA node 0：

```
NUMA Node 0 (CPU 0-95)
──────────────────────────────────────────────────
CPU 0-1     : Housekeeping
              ├── 内核线程（ksoftirqd, kworker, rcu...）
              ├── 系统服务（sshd, journald, systemd...）
              └── 其他非关键中断

CPU 2-5     : 网卡中断专用
              ├── enP11p4s0 的 32 个 RX 队列中断
              │   （可以将队列数缩减，或将多个队列的 IRQ 绑到同一个核）
              └── ksoftirqd/2-5（NAPI 软中断收包）

CPU 6-15    : 行情接收线程
              ├── binance-MD, okx-MD, gate-MD 等
              ├── WebSocket 解析 + 行情分发
              └── 建议与中断核在同一 L3 域内（同 NUMA node 0）

CPU 16-80   : 策略计算 / 业务逻辑
              ├── 策略引擎
              ├── 风控模块
              └── 订单管理

CPU 81-95   : 备用 / 其他服务

NUMA Node 1 (CPU 96-191)
──────────────────────────────────────────────────
CPU 96-100  : 其他网卡中断（enP11p8s0 等次要网卡）
CPU 101-191 : 其他业务、回测、数据处理等非延迟敏感任务
```

### 6.4 内核启动参数

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX="isolcpus=managed_irq,domain,2-95,101-191 \
nohz_full=6-95,101-191 \
rcu_nocbs=6-95,101-191 \
nosoftlockup \
processor.max_cstate=0 \
idle=poll"
```

参数说明：

- **`isolcpus=managed_irq,domain,2-95,101-191`**：将这些核从调度域中移除，同时让内核管理这些核上的中断分配（`managed_irq`）。CPU 0-1 保留为 housekeeping。
- **`nohz_full=6-95,101-191`**：在这些核上关闭定时器 tick（adaptive-ticks），当核上只有一个 runnable 任务时，不再产生周期性的时钟中断。注意网卡中断核（CPU 2-5）不加 `nohz_full`，因为它们需要处理中断，tick 对它们影响不大。
- **`rcu_nocbs=6-95,101-191`**：将这些核上的 RCU 回调卸载到专门的内核线程上处理，避免 RCU 回调打断用户线程。
- **`processor.max_cstate=0`**：禁止 CPU 进入深度睡眠状态。C-state 越深，唤醒延迟越大（C1 约 1μs，C6 可达 100μs+）。交易系统宁可空转也不能容忍唤醒延迟。
- **`idle=poll`**：CPU 空闲时不进入任何低功耗状态，直接在 idle 循环里 spin。与 `max_cstate=0` 配合，确保 CPU 始终处于最高性能状态。

### 6.5 运行时配置脚本

```bash
#!/bin/bash
# setup_affinity.sh - 系统启动后执行

# 1. 关闭 irqbalance
systemctl stop irqbalance
systemctl disable irqbalance

# 2. 缩减网卡队列数（减少中断分散）
ethtool -L enP11p4s0 combined 4   # 只用 4 个队列

# 3. 绑定网卡中断到专用核
# 查找 enP11p4s0 的中断号
IRQS=$(grep enP11p4s0 /proc/interrupts | awk '{print $1}' | tr -d ':')
CPU=2
for irq in $IRQS; do
    echo $CPU > /proc/irq/$irq/smp_affinity_list
    CPU=$(( (CPU - 2 + 1) % 4 + 2 ))  # 在 CPU 2-5 之间轮转
done

# 4. 关闭 GRO（减少攒包延迟）
ethtool -K enP11p4s0 gro off

# 5. 关闭 Adaptive Coalescing
ethtool -C enP11p4s0 adaptive-rx off rx-usecs 0 rx-frames 1

# 6. 把所有非关键进程限制到 housekeeping 核
for pid in $(ps -eo pid --no-headers); do
    taskset -apc 0-1 $pid 2>/dev/null
done

# 7. 开启 busy poll
sysctl -w net.core.busy_poll=50
sysctl -w net.core.busy_read=50

# 8. 增大 socket buffer
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.rmem_default=26214400

# 9. 关闭 conntrack 和 iptables（如果不需要防火墙）
# rmmod nf_conntrack 2>/dev/null
# iptables -F 2>/dev/null

# 10. 启动行情进程（绑到隔离核）
taskset -c 6  ./binance_md_receiver &
taskset -c 7  ./okx_md_receiver &
taskset -c 8  ./gate_md_receiver &
taskset -c 16 ./strategy_engine &
```

### 6.6 验证配置是否生效

```bash
# 检查 isolcpus 是否生效
cat /sys/devices/system/cpu/isolated

# 检查 nohz_full 是否生效
cat /sys/devices/system/cpu/nohz_full

# 检查中断亲和性
for irq in $(grep enP11p4s0 /proc/interrupts | awk '{print $1}' | tr -d ':'); do
    echo "IRQ $irq → CPU $(cat /proc/irq/$irq/smp_affinity_list)"
done

# 检查网卡 NUMA 亲和性
cat /sys/class/net/enP11p4s0/device/numa_node

# 实时观察中断分布（确认没有漂移）
watch -n1 'cat /proc/interrupts | grep enP11p4s0 | head -5'

# 检查行情线程的核绑定
for pid in $(pgrep -f md_receiver); do
    echo "PID $pid → CPU $(taskset -p $pid | awk '{print $NF}')"
done

# 观察 housekeeping 核负载
mpstat -P 0,1 1
```

---

## 七、与上一篇文章的关系

本文和[上一篇](/blog/2026-03-17-net_proc/)构成一个系列，分别从两个不同的视角分析同一个系统：

| 维度 | 上一篇 | 本篇 |
|---|---|---|
| 核心问题 | 数据包怎么走 | CPU 核心怎么分 |
| 视角 | Packet-centric（以包为中心） | CPU-centric（以核为中心） |
| 覆盖范围 | 物理层 → NIC → 硬中断 → NAPI → 协议栈 → socket → 用户态 | isolcpus → housekeeping → 中断绑核 → 抢占机制 → busy poll |
| 回答的关键决策 | 流量该走哪张网卡？GRO 要不要关？conntrack 要不要卸？ | 哪些核跑内核家务？中断和行情线程放同核还是分开？busy poll 怎么配？ |

两篇文章交叉引用的要点：

- 上一篇的第三章（硬中断）和第四章（NAPI）是理解本篇第四章（中断抢占）和第五章（busy poll）的前置知识。
- 上一篇的 10.2 节（IRQ core 与应用进程 core 亲和）在本篇第三章做了更深入的展开，解释了同核 cache 命中的底层原因。
- 上一篇的 10.5 节（Busy Polling）在本篇第五章做了完整的内核代码级解析，并与用户态 busy loop 做了清晰区分。

> **延伸阅读**：本文讨论了 IRQ 核组与计算核的分离原则。下一篇[《同一专线、同一秒、延迟不一样——从一次排查看网卡中断与核心隔离的本质》]({{< ref "2026-04-09-buffer" >}})从一次真实延迟排查出发，进一步展开网卡物理隔离、PPS 瓶颈与 Buffer Bloat 的分析。
