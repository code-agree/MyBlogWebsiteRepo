+++
title = '低延迟 Socket 优化:从成本模型到平台层'
date = 2026-08-27T00:10:00+08:00
draft = false
tags = ["Network", "HFT", "Performance", "Linux"]
+++

> 一份自顶向下的分析框架。目标不是罗列参数,而是建立"为什么"的因果链——
> 每一项优化都应该能追溯到它消除了哪一类物理成本。

---

## 0. 方法论:为什么不能从参数列表开始

"Socket 有哪些优化"是一个被问烂了的问题,而绝大多数答案是失败的,因为它们是**平铺的清单**:
`TCP_NODELAY`、`SO_REUSEPORT`、零拷贝、DPDK……

清单式回答有三个致命缺陷:

1. **无法判断适用性**。同一个参数在吞吐场景和延迟场景下的取值是相反的,脱离目标谈优化没有意义。
2. **无法排序**。不知道哪一项值 10μs、哪一项值 100ns,就会把精力花在错误的地方。
3. **无法发现清单外的问题**。真实系统的瓶颈常常不在清单上——它在 BIOS 里、在 NUMA 拓扑里、在 cache 替换策略里。

本文采用的路径是:

```
解剖数据路径  →  建立成本模型  →  确立度量纪律  →  逐层消除成本  →  验证
   (第 1 节)      (第 2 节)        (第 3 节)      (第 4-7 节)   (第 8 节)
```

**核心论点:Socket 优化的本质是在从网线到应用逻辑的路径上,系统性地消除排队点、
切换点、拷贝点和失效点。所有具体参数都是这四个原理在不同层次上的投影。**

---

## 1. 解剖:一个包到底经历了什么

### 1.1 接收路径(RX)

```
① NIC 收包,DMA 写入 RX ring 预挂的 buffer
② NIC 触发 MSI-X 中断(可能被 interrupt coalescing 延迟)
③ 硬中断处理:屏蔽该队列中断,raise NET_RX softirq
④ softirq 上下文 napi_poll:取 descriptor,构造 skb,GRO 聚合
⑤ netif_receive_skb → ip_rcv → tcp_v4_rcv
     查 socket hash → 加 socket 锁 → 序号检查 → 入 receive_queue
⑥ sk_data_ready → wake_up → try_to_wake_up
     目标线程若在别的核 → 发 IPI → 对端调度器抢占
⑦ 用户态 epoll_wait 返回 → recv() → copy_to_user
```

**第一个反直觉的结论**:第 ⑤ 步——真正的 TCP 协议处理——在 fast path 上只有几百纳秒。
而整条路径的 wire-to-app 延迟通常是 5–15μs。

**协议栈本身占不到 20%。绝大部分成本在 ②③④ 的中断/软中断链和 ⑥ 的唤醒/调度链上。**

这一个观察就决定了后面所有优化的优先级:**通知机制比协议处理贵一个数量级**。
它也直接解释了为什么 busy polling 和 kernel bypass 的收益如此巨大——
它们砍掉的从来不是"TCP 太慢",而是"叫醒你太慢"。

### 1.2 发送路径(TX)

```
send() → copy_from_user 构造 skb → tcp_sendmsg 分段
       → tcp_push(Nagle 判断)→ ip_queue_xmit → qdisc 排队
       → 驱动 ndo_start_xmit → 写 TX descriptor
       → doorbell:MMIO write(uncached posted write,~200-500ns)
       → NIC DMA 读取 → 上线
       → TX completion 中断回收 skb
```

TX 侧有两个容易被忽略的成本:

- **qdisc 是一个额外的排队层**。具体默认值依内核和发行版而异,延迟路径上必须检查实际配置。
- **doorbell 的 MMIO 写是 uncached / WC 映射相关的 posted write**,单次数百纳秒量级。
  高频小包场景下这一项占比可观——这正是 DPDK/ef_vi 要做 tx burst、尽量摊薄 doorbell 的原因。

---

## 2. 成本模型:只有四类成本

解剖完路径,可以把所有可优化的成本归入四类。这是本文的骨架。

| 类别 | 攻击的对象 | 典型量级 | 代表手段 |
|---|---|---|---|
| **消除排队** | 缓冲、合并、定时器造成的等待 | μs ~ ms | 关 Nagle/delack、小 buffer、小 ring、关合并 |
| **消除切换** | 中断、softirq、唤醒、调度、syscall | 每次 0.1 ~ 10μs | busy poll、io_uring、run-to-completion |
| **消除拷贝** | copy_to_user、skb 分配释放 | 拷贝本身次要,cache 污染为主 | mmap ring、MSG_ZEROCOPY |
| **消除失效** | cache miss、TLB miss、跨 NUMA | 每次 80 ~ 450 cycles | NUMA 绑定、DDIO、huge page、预热 |

### 2.1 一条贯穿全文的原则:吞吐与延迟是对立的

同一个旋钮,两个方向相反。这是回答"有哪些优化"时**必须先说清楚**的前提:

| 参数 | 延迟优化 | 吞吐优化 |
|---|---|---|
| Nagle (`TCP_NODELAY`) | 关 | 开 |
| 延迟 ACK (`TCP_QUICKACK`) | 开 QUICKACK(临时关闭 delayed ACK) | 允许 delayed ACK |
| GRO / LRO / TSO / GSO | 避免引入等待,逐项实测 | 开 |
| interrupt coalescing | 最小(`rx-usecs 0`) | 调大 |
| socket buffer | 小(≈ BDP) | 大 |
| NIC ring buffer | 小 | 大 |
| `sendmmsg` 批量 | 只批天然存在的 | 主动攒批 |
| MTU | 标准 | jumbo frame |
| 轮询 vs 中断 | busy poll | 中断驱动(省 CPU) |

**所以"Socket 有哪些优化"这个问题本身是不完整的,必须先问"优化什么"。**

---

## 3. 度量纪律:三个时钟域

在讨论具体手段之前必须先统一度量单位,否则后面所有数字都会被误读。这一节是全文
最容易出错、也最少被讲清楚的部分。

### 3.1 芯片上有三个独立时钟域

```
┌──────────────────── 一颗 CPU die ────────────────────┐
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
│  │ Core 0 │ │ Core 1 │ │ Core 2 │ │ Core 3 │  CORE  │  ← core clock
│  │ ALU    │ │        │ │        │ │        │        │     3.0 GHz
│  │ L1/L2  │ │ L1/L2  │ │ L1/L2  │ │ L1/L2  │        │
│  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘        │
│  ════╪══════════╪══════════╪══════════╪════          │
│      │     互联总线 (mesh / ring)      │      UNCORE │  ← uncore clock
│  ════╪══════════╪══════════╪══════════╪════          │     2.4 GHz
│  ┌───┴────┐ ┌───┴────┐ ┌───┴────┐ ┌───┴────┐        │
│  │LLC slice│ │LLC slice│ │LLC slice│ │LLC slice│      │
│  └────────┘ └────────┘ └────────┘ └────────┘        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │内存控制器│  │PCIe 控制器│  │   UPI    │           │
│  └────┬─────┘  └────┬─────┘  └──────────┘           │
└───────┼─────────────┼────────────────────────────────┘
        ↓             ↓
      DRAM          网卡                                   ← memory clock
                                                             1600 MHz
```

- **Core**:执行指令的部分,ALU、流水线、L1/L2。每核私有。
- **Uncore**:核心之外但仍在芯片上的共享部分——LLC、互联、内存控制器、PCIe 控制器、
  一致性目录。名字就是字面意思:un-core。AMD 称 Data Fabric。
- **Memory**:DRAM 器件自己的时钟域,tRCD/tCL 等时序参数定义在这里。

Uncore 之所以需要独立时钟,有三个硬性理由:它被所有核共享(没法跟着某一个核走)、
物理跨度大跑不快(通常只到 2.0–2.6 GHz)、面积大功耗高(需要独立调频)。

### 3.2 cycle 是尺子的刻度,不是物理量

这是一个高频误解点。厘清它:

- **一个 cycle 有多长** = 1/f —— 频率越高越短 ✓
- **一件事花了多少 cycle** = 该事件的墙钟时间 × f

关键在于问:**这件事的时长由哪个时钟域决定?**

**第一类:在 core 时钟域完成的工作**(如一次整数加法)——耗时天然以 core cycle 计。

| 频率 | cycle 长度 | 需要 cycles | 墙钟时间 |
|---|---|---|---|
| 3.0 GHz | 0.333 ns | 1 | 0.333 ns |
| 4.0 GHz | 0.250 ns | 1 | **0.250 ns ↓** |

cycle 数恒定,时间随频率下降。**这是超频有用的原因。**

**第二类:等待其他时钟域的工作**(如一次 DRAM 访问)——耗时由 DRAM 器件物理特性钉死,
约 75 ns,与 CPU 频率无关。

| 频率 | cycle 长度 | 墙钟时间 | 消耗 cycles |
|---|---|---|---|
| 3.0 GHz | 0.333 ns | 75 ns | 225 |
| 4.0 GHz | 0.250 ns | 75 ns | **300 ↑** |

时间恒定,cycle 数随频率上升。

```
墙钟:   |————————————— 75 ns —————————————|
3.0GHz: |·|·|·|·|·|·| ... |·|·|      225 个格子
4.0GHz: ||||||||||||| ... |||||      300 个格子
        ↑ 刻度更细,所以同样长度里格子更多
```

**"cycle 变多"不等于变慢**,只是换了把更细的尺子。DRAM 没有任何变化——而这正是问题所在。

### 3.3 推论:memory wall

设某循环每次迭代 = 100 cycles 计算 + 1 次 DRAM 访问:

| | 3.0 GHz | 4.0 GHz | 变化 |
|---|---|---|---|
| 计算 | 100 cyc = 33.3 ns | 100 cyc = 25.0 ns | −8.3 ns |
| DRAM | 225 cyc = 75 ns | 300 cyc = **75 ns** | **0** |
| 合计 | 108.3 ns | 100.0 ns | **仅 −7.7%** |

**频率提升 33%,性能提升 7.7%。**

这个结论的分量:在低延迟系统里,**让数据留在 cache 里的价值,远大于把 CPU 超频**。
而且差距还在扩大——几十年来核心频率涨了几十倍,DRAM 延迟只从 ~100ns 降到 ~70ns,
以 cycle 计的内存延迟一直在恶化。

### 3.4 uncore 频率:第三种情况

LLC 命中延迟本质上是"走 N 个 uncore 节拍",因此以 core cycle 计:

```
LLC 延迟(core cycles) = N_uncore × (f_core / f_uncore)
```

| 变化 | LLC 延迟 (ns) | LLC 延迟 (core cycles) |
|---|---|---|
| core 频率 ↑ | 不变 | 变多(无害,尺子变细) |
| **uncore 频率 ↓** | **变长** | 变多(**真的变慢**) |

**两种情况在 perf 的 cycle 计数上表现相同,但一个无害一个致命。**
唯一的区分方法是换算成 ns。

**危险场景**:busy polling 线程反复读同一小块内存,几乎全部命中 L1,
硬件看到"内存请求密度极低",判定不需要带宽 → uncore 降频。

| | uncore 2.4 GHz | uncore 1.2 GHz |
|---|---|---|
| LLC 命中 | ~20 ns | **~40 ns** |
| DRAM 访问 | ~75 ns | **~110 ns** |
| **core 频率显示** | 3.0 GHz | **3.0 GHz(正常)** |

整个内存子系统慢了一倍,而所有常规监控显示一切正常。且升频有几十微秒响应延迟,
恰好在包真正到来时还没回来——典型的"均值好看、p99 塌方"。

```bash
turbostat --show Core,CPU,Bzy_MHz,UncMHz --interval 1   # UncMHz 列
wrmsr -a 0x620 0x1818     # 锁定 uncore 上下限(单位 100MHz)
```

### 3.5 计时工具的正确用法

| 工具 | 计的是什么 | 陷阱 |
|---|---|---|
| `CPU_CLK_UNHALTED.THREAD` (perf `cycles`) | 真实 core cycles | 变频时快慢不同;halt 时不走 |
| `CPU_CLK_UNHALTED.REF_TSC` (perf `ref-cycles`) | 固定参考频率 | 与实际执行速度无关 |
| `rdtsc` / `rdtscp` | **参考频率,即墙钟** | **常被误当成 cycles** |

#### TSC 根本不是 cycle 计数器

在 invariant TSC 平台上,TSC 以**固定频率**递增,与核心当前实际频率完全解耦。
这个频率由 CPUID leaf `0x15` 给出——一个晶振基准(通常 24 或 25 MHz)乘固定倍率,
数值上一般等于标称基频:

```bash
dmesg | grep -i "tsc: Detected"      # 例:tsc: Detected 2500.000 MHz processor
```

**因此 `rdtsc` 的差值是墙钟时间的整数表示,单位是"TSC tick",不是 core cycle。**

#### 偏差的方向与量级

```
实际 core cycles = 墙钟时间 × f_core
rdtsc 读数       = 墙钟时间 × f_TSC
低估比例         = f_core / f_TSC
```

基频 2.5 GHz、全核 turbo 3.8 GHz 的 CPU,测一段 100 ns 的代码:

| | 读数 |
|---|---:|
| 实际消耗 core cycles | 380 |
| `rdtsc` 读数 | 250 |
| **低估** | **34%** |

**为什么是"系统性"而非随机**——偏差方向单向,取决于 `f_core` 相对 `f_TSC` 的位置:

| 运行状态 | f_core vs f_TSC | rdtsc 偏差 |
|---|---|---|
| **Turbo(busy spin 的常态)** | 高于 | **低估** ✗ |
| 恰在基频 | 相等 | 准确 |
| 热降频 / AVX-512 降档 / P-state 掉档 | 低于 | 高估 |

低延迟系统里线程 100% 占用一个核、几乎永远在 turbo,所以**在你最关心的场景里
偏差稳定朝一个方向,不会被多次采样平均掉**。

**反向误差源**:`CPU_CLK_UNHALTED` 在核心 halt(C-state)时停止计数,`rdtsc` 不停。
对会阻塞/睡眠的代码,`rdtsc` 反而**高估** core cycles——把睡觉时间算进了"执行成本"。
两个误差方向相反且不抵消,只会让读数更不可解释。

#### 正确做法

**测时间就用 `rdtscp`,但别叫它 cycles:**

```c
uint32_t aux;
_mm_lfence();
uint64_t t0 = __rdtsc();
/* ... 关键路径 ... */
uint64_t t1 = __rdtscp(&aux);
_mm_lfence();
// aux 携带 CPU ID,可用于检测线程是否被迁移(迁移会污染被测路径)

uint64_t ns = (t1 - t0) * 1000000000ULL / tsc_hz;   // 这是纳秒,不是 cycles
```

`RDTSCP` 会等待之前的指令完成,但不阻止之后的指令提前执行,因此终点之后仍需要
`lfence`。起点通常用 `lfence; rdtsc` 或等价封装。现代 invariant TSC 平台通常跨核同步,
迁移后数值未必不可比,但迁移本身会把调度、cache 冷却等噪声带进测量,所以仍应检测并丢弃。

**要 cycles 有三条路:**

```bash
# 1. 直接测(最可靠)
perf stat -e cycles,ref-cycles,instructions ./prog
```

```c
// 2. APERF/MPERF —— 硬件专为此设计的一对计数器
//    APERF 按实际频率走,MPERF 按 TSC 频率走
//    f_core / f_TSC = ΔAPERF / ΔMPERF
uint64_t aperf0 = rdmsr(0xE8), mperf0 = rdmsr(0xE7);
/* ... */
double ratio = (double)(aperf1 - aperf0) / (mperf1 - mperf0);
uint64_t real_cycles = (uint64_t)((t1 - t0) * ratio);
```

```bash
# 3. 锁死频率,让 f_core ≡ f_TSC,rdtsc 差值直接等于 cycles
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
# 配合 governor=performance
```

**第 3 条在实践中最省事**:锁频后 `rdtsc` 就成了合法的 cycle 计数器,
而锁频本身出于确定性考虑也本该做(见 9.4)。`perf` 的 `cycles / ref-cycles`
与 APERF/MPERF 是同一个量,可互相印证。

**跨频率、跨机器比较一律换算成 ns;同频率下做微架构对比才用 cycles。**

### 3.6 成本速查表:两类不变量

一张只有 cycles 和 ns 两列的速查表是有缺陷的——它让性质完全不同的数字长得一样。
**必须区分:哪个数字是该访问的原生单位(跨机器可直接引用),哪个是派生值(换机器必须重算)。**

| 访问 | 域 | **不变量** | @3.0GHz cycles | ns |
|---|---|---|---:|---:|
| L1d 命中 | core | **4–5 core cyc** | 4–5 | 1.5 |
| L2 命中 | core | **~14 core cyc** | ~14 | 4.7 |
| LLC 命中 | uncore | ~N uncore ticks | 50–70 | ~20 † |
| 跨 socket LLC snoop | uncore+UPI | **~100 ns** | ~300 | ~100 |
| 本地 DRAM | memory | **~75 ns** | 200–260 | ~75 |
| 远端 NUMA DRAM | 混合 | **~130 ns** | 350–450 | ~130 |
| syscall | core | **~150–300 core cyc** | 150–300 | 50–100 ‡ |
| 硬中断 + softirq | core | ~3000–6000 core cyc | 3000–6000 | 1–2 μs |
| 跨核唤醒 + 调度 | 混合 | 5–15 μs | 15000–45000 | 5–15 μs |
| PCIe non-posted read | PCIe+uncore | **~1 μs** | ~3000 | ~1000 |

† 仅在 uncore 频率锁定时恒定(见 3.4) ‡ 开 KPTI 后更高

**加粗列是原生单位,其余为派生值。**

#### 为什么 L1/L2 用 core cycles 是唯一正确的

它们物理上就在核心里,跟着核心时钟跳。"L1 命中 4 个 cycle"是一个器件级事实,
与频率无关;反过来说"L1 命中 1.5 ns"才是需要标注频率的派生值。

这也带来一个实际差异:L1 命中成本 = `4/f` 秒,**会随频率缩短**,
所以对 L1 密集的负载超频是有效的——而 3.3 节已证明对内存密集负载无效。
**这两个结论的分歧,正是"分域"这件事的实际价值。**

#### 那为什么 LLC/DRAM 仍要给出 core cycles

不是为了描述那次访问,而是因为**成本的承担者是核心的流水线**。

一次 DRAM miss 的实际伤害不是"DRAM 忙了 75 ns",而是"我的核心在这 225 个节拍里
损失了什么":

```
225 core cycles 意味着:
  · 乱序窗口(ROB ~350 项)能否吃下这个 stall
  · 4-wide 前端本可退休约 900 条指令
  · Line Fill Buffer(~10-12 项)只能覆盖这么多并发 miss
  · 预取需要提前多少次迭代才够
```

**ROB 深度、LFB 数量、调度器条目——所有用于隐藏延迟的硬件资源都以 core cycle 计量。**
要判断"这个 miss 能否被隐藏",就必须换算到 core cycles,别的单位回答不了。

#### 单位选择判据

| 你在问什么 | 用什么单位 |
|---|---|
| 这次 stall 能被乱序隐藏吗?预取要提前多少? | **core cycles** |
| L1/L2 的固有成本? | **core cycles**(域内原生) |
| 换机器 / 换频率,DDIO 还生效吗? | **ns** |
| uncore 有没有偷偷降频? | **ns**(唯一能区分) |
| 内存时序配置对不对? | **memory cycles**(tCL 等) |

**DDIO 命中与否的差值:约 150–200 core cycles,每次访问。**

### 3.7 每包 cycle 预算

这个视角能立刻说明 200 cycles 是什么概念:

| 场景 | 包速 | 每包间隔 | **每包 cycle 预算 @3GHz** |
|---|---:|---:|---:|
| 10G 线速 64B | 14.88 Mpps | 67 ns | **202** |
| 25G 线速 64B | 37.2 Mpps | 27 ns | **81** |
| 行情爆发 2 Mpps | 2 Mpps | 500 ns | 1500 |
| 10G 线速 1500B | 812 kpps | 1231 ns | 3694 |

**小包线速场景下,一次 DRAM miss 吃掉全部预算。** 不是"慢一点",是这一包处理时间翻倍,
队列开始累积,后续每包更慢——正反馈。

#### 自洽性检验:为什么可以用频率相关的量下频率无关的结论

上表的"202 cycles"本身是 `67 ns × 3.0 GHz` 算出来的。用一个频率相关的量去比
另一个频率相关的量,结论可靠吗?**恰恰因为两边同比缩放,比值是频率无关的:**

```
预算 = t_wire  × f       (线速间隔 67 ns × f)
成本 = t_DRAM  × f       (DRAM 延迟 75 ns × f)

成本 / 预算 = t_DRAM / t_wire = 75/67 = 1.12      ← f 抵消
```

所以"一次 DRAM miss 吃掉全部每包预算"在任何频率下都成立,**超频救不了**。

这与 7.4 节 `N·b < C` 中 `r` 和 `f` 同时抵消是同一种结构:

> **真正硬的结论都是比值,而比值里频率会消掉。**
> 一个结论如果随频率变化,说明它描述的是实现细节而非系统约束。

---

## 4. 消除排队

### 4.1 原理

排队论的基本结论:等待时间 `W ≈ ρ/(1−ρ) × S`,利用率趋近 1 时发散。

**任何缓冲区都是把"丢包"换成"延迟"。** 在延迟敏感系统里,一个晚到 500μs 的行情包
和丢掉没有区别——但它还消耗了本可用于处理新包的资源。

**核心原则:热路径上一切队列都应尽可能浅。**

### 4.2 `TCP_NODELAY` — 关闭 Nagle

Nagle 规则:存在未被 ACK 的已发送数据时,新的小于 MSS 的数据必须等待。
设计目的是解决 telnet 时代 41 字节包传 1 字节的问题。

后果:请求-响应模式下,第二个请求要等第一个响应的 ACK 才发得出去,凭空多一个 RTT。

### 4.3 `TCP_QUICKACK` — 关闭延迟 ACK

接收端为捎带(piggyback)ACK,最多等 40ms。与 Nagle 组合产生经典死锁:
发送端等 ACK 才发,接收端等数据才 ACK,双方卡满一个 delack 周期。

**实现细节**:`TCP_QUICKACK` 的用法是 `setsockopt(TCP_QUICKACK, 1)`,请求内核尽快发送 ACK,
也就是临时关闭 delayed ACK。它**不是 sticky 的**,内核在若干包后会回到常规 ACK 策略,
低延迟交互场景通常需要在每次 `recv` 后重新设置。这是区分"用过"和"背过"的点。

### 4.4 避免 write-write-read 反模式

header 和 body 分两次 `write`,在 `TCP_NODELAY` 关闭且前一个小包仍未确认/未发送时,
第二次可能撞上 Nagle。用 `writev` 一次提交,或在应用层组包。

### 4.5 socket buffer 要小,不是要大

最反直觉的一条。大发送缓冲意味着应用可以往内核塞很多数据,这些数据在内核排队,
而**应用收不到背压**,还以为已经发出去了。

延迟场景要的是尽早感知拥塞。缓冲应刚好覆盖 BDP(带宽时延积):
同机房 10G / 50μs RTT 的 BDP 只有 62KB,默认自动调优上限(几 MB)完全是浪费。

### 4.6 `tcp_slow_start_after_idle = 0`

内核默认:连接空闲超过一个 RTO 后,cwnd 重置回 initial cwnd(10 MSS)。
对"平时安静、突发爆发"的行情/报单连接是灾难——最需要带宽的那一刻反而被限速。

### 4.7 interrupt coalescing

驱动攒够 N 个包或等够 T 微秒才发中断。默认通常几十微秒,直接加在延迟上。
延迟场景 `ethtool -C ethX rx-usecs 0 rx-frames 1`,代价是中断率飙升、吞吐下降。

### 4.8 ring buffer 不是越大越好

常见错误直觉:"调大 ring 防丢包"。实际效果是突发来临时包不丢了,改成排在 ring 里等——
p99 一样烂,而且更难发现。

**正确做法是小 ring + 保证消费速度,让丢包成为可见的报警信号。**
(第 5 节会给出这条建议的第二个、更硬的理由。)

### 4.9 qdisc

qdisc 是又一层排队点。现代发行版默认常见是 `fq_codel`,老系统或特定配置可能仍是
`pfifo_fast`。延迟场景应先用 `tc qdisc show` 看实际配置;TCP 出口可考虑 `fq`(带 pacing)
或调小队列/limit。`noqueue` 通常不是普通物理网卡的通用可选方案,不要把它当成固定建议。

---

## 5. 消除切换

这是收益最大的一类,因为第 1 节已经证明通知链比协议处理贵一个数量级。

### 5.1 `SO_BUSY_POLL` — 内核态常见高收益优化

**原理**:当 `recv`/`epoll_wait` 发现无数据时,不立刻睡眠,而是在当前用户线程的上下文里
短时间尝试执行关联 NAPI 的 poll,把可能已经到达但尚未通过中断/softirq 送上来的包捞上来。
它依赖驱动/NAPI 支持、socket 已关联 NAPI id,以及 `net.core.busy_read` /
`net.core.busy_poll` 等配置。

命中时可以绕开或缩短大部分通知链:

- 可以在中断到来前就把包处理掉,减少中断路径参与
- 不需要 softirq 上下文切换
- 不需要 `wake_up` / IPI
- 不需要调度器介入
- 包在自己的核上处理,socket 结构体和 skb 全在本地 L1/L2

代价:CPU 占用显著上升,轮询窗口设得激进时等价于烧掉一个核。是否划算取决于包到达模式和
驱动支持,必须实测。

### 5.2 `io_uring`

共享内存的 SQ/CQ 环形队列,批量提交批量收割。开启 `SQPOLL` 后有内核线程轮询提交队列,
提交侧可以在热路径上避免 syscall,只写共享内存。但 socket 协议栈、CQ 等待和唤醒仍然存在;
它不是对网络收包路径的完整 bypass。

### 5.3 epoll 的正确用法

- ET(边缘触发)+ 非阻塞 fd + 循环读到 `EAGAIN`,减少 `epoll_wait` 返回次数
- 多线程共享 epfd 用 `EPOLLEXCLUSIVE` 避免惊群

但要清楚定位:**epoll 优化的是"管理大量 fd 的开销"**。在只有几条连接的交易场景里,
它的收益远不如 busy poll。

### 5.4 `SO_REUSEPORT`

多个 socket 绑同一端口,内核按四元组哈希直接分发。TCP server 场景下每线程有独立的
listen/accept queue,能减少共享监听 socket 的锁竞争和惊群唤醒。已建立连接本来就是独立
socket,不要把它理解成给同一个 established socket 拆 receive queue。

进阶:挂 `SO_ATTACH_REUSEPORT_EBPF` 自定义分发,保证同一客户端总落到同一线程(状态本地化)。

### 5.5 批量:`sendmmsg` / `recvmmsg`

一次 syscall 收发多包,摊薄固定开销。

**注意这是吞吐优化**——它隐含"等待凑批",与延迟目标冲突,
除非批天然存在(一次 NAPI poll 捞上来多个包)。

### 5.6 run-to-completion 架构

收包 → 解码 → 策略 → 下单在同一线程、同一核完成。

理由不是"减少线程",而是:任何跨线程投递要么是一次唤醒(μs 级),
要么是无锁队列上的一次 cache line 弹跳(所有权在两核间转移,~100ns+ 且不可预测)。

**流水线架构在吞吐上更优,在 tail latency 上更差。**

---

## 6. 消除拷贝

### 6.1 先破除一个迷思

对小包(几百字节)而言,`copy_to_user` 本身只有几十纳秒,**不是瓶颈**。真正的代价是:

1. 拷贝污染 L1/L2,把策略状态挤出去
2. `skb` 的分配和释放(内存分配器 + 引用计数 + 跨核释放)

**"零拷贝"在小包场景的价值被高估,"零 syscall / 零唤醒"被低估。**

### 6.2 手段与适用性

| 手段 | 机制 | 适用 |
|---|---|---|
| `MSG_ZEROCOPY` | pin 用户页让 NIC 直接 DMA 读 | 内核文档明示**仅 >10KB 划算**(页 pin/unpin + 异步 completion 开销) |
| `splice` / `sendfile` | 传递 page 引用而非内容 | 文件转发、代理 |
| **mmap ring** | 用户态与 NIC 共享预注册内存 | 真正的零拷贝,顺带消除 skb 分配 |

`AF_PACKET` v3 / `AF_XDP` / DPDK 都属于最后一类。

---

## 7. 消除失效:cache、DDIO 与平台层

这是最容易被忽略、但收益/成本比最高的一层。它的特点是:**改动量小、完全不可见、
不测就不知道**。

### 7.1 DDIO 是什么

**传统 PCIe DMA 路径:**

```
NIC → PCIe → Root Complex → 内存控制器 → DRAM
                                          ↑
                        CPU 读取时 LLC miss → 回 DRAM → ~225 cycles
```

每个包"落一次内存、再捞一次内存"。更糟的是 DMA 写必须先 invalidate 对应 cache line
(一致性要求),CPU 之后的访问必然 miss。

**DDIO(Data Direct I/O,Intel Sandy Bridge-EP 起)在支持并开启的平台上,可把 LLC 而非 DRAM
作为 PCIe DMA 的优先落点:**

- **入站写**(RX 数据、TX completion):优先写进 LLC。命中已有 line 则原地更新;
  未命中则可在 LLC 中分配。后续若被驱逐,仍可能写回 DRAM。
- **出站读**(NIC 读取待发包、读 descriptor):数据在 LLC 则可直接供给,减少等 DRAM 的概率。

**收益:CPU 读取刚收到的包,从 ~225 cycles 降为 ~60 cycles。**

它是前代 DCA(Direct Cache Access)的替代品。DCA 只是"提示 CPU 预取",需驱动配合且不可靠;
DDIO 更偏硬件路径,通常对软件透明,但是否开启、可用 way 数和 BIOS/平台行为都要按机器确认。

**所以多数情况下"用上 DDIO"不需要改应用代码。真正需要做的是确认平台状态,并避免它失效。**

### 7.2 前置概念:什么是 way

cache 不是平坦数组,是一个二维表格:

```
                way 0      way 1      way 2      ...   way 15
              ┌─────────┬─────────┬─────────┬─────┬─────────┐
    set 0     │ 64B line│ 64B line│ 64B line│ ... │ 64B line│
              ├─────────┼─────────┼─────────┼─────┼─────────┤
    set 1     │ 64B line│ 64B line│ 64B line│ ... │ 64B line│
              ├─────────┼─────────┼─────────┼─────┼─────────┤
    set N-1   │ 64B line│ 64B line│ 64B line│ ... │ 64B line│
              └─────────┴─────────┴─────────┴─────┴─────────┘
                ↑ 一个 way = 表格的一整列
```

- **set(组)**:由地址中间几位直接索引。一个地址**只能**落在唯一确定的那一行。
- **way(路)**:那一行里有多少槽位可选,即"N 路组相联"的 N。

地址拆解(以 L1d 32KB / 8-way / 64B line 为例,sets = 32768/(64×8) = 64):

```
┌──────────────────┬──────────┬──────────┐
│       tag        │  index   │  offset  │
│                  │  6 bit   │  6 bit   │
└──────────────────┴──────────┴──────────┘
                       ↓          ↓
                   选哪个 set   line 内偏移

查找:index 定位 set → 并行比较该 set 内 8 个 way 的 tag → 命中返回
```

**index 决定的 set 没得选,唯一的自由度是"放在这个 set 的哪个 way"。**
因此 way 数 = 冲突容忍度。直接映射 = 1-way;全相联 = 只有 1 个 set。

### 7.3 "DDIO 只占 2 个 way"的含义

DDIO 在 LLC miss 时只能往有限的几个 way 里分配,典型是 2 个,约占 LLC 的 10%。

以 32MB / 16-way 为例:

```
每 way 容量 = 32MB / 16 = 2MB
DDIO 预算 = 2 × 2MB = 4MB
```

含义**不是**"DDIO 只能用某一块连续的 4MB",而是:

> **每一个 set 里,DMA 写入在 miss 时只允许分配到指定的那 2 个槽位。**

硬件实现就是给替换算法加一个 **way mask**:选牺牲者时只在掩码允许的列里挑。

这样设计的好处是天然均匀——不管数据落在哪个 set,I/O 都只能动那两列,
永远动不了其余 14 列里的应用数据。按容量限制做不到这一点(热点 set 仍会被冲垮),
按 way 限制则是硬隔离。

**CAT 用的是同一机制:**

```bash
mount -t resctrl resctrl /sys/fs/resctrl
mkdir /sys/fs/resctrl/strategy
echo "L3:0=0xff00" > /sys/fs/resctrl/strategy/schemata   # 16 位掩码对应 16 个 way
echo <pid>        > /sys/fs/resctrl/strategy/tasks
```

给策略线程 `0xff00`、其他进程 `0x00ff`,两组在**每个 set 上都互不驱逐**,
LLC 被硬切成两半。掩码必须是连续的 1(硬件要求),分配粒度就是 way——
16-way 的 LLC 最细只能按 1/16 切。

```bash
cat /sys/fs/resctrl/info/L3/cbm_mask    # 看本机掩码宽度,即 way 数
```

### 7.4 核心推导:驻留寿命 vs 复用周期

现在用 cycle 严格表述"为什么小池高频复用优于大池轮转"。

**定义:**

| 符号 | 含义 |
|---|---|
| `C` | DDIO 可用容量(bytes)= way 数 × 每 way 容量 |
| `b` | 每包在 cache 中实际占用的字节数 |
| `r` | 包速率(pps) |
| `N` | 池中 buffer 数量 |
| `f` | 核心频率(cycles/s) |

**驱逐寿命** `T_evict` —— 一条 line 从写入到被挤出所经历的 cycles。
DDIO 区域装得下 `C/b` 个包,填满一轮即发生驱逐:

```
T_evict = (C / (b · r)) · f      [cycles]
```

**复用周期** `T_reuse` —— 同一 buffer 两次被 DMA 写入之间的 cycles。
FIFO 轮转下需走完整个池:

```
T_reuse = (N / r) · f            [cycles]
```

**命中条件:**

```
T_reuse < T_evict
⟺ (N/r)·f < (C/(b·r))·f
⟺ N · b < C
```

**这个结果有三个重要含义:**

**(1) `r` 和 `f` 完全抵消了。**

在这个一阶模型里,判据是容量条件,与包速无关、与 CPU 频率无关。这意味着:

- **不能靠换更快的 CPU 解决**——频率翻倍,两个时间尺度同比缩短,比值不变
- 若访问模式和 in-flight 数相同,低速测试和高速测试会得到相同的命中/未命中结论
  (所以这个问题在 benchmark 里不容易暴露)

**(2) LIFO 把 `T_reuse` 从 O(N) 降到 O(1)。**

栈式 free list 下,复用周期不再取决于池大小:

```
T_reuse(LIFO) = (k / r) · f,    k ≈ 并发在途的 buffer 数 ≪ N
```

只要 `k·b < C` 就命中。

| free list 策略 | 行为 | 重用距离 |
|---|---|---|
| **FIFO(队列)** | 释放的 buffer 排到队尾,轮完一圈才再用 | = 整个池大小 ❌ |
| **LIFO(栈)** | 释放的 buffer 压栈,下次立刻取出 | ≈ 几个 buffer ✅ |

**同样大小的池子,仅改一行"从头取"还是"从尾取",性能可差一个数量级。**
DPDK 的 `rte_mempool` 每核本地 cache 正是用栈语义管理的——这不是巧合。

**(3) 真正的变量是"在途量"而非"池大小"。**

上述推导假设池在稳态下全部轮转。实际系统里,DMA 写入的 footprint 由**同时在途
(已 DMA、未被消费)的包数** `k` 决定,ring 深度只是 `k` 的上界。由 Little's Law:

```
k ≈ r · T_service
```

- 消费快(`T_service` 小)→ `k` 小 → 深 ring 也无害
- 突发到来、消费跟不上 → `k` 涨到接近 ring 深度 → 越过悬崖

**这精确地解释了为什么它表现为 p99 问题:平时 `k` 很小一切正常;突发时 `k` 暴涨,
DDIO 失效,延迟塌方——而失效本身又推高 `T_service`,进一步推高 `k`,形成正反馈。**

### 7.5 断崖:不是斜坡

设 cache 容量 `N_c` 个 buffer,池 `N` 个,FIFO 循环:

- **N ≤ N_c**:命中率 100%
- **N = N_c + 1**:命中率 0%(纯 LRU 的经典病态)

```
cache 容量 N_c=4,池 N=5:

访问 B1: miss  → [B1]
访问 B2: miss  → [B1 B2]
访问 B3: miss  → [B1 B2 B3]
访问 B4: miss  → [B1 B2 B3 B4]
访问 B5: miss  → 踢 B1 → [B2 B3 B4 B5]
访问 B1: miss! (刚被踢) → 踢 B2 → [B3 B4 B5 B1]
访问 B2: miss! (刚被踢) → ...
永远 100% miss
```

**池子只大了 1 个 buffer,命中率从 100% 掉到 0%。**

以 cycle 表达:

| 池大小 | 平均访问 cycles |
|---|---:|
| `N ≤ N_c` | **50–70** |
| `N = N_c + 1` | **200–260** |

放进每包预算(10G 小包线速 202 cycles/包):

```
命中:   60 cycles 访问  →  还剩 142 cycles 干活          ✓
未命中: 240 cycles 访问  →  已超预算 38 cycles,队列堆积   ✗
关键路径 3 次 miss = 720 cycles  →  超预算 3.5 倍,无法跟上线速
```

真实硬件用近似 LRU/RRIP 且有哈希随机性,还叠加 set/slice 映射、多队列、多流和预取行为,
不会精确掉到 0%。很多平台上的过渡带仍然很窄,更像断崖而非平滑斜坡,但拐点必须实测。

### 7.6 失效的三层代价

很多人以为 miss 就是"多花 200 cycles"。实际是三笔账:

1. **写回**:DMA 要写 B 但 B 不在 cache,需分配 way,被踢的牺牲者是脏的(它也是个刚收到的包),
   必须写回 DRAM。
2. **读取**:CPU 后来读 B,若 B 在被读之前已被挤出,又要从 DRAM 取回。
   原本"零次 DRAM 访问"变成"两次 DRAM 往返"。
3. **你在踢别人的包**(最要命):被踢掉的牺牲者不是无关数据,
   **它是另一个刚 DMA 进来、CPU 还没来得及读的包**。

```
包 A 到达 → 写入 LLC
包 B 到达 → 写入 LLC
...
包 Z 到达 → LLC 满 → 踢掉包 A(CPU 还没读!)→ A 写回 DRAM
CPU 终于来读包 A → miss → 从 DRAM 取
```

这就是 **leaky bucket / leaky DMA**:包在被消费前就从 cache 漏到内存。

### 7.7 重要修正:`b` 到底是多少

**一个常见的错误算法**(本文作者在讨论中曾犯):
"ring 4096 × 2KB buffer = 8MB > 4MB 预算,所以 leaky DMA"。

**这是错的。DMA 只写入实际的包字节,不会写 buffer 里没用到的部分。**
一个 2KB buffer 里放 64B 的包,DDIO 只分配 1 条 line,剩余 1984 字节从不进 cache。

```
b = ⌈pktlen/64⌉ × 64 + descriptor 分摊
```

descriptor 是 16–32B 且紧密排列,约 2–4 个共享一条 line,分摊约 16–32B/包。

| 包长 | `b` | `C/b` = 可容纳包数(C=4MB) |
|---|---:|---:|
| 64B(行情) | ~96B | **~43,000** |
| 512B | ~544B | ~7,700 |
| 1500B | ~1,530B | **~2,700** |

**修正后的结论:**

- **小包场景**:容量根本不是瓶颈,ring 4096 在容量上完全没问题
- **大包场景**(1500B):ring 4096 = 6MB > 4MB,leaky DMA 确实发生。
  文献中 DDIO 失效的案例基本都是大包 + 多队列
- "把 buffer 从 2KB 缩到 256B 能多装 64 倍"对小包**毫无作用**

**那么小包场景下大 buffer 有没有害处?有,但机制是 set 冲突,不是容量。**

Buffer 按 2KB 对齐排列时,地址低 11 位恒为 0。LLC set index 取自物理地址中间位段,
固定的 2 的幂步长会让所有 buffer 只映射到有限的一部分 set:

```
32MB / 16-way / 64B line → 32768 sets,需 15 位 index
2KB 步长 → 只有高位在变 → 实际触及的 set 数大幅减少
→ 这些 set 局部超载,其余 set 完全空闲
→ 有效容量远小于 4MB
```

现代 Intel LLC 用复杂哈希选 slice,削弱但未消除该效应。
**证据在 DPDK 里**:`rte_mempool` 会给每个 object 加递增偏移,
专门用于把对象打散到不同 cache set 和内存通道——这个设计如果没必要不会存在。

**正确表述:小包场景下 buffer 大小影响的不是占用量,而是地址分布。
避免 2 的幂对齐、使用带偏移的分配器,比缩小 buffer 更对症。**

### 7.8 DDIO 的另外两个失效模式

**NUMA 错位:DDIO 只对 NIC 所连 socket 的 LLC 生效。**

```
NIC → 本地 socket LLC(DDIO 写入)
    → 线程在远端 socket 读 → 跨 UPI snoop / 回 DRAM → +350-450 cycles 每次访问
```

不但付了跨 node 代价,还完全浪费了 DDIO。

```bash
cat /sys/class/net/eth0/device/numa_node
lstopo    # 看 NIC 挂在哪个 socket 的 PCIe root complex 下
```

线程、内存、中断三者全部绑到这个 node。**这一条是整套平台调优里性价比最高的。**

**I/O 污染应用 cache**:大流量下 DDIO 持续占用那 2 个 way 并产生替换压力,
把策略状态、订单簿挤出 LLC。对策是 7.3 节的 CAT,配合 MBA 限制其他进程内存带宽。

**什么时候该关掉 DDIO**:如果工作负载是大流量转发但几乎不读包内容
(纯 forwarding、存储节点),DDIO 可能只污染 cache 没有收益,关掉反而更好。BIOS 里的名称
依厂商而异,有的把相关选项写成 DDIO、I/O cache allocation 或 DCA,但 DCA 与 DDIO 不是
同一个机制,不要只按名字判断。交易场景基本不关。

**平台差异:**

| 平台 | 情况 |
|---|---|
| Intel Xeon SP | DDIO 默认开启 |
| AMD EPYC | 传统上无等价机制,DMA 落 DRAM。选型时需实测 |
| Arm Neoverse | CHI 支持 cache stashing,由具体 SoC 和互联实现决定,能力不统一 |

### 7.9 小池的代价

不能只讲好处。小池的代价是**突发吸收能力下降**:流量爆发时没有空闲 buffer,包被 NIC 丢弃。

但回到 4.1 节的结论:**深队列不消除问题,只是把"丢包"变成"延迟"**。
排了 8000 个位置才轮到的包,即使处理了也已过期——对交易系统而言和丢掉没区别,
而且它消耗了本可用于处理新包的资源。

更重要的是:**丢包是可见的、能报警的信号;延迟膨胀是隐形的。**
小池让问题暴露,逼你解决真正的原因(消费速度不够),而不是把它藏进缓冲区。

**正确的调法:池设到刚好覆盖实际突发规模,且不超过 DDIO 预算。
若两个条件矛盾,说明消费速度不达标,该优化的是处理逻辑,不是加缓冲。**

### 7.10 其他 cache 层面手段

- **保持流的核亲和性**:RSS(硬件按四元组哈希分队列)+ IRQ affinity(队列绑核)
  + XPS(发送选对应 TX 队列)+ aRFS(硬件学习应用所在 CPU)。
  目标是让同一条流的 skb、socket 结构体、TCP 状态始终待在同一核的 L1/L2。
- **huge pages**:减少 TLB 条目消耗和 page walk
- **`mlock` / 预触摸**:消除热路径上的缺页中断
- **cacheline 对齐**:无锁队列的 head/tail 分在不同 cacheline,否则生产者消费者互相
  invalidate(false sharing)
- **谨慎处理 offload**:LRO 通常不适合低延迟和转发;GRO 可能引入聚合等待,也可能只是在
  NAPI 批内摊销成本;TSO/GSO 对小包无关,对大写入可能减少 CPU 成本。原则是避免为了聚合
  主动等待,具体开关逐项测量。

### 7.11 路径预热

若几百毫秒无收发,整条路径的 icache、dcache、branch predictor、TLB、
甚至 CPU turbo 状态全部变冷,第一发延迟可能比稳态慢 5–10μs——
**而这一发往往正是最重要的那一发**。

对策:定期发心跳包走完整代码路径(含策略逻辑,最后一步丢弃),保持全部状态热。
这是实盘与 benchmark 结果差异巨大的常见原因。

---

## 8. PCIe 与 IOMMU

DDIO 优化的是"数据到了 CPU 之后",PCIe 决定"数据怎么到"。

### 8.1 Posted vs Non-posted:最重要的一条

- **Posted(写)**:MMIO 写、DMA 写。发出即完成,不等响应。
- **Non-posted(读)**:MMIO 读、DMA 读。必须完整往返,**~3000 cycles / ~1μs**。

**推论:热路径上应避免读 NIC 寄存器。** 一次读网卡状态可能比整个 TCP 协议栈还贵。
这正是 DPDK/ef_vi 全部依赖轮询本地内存中的 descriptor(由 NIC DMA 更新)
而非读设备寄存器的原因。

doorbell 是 MMIO 写(posted),但 uncached,单次 200–500ns 且不可乱序合并。
高频小包场景需用 write-combining 内存类型批量提交。

### 8.2 关键参数

| 项目 | 说明 |
|---|---|
| **MPS** (Max Payload Size) | 每 TLP 最大载荷。默认常见 128B,系统按最小公共值协商。调到 256/512B 减少 TLP 数量 |
| **MRRS** (Max Read Request Size) | 影响 TX 时 NIC 读取包数据的粒度 |
| **TLP 开销** | 每 TLP 约 24–30B 固定开销。传 64B descriptor 时开销接近 50%——小包场景 PCIe 带宽"打折"的原因 |
| **Relaxed Ordering** | 允许 TLP 重排,避免 head-of-line blocking。多数 NIC 场景建议开 |
| **Gen / Lane** | Gen3 x8 实际可用约 63Gbps。100G 网卡插 Gen3 x8 必成瓶颈 |
| **插槽位置** | 必须插在 CPU 直连的 root complex。经 PCH(DMI)或 PCIe switch 转接会增加数百纳秒并可能失去 DDIO |

### 8.3 IOMMU

`intel_iommu=on` 提供设备隔离,代价是每次 DMA 都要地址翻译,IOTLB miss 显著增加抖动。

- 宿主机跑 DPDK:用 `iommu=pt`(passthrough),保留 VFIO 可用性但跳过翻译开销
- DMA buffer 用 huge page,大幅减少 IOTLB 条目消耗
- 设备支持 ATS 时,让设备侧缓存翻译结果

### 8.4 TPH / Steering Tags

TLP Processing Hints 允许设备在 TLP 里携带提示,告诉 root complex
**把数据放进哪个 cache**。这是"定向 DDIO"——让包直接落在处理它的那个核的 LLC slice 上。
需 NIC、平台、驱动三方支持。

---

## 9. 抖动源:看不见的部分

这类问题的特征:**平均延迟很好看,p99.9 和 max 惨不忍睹,而 perf 里什么都看不到**。

### 9.1 C-state(最常见的元凶)

核心进入 C6 后**退出延迟可达几十到上百微秒**。busy spin 的线程不受影响;
但"平时安静突然爆发"的模式,第一发很容易被打。

```bash
# 方法一:内核参数
intel_idle.max_cstate=0 processor.max_cstate=1 idle=poll

# 方法二:PM QoS(运行时,更灵活)
# 打开 /dev/cpu_dma_latency 写入 0,并保持 fd 不关闭
```

BIOS 里同时关掉 package C-state 和 Energy Efficient Turbo。

### 9.2 Uncore 降频

见 3.4 节。这是本文强调的隐蔽项——**监控显示核心频率正常,但内存子系统慢了一倍**。

### 9.3 SMI / SMM

System Management Interrupt 把核心拉进 SMM 模式,**操作系统完全不可见、不可屏蔽**,
持续几十到几百微秒。来源:BIOS 温度轮询、内存 ECC 巡检、电源管理、USB 模拟。

```bash
rdmsr -p 3 0x34    # SMI 计数器,隔段时间读两次,稳定核心上应基本不增长
```

**若发现某核 SMI 持续增长,再怎么调软件都是白费。**

### 9.4 其他

| 项 | 建议 |
|---|---|
| **P-state** | governor 设 `performance`;多数做法是锁定在全核 turbo 频率(确定性优于峰值) |
| **AVX 降频** | Skylake-SP 那代重度 AVX-512 会触发频率许可降档,拖慢同核其他代码;Ice Lake 后改善,热路径仍需谨慎 |
| **HT / SMT** | 关闭,或至少保证 sibling 核空闲。共享 L1/L2 和执行端口是抖动来源 |
| **推测执行缓解** | `mitigations=off`。KPTI 每次 syscall 多 100–300ns 且刷 TLB,retpoline 拖慢间接跳转。收益大,需评估安全边界 |
| **SNC** | Sub-NUMA Clustering 切分 socket 降低 LLC/mesh 内部延迟,前提是已做细致绑核 |
| **硬件预取器** | MSR `0x1A4` 控制四个预取器。默认全开通常最好,顺序性弱的负载可试关 adjacent-line 提升确定性——必须实测 |
| **时钟源** | `clocksource=tsc`,确认 invariant TSC |
| **内存** | 插满所有通道、1DPC、关闭 node interleaving |
| **CPU 隔离** | `isolcpus` + `nohz_full` + `rcu_nocbs` + IRQ 排除 |

---

## 10. Kernel Bypass:阶梯与代价

| 方案 | 机制 | 延迟量级 | 代价 |
|---|---|---|---|
| `AF_XDP` | eBPF 在驱动层把包送进用户态 UMEM ring | 1–2 μs | 需自实现协议;可只劫持特定流,兼容性最好 |
| Onload | `LD_PRELOAD` 拦截 libc socket,用户态 TCP 栈 | ~1–2 μs | 应用零改动、兼容 epoll;绑定 Solarflare 硬件 |
| DPDK | PMD 轮询完全接管网卡 | ~1 μs | 独占核;协议栈自理(mTCP/F-Stack/VPP) |
| ef_vi / TCPDirect | 直接操作 NIC 的 VI 队列 | <1 μs | API 底层,开发量大 |
| FPGA / SmartNIC | 硬件实现 tick-to-trade | 数百 ns | 开发成本极高,策略复杂度受限 |

**共同代价**:失去 tcpdump、iptables、内核路由、内核统计,运维与调试难度陡增,CPU 独占。

**判断准则:先测量,确认延迟确实卡在内核路径上,再决定是否 bypass。**
很多系统的实际瓶颈在应用层的锁、内存分配或日志上,上了 DPDK 也不会变快。

---

## 11. 测量方法论

不测量的优化都是猜测。

### 11.1 分段时间戳:定位在哪一段

`SO_TIMESTAMPING` 可拿到三个时间点:

1. `SOF_TIMESTAMPING_RX_HARDWARE` — 网卡硬件时间戳(需 PTP 对时)
2. `SOF_TIMESTAMPING_RX_SOFTWARE` — 内核 softirq 处理时刻
3. 应用 `recv` 返回后自己打的 `rdtscp`

| 差值大 | 指向 |
|---|---|
| ① → ② | 中断合并、IRQ 亲和性、softirq 被抢占 |
| ② → ③ | 唤醒和调度路径 → 上 busy poll |
| ③ 之后 | 应用自身问题,与 socket 无关 |

### 11.2 验证 DDIO 是否在漏

```bash
perf stat -a -e uncore_imc/cas_count_read/,uncore_imc/cas_count_write/ sleep 10
```

**判据要谨慎**:稳定收包时,若 DDIO 有效且应用很快消费,包数据本身不应立刻形成大量 DRAM
写流量。但 IMC 计数包含全系统写回、应用写、内核活动和其他进程,不能单独作为 DDIO 命中率。
若隔离环境下 `cas_count_write` 随包速明显线性增长,可怀疑 DDIO 在漏(leaky bucket),
第一件事是缩小 ring size 和 in-flight 量,然后结合 LLC/CHA 事件重测。

更细可看 CHA 的 `LLC_VICTIMS` 确认是否 I/O 流量在驱逐,
以及 `resctrl` 的 MBM 计数器按进程归属内存带宽。

### 11.3 用 cycle 做归因

```bash
perf stat -e cycles,instructions,ref-cycles,\
mem_load_retired.l3_hit,mem_load_retired.l3_miss <进程>
```

- `cycles / instructions` = IPC。热路径 IPC 从 2.0 掉到 0.5,基本是在等内存
- `cycles / ref-cycles` = 实际频率相对基频的倍数,顺便验证有无偷偷降频
- `l3_miss` 计数大体对应昂贵内存访问,但具体代价取决于本地/远端 NUMA、uncore 频率和是否被预取隐藏

**注意 IPC 会骗你**:频率升高时分母因内存等待而膨胀,IPC 下降但实际吞吐可能略升。
IPC 只在同频率下横向比较才有意义。

### 11.4 扫描实验:验证断崖

固定包速,把 ring size / mempool size 从小到大扫一遍,画出 `l3_miss` 与 p99。
若 DDIO 容量或 set 冲突是主因,通常会看到明确拐点而非平滑上升。**拐点位置就是这台机器、
这组队列/分配器/流量模式下的实际有效容量,比任何理论计算都准**。

### 11.5 通用纪律

- 用交换机端口镜像 + 独立抓包设备做 wire-to-wire 验证,避免自己测自己
- **只看 avg 等于没测**,必须看 p99 / p99.9 / max
- 跨频率、跨机器比较一律换算成 ns

---

## 12. 优先级:按投入产出比排序

```
1. NIC 的 NUMA 归属 + 线程/内存/中断绑定        ← 免费,收益极大
2. 关 C-state、锁 uncore 频率、查 SMI            ← BIOS 层面,免费
3. rx-usecs=0、关 GRO/LRO、ring 与 in-flight 收敛 ← 一条 ethtool 命令
4. TCP_NODELAY / QUICKACK / buffer 收小          ← 几行 setsockopt
5. LIFO free list、避免 2 的幂对齐                ← 分配器改造,收益隐蔽但可观
6. busy poll / run-to-completion 架构            ← 架构改动,收益微秒级
7. CAT 隔离 LLC                                  ← 有 noisy neighbor 时才需要
8. Kernel bypass                                 ← 前面都做完仍不够时再上
```

---

## 13. 完整成本链

把全文合成一条链,每一环对应一类优化:

```
网线
 ├─ NIC 硬件解析                → SmartNIC / FPGA offload
 ├─ PCIe TLP 传输               → MPS/MRRS、Gen/lane、插槽位置、relaxed ordering
 ├─ IOMMU 地址翻译              → iommu=pt、huge page DMA buffer
 ├─ DMA 落点                    → DDIO(in-flight 要小、NUMA 要对、CAT 隔离、地址打散)
 ├─ 通知机制:中断/softirq/唤醒  → busy poll、IRQ affinity、关中断合并
 ├─ 协议栈处理                  → kernel bypass、cache 局部性
 ├─ 内核→用户拷贝               → mmap ring、零拷贝
 └─ 应用逻辑                    → 预热、无锁、无分配
     ↑ 全程叠加:C-state、uncore 降频、SMI、跨 NUMA、AVX 降频
```

---

## 14. 结论

**三条主线:**

1. **成本模型先于参数清单。** 所有 socket 优化都归入四类:消除排队、消除切换、
   消除拷贝、消除失效。参数只是原理的投影。

2. **度量单位决定结论的正确性。** 芯片上有三个独立时钟域,cycle 是刻度而非物理量。
   每个成本项都要问清它的**原生单位**:L1/L2 的不变量是 core cycles,
   DRAM 的不变量是 ns,混用会让"尺子变细"被误读为"变慢",也会让 uncore 降频这类
   真实故障隐身。同理,`rdtsc` 计的是墙钟而非 cycles——在 turbo 常态下系统性低估,
   且偏差单向、无法被平均掉。

3. **很多失效首先是工作集问题,而非速度问题。** 在 `N·b < C` 这个一阶模型里,
   包速与频率完全抵消——这意味着这类问题通常无法靠更快的核心频率解决,只能靠约束
   in-flight 工作集、改善地址分布和提升消费速度。真实硬件的过渡不一定是理想断崖,
   但 p99 上常表现为突然塌方。

**最后一条经验:平台层优化不改变代码逻辑,只改变数据在硬件里走的物理路径。
收益通常在 100ns 到 10μs 之间,配置成本极低,但因为完全不可见,不主动测量就永远发现不了——
而错误配置(in-flight 过大、NUMA 错位、C-state 没关、uncore 降频)的代价,
往往比在应用层辛苦优化掉的还多。**
