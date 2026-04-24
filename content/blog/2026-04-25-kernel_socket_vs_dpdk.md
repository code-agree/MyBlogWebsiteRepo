+++
title = 'kernel socket vs DPDK：一条 WebSocket 帧的两段旅程与纳秒级实测'
date = 2026-04-25T00:00:00+08:00
draft = false
tags = ["Network", "HFT", "Performance", "Linux"]
+++

*— 一条 180 字节的 TLS 帧，从网卡到用户回调，在两条路径上分别要走多久？走哪些步骤？为什么差 3-10 倍？*

---

## 0. TL;DR

本文做三件事：

1. **走一遍 kernel socket 收包路径**——9 步，每步做什么，花多少纳秒
2. **走一遍 DPDK + F-Stack + BIO_s_mem 路径**——5 步，每步的用户态替代品
3. **用真实项目数据（FlashShark-ws，AWS EC2 VM，60 s，n=26 835）**对比两条路径的差距，**包括一组真 A/B 对照**（M0 kernel 9.6 µs vs M7 DPDK 2.8 µs 的 TLS 解密段）

**最硬的两个数**：

- 一条 180 B 的 Binance bookTicker 帧在 DPDK 路径上 e2e **p50 = 5.3 µs、min = 1.1 µs**
- 同样的 TLS 解密工作，kernel socket + OpenSSL `BIO_s_socket` 路径 p50 ≈ 9.6 µs，DPDK + `BIO_s_mem` 路径 p50 = 2.8 µs——**同一台机器下** `BIO_s_mem` 旁路 syscall 直接把 TLS 段 p50 降了 59 %

**DPDK 的代价**（必须认清）：

- 1 个 CPU 核永久 100 % 占用（轮询代价）
- 独占一张网卡，丢失 `iptables` 过滤、`ss -tnp` 观察、多进程共享 socket 的能力
- 部署门槛：hugepage 预分配、`igb_uio` / `vfio-pci` 抢卡、`isolcpus + nohz_full` 配核

---

## 一、一条包在 kernel socket 路径上怎么走

### 1. 路径总览

{{< mermaid >}}
flowchart LR
    NIC["NIC<br/>(hardware)"] -->|DMA| A1["RX ring<br/>(kernel memory)"]
    A1 -->|MSI-X| A2["IRQ entry<br/>⚡ring 3→0"]
    A2 --> A3["softirq<br/>NET_RX"]
    A3 --> A4["tcp_v4_rcv<br/>(protocol stack)"]
    A4 --> A5["sk_receive_queue<br/>+ epoll wake"]
    A5 -->|"⚡ring 0→3"| A6["epoll_wait<br/>returns"]
    A6 -->|"read(2)<br/>⚡ring 3→0→3"| A7["copy_to_user<br/>→ user buffer"]
    A7 -->|"SSL_read may<br/>read(2) again"| A8["AES-GCM decrypt<br/>(OpenSSL)"]
    A8 --> A9["user handler"]

    classDef boundary fill:#ffe5e5,stroke:#c62828,color:#000
    classDef userland fill:#e8f5e9,stroke:#2e7d32,color:#000
    classDef kernbuf fill:#fff3e0,stroke:#ef6c00,color:#000
    classDef nic fill:#eceff1,stroke:#37474f,color:#000
    class A2,A3,A4,A5,A6,A7 boundary
    class A1 kernbuf
    class A8,A9 userland
    class NIC nic
{{< /mermaid >}}

红色方框 = 内核态执行，绿色 = 用户态，每次跨色必有一次 ring 切换。一包走完**至少 4 次跨 ring**（IRQ 入、epoll 唤醒、read 入、read 出），TLS 补字节时更多。

### 2. 9 步详细拆解

下表是每步在做什么、每步的典型耗时。小帧（180 B）+ VM 环境，裸金属上会更快：

| # | 层 | 事件 | 耗时量级 |
|---|-----|------|---------|
| 1 | NIC | 帧到达，DMA 进 RX ring（kernel 启动时给 NIC 注册的 DMA buffer）| DMA，无 CPU |
| 2 | NIC → CPU | NIC 发 MSI-X 中断；ENA 默认 DIM（动态中断节流）可能把 IRQ 拉到 ~20 µs 间隔 | IRQ 延迟 1-5 µs，DIM 节流时更高 |
| 3 | CPU ISR | `ena_intr_msix_io` 保存寄存器、切换栈、调度 NAPI poll | ~1 µs |
| 4 | softirq | `NET_RX_SOFTIRQ` 执行 NAPI poll：从 RX ring 取描述符，`build_skb` 在预分配的 DMA buffer 外套一个 `sk_buff` 头（~256 B 控制结构）| skb 头分配 100-200 ns/包 |
| 5 | 协议栈 | `__netif_receive_skb_core` → `ip_rcv` → `tcp_v4_rcv` → `tcp_v4_do_rcv`：协议解复用 + TCP 状态机 + 可能的 LRO/GRO 合并 | 1-3 µs 纯 CPU |
| 6 | socket | `tcp_rcv_established` 把 skb 挂 `sk->sk_receive_queue`；`sock_def_readable` 唤醒 epoll waiter | 入队 ~100 ns + 唤醒 500 ns-1 µs |
| 7 | epoll | `ep_poll_callback` 被唤醒；阻塞在 `epoll_wait` 的 task 放回 runqueue | 500 ns-1 µs |
| 8 | syscall | 用户调 `read(2)` / `recvmsg(2)`：`tcp_recvmsg` → `skb_copy_datagram_iter` → `copy_to_user`（SMAP 切换 + KPTI 页表切换）| syscall 往返 200-500 ns + `copy_to_user` 20 ns（180 B） |
| 9 | OpenSSL | 若用 TLS，`SSL_read` 通过 `BIO_s_socket` 调 `read(2)` 拉加密字节——**第二次 syscall**；然后 AES-GCM 解密 | 又一次 syscall + 硬解 100-200 ns |

**典型 e2e（小帧，VM）**：p50 15-25 µs，p99.9 100-300 µs。这个数是基于公开 kernel socket benchmark 的估算，**本文没有同机 asio 实测基线**（§6 会单独给一组 M0 TLS 段的真实对照数据）。

### 3. 两个被低估的成本

**成本 1：TLS record 跨 TCP segment 时的 syscall 风暴**

OpenSSL 的 `SSL_read` 对 TLS record 有内部缓冲，不是每次调用都触发 syscall；但**内部缓冲耗尽需要补加密字节时**，`BIO_s_socket` 会调 `read(2)`。更糟的是 **TLS record 跨 TCP segment**：一个 16 KB record 在 MSS=1448 的链路上最坏要 **12 次 `read(2)`** 才能凑齐。每次都是 200-500 ns syscall + KPTI 切页表，还可能被其他 softirq 抢占。

这是 DPDK + `BIO_s_mem` 彻底消掉的那个东西（§6 的 A/B 对照就量化了这部分）。

**成本 2：抖动源不可枚举**

下表列出 kernel 路径**每包 p50 之外还可能发生的事**——任何一条触发都会把这包延迟抬到尾部：

| 抖动源 | 发生条件 | 量级 |
|---|---|---|
| 同 CPU 其他 softirq（timer / block / NET_TX）串行化 | 高并发 | 10-100 µs |
| NAPI poll budget 耗尽（一轮最多 64 包）| 高速率 | 10-50 µs |
| GRO 聚合等待 flush | LRO/GRO 开启 | 10-100 µs |
| 进程被 RT 或其他 runnable task 抢占 | 系统有其他负载 | 数百 µs |
| `copy_to_user` 缺页 / KPTI 额外成本 | Meltdown 缓解开启 | 100-500 ns |
| NUMA 错位（skb 在 NIC 所在 node，reader 在另一 node）| 多 socket 机器 | 100 ns-几 µs |

注意这张表**没有穷尽**——kernel 路径最坏情况是"整个内核正在发生的事的并集"，不可枚举。这直接决定了 p99.9 的不可控性（§8 回到这个话题）。

---

## 二、一条包在 DPDK + F-Stack + BIO_s_mem 路径上怎么走

### 4. 路径总览

{{< mermaid >}}
flowchart LR
    NIC["NIC<br/>(hardware)"] -->|DMA to hugepage| B1["RX ring<br/>(user-accessible)"]
    B1 -->|rte_eth_rx_burst| B2["PMD poll<br/>on lcore 1"]
    B2 --> B3["F-Stack<br/>tcp_input"]
    B3 --> B4["ff_epoll<br/>+ dispatch"]
    B4 -->|ff_read| B5["app buffer<br/>(user memory)"]
    B5 -->|BIO_write| B6["SSL_read<br/>(AES-NI)"]
    B6 --> B7["user handler"]

    classDef userland fill:#e8f5e9,stroke:#2e7d32,color:#000
    classDef nic fill:#eceff1,stroke:#37474f,color:#000
    class B1,B2,B3,B4,B5,B6,B7 userland
    class NIC nic
{{< /mermaid >}}

全绿——除了 NIC 本身，**整条路径都在用户态（ring 3）**，没有任何 ring 切换、没有 syscall、没有 IRQ。

### 5. 5 步详细拆解

| # | 层 | 事件 | 耗时量级 |
|---|-----|------|---------|
| 1 | NIC | 帧到达，DMA 进 **hugepage 里的 RX ring**（启动时通过 `rte_eth_rx_queue_setup` 注册给 NIC 的 DMA 引擎）| DMA，无 CPU |
| 2 | PMD on lcore | lcore 1 在 busy loop 里持续调 `rte_eth_rx_burst(port, queue, pkts, 32)`。PMD 读 RX 描述符的 "own bit"，有新包则返回预分配好的 mbuf 指针数组 | `rx_burst` 空转 ~50 ns/call；命中时 ~30-50 ns/包 |
| 3 | F-Stack | `ff_veth_input` → `ether_input` → `ip_input` → `tcp_input`（**FreeBSD TCP 栈源码移植为库**）。TCP 段入 socket 的 `so_rcv` 队列，socket 标记可读，事件挂 `ff_epoll` ready list | 100-300 ns，**全部在同一用户线程里**，无上下文切换 |
| 4 | EventTable | `ff_run` 每轮末尾检查 `ff_epoll`；事件按 fd 从用户维护的回调表分派到 `TcpSocket::on_event` | 函数指针跳转 ~5-10 ns |
| 5 | 应用层 | `TcpSocket::on_event` 调 `ff_read(fd, buf, n)` 把字节拷到 app buffer；`TlsLayer::on_tcp_data(buf, n)` 用 `BIO_write` 塞进 OpenSSL 的内存 BIO；`SSL_read` 拉明文，AES-128-GCM 硬解；Parser 解 WS 头；user handler | `ff_read` ~50-100 ns + TLS 工作（见 §6 数据） |

**典型 e2e（小帧，VM）**：p50 5 µs，min 1 µs——§6 给完整数据。

### 6. 为什么能做到：三次解绑

kernel 路径慢不是实现不优秀，是**三条架构前提**把它锁住了：
- NIC 由 kernel 驱动持有（用户进程无权直接发 MMIO）
- TCP 栈是多进程共享资源（必须在 kernel 里统一管理）
- ring 3/0 是 CPU 硬件保护边界（跨 ring 必经 syscall + 页表切换 + 拷贝）

DPDK 系方案**逐条解绑**：

**解绑 1：把网卡从 kernel 手里抢走**

用 `igb_uio` 或 `vfio-pci` 把网卡从 kernel 驱动 unbind，重新绑到一个 stub 驱动，stub 把 BAR 空间 mmap 进用户进程。用户代码从此能直接读 RX descriptor ring、写 TX descriptor ring——NIC 不再是 "kernel 的"，它变成这个用户进程的外设。**代价**：这张卡被独占，其他进程和 kernel 都没法用。

**解绑 2：把 TCP 栈搬进用户进程**

kernel 的 TCP 不能搬（它是共享的）——但 **FreeBSD 的 TCP 源码可以被移植成库**（F-Stack 就是这条路）。完整的 FreeBSD TCP 状态机、socket buffer、sysctl 编译成一个 C 静态库链进应用。从此 `tcp_input` 是一次普通函数调用，跟用户的 `parser::feed` 在同一调用栈上跑。（另一类如 Seastar / mTCP / onload 是"重写一套用户态 TCP"，本质相同。）**代价**：丢掉 `ss -tnp` 观察、iptables 过滤、多进程共享 socket。

**解绑 3：让 OpenSSL 不走 socket fd**

默认的 `BIO_s_socket` 会调 `read(2)` 从 socket fd 拿密文——但我们没有 kernel socket（F-Stack 的 socket 是 `ff_socket`，不是 Linux fd）。改用 `BIO_s_mem`：`BIO_write(rbio, encrypted_bytes, n)` 把 F-Stack 吐出来的密文**手动塞进**内存 BIO，`SSL_read` 从这块内存 BIO 拿字节。**整条路径 0 syscall**。**代价**：TLS 收字节变成手动的几行 pump 代码。

### 7. 架构的代价

| 代价 | 原因 |
|---|---|
| 1 个 CPU 核永久 100 % | PMD busy poll 不能停 |
| 独占网卡 | igb_uio/vfio-pci 抢卡后 kernel 看不到 |
| 无 iptables / ss / conntrack | 协议栈在用户态，绕过所有 kernel 网络工具链 |
| 部署门槛 | hugepage 预留、驱动加载、isolcpus + nohz_full 配核、F-Stack 配置 |
| TCP 调参自担 | F-Stack 就是 FreeBSD 源码，sysctl 你自己调 |

这套代价对 HFT / 金融实时场景完全值，对通用 web 后端几乎一定不值（§10 给场景对照）。

---

## 三、差距在哪，实测多少

### 8. 单包延迟：5 段 pipeline 拆解

**环境与样本**：

| 项 | 值 |
|---|---|
| 机器 | AWS EC2，2 vCPU VM |
| OS | Debian 12，kernel 6.1 |
| 网卡 | ENA（AWS 弹性网络适配器）|
| Hugo | hugepage 预分配，DPDK 23.11 |
| TCP 栈 | F-Stack v1.24（FreeBSD 11 TCP 源码移植）|
| TLS | OpenSSL 3，AES-128-GCM（AES-NI + PCLMULQDQ 加速）|
| 连接 | 单条 wss://fstream.binance.com:443 |
| 流 | bookTicker，~180 B/帧，~447 帧/s（USDⓈ-M Futures）|
| 采样窗口 | 60 s |
| 样本数 | **n = 26 835** |
| 打点方式 | 5 个 `__rdtsc` 时间戳，HdrHistogram_c 聚合 |

**5 个打点**：

- **T0**：`TcpSocket::on_event` 进入
- **T1**：`TlsLayer::on_tcp_data` 入口
- **T2**：`SSL_read` 返回明文
- **T3**：Parser emit Frame
- **T4**：`Client::on_frame` 调用 user handler 前

**实测数据**：

| 段 | T(i)→T(i+1) | min | p50 | p99.9 | 做什么 |
|---|---|---|---|---|---|
| tcp_to_tls | T0→T1 | 142 ns | **302 ns** | 8.3 µs | `ff_read` 拷字节 + 函数指针跳转 |
| tls_decrypt | T1→T2 | 888 ns | **2 757 ns** | 31.9 µs | `BIO_write` + `SSL_read` + AES-GCM 解密 + GHASH |
| parser | T2→T3 | 20 ns | **888 ns** | 18.6 µs | `Parser::feed` 解 WS 头 + 构造 `Frame` |
| handler | T3→T4 | 9 ns | **9 ns** | 0.11 µs | 两次 `__rdtsc` + 一次函数调用 |
| **e2e** | **T0→T4** | **1 099 ns** | **5 278 ns** | **39.9 µs** | 上面四段相加 |

**架构正确性的三个证据**：

1. **e2e min = 1 099 ns ≈ 各段 min 之和（1 059 ns）**，差 40 ns——说明**没有隐藏的 allocator、GC 或 schedule 成本**，整条流水线就是这五段线性串起来
2. **parser min = 20 ns ≈ 同一 Parser 的 microbench p50（28 ns）**——证明 fast-path 在真实 e2e 路径里**仍然触发**，没有被环境拖慢
3. **handler min = 9 ns = 两次 `__rdtsc` 的成本**——说明用户回调路径真的就是"两次时间戳 + 一次函数调用"，没有 vtable、没有堆分配

**解读 p50 的占比**：

```
e2e p50 = 5 278 ns 里
  tcp_to_tls  302 ns   (5.7%)
  tls_decrypt 2 757 ns (52.2%)  ← 瓶颈
  parser      888 ns   (16.8%)
  handler     9 ns     (0.2%)
  [路径汇合损耗  1 322 ns  (25.0%)]
```

**TLS 解密占一半——这是当前瓶颈**。其中 AES-NI + GHASH 合计只占 ~300 ns（11 %），剩下 2.4 µs 是 OpenSSL 的状态机开销（record 解帧、分支、虚分派）+ `BIO_write`/`SSL_read` 两次 memcpy + 函数调用链。这是后续优化（BoringSSL / wolfSSL）能动的部分。

### 9. syscall 旁路的 A/B：M0 kernel vs M7 DPDK

§8 的数据证明了"DPDK 路径做到了 X 微秒"，但没证明"**同样的 TLS 工作量在 kernel 路径上是多少**"——这种对比才有说服力。

项目开发过程中有一组**同机对照**数据（M0 测评阶段 vs M7 集成阶段），两者用完全一样的 TLS 配置（OpenSSL 3，AES-128-GCM，同一 session），区别只有 **数据进 OpenSSL 的方式**：

| 阶段 | 路径 | TLS 解密段 p50 | p99.9 |
|---|---|---|---|
| **M0** | kernel socket + `read(2)` + `BIO_s_socket` | **9.6 µs** | 61.7 µs |
| **M7** | DPDK + F-Stack + `BIO_s_mem`（本文主架构） | **2.76 µs** | 31.9 µs |
| **变化** | | **−59 %** | **−48 %** |

**这 59 % 的 p50 下降来自哪里？**

拆开来看：
- `BIO_s_socket` 每次缺字节触发一次 `read(2)`——syscall 入/出 + `copy_to_user`，典型 300-500 ns/次
- 一个 180 B 的 TLS record 在单个 TCP 段内，通常 1 次 syscall 凑齐；但有时需要 2-3 次
- `BIO_s_mem` 把这个 syscall 彻底消掉——字节已经在用户态了，`BIO_write` 是纯 memcpy
- 剩下的差距（~6 µs 减到 ~3 µs 还有一半）来自 kernel 路径上的**其他开销**：skb 控制结构拷贝、`copy_to_user` SMAP/KPTI 切页表、L1 cache 被内核代码污染

**这是文章里最硬的一组对照数据**——不是估算、不是公开 benchmark，是同一台机器、同一个 TLS 库、同一个 session 的两阶段实测。

### 10. 尾部确定性：为什么 p99.9/p50 = 7.5×

kernel 路径的"尾部不可枚举"（§3 成本 2）是它的原罪。DPDK 路径尾部源**可枚举**——只剩 cache miss 和 hypervisor 注入，能精确预估。

看本项目数据：

| 段 | p50 | p99.9 | p99.9/p50 |
|---|---|---|---|
| tcp_to_tls | 302 ns | 8.3 µs | 27× |
| tls_decrypt | 2.76 µs | 31.9 µs | 11.5× |
| parser | 888 ns | 18.6 µs | 21× |
| handler | 9 ns | 0.11 µs | 12× |
| **e2e** | 5.3 µs | **39.9 µs** | **7.5×** |

**关键观察**：所有段的 p99.9/p50 比值都在 10-20×——这是 VM 抖动的 **fingerprint**。每段被 hypervisor 摊到差不多的比例，**不是某一段代码慢**。

**怎么知道是 hypervisor 不是代码**？

- VM 上无法 mask timer interrupt（hypervisor 强注入）
- 邻居 vCPU 抢物理核时 isolcpus 也拦不住（只能隔离 guest 内）
- vhost-net 的 kthread 调度每包都介入

裸金属上这三条全部可消（`nohz_full` + `isolcpus` + 物理 IRQ affinity），预期 p99.9/p50 降到 3-5×，e2e p99.9 从 39.9 µs 降到 **5-10 µs**。

**对 kernel 路径来说**，即使在裸金属上，尾部也是 IRQ 抢占 + softirq 串行化 + 调度延迟的合集，不可能压到同一水平——这是 hard real-time SLA 只能选 DPDK 的原因。

### 11. 机制能推出但本项目没测的

坦诚：本项目场景是**单连接 + 单 lcore + HFT**，下面这些维度机制上能推，但没做针对性实验——给读者几句 context，不装有数据。

**吞吐量 PPS（单核）**

- kernel 单核瓶颈在**串联**：IRQ 率 ~1 Mirq/s、skb 分配率 ~5-10 M/s、syscall 率 ~5 M/s——哪条先顶哪条就是上限，典型 **1-3 Mpps**
- DPDK 单核 PMD + F-Stack 做过公开 benchmark 到 **10-14 Mpps**（纯计算上限 + batch 处理）
- 本项目跑 447 fps，**远未触及任一方天花板**——说明在 pps 层面本项目不是瓶颈型场景

**CPU cycle 效率（每包 cycles）**

- kernel 路径典型 **5 000-15 000 cyc/pkt**（IRQ 入出 + skb 处理 + syscall + copy_to_user + cache 污染）
- DPDK 路径典型 **500-1 500 cyc/pkt**（纯业务工作）
- 本项目没采 perf counter，这个数据来自 Intel DPDK 白皮书和 Cloudflare / Facebook 公开 benchmark

**多核扩展性**

- kernel 路径亚线性：全局 conntrack 表、routing cache、rfs/rps 锁在多核下导致 cache line bouncing 和锁竞争
- DPDK shared-nothing lcore 模型：每核一条 RSS 队列，核间零共享，近线性
- 典型：16 核时 kernel 拿到 5-8 倍 pps，DPDK 拿到 ~15 倍
- 本项目单 lcore，**本维度完全不涉及**

---

## 四、什么时候该用哪条路径

不是抽象问题——看场景特征：

| 场景 | 推荐 | 理由 |
|---|---|---|
| **HFT / 金融实时交易** | DPDK + F-Stack + BIO_s_mem | min / p50 / p99.9 三端都吃到，几 µs 反应时间直接换盈利 |
| **高 pps 网关 / L4-L7 代理** | AF_XDP / XDP 或 DPDK-L2 | 只需要 pps + cycle 效率，不用全套 L7 协议栈，工程代价低得多 |
| **高连接数 web 服务 / API 后端** | kernel socket + epoll / asio / io_uring | 连接数万-千万量级，单位连接流量低，能容忍 50-100 µs 尾部——DPDK 反而浪费核 |
| **低连接数 + 延迟敏感但非极致** | kernel socket + io_uring / SO_BUSY_POLL | 拿到 20-40 % 的 p50 改善，不付 DPDK 的运维代价 |
| **边缘 DDoS 防护 / 过滤** | XDP | 协议栈前拦截，不 attach L7 |

**底线**：DPDK 不是银弹。它拿 "1 核 100 % + 独占网卡 + 复杂部署 + 自担 TCP 调优" 换 "**架构天花板的延迟下限 + 确定性尾部**"。前四者是日常代价，后者是别的路径技术上做不到的东西——只有需要这个"做不到的东西"时才值。

---

## 5. 延伸阅读

**DPDK / 用户态网络栈**

- [DPDK Programmer's Guide — Poll Mode Driver](https://doc.dpdk.org/guides/prog_guide/poll_mode_drv.html)
- [F-Stack](https://github.com/F-Stack/f-stack) — 腾讯开源，FreeBSD TCP 栈用户态库
- [Seastar](https://seastar.io/)、[mTCP](https://github.com/mtcp-stack/mtcp) — 另一类用户态 TCP 路线

**Linux 内核网络路径**

- 内核源码：`net/core/dev.c`（NAPI）、`net/ipv4/tcp_input.c`（TCP 入栈）、`net/core/skbuff.c`（skb 分配）
- [The Journey of a Packet Through the Linux Network Stack](https://wiki.linuxfoundation.org/networking/kernel_flow)
- [Understanding NAPI](https://wiki.linuxfoundation.org/networking/napi)

**OpenSSL BIO**

- [OpenSSL BIO 手册](https://www.openssl.org/docs/man3.0/man7/bio.html)
- [BIO_s_mem 用法](https://www.openssl.org/docs/man3.0/man3/BIO_s_mem.html)

**延迟测量**

- [HdrHistogram_c](https://github.com/HdrHistogram/HdrHistogram_c) — 本项目用的直方图库
- [hdr-plot](https://github.com/BrunoBonacci/hdr-plot) — 可视化

**公开 benchmark**

- [Cloudflare 的 kernel bypass 评估](https://blog.cloudflare.com/kernel-bypass/)
- [Linux 网络性能优化的几个层次](https://lwn.net/Articles/629155/) — LWN 系列

**本站相关**

- {{< ref "2026-03-17-net_proc" >}} — 网卡中断与多队列架构排查实录
- {{< ref "2026-03-30-cpu_bindcore" >}} — 核心隔离与 IRQ 亲和性
- {{< ref "2025-07-05-dpdk_application" >}} — DPDK 应用层落地
- {{< ref "2025-07-21-hugepage_indpdk" >}} — hugepage 在 DPDK 里的作用
- {{< ref "2025-07-09-asio" >}} — asio 在 Linux 上的 I/O 模型本质
- {{< ref "2026-04-17-iceoryx_ipc_benchmark" >}} — 同风格的 HFT 纳秒级选型分析

---

*发布时间：2026-04-25；CC BY 4.0，转载请署名并保留链接。欢迎讨论和指正。*
