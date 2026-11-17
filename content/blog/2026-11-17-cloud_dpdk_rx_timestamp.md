+++
title = '云环境下 DPDK 收包路径中的时间可观测性缺口'
date = 2026-11-17T16:30:00+08:00
draft = false
tags = ["HFT", "Network", "Performance", "Linux"]
+++


### 背景

延迟测量的本质是在事件链上放置两个时间戳，然后求差。对于网络收包，理想的事件链是：

```
数据包到达网卡 → MAC 层接收 → 软件可见 → 协议栈处理 → 应用消费
```

每个箭头都是延迟的一部分。你能放置时间戳的位置越早，能观测到的延迟分量就越多。

在物理网卡上，这个问题有标准解法：**IEEE 1588 / PTP 硬件时间戳**。网卡在 MAC 层收到帧的瞬间，由硬件电路写入时间戳。DPDK 对此有完整的 API：`rte_mbuf.timestamp`、`PKT_RX_TIMESTAMP`、`rte_eth_read_clock()`。在 Intel、Mellanox 等物理网卡上，这条路径是通的。

**但在云上，网卡是虚拟的，这条路径断了。**

我们在 AWS 上运行低延迟行情接收服务，需要对收包路径做逐包级别的延迟分解。在这个过程中，我们发现了 DPDK 架构中一个结构性的可观测性缺口——并不得不用一个 PMD 驱动层面的 patch 来填补它。这篇文章记录问题的来龙去脉和我们的做法。

---

### 问题

#### 虚拟网卡没有"到达"的概念

Virtio 和 AWS ENA 是两种典型的虚拟/半虚拟网络设备。它们的收包机制与物理网卡有根本区别：

| | 物理网卡 | virtio / ENA |
|--|---------|-------------|
| 数据来源 | 线缆上的电信号 | Hypervisor 写入共享内存 |
| "到达"的含义 | 帧到达 MAC 层 | Host 侧将 descriptor 放入 used ring / CQ |
| 硬件时间戳 | ✅ 由网卡电路打入 | ❌ 没有对应硬件 |
| `rte_eth_read_clock()` | ✅ 读网卡本地时钟 | ❌ 未实现 |

虚拟网卡的"到达"不是一个物理事件，而是一次内存写入。Host 侧的 vhost/Nitro 进程将包数据拷贝到 Guest 的共享内存区，然后更新 used ring 或 completion queue 的指针。Guest 侧的 PMD 驱动在下一次 poll 时读到这个变化。

**这是 Guest 内软件能感知到的最早时刻。但 DPDK 不会在这个时刻打时间戳。**

#### `rte_eth_rx_burst()` 是一个刻意的黑盒

DPDK 的收包 API 只有一个函数签名：

```c
uint16_t rte_eth_rx_burst(uint16_t port_id, uint16_t queue_id,
                          struct rte_mbuf **rx_pkts, uint16_t nb_pkts);
```

语义很简单：给我最多 `nb_pkts` 个包，返回实际拿到的数量。调用者不需要知道、也无法知道：包是在这次 poll 中首次出现在 used ring 里的，还是上次 poll 就在了但没取完；burst 内部处理了多长时间；各个包在 burst 内部是按什么顺序从 descriptor ring 中摘取的。

这个黑盒抽象是有意为之。DPDK 支持几十种网卡驱动，每种驱动的内部实现差异极大（split ring / packed ring / completion queue；scalar / vector / NEON 路径；mergeable / non-mergeable buffer）。统一的 API 契约必须足够简单，才能让上层代码不依赖任何驱动特定的行为。

**代价是：burst 内部的时间维度信息被彻底抹掉了。**

应用层能做的最早打点，是在 `rte_eth_rx_burst()` 返回之后。DPDK 提供了 `rte_eth_add_rx_callback()` 机制，允许注册回调函数在 burst 返回后执行。但这个回调拿到的时间戳（`rx_tsc`），包含了 burst 内部所有处理的耗时：

```
PMD 首次读到 used ring ──┐
   descriptor 解析        │
   mbuf 构建              ├── 全部被压进 rx_tsc
   scatter-gather 合并    │
   ring refill            │
   burst 返回 ───────────┘
   RxCallback: rx_tsc = rdtscp()
```

对于一个 burst 32 个包、其中有 mergeable buffer 需要多段拼接的场景，这段被压在一起的时间可以到微秒量级。而在低延迟行情接收中，微秒就是你要测量的信号本身。

#### 在 AWS 上，不存在替代方案

| 替代方案 | 在 AWS 上可行？ | 说明 |
|---------|---------------|------|
| IEEE 1588 / PTP 硬件时间戳 | ❌ | ENA / Nitro 未实现 |
| `rte_eth_read_clock()` | ❌ | ENA 驱动未实现 |
| `rx_timestamp` mbuf offload | ❌ | 需要硬件支持 |
| eBPF / XDP 时间戳 | ❌ | 绕过了用户态协议栈，不兼容 F-Stack 架构 |
| burst 返回后立即打 TSC | ✅ 但不够 | 就是 `rx_tsc`，无法分解 PMD 内部耗时 |

关键点：**无论用 VM 还是 bare metal（*.metal），AWS 上的网络接口都是 ENA**。Bare metal 只是消除了 hypervisor 的调度抖动，底层网卡仍然是 Nitro/ENA，仍然没有硬件时间戳。

---

### 方案

#### 在 PMD 收包路径最早可见处注入 TSC

做法在概念上很简单：在 PMD 驱动内部、`virtqueue_nused()` 或 CQ phase 检查返回"有新包"的那一刻，立即读一次 TSC，写入 mbuf 的动态字段。

实现利用 DPDK 的 `rte_mbuf_dynfield` 机制（19.11 引入），在 mbuf 中注册一个 8 字节字段存储这个时间戳（`pmd_tsc`）。

以 virtio split-ring mergeable 路径为例，打点位置是：

```c
// virtio_rxtx.c — virtio_recv_mergeable_pkts()

nb_used = virtqueue_nused(vq);         // acquire barrier, 读 used ring
observe_cons_idx = vq->vq_used_cons_idx;
pmd_observe_snapshot(vq, nb_used,      // ← 在这里打 pmd_tsc
    observe_cons_idx);

// ... 后续才是 descriptor 解析、mbuf 构建、merge 处理
```

`snapshot` 函数的核心逻辑：

```c
static inline void
pmd_observe_snapshot(struct virtqueue *vq,
        uint16_t nb_used, uint16_t used_cons_idx)
{
    uint64_t observe_tsc;
    uint16_t i;

    if (nb_used == 0 || !pmd_observe_active)
        return;

    // lfence; rdtscp; lfence — 完全有序的 TSC 读取
    observe_tsc = pmd_observe_ordered_tsc();

    for (i = 0; i < nb_used; i++) {
        const uint16_t ring_idx = (used_cons_idx + i) &
            (vq->vq_nentries - 1);
        const uint16_t desc_idx = (uint16_t)
            vq->vq_split.ring.used->ring[ring_idx].id;
        struct rte_mbuf *mbuf = vq->vq_descx[desc_idx].cookie;
        uint64_t *field;

        if (mbuf == NULL)
            continue;
        field = pmd_observe_field(mbuf);
        if (*field == 0)        // 仅首次写入，不覆盖更早的观测
            *field = observe_tsc;
    }
}
```

ENA 驱动的做法类似，切入点是 completion queue 的 phase bit 翻转检查。

#### 获得 `pmd_tsc` 之后，延迟分解变为可能

```
pmd_tsc ───────────────── rx_tsc ───────────── 应用处理完成
   │                         │                      │
   └── PMD 内部处理耗时 ─────┘── 协议栈 + 回调开销 ─┘
       (descriptor 解析,           (TCP/IP 处理,
        mbuf 构建,                  TLS 解密,
        scatter-gather)             帧解析)
```

#### 工程细节

**激活控制**。通过环境变量 `CRYPTO_RX_PMD_OBSERVE=1` 在驱动初始化时决定是否注册 dynfield。运行时用 `active` flag 控制热路径分支。未激活时唯一的开销是一次分支判断，分支预测器会学到总是不跳转。

**路径兼容性**。并非所有 PMD 收包路径都能安全插入观测。Virtio 的 packed ring、vector、inorder 路径的 descriptor 布局和遍历方式不同，当前实现仅支持 split ring scalar mergeable 路径——这是 virtio 在 QEMU/KVM 下的默认配置。如果检测到不兼容的路径组合，驱动初始化会拒绝激活并返回 `-ENOTSUP`。

**多段包（chained mbuf）**。一个逻辑包可能由多个 mbuf segment 拼接而成。每个 segment 有自己的 `pmd_tsc`，应用层取所有 segment 中最大的值作为该包的观测时间（包在所有段都可见之后才算"到达"），并校验所有段都有有效值（非零且不超过 `rx_tsc`）。

**Weak symbol 链接**。应用层通过 `__attribute__((weak))` 引用驱动中的全局变量，使得同一份应用代码既能链接 patched DPDK（trace 构建）也能链接原版 DPDK（生产构建）。

#### 为什么 DPDK 上游不做这个

这个 patch 在技术上不复杂，但它没有出现在 DPDK 上游，原因是生态结构问题：

**DPDK 社区的假设**：需要精确时间戳的用户 → 使用物理网卡 → 有硬件时间戳 → 不需要软件观测点。核心贡献者是网卡厂商（Intel、NVIDIA/Mellanox、Marvell）和电信厂商，场景都是物理网卡。

**AWS Nitro 团队的优先级**：ENA 驱动的设计目标是高吞吐、低 CPU 占用、多租户隔离。延迟观测不在产品定位中。

**云上量化交易的现实**：大量机构在 AWS 上运行行情接收。它们全部使用 ENA，全部没有硬件时间戳，全部需要延迟测量。但这个群体在 DPDK 社区里没有话语权。

三方不重叠：有需求的人不在社区里，有能力做的人不认为是需求，定义标准的人假设这个场景不存在。

#### 代价与边界

**不是硬件到达时间**。`pmd_tsc` 是 Guest 侧 PMD 软件首次读到 used ring / CQ 变化的时刻。之前的 Host 侧 vhost 处理、IOMMU 翻译、PCIe 传输等环节不可见。

**依赖 poll 频率**。DPDK 是轮询模型，`pmd_tsc` 的精度上限是 poll 间隔。包在两次 poll 之间的等待时间无法被观测。`pmd_tsc` 告诉你"这次 poll 看到它了"，不是"它什么时候出现在 ring 里的"。

**维护成本**。Patch 直接修改驱动代码，每次 DPDK 升级需要重新适配。上游重构收包路径（比如 virtio 从 split 迁移到 packed 作为默认）时，patch 可能需要大幅重写。

**仅覆盖 x86**。`rdtscp` 和 `lfence` 是 x86 指令。迁移到 ARM 实例（Graviton）需要替换为 `cntvct_el0` 等。

---

### 总结

在虚拟化环境中做网络收包延迟分解，存在一个结构性的可观测性缺口：硬件时间戳不可用，而 DPDK 的 API 抽象将 PMD 内部的时间维度信息完全封装。

在 `rte_eth_rx_burst()` 内部、used ring / completion queue 首次被观测到有新数据包的时刻注入一个 TSC 时间戳，是当前架构约束下能获得的最早的软件侧观测点。

这个方案的必要性来自一个简单的事实：在 AWS 上，不管你用 VM 还是 bare metal，你的网卡都是 ENA，它没有硬件时间戳，而你需要知道包是什么时候到的。在上游生态解决这个问题之前，这是你唯一的选择。

后续可以考虑：将 patch 整理为 DPDK 社区可接受的 RFC，定义一个标准的 `RTE_MBUF_DYNFIELD_PMD_OBSERVE_TSC` 语义，推动虚拟设备驱动的可选观测能力成为上游功能。
