+++
title = 'MengRao/SPSC_Queue 源码精读：把跨核延迟做到 50ns 的四种 SPSC 队列设计'
date = 2026-08-07T09:00:00+08:00
draft = false
tags = ["Concurrency", "HFT", "C++", "LockFree"]
aliases = ['/blog/2025-06-24-lock_free_queue_implementation/']
+++

> [MengRao/SPSC_Queue](https://github.com/MengRao/SPSC_Queue) 是国内低延迟圈知名开发者饶萌（tcpshm、fmtlog 的作者）开源的单生产者单消费者无锁队列，README 宣称 10–200B 消息的跨核通信延迟在 **50–100ns**。整个仓库只有 4 个头文件、每个不到 150 行，却把 SPSC 队列设计空间里几乎所有关键取舍都覆盖了：**定长 vs 变长消息、IPC crash-safe vs 极致延迟**。本文逐个拆解这四个实现，重点回答一个问题：同样是无锁环形队列，凭什么它能比教科书写法快一倍？拆完源码后，文章会再退一步补齐全景：支撑这一切的寻址/缓存一致性/内存序三层地基，以及走出 SPSC 之后 MPSC/MPMC 的核心机制与选型。

---

## 一、仓库总览：一个 2×2 设计矩阵

四个头文件不是四个孤立实现，而是两个维度的组合：

| | 定长消息（模板参数 `T`） | 变长消息（带 MsgHeader） |
|---|---|---|
| **原子发布，crash-safe，可用于共享内存 IPC** | `SPSCQueue.h` | `SPSCVarQueue.h`（用于作者的 [tcpshm](https://github.com/MengRao/tcpshm) 框架） |
| **极致延迟优化，仅限线程间** | `SPSCQueueOPT.h` | `SPSCVarQueueOPT.h` |

两行的本质区别只有一条：**消费者靠什么发现新消息**。

- 基础版：消费者轮询生产者发布的共享索引 `write_idx`——发现消息要读 **两条缓存行**（索引一条、数据一条）；
- OPT 版：把"有没有消息"这个标志**内嵌进数据所在的缓存行**——发现消息只要读 **一条缓存行**。

跨核通信的延迟基本上就是缓存行在两个核之间传输的次数 × 单次传输耗时（几十 ns）。OPT 版把次数从 2 降到 1，延迟近乎减半——这是整个仓库最核心的亮点。代价是发布操作从"单条原子 store"变成多步写入，进程中途崩溃会把队列留在不一致状态，所以 OPT 版不能用于共享内存 IPC。

在深入源码之前，先交代两件事：这类队列在设计空间里的位置（它是"队列"，不是"广播"），以及四个实现共享的三条"设计基因"。

> **延伸阅读**：并发原语的硬件成本（MESI、原子指令、六种内存序）可以先看这篇打底：[并发原语深度剖析：从 Mutex 到 Atomic 到 Lock-Free 数据结构]({{< ref "2026-03-03-mutext" >}})

---

## 二、队列还是广播：一个先于所有代码的设计决策

深入源码前值得先停一步。SPSC_Queue 的一切设计都建立在一个前提上：**读者的消费进度（`read_idx`）放在共享结构里，写者看得见**。这个决策先于所有实现细节，直接划定了这类队列的能力边界——它的对立面是把读进度私有化的"广播"模型：

> **读者状态放进共享结构 ⇒ 队列语义**：写者能判满 → 有背压、永不覆盖、每条消息恰好消费一次；代价是读者要写共享状态，**只能有一个读者**——两个读者会在 `read_idx` 上互相"偷走"对方的消息。
>
> **读者状态私有化（各读者自持进度）⇒ 广播语义**：写者对读者完全无感知 → 写侧 wait-free、无背压、**任意多读者**；代价是慢读者被套圈覆盖丢数据，且读端要自己检测撕裂（seqlock 式读后校验）。

| | 队列（本文主角） | 广播 |
|---|---|---|
| 读者游标位置 | 共享结构，读者写它 | 读者私有 |
| 读者数量 | 恰好 1 | 任意 N，互不感知 |
| 队列满时 | 拒绝写入（背压） | 直接覆盖，慢读者被套圈 |
| 数据完整性 | 永不丢，恰好一次 | 慢读者丢数据 |
| 读一致性 | 槽位所有权互斥，天然无撕裂 | 乐观读 + 读后二次校验 |
| 典型场景 | 订单流、命令流（每条必达） | 行情流（人人可读、只要最新） |

两者不是优劣关系，而是"每条必达"和"只要最新"两种业务语义在同一根设计轴上的两个端点。MengRao 本人两边都写了：SPSC_Queue 是队列侧，同作者的 [PubSubQueue](https://github.com/MengRao/PubSubQueue) 是广播侧。本文四个实现全部在队列侧，但读的时候不妨对照着想：每个设计点（判满、背压、crash-safe）到了广播侧要么消失、要么换一副面孔。

---

## 三、三条共同的设计基因

### 3.1 真正的零拷贝：alloc/push 两段式 API

教科书式的队列接口是 `push(const T& msg)`——用户先在自己的栈上构造消息，再拷进队列。SPSC_Queue 的接口是反过来的：

```cpp
// 生产者：先拿槽位指针，原地构造，再发布
Msg* msg = q->alloc();      // 拿到队列内存里的槽位
if (msg) {
    msg->ts = rdtsc();      // 直接在队列内存上写
    q->push();              // 发布（仅移动索引）
}

// 消费者：原地读，读完再释放
Msg* msg = q->front();      // 直接拿到队列内存里的消息指针
if (msg) {
    handle(*msg);           // 原地消费
    q->pop();               // 释放（仅移动索引）
}
```

消息从生到死只存在一份：生产者在队列槽位上构造，消费者在同一块内存上读取，**全程一个字节都不拷贝**。`tryPush(writer)` / `tryPop(reader)` 只是接受 lambda 的语法糖。

这个 API 还有个隐藏好处：`alloc()` 和 `push()` 之间写了一半的消息对消费者完全不可见（索引还没动），生产者可以慢慢填充大消息而不用担心消费者读到半成品。

### 3.2 对象可以直接躺进共享内存

看 test 目录里的 IPC 用法：

```cpp
typedef SPSCQueue<Msg, 4> MsgQueue;

MsgQueue* q = shmmap<MsgQueue>("/shm_queue");  // shm_open + ftruncate + mmap
```

没有构造函数调用、没有初始化握手——`mmap` 出来的新共享内存页全是零，而队列的全部状态就是几个整数索引，**全零恰好就是合法的空队列状态**。任何一方（甚至两方同时）attach 上来即可直接用。能做到这一点是因为整个类里没有指针、没有虚表、没有堆分配，所有成员都是 POD 数组和整数，进程间地址不同也无所谓。

### 3.3 纯 busy-poll，不 sleep 不 futex

`blockPush` 就是裸自旋：

```cpp
template<typename Writer>
void blockPush(Writer writer) {
    while (!tryPush(writer))
        ;
}
```

没有退避、没有 futex 唤醒。这是 HFT 的典型假设：收发双方各自绑定在隔离的专属核心上，延迟远比 CPU 占用率重要。test 代码里 `cpupin(6)` / `cpupin(7)` 也印证了这一点。

> **延伸阅读**：为什么低延迟系统一定要绑核 + busy-poll，内核侧要怎么配合：[低延迟系统的 CPU 核心规划：从 isolcpus 到 Busy Poll 的内核级实战]({{< ref "2026-03-30-cpu_bindcore" >}})

---

## 四、SPSCQueue：教科书写法的"满血版"

先看基准实现，全部核心代码如下（去掉了语法糖）：

```cpp
template<class T, uint32_t CNT>
class SPSCQueue {
public:
    static_assert(CNT && !(CNT & (CNT - 1)), "CNT must be a power of 2");

    T* alloc() {
      if (write_idx - read_idx_cach == CNT) {              // 用本地缓存的 read_idx 判满
        read_idx_cach = ((std::atomic<uint32_t>*)&read_idx)
                            ->load(std::memory_order_consume);
        if (__builtin_expect(write_idx - read_idx_cach == CNT, 0)) {
          return nullptr;                                  // 真的满了
        }
      }
      return &data[write_idx % CNT];
    }

    void push() {
      ((std::atomic<uint32_t>*)&write_idx)
          ->store(write_idx + 1, std::memory_order_release);
    }

    T* front() {
        if (read_idx == ((std::atomic<uint32_t>*)&write_idx)
                            ->load(std::memory_order_acquire)) {
          return nullptr;                                  // 空
        }
        return &data[read_idx % CNT];
    }

    void pop() {
      ((std::atomic<uint32_t>*)&read_idx)
          ->store(read_idx + 1, std::memory_order_release);
    }

private:
    alignas(128) T data[CNT] = {};

    alignas(128) uint32_t write_idx = 0;
    uint32_t read_idx_cach = 0;   // 仅生产者线程使用

    alignas(128) uint32_t read_idx = 0;
};
```

短短几十行里有五个值得展开的点。

### 4.1 自由递增索引：不取模、不浪费槽位

`write_idx` / `read_idx` 是**一直递增**的逻辑序号，只在访问数组时才 `% CNT`（CNT 是 2 的幂，编译成一条 AND）。判空是 `read_idx == write_idx`，判满是 `write_idx - read_idx == CNT`。

对比常见的"索引本身回绕"写法：那种写法里 `write == read` 既可能是空也可能是满，只好牺牲一个槽位（容量 CNT-1）来消歧。自由递增索引没有这个歧义，**CNT 个槽位全部可用**。`uint32_t` 溢出也不是问题——无符号减法天然是模 2³² 运算，而 CNT 整除 2³²，回绕前后差值依然正确。

### 4.2 read_idx_cach：热路径上不碰对方的缓存行

这是本实现最重要的优化。生产者判满需要知道消费者读到哪了，但 `read_idx` 所在的缓存行由消费者高频写入——生产者每次 push 都去读它，会造成该行在两个核之间持续 ping-pong。

解法：生产者本地留一份陈旧副本 `read_idx_cach`，平时只跟副本比较；**只有副本显示"满了"时才去真正加载一次 `read_idx`**。队列不满时（正常情况），生产者的热路径完全不访问消费者写的缓存行，一致性流量从"每次 push 一次"降到"每次队列写满一次"。

用陈旧值判满为什么是安全的？因为误差只有一个方向：消费者的进度单调递增，过时的 `read_idx` 只会**低估**它——生产者把队列想象得比实际更满，最坏结果是误判一次"满"、触发一次真正的加载，**永远不会**高估而覆盖未读数据。这种"旧值安全"的单向误差结构，是所有索引缓存类优化（包括下文 OPT 版的本地配额）的正确性根基。

这个技巧和 rigtorp::SPSCQueue 的 cached index、LMAX Disruptor 的 sequence cache 是同一个思想，属于高性能 SPSC 的标配。

### 4.3 alignas(128)：为什么是 128 而不是 64

成员被切成三个 128 字节对齐的组：

```
[data ...]                     ← 生产者写、消费者读
[write_idx | read_idx_cach]    ← 生产者写 write_idx，消费者读它；read_idx_cach 是生产者私有
[read_idx]                     ← 消费者写，生产者偶尔读
```

分组原则很清晰：**每条共享缓存行只有一个写方**，而且把"生产者私有"的 `read_idx_cach` 塞进生产者自己写的那一行，不另占空间。

对齐到 128 而非 64，是为了躲开 Intel 的 **adjacent cache line prefetcher**——L2 硬件预取器会成对（128B）拉取缓存行，两个变量哪怕各占一条 64B 行，只要落在同一个 128B 对里，仍可能出现"预取粒度上的伪共享"。这也是不少库把 `hardware_destructive_interference_size` 取 128 的原因。

> **延伸阅读**：伪共享对原子操作性能的影响有多大，实测数据见：[深入理解 False Sharing：实测原子操作与缓存行对齐对性能的影响]({{< ref "2025-06-23-cache_false_sharing_analysis" >}})

### 4.4 把普通 uint32_t 强转成 atomic：历史包袱与现代替代

```cpp
((std::atomic<uint32_t>*)&write_idx)->store(write_idx + 1, std::memory_order_release);
```

索引声明为普通 `uint32_t`，需要原子语义时临时强转。动机是：**索引的所有者线程对它的读取（判满、取模、+1）全部是普通变量语义**，代码干净且不给编译器任何额外约束；只在跨线程交接的那一次 load/store 上付出原子语义。

严格按标准这是 UB（对象的声明类型不是 `std::atomic`），实践上因为 `std::atomic<uint32_t>` 与 `uint32_t` 布局相同且 x86 上 lock-free 而工作正常。2018 年写这份代码时没有更好的选择；今天的标准答案是 **C++20 `std::atomic_ref`**——它就是为"给普通变量临时套原子语义"这个模式量身定做的合法版本。

### 4.5 为什么单写者也离不开 atomic：一对经典的 release/acquire

一个常见疑问：SPSC 里每个索引都只有一个线程写，为什么还需要 atomic？因为**单写者不等于单访问者**——`write_idx` 由生产者写、消费者读，`read_idx` 反之，每个索引都是"一写一读"的共享变量。这里的 atomic 承担三个职责：

1. **管住编译器**：消费者的自旋等待若写成普通变量，`while (read_idx == write_idx)` 在 -O2 下会被优化成"load 一次进寄存器、永远自旋"，生产者怎么 push 都看不见；
2. **防撕裂**：读方可能撞上写方正在进行的 store，C++ 对普通变量的并发读写直接定义为 data race（UB）。x86 硬件对对齐的 32 位访问天然原子，但那是硬件的善意，不是语言的承诺；
3. **内存序**：索引不只是个数字，它是消息数据的**发布信号**——这正是下面这对 release/acquire 保证的东西：

- 生产者 `push()`：release store `write_idx`——保证槽位数据的写入不会被重排到索引发布之后。消费者 `front()`：acquire load `write_idx`——看到新索引就一定能看到完整数据。
- 消费者 `pop()`：release store `read_idx`——保证对数据的**读取**先于索引释放完成，生产者复用槽位时不会覆盖还没读完的数据。生产者 `alloc()` 里用 `memory_order_consume` 读 `read_idx`，主流编译器一律按 acquire 处理。

单写者真正省掉的是读-改-写竞争：`write_idx + 1` 可以先普通读、算好、再一条 store 发布，不需要 `lock xadd` 也不需要 CAS 重试。所以在 x86 (TSO) 上这些 atomic 全部编译成普通 `mov`，零指令开销，约束的只是编译器重排（换到弱内存模型硬件上才会生成真屏障）。

> **延伸阅读**：不同内存序在真实硬件上的开销差异：[C++原子操作内存序性能分析：seq_cst vs relaxed]({{< ref "2025-06-21-memory_order_performance_analysis" >}})

### 4.6 crash-safe 从何而来

README 说这个版本"atomic, crash safe when used in shared-memory IPC"。原因是：**所有对对端可见的状态变更都是一条对齐的 32 位 store**（`write_idx` 或 `read_idx` 的发布），x86 上天然原子。任何一方在任意指令处被 `kill -9`：

- 死在 `alloc()` 和 `push()` 之间：索引没发布，写了一半的消息不可见，队列状态完好，最多丢这一条没发出去的消息；
- 死在 `front()` 和 `pop()` 之间：索引没释放，重启后同一条消息还在，重读一遍即可。

对共享内存 IPC 来说这是关键性质——对端进程可能在任何时刻死掉，队列必须永远处于合法状态。

---

## 五、SPSCQueueOPT：一条缓存行的胜利

基础版消费者发现新消息的路径是：读 `write_idx`（缓存行 A）→ 读 `data[read_idx % CNT]`（缓存行 B）。生产者每 push 一次要写这两条行，消费者要依次把两条行从生产者核搬过来——**关键路径上是两次跨核缓存行传输**。

OPT 版的改动直击这一点：

```cpp
template<class T, uint32_t CNT>
class SPSCQueueOPT {
  struct alignas(64) Block {
    bool avail = false;   // 生产者置 true 发布，消费者置 false 释放
    T data;
  } blk[CNT] = {};

  alignas(128) uint32_t write_idx = 0;      // 生产者私有
  uint32_t free_write_cnt = CNT - 1;        // 生产者私有
  alignas(128) uint32_t read_idx = 0;       // 消费者写，生产者偶尔读
};
```

### 5.1 标志与数据同行：2 次传输 → 1 次

每个槽位自带一个 `avail` 标志，和数据**同处一条 64B 缓存行**：

```cpp
T* front() {
    auto& cur_blk = blk[read_idx];
    if (!((std::atomic<bool>*)&cur_blk.avail)->load(std::memory_order_acquire))
        return nullptr;
    return &cur_blk.data;
}
```

消费者轮询的不再是全局索引，而是**下一个槽位自己的 avail 标志**。生产者发布消息 = 写数据 + release store `avail = true`，全部落在同一条缓存行；消费者一次缓存行传输就同时拿到了标志和数据。用 MESI 的语言说：

```
基础版（2 次传输串行在关键路径上）:
  生产者: 写 data 行(RFO) → 写 write_idx 行(RFO)
  消费者: 轮询 write_idx 行 → miss → 传输①
          读 data 行        → miss → 传输②

OPT 版（1 次传输）:
  生产者: 写 (avail+data) 行(RFO)
  消费者: 轮询 avail       → miss → 传输①，数据已在手
```

单次跨核 cache-to-cache 传输是几十 ns 量级，省掉一次就是省掉小几十 ns——对 50–100ns 的总延迟来说这是决定性的。

### 5.2 索引彻底退出热路径

注意成员注释：`write_idx` 和 `free_write_cnt` **只有生产者访问**，消费者从头到尾不读它们；`read_idx` 也只在生产者的空间预算用完时才被读一次：

```cpp
T* alloc() {
    if (free_write_cnt == 0) {   // 本地预算用完，才去读一次对方的 read_idx
        uint32_t rd_idx = ((std::atomic<uint32_t>*)&read_idx)->load(std::memory_order_consume);
        free_write_cnt = (rd_idx - write_idx + CNT - 1) % CNT;   // 一次性批发一批配额
        if (__builtin_expect(free_write_cnt == 0, 0)) return nullptr;
    }
    return &blk[write_idx].data;
}
```

这是 `read_idx_cach` 思想的强化版：不是缓存对方索引的值，而是把它换算成"还能写多少条"的**本地配额**，用完才补货。稳态下两个方向的索引缓存行几乎不再跨核移动。

一个值得琢磨的落选方案：其实生产者可以完全不读 `read_idx`——直接看 `blk[write_idx].avail`，为 false 就说明该槽位已被消费、可以复用，流控信息同样内嵌进了数据行。作者没这么做，因为那样**每次 push** 都要先读一次数据行的标志（一次潜在 miss 加一个难预测的分支），而配额方案把远程读摊薄到每 CNT-1 次 push 才一次，热路径上只剩 `free_write_cnt == 0` 这个几乎永远不跳的本地分支。两种都正确，配额更便宜——这类"每次检查 vs 批量授权"的取舍在流控设计里反复出现。

### 5.3 两处代价

**牺牲一个槽位**。这里索引是回绕式的（`write_idx = (write_idx + 1) % CNT`），`(rd_idx - write_idx + CNT - 1) % CNT` 里那个 `-1` 就是经典的"空一格消歧"，可用容量 CNT-1。

**avail 由双方写**。消费者 `pop()` 要把 `avail` 清回 false（否则绕一圈回来无法区分新旧消息），于是数据缓存行变成了双写方——但这次写发生在消息已经消费完之后，不在延迟关键路径上；生产者下一圈复用槽位时反正要 RFO 这条行，代价被自然吸收了。

### 5.4 为什么不能用于 IPC

发布和释放都不再是单条 store 了。比如 `pop()`：

```cpp
void pop() {
    blk[read_idx].avail = false;                                   // store ①
    ((std::atomic<uint32_t>*)&read_idx)->store((read_idx + 1) % CNT, ...);  // store ②
}
```

消费者进程死在 ① ② 之间：`avail` 已清但 `read_idx` 没前进。重启后消费者在 `read_idx` 上永远等到 `avail == false`，而生产者认为该槽位仍被占用——**队列永久卡死**。同理生产者死在 `push()` 中途会导致槽位状态错乱。这就是 README 强调 OPT 版 "not atomic, should not be used in IPC" 的具体含义：不是不能放进共享内存，而是**扛不住进程半路崩溃**。

线程间通信没有这个问题——线程要死一起死。

---

## 六、SPSCVarQueue：变长消息 + crash-safe

定长队列要求收发双方约定死一个 `T`。真实系统（比如行情+订单混跑的通道）需要变长消息，这就是 SPSCVarQueue：以 **64 字节 Block（正好一条缓存行）**为分配粒度，每条消息带一个 8 字节头：

```cpp
struct MsgHeader {
    uint16_t size;      // 含 header 的总字节数，库自动填写
    uint16_t msg_type;  // 用户自定义消息类型
    uint32_t userdata;  // 用户自定义（比如塞时间戳）；反正对齐后有 4B padding，不用白不用
};

struct Block {          // 64 字节，与缓存行同宽
    alignas(64) MsgHeader header;   // payload 紧跟 header 之后
} blk[BLK_CNT];
```

一条消息占 `⌈(size + 8) / 64⌉` 个**连续** Block，索引仍是自由递增的 Block 序号。

### 6.1 rewind：变长消息的回绕难题

变长消息必须连续存放，环形数组尾部剩余空间可能塞不下一条大消息。处理办法是"回绕标记"：

```cpp
// alloc() 中
if (rewind) {                                     // 尾部空间不够
    blk[write_idx % BLK_CNT].header.size = 0;     // 写一个 size=0 的标记头
    asm volatile("" : : "m"(blk), "m"(write_idx) :);
    write_idx += padding_sz;                      // 跳过尾部，从数组头重新开始
}
```

消费者在 `front()` 里读到 `size == 0` 就知道"后面没消息了，跳到数组开头"：

```cpp
if (size == 0) {   // rewind 标记
    read_idx += BLK_CNT - (read_idx % BLK_CNT);   // 对齐到下一圈起点
    ...
}
```

### 6.2 有符号差值判断：TCP 序号的老手艺

空间检查这两行很精彩：

```cpp
uint32_t min_read_idx = write_idx + blk_sz + (rewind ? padding_sz : 0) - BLK_CNT;
if ((int)(read_idx_cach - min_read_idx) < 0) { ... }   // 空间不足
```

`min_read_idx` 是"这次写入不踩到读者"所要求的读者最小进度，它可能"负"成一个巨大的无符号数。把差值强转成 `int` 再和 0 比较——无符号回绕下依然正确的**有符号窗口比较**，和 TCP 序列号比较（RFC 1982 serial number arithmetic）是同一个 idiom。条件成立才去真正刷新 `read_idx_cach`，套路与基础版一致。

### 6.3 空 asm 编译器屏障：x86 TSO 下的零开销同步

这个文件里看不到 `std::atomic`，同步全靠这种东西：

```cpp
void push() {
    asm volatile("" : : "m"(blk), "m"(write_idx) :);   // 先把 payload 的写全部落地
    uint32_t blk_sz = (blk[write_idx % BLK_CNT].header.size + sizeof(Block) - 1) / sizeof(Block);
    write_idx += blk_sz;                               // 再发布索引
    asm volatile("" : : "m"(write_idx) :);             // 逼编译器立刻把 store 写出去
}
```

空的 `asm volatile` 不产生任何指令，作用全在约束上：`"m"(x)` 作为输入告诉编译器"这段汇编要读 x 的内存"，于是所有挂起的对 x 的写必须先落地；`"=m"(x)` 作为输出告诉编译器"x 的内存可能被改了"，于是后续读 x 必须重新 load，不能用寄存器里的旧值。

这能成立依赖 x86 的 **TSO 内存模型**：硬件本来就保证 store-store、load-load 不乱序，release/acquire 语义只差"管住编译器"这一步——空 asm 恰好补上这一步，运行期零开销。相比 `asm volatile("" ::: "memory")` 全量 clobber，这里按变量精确约束，编译器缓存在寄存器里的**其他**变量都不用刷掉，是更外科手术式的写法。

代价是**彻底不可移植**：ARM 是弱内存模型，store-store 会真乱序，这套代码搬过去必挂，得换成真屏障（`stlr`/`dmb`）。x86 上它和 `std::atomic` release/acquire 生成的代码其实一模一样（都是普通 mov + 编译器屏障），所以这更多是 2018 年的风格遗产——今天直接写 atomic/atomic_ref，可读性、可移植性全赢，性能不输。

### 6.4 依然 crash-safe

发布依然是单条 store（`write_idx += blk_sz` 由唯一写者执行，就是一条 32 位 store）；rewind 标记先写、索引后发布，任何一步中断都不会让消费者看到中间态。所以 VarQueue 保持了 IPC crash-safe，这也是它被用作 tcpshm 底层队列的原因。

> **延伸阅读**：共享内存 IPC 的完整选型（iceoryx / Aeron / 自研 SPSC 同平台实测），以及跨进程 atomic 为什么能工作：[共享内存 IPC 深度实测：从 iceoryx 到自研 SPSC，HFT 场景下的终极选型]({{< ref "2026-04-17-iceoryx_ipc_benchmark" >}})

---

## 七、SPSCVarQueueOPT：自描述消息流

最后一个实现把 OPT 思想推广到变长消息，手法比 SPSCQueueOPT 更妙：**不加独立的 avail 标志，而是让消息头的 `size` 字段自己承担发布语义**。Block 粒度也细化到 8 字节（一个 MsgHeader 大小）。

消费者看到的 `blk[read_idx].size` 是个三态信号：

| size 值 | 含义 |
|---|---|
| `0` | 还没有消息，继续轮询 |
| `1` | 回绕标记：跳回数组开头再看 |
| `n > 1` | 一条 n 字节的消息就绪 |

```cpp
MsgHeader* front() {
    uint16_t size = blk[read_idx].size;
    if (size == 1) {            // 回绕
        read_idx = 0;
        size = blk[0].size;
    }
    if (size == 0) return nullptr;
    return &blk[read_idx];
}
```

消费者**从头到尾没有读过 `write_idx`**——README 说的 "reader doesn't need to read write_idx so latency is reduced" 就是指这一点。新消息到达时，消费者轮询的头部和消息数据大概率同在一条缓存行（小消息场景），又是一次传输搞定。

### 7.1 发布顺序：先清下一个，再亮当前的

`push()` 的两步顺序是这个设计的命门：

```cpp
void push() {
    uint32_t blk_sz = (size + sizeof(MsgHeader) - 1) / sizeof(MsgHeader);
    blk[write_idx + blk_sz].size = 0;              // ① 先把"下一条"的头清零
    std::atomic_thread_fence(std::memory_order_release);
    blk[write_idx].size = size;                    // ② 再发布当前消息
    write_idx += blk_sz;
    free_write_cnt -= blk_sz;
}
```

为什么必须先 ①？环形缓冲绕过一圈后，`write_idx + blk_sz` 位置残留的是**上一圈某条旧消息的头**，size 是个非零脏值。如果先发布当前消息，消费者 pop 完立刻看下一个头，会把这个脏 size 当成一条合法消息读出去——纯垃圾数据。先把下一格清零、release fence 保序，才能保证"消费者看得见当前消息时，下一格必然读作 0（暂无消息）"。

消息流于是变成了一条**自描述的单向链**：每条消息发布时顺手为下一条埋好"链尾哨兵"。这和 fmtlog（同作者）里日志队列的手法一脉相承。

alloc 里的回绕分支同样讲究顺序：先清 `blk[0].size = 0`（新的链尾），release fence，再写 `blk[write_idx].size = 1`（发布回绕标记）。另外注意 alloc 要求 `free_write_cnt > blk_sz` 严格大于——**多留一格**，保证 `blk[write_idx + blk_sz]` 这个哨兵位永远不会越界、也不会踩到读者。

### 7.2 流控与私有配额

和 SPSCQueueOPT 一样，`write_idx`、`free_write_cnt` 是生产者私有的，`read_idx` 只在配额耗尽时通过 `volatile` 读一次，换算成新配额。消费者用 `volatile` store 发布 `read_idx`。这里用 `volatile` 而不是 atomic cast，效果相同（x86 上都是普通 mov + 阻止编译器优化），风格上更"上古"一些。

顺带一提：这个文件里 `front()` 对 `size` 的读取连 volatile 都没有，严格说消费者自旋时编译器有权把 load 提出循环。实践上因为轮询通常跨函数调用、以及 x86 的宽容，它一直工作正常——但这是四个实现里"住在 UB 边缘"最狠的一个，自己抄作业时建议至少补上 `atomic_ref` 的 acquire load。

### 7.3 crash 语义

`push()` 是两条 store + fence，进程死在中间：哨兵清了但消息没发布，这条消息永久丢失且 `free_write_cnt`（存在共享内存里的生产者私有状态）与实际不符——不 crash-safe，只用于线程间。

---

## 八、退一步：正确性的三层地基

四个实现看完，值得回头问一个更基本的问题：**两个执行流（线程或进程）凭什么能读到对方更新的索引？** 把它拆成三层回答，就能看清"同一份代码既能跑线程间、又能躺进共享内存"（3.2 节）到底靠什么——线程与进程只在第一层有区别，往下完全同构。

### 8.1 寻址层：变量为什么只有一份

进程内存"私有"的准确含义是：每个进程有自己的**页表**，默认各自的虚拟地址映射到互不相干的物理页。

| | 地址空间（页表） | 要共享一个队列对象 |
|---|---|---|
| 两个**线程** | 共用同一套页表（这正是线程的定义） | 什么都不用做——堆/全局对象天然对所有线程可见 |
| 两个**进程** | 各有一套页表 | `shm_open + mmap(MAP_SHARED)`，让 OS 把两套页表指向**同一批物理页** |

```
写进程虚拟地址空间                读进程虚拟地址空间
   0x7f3a...000 ─┐             ┌─ 0x7f81...000   ← 两边虚拟地址可以不同!
                 ▼             ▼
            ┌────────────────────────┐
            │ 同一批物理页 (内核 tmpfs) │
            │ │write_idx│…│read_idx│ │   ← 变量只有一份
            │ │data[CNT]…           │ │
            └────────────────────────┘
```

两个推论直接对应本文的设计基因：虚拟地址两边不同，所以**共享结构里绝不能有指针和虚表**；`mmap` 出来的页全零，所以"全零即合法空队列"的 POD 状态设计（3.2 节）让 attach 连初始化握手都省了。

顺带纠正一个常见误解：线程在硬件层面**没有任何私有内存**——栈和 `thread_local` 也都在共享地址空间里，拿到地址就能读写；真正私有的只有寄存器。栈的"私有"只是约定。

### 8.2 一致性层：对方的 store 怎么传到我这个核

"地址相同"不等于"更新自动可见"——两个执行流通常跑在不同核上，各核有私有 L1/L2。答案是 **MESI 缓存一致性协议**：写方 store 前必须先取得该缓存行的独占权（作废他核副本），读方下次 load 时 miss、跨核取到新值。全程硬件自动完成，软件无需也无法"手动刷缓存"。

关键在于：**MESI 按物理地址工作，根本不知道进程和线程的存在**。所以跨线程与跨进程在这一层是同一套机制——这就是 SPSCQueue 一字不改就能当 IPC 队列用的底层原因。本文反复计算的"跨核缓存行传输次数"，说的正是这一层的开销。

### 8.3 顺序层：内存序钉的是普通读写

可见性由硬件保证之后，`std::atomic` + memory_order 解决的是另外两个问题：atomic 本身保证访问不可分割、强制每次真实访存（否则编译器把自旋读优化成寄存器死循环）；而**内存序约束的不是原子变量自己，而是它前后普通读写的顺序**——索引只是"旗子"，槽位数据才是"货物"，release 是"封箱才发货"，acquire 是"签收才拆箱"。这在 4.5 节已经展开。

平台差异也源于这一层：x86 (TSO) 硬件本不做 store-store / load-load 乱序，release/acquire 只剩"管住编译器"一个作用，编译成普通 `mov`——这既是 6.3 节空 asm 屏障能零开销工作的原因，也是它换到 ARM 必挂的原因（弱内存模型下需要真屏障指令）。

---

## 九、横向对比与选型

| | SPSCQueue | SPSCQueueOPT | SPSCVarQueue | SPSCVarQueueOPT |
|---|---|---|---|---|
| 消息类型 | 定长 `T` | 定长 `T` | 变长 | 变长 |
| 消费者发现消息 | 读共享 `write_idx` | 读槽内 `avail` 标志 | 读共享 `write_idx` | 读头部 `size` 三态 |
| 关键路径缓存行传输 | 2 次 | **1 次** | 2 次 | **1 次** |
| 索引热路径开销 | 生产者侧已用 cache 消除 | 双向全部消除 | 生产者侧已消除 | 双向全部消除 |
| 可用容量 | CNT（不空格） | CNT-1（空一格） | 按 64B Block | 按 8B Block，多留一哨兵格 |
| 发布操作 | 单条 atomic store | 多步写入 | 单条 store（含屏障） | 两条 store + fence |
| 进程崩溃安全（shm IPC） | ✅ | ❌ | ✅ | ❌ |
| 同步原语风格 | atomic cast | atomic cast | 空 asm 编译器屏障 | volatile + atomic fence |

选型规则作者在 README 里已经写明，翻译成决策树就是：

1. **跨进程（共享内存 IPC）？** → 只能选左列：定长用 SPSCQueue，变长用 SPSCVarQueue。对端可能随时崩溃，crash-safe 不可妥协。
2. **同进程线程间，追求极限延迟？** → 选 OPT 版，白赚一次缓存行传输。
3. **消息大小固定且单一？** → 定长版更简单，slot 定位是纯位运算；否则用 Var 版。

### 和其他知名实现比一比

- **rigtorp::SPSCQueue / folly::ProducerConsumerQueue**：同样是 cached-index 环形队列，等价于本仓库的 SPSCQueue 层次；rigtorp 也提供 `emplace` 原地构造。但它们都没有 OPT 版的"标志内嵌数据行"设计，也不以 shm crash-safe 为目标。
- **boost::lockfree::spsc_queue**：接口是拷贝语义（`push(const T&)`），天然多一次拷贝，延迟场景不占优。
- **LMAX Disruptor**：思想同源（sequence cache、避免伪共享），但那是 Java 生态的吞吐型设计，和这里 ns 级延迟目标不同。

MengRao 这个仓库真正独特的是三件事的组合：**零拷贝两段式 API + 共享内存 crash-safe 语义 + OPT 版的单缓存行发现机制**。前两者是工程完备性，第三个是延迟数字的来源。

---

## 十、走出 SPSC：多生产者/多消费者的机制与选型

SPSC 的一切优雅都来自"每个索引只有一个写者"。一旦放开这个约束，竞争出现，设计就换了一个世界——这里补上 MPSC/MPMC 的核心机制，凑齐无锁队列的完整地图。

### 10.1 MPSC：用 exchange 串起链表

多个生产者竞争的是队尾。链表式 MPSC 的标准解法是把"抢位置"压缩成一条原子 `exchange`：

```cpp
void push(T item) {
    Node* new_node = make_node(std::move(item));

    // 原子地把自己换成新队尾，拿回前驱——竞争在这一条指令内分出胜负
    Node* prev_tail = tail.exchange(new_node, std::memory_order_acq_rel);

    // 链接可以慢慢做：没链上之前，消费者最多暂时看不到新节点
    prev_tail->next.store(new_node, std::memory_order_release);
}
```

`exchange` 无条件成功、不需要 CAS 重试循环，所以生产者侧是 wait-free 的；代价是"获得位置"与"建立链接"之间存在一个窗口，消费者要容忍 `next == nullptr` 的瞬时断链。这个思路源自 Dmitry Vyukov 的 intrusive MPSC queue。生产级实现还要解决示例里被略去的问题：热路径上的 `new` 必须换成内存池或侵入式节点，否则分配器的锁和延迟会吃掉无锁的全部收益。

### 10.2 MPMC：序列号机制

MPMC 是最难的情形：入队和出队两端都有竞争。有界数组式 MPMC 的经典答案是 [Vyukov bounded MPMC queue](https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue)——给每个槽位配一个**序列号**，用它编码槽位状态：

```cpp
struct Cell {
    std::atomic<size_t> sequence;   // 与 enqueue/dequeue 位置的差值编码槽位状态
    T data;
};

bool push(T item) {
    size_t pos = enqueue_pos.load(std::memory_order_relaxed);
    for (;;) {
        Cell* cell = &buffer[pos & mask];
        size_t seq = cell->sequence.load(std::memory_order_acquire);
        intptr_t diff = (intptr_t)seq - (intptr_t)pos;

        if (diff == 0) {            // 槽位空闲，尝试占位
            if (enqueue_pos.compare_exchange_weak(pos, pos + 1,
                                                  std::memory_order_relaxed))
                break;
        } else if (diff < 0) {
            return false;           // 转了一整圈还没被消费——队列满
        } else {
            pos = enqueue_pos.load(std::memory_order_relaxed);  // 被人抢先，重读
        }
    }
    cell->data = std::move(item);
    cell->sequence.store(pos + 1, std::memory_order_release);   // 发布：可消费
    return true;
}
```

妙处有三：**状态编码**——`seq - pos` 的符号与零值区分"可写/可读/满"，槽位状态自描述，无需全局标志；**天然免疫 ABA**——序列号单调递增，绕一圈回来数值不同；**竞争分散**——CAS 只争位置计数器，数据读写各自落在不同槽位上。对比 SPSC：这里每次操作至少一次 CAS（失败还要重试），加上双端竞争的缓存行 ping-pong，延迟通常比 SPSC 高一个数量级。

### 10.3 选型：先问结构，再谈实现

```
只有一个生产者？
├── 是 → 只有一个消费者？
│   ├── 是 → SPSC ✓（本文全部内容）
│   └── 否 → SPMC / 广播（见第二节）
└── 否 → 只有一个消费者？
    ├── 是 → MPSC ✓（日志收集、事件汇聚）
    └── 否 → MPMC ✓（通用任务池）
```

| | 同步复杂度 | 典型延迟量级 | 典型场景 |
|---|---|---|---|
| SPSC | 无竞争，纯 load/store | 数十 ns | 流水线相邻两级（网络线程→策略线程） |
| MPSC | 生产端一条 exchange | 约百 ns | 多线程日志、多源事件汇聚 |
| MPMC | 双端 CAS + 重试 | 数百 ns | 线程池任务队列 |

但决策树之外有一条更重要的工程经验：**能拆成 SPSC 就不要上 MPSC/MPMC**。很多"多生产者"需求可以改造成 N 条 SPSC + 消费者轮询（sharding），彻底消灭竞争，延迟和可预测性都更好——低延迟系统里，改结构永远优先于换更强的队列。确实需要通用 MPMC 时，生产可用的现成选择是 [moodycamel::ConcurrentQueue](https://github.com/cameron314/concurrentqueue)。

> **延伸阅读**：各类同步原语（mutex/spinlock/RMW 原子操作）的硬件成本全景，以及 Seqlock、RCU 等更进一步的无锁技巧：[并发原语深度剖析]({{< ref "2026-03-03-mutext" >}})

---

## 十一、抄作业前的注意事项

如果想把这套代码搬进自己的系统，有几个 2018 年遗产需要现代化：

1. **x86-only**。空 asm 屏障和"普通变量 + 编译器屏障"的组合依赖 TSO，ARM（如 Graviton、Apple Silicon）上会真实乱序。移植时把所有跨线程变量访问换成 `std::atomic_ref` 的 release/acquire，x86 上生成的代码不变，ARM 上自动获得正确屏障。
2. **atomic 强转是 UB**。C++20 起用 `std::atomic_ref` 获得同样的"所有者线程零约束 + 交接点原子语义"，且完全合法。
3. **VarQueueOPT 的 `front()` 缺 acquire**，自旋场景理论上可能被编译器优化坏，补上再用。
4. **容量必须 2 的幂**（前三个实现有 static_assert 兜底），且 OPT 版实际容量是 CNT-1。
5. 想复现 README 的 50–100ns，**绑核是前提**：test 代码把收发线程 pin 在同一 NUMA 节点的两个核上，并用 rdtsc 打点测量。跨 NUMA 节点时缓存行传输要走 UPI，数字会明显变差。

---

## 十二、总结

这个不到 600 行的仓库值得精读，因为它把 SPSC 队列的延迟优化讲成了一个层层递进的故事：

1. **第 0 层**：环形缓冲 + release/acquire 索引交接——正确性的地板；
2. **第 1 层**：cached index / 本地配额——把"读对方索引"从热路径上摘掉，消灭稳态下的索引行 ping-pong；
3. **第 2 层**：alignas(128) 分组——每条共享行唯一写方，连预取器粒度的伪共享都躲开;
4. **第 3 层（点睛）**：把发布标志内嵌进数据所在的缓存行——新消息的"发现"与"读取"合并为一次跨核传输，这是 50ns 数字的直接来源；
5. **贯穿始终**：零拷贝 API、全零即合法的 POD 状态、单 store 发布带来的 crash-safe——决定了它能不能安全地躺进共享内存。

跨核通信的延迟下限不由代码行数决定，而由**缓存一致性协议的消息往返次数**决定。四个实现就是在"传输次数"和"状态机原子性"之间做的四次不同定价——看懂了这张定价表，教科书上的环形队列和生产级 50ns 队列之间的距离，也就量化清楚了。

再放大一层看：SPSC 与广播的分野（第二节）由"读者状态放哪里"决定，SPSC 与 MPSC/MPMC 的分野（第十节）由"每个索引有几个写者"决定。选队列先选对这两个结构问题，再谈实现——结构选对了，剩下的才是本文这些 ns 级的功夫。
