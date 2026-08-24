+++
title = 'HFT 系统中的延迟测量与绝对时间戳：一份工程实践指南'
date = 2026-04-27T00:42:44+08:00
draft = false
tags = ["HFT", "Performance", "Linux", "Network"]
+++

> 面向 Linux/x86_64 平台,覆盖进程内耗时测量、端到端链路延迟、日志时间戳以及监管合规场景。

---

## 0. 为什么 HFT 对"时间"如此苛刻

在高频交易系统里,"时间"其实包含三个不同的工程问题,它们的解法几乎没有交集,初学者最容易混为一谈:

1. **相对延迟(Relative Latency)**:我执行一段代码/一次订单处理花了多少纳秒?内部哪段代码是瓶颈?这关心**单机内的时间差**,要求极低的测量开销和极高的精度。
2. **本机间隔与超时(Local Intervals)**:每 5 分钟跑一次校对、心跳 30 秒一次、订单 100 ms 内未回报视为超时——这关心**单机内的时间流逝**,要求时钟单调、不被 NTP 跳变干扰。
3. **绝对时间戳与跨机器比较(Absolute Timestamp)**:某事件发生在 UTC 的哪一刻?接收时刻和交易所发出时刻差多少?这关心**与外界对齐的墙上时间**,要求与交易所、监管的时间基准一致,MiFID II RTS 25 规定业务时钟偏离 UTC 不得超过 100 μs。

第一类追求极致的低开销(单次测量 <10 ns),第二类追求**逻辑正确性**(不能被时钟跳变坑),第三类追求极致的对齐精度(与 UTC 偏差 <1 μs)。本文按这三条主线展开。

---

## 1. Linux 上的时钟源总览

把所有候选工具按"离硬件远近"排一次,对应它们的精度、开销和 HFT 可用性:

| 工具 | 精度 | 单次开销 | HFT 适用 | 说明 |
|------|------|---------|---------|------|
| `rdtsc` / `rdtscp` | CPU 周期(~0.3 ns) | 15~40 cycles(~5~15 ns) | ✅ 首选 | 进程内热路径唯一能做到个位数纳秒开销的手段 |
| `clock_gettime(CLOCK_MONOTONIC)` (vDSO) | 纳秒 | ~20~30 ns | ✅ 常用 | 底层也是 TSC + 换算,省去自己标定 |
| `clock_gettime(CLOCK_MONOTONIC_RAW)` | 纳秒 | ~20~30 ns | ⚠️ 特殊 | 不受 NTP 频率调整,更"原生" |
| `clock_gettime(CLOCK_REALTIME)` | 纳秒 | ~20~30 ns | ❌ 测延迟 / ✅ 打墙钟 | 会被 NTP 跳变,不能用于计算耗时 |
| `clock_gettime(CLOCK_TAI)` | 纳秒 | ~20~30 ns | ✅ 日志 | 不含闰秒,但仍会跟随系统墙钟 step |
| `gettimeofday()` | 微秒 | ~20 ns | ❌ | 精度不够,POSIX 已不推荐 |
| HPET | 10~100 ns | 几百 ns ~ 1 μs | ❌ | MMIO 访问,比 TSC 慢数十倍 |
| NIC 硬件时间戳 | 数十 ns(含 PHY) | 内核旁路返回 | ✅ 必备 | 唯一能测 wire-to-wire 的手段 |
| `time()` / `clock()` | 秒 / 进程 CPU 时间 | — | ❌ | `time()` 太粗,`clock()` 不是墙钟 |

表中的 `clock_gettime` 开销默认假设 x86_64 新内核走 vDSO。较老内核上 `CLOCK_MONOTONIC_RAW`/`CLOCK_TAI` 可能退化为 syscall,开销会高出数倍。

---

## 2. 进程内延迟测量:`rdtsc` 深入

### 2.1 为什么是 TSC

现代 Intel/AMD 的 **invariant TSC**(CPUID 里 `constant_tsc` + `nonstop_tsc` 两个 flag)以恒定频率递增,不受 CPU 频率变化、C-state、P-state 影响。读一条 `rdtsc` 指令只要十几个周期,是软件测量的物理下限。

检查你的 CPU 是否支持:

```bash
cat /proc/cpuinfo | grep -oE "constant_tsc|nonstop_tsc|tsc_reliable" | sort -u
# 期望看到: constant_tsc, nonstop_tsc
```

再检查内核选用的 clocksource:

```bash
cat /sys/devices/system/clocksource/clocksource0/current_clocksource
# 期望: tsc
```

### 2.2 正确的读法:Fence 与 `rdtscp`

裸 `rdtsc` 可以被 CPU 乱序执行和编译器重排移动到你不期望的位置。两种主流解法:

```c
#include <x86intrin.h>

// 方案 A: rdtscp 等前面的指令完成后才读;作为起点时后面仍建议 lfence
static inline uint64_t rdtscp_start(void) {
    unsigned aux;
    uint64_t t = __rdtscp(&aux);
    _mm_lfence();
    return t;
}

// 方案 B: lfence + rdtsc(对测量起点更精确)
static inline uint64_t rdtsc_start(void) {
    _mm_lfence();
    uint64_t t = __rdtsc();
    _mm_lfence();
    return t;
}

static inline uint64_t rdtsc_end(void) {
    uint64_t t = __rdtscp(&(unsigned){0});
    _mm_lfence();
    return t;
}
```

Intel 在 "How to Benchmark Code Execution Times on Intel IA-32 and IA-64" 白皮书里推荐的典型模式是 **起点用 `CPUID; RDTSC`,终点用 `RDTSCP; CPUID`**,但 `CPUID` 本身抖动很大(有时 100+ cycles),生产代码里大多折中为 `LFENCE; RDTSC ... RDTSCP; LFENCE`。

### 2.3 TSC 到纳秒的换算

TSC 的频率需要一次性标定(进程启动时做即可):

```c
// 简化示意: 用 CLOCK_MONOTONIC 校准 TSC 频率
double calibrate_tsc_ghz(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    uint64_t c0 = rdtsc_start();

    // 忙等 100 ms,这段时间越长标定越准
    while (1) {
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double elapsed_ns = (t1.tv_sec - t0.tv_sec) * 1e9
                          + (t1.tv_nsec - t0.tv_nsec);
        if (elapsed_ns > 100e6) break;
    }
    uint64_t c1 = rdtsc_end();

    double elapsed_ns = (t1.tv_sec - t0.tv_sec) * 1e9
                      + (t1.tv_nsec - t0.tv_nsec);
    return (c1 - c0) / elapsed_ns;  // cycles per ns,即 GHz
}
```

在生产系统里,要么这样标定一次后缓存系数,要么从 `perf_event_open` 的 mmap page 或 vDSO 暴露的时间换算参数反推(高级玩法)。`/sys/devices/system/clocksource/clocksource0/` 只能看到当前/可用 clocksource,主线内核不在这里导出 TSC 频率。

### 2.4 跨 core / 跨 socket:TSC 到底能不能相减?

要先解释 "socket" 是什么:这里指**主板上的物理 CPU 插槽**(中文有时叫"路"),不是网络编程里的 socket,也不是 Unix domain socket。一台双路服务器就是主板上插了两颗独立的 CPU 芯片,每颗叫一个 socket,内部各有若干核心(core)。HFT 服务器常见 1~2 路。

```
┌───────── Socket 0 ─────────┐    ┌───────── Socket 1 ─────────┐
│  Core0 Core1 ... CoreN     │    │  Core0 Core1 ... CoreN     │
│   TSC 均派生自本包的 ART    │    │   TSC 均派生自本包的 ART    │
│  L3 / Uncore / MemCtrl     │    │  L3 / Uncore / MemCtrl     │
└──────────────┬─────────────┘    └──────────────┬─────────────┘
               └──── UPI/QPI (Intel) 或 Infinity Fabric (AMD) ──┘
       两颗 socket 共用主板同一时钟发生器的 BCLK,RESET 同时解除、TSC 同时起跳
```

**先给结论:在"内核已选用 `tsc` 作为 clocksource"的健康裸机上,跨 core 甚至跨 socket 的 TSC 读数是可以直接相减的**。"跨核不可减、减出来是负数"的印象主要来自老平台和虚拟机。原理分四层说清楚:

**第一层:同 socket 内,所有核读的是同一个计数器的派生值**。现代 Intel 上 TSC 并不是每个核独立自由跑的计数器,而是从 uncore 里同一个 **ART**(Always Running Timer,晶振直接驱动的不停表)按固定比率换算出来的:

```
TSC(core_i) = ART × (CPUID.15H.EBX / CPUID.15H.EAX) + K(core_i)
             // K 含 IA32_TSC_ADJUST 等软件可写偏移,正常情况下为 0
```

同 socket 所有核共享同一个 ART 和同一个比率,只要各核的偏移一致,任意两个核读到的 TSC 就落在同一条时间轴上,相减天然成立。AMD 结构类似(per-package 计数器 + 公共参考时钟)。

**第二层:跨 socket 由同一个参考时钟驱动、同时起跳**。典型 1~2 路服务器主板上,100 MHz BCLK 由同一颗时钟发生器分发给两颗 CPU——两边的 ART 用的是**同一个频率源**,不存在"各自晶振 ppm 级漂移、越跑越远"。上电时 RESET 对两颗 CPU 同时解除,TSC 从 0 同时起跳。硬件层面残留的只是时钟分发路径造成的固定小偏差,量级纳秒到几十纳秒。

**第三层:内核开机时替你验证过了**。Linux 在每个 CPU 上线时运行同步校验(`arch/x86/kernel/tsc_sync.c`):两个 CPU 交替读 TSC,检查是否观察到"时间倒流";支持 `IA32_TSC_ADJUST` 的平台还会校验各核该 MSR 是否一致,不一致直接修平。校验失败会打印 `Marking TSC unstable` 并放弃 tsc clocksource。反过来说,**你的系统正在用 tsc clocksource,这件事本身就是跨核一致性的证明**。

**第四层:vDSO 每天都在做跨核相减**。`clock_gettime(CLOCK_MONOTONIC)` 的 vDSO 实现就是"在**当前核**上执行 `rdtsc`,套一组**全局**的 mult/shift 和基准值"。线程这次在 Core 3 调用、迁移到 Core 10 再调用,内核依然承诺结果单调——这个承诺成立的前提恰恰是跨核 TSC 可比。(vDSO 里有一个防倒流细节:读数若小于上次 timekeeping 更新记录的 `cycle_last` 就取后者,这正说明内核清楚残余 skew 存在但仅纳秒级、可掩盖。)跨线程测 handoff 延迟——收包线程打戳写共享内存、策略线程消费后相减——也是同一原理,这是 HFT 的标准做法。

那"不能相减"的说法从哪来?以下场景是真的不能:

- **虚拟机**:hypervisor 做 TSC offsetting,vCPU 调度、live migration 后 offset 会变,guest 里跨 vCPU 相减不可信(底层机制见下面小节)。
- **异常路径**:S3 挂起恢复、物理 CPU 热插拔、SMM/BIOS 写过 `IA32_TSC`/`IA32_TSC_ADJUST` 之后可能留下跨核偏移。内核 watchdog 通常能抓到并降级 clocksource——除非你把它关了(见 3.1 的 `tsc=reliable`)。
- **老平台**:pre-Nehalem 的 Intel、TSC 随 P-state 变频的老 AMD——"减出来是负数"的恐怖故事大多来自那个年代。
- **超短间隔**:同步校验和时钟分发的精度有限,跨 socket 残余 skew 最坏几十 ns。被测间隔比 skew 还短时,跨核相减确实可能出小负数。**测个位数纳秒必须同核**,这一条是严格成立的。

#### 为什么裸机可以、虚拟机不行

核心区别一句话:**裸机上 `rdtsc` 读到的是物理计数器本身;VM 里读到的是"物理计数器 + 一个 per-vCPU 的软件变换"**,这个变换是否跨 vCPU 一致,只靠 hypervisor 的簿记维持——硬件不保证,guest 也无法验证。

裸机上,时间轴由前面四层说的硬件物理性质决定;唯一能破坏它的软件手段(写 `IA32_TSC`/`IA32_TSC_ADJUST`)在**你自己内核**的掌控之下,开机校验过、watchdog 盯着,证据链闭环。

VM 里,硬件虚拟化给 `rdtsc` 加了一层变换。Intel VMX 下:

```
guest_TSC = (host_TSC × TSC_multiplier) >> 48 + TSC_OFFSET
             └── TSC scaling,跨频率迁移用 ──┘   └─ per-vCPU 字段 ─┘
```

`TSC_OFFSET` 和 multiplier 都是 **per-vCPU** 的 VMCS 字段(AMD SVM 对应 VMCB offset + `TSC_RATIO`)。guest 执行 `rdtsc` 不触发 VM exit,硬件自动套上**这个 vCPU 自己的**变换再返回——每个 vCPU 看到的时间轴是 hypervisor 逐个构造出来的虚拟量。让所有 vCPU 的 offset 相等只是 hypervisor 的尽力而为,以下事件会让它们悄悄错开:

- **vCPU 创建时刻不同 / 热插拔**:每个 vCPU 的 offset 在创建时单独计算,起点自带误差;KVM 会用启发式(短窗口内写相同目标值判定为"同步意图")对齐,但那是 heuristic 不是硬件保证。
- **guest 写 TSC 被虚拟化成只改本 vCPU 的 offset**——裸机上会被 `tsc_sync` 修平的操作,VM 里反而成了偏差来源。
- **快照恢复、live migration**:换宿主机后 host TSC 的值和频率都变,hypervisor 逐 vCPU 重建 offset(频率不同还要设 scaling),各自带误差,且 guest 全程无感知。
- **catchup 退化**:宿主机不支持 TSC scaling 却要呈现不同频率时,KVM 退到软件"追赶"模式,逐 vCPU 动态调虚拟 TSC,一致性没有下限。

关键的不对称在**可验证性**:guest 的 `tsc_sync` 校验只在 guest 启动那一刻跑过,验证的是"此刻 hypervisor 把 offset 摆齐了";之后 offset 随迁移、快照随时变,guest 既感知不到也无法重新校验。信任根从"硬件 + 自己的内核"变成了"hypervisor 的持续善意"。

这也正是 **kvmclock/pvclock** 存在的原因:KVM 给每个 vCPU 一页 `{tsc_timestamp, system_time, mult, shift}` 换算参数,guest 用"本核 rdtsc + 本 vCPU 参数"算时间,绕开跨 vCPU 直接比较;只有 hypervisor 通过 `PVCLOCK_TSC_STABLE_BIT` 明确承诺 TSC 稳定同步时,guest 的 vDSO 才敢直接用裸 rdtsc。所以 VM 里 `current_clocksource` 常见 `kvmclock`/`hyperv_clocksource` 而不是 `tsc`——这是 guest 内核在告诉你:这台机器上裸 TSC 不可全信。反之,若 VM 里 clocksource 就是 tsc 且平台明确承诺(如 AWS Nitro 暴露 invariant TSC、不做 live migration),跨 vCPU 相减通常也没问题——但那是平台承诺,不是裸机那种可自证的硬件性质,HFT 的保守做法仍是 VM 里不信裸 TSC 跨核比较。

实战后果:

```c
// 线程在 Socket 0 的 Core 3 上
uint64_t t0 = rdtsc_start();
// ... 线程被内核调度到 Socket 1 的 Core 10 ...
do_some_work();
uint64_t t1 = rdtsc_end();
uint64_t elapsed = t1 - t0;
// 健康裸机上这个差值本身有效;真正的问题是"迁移"这个动作
// 给测量叠加了微秒级调度开销和缓存失效,噪声远大于几十 ns 的 skew
```

应对方法:

- 生产环境仍然把线程 pin 死(`pthread_setaffinity_np` 或 `taskset`),但主要理由是**消除调度/迁移噪声、保住缓存与 NUMA 局部性、规避上面的异常路径**,而不是"跨核不可减"。
- 追求个位数纳秒精度的微基准:起点和终点必须在**同一个 core** 上读。
- 跨线程的 handoff 延迟可以放心跨核相减,前提是 clocksource 为 tsc 且 dmesg 干净(见下)。

顺带,Linux 内核对 TSC 的信任程度会写在启动日志里:

```bash
dmesg | grep -i tsc
# 期望看到: "clocksource: Switched to clocksource tsc"
# 不期望看到: "Marking TSC unstable due to ..."
```

如果内核判定 TSC unstable,会自动切换到 HPET 等慢速 clocksource,`clock_gettime` 开销飙升,这种配置在 HFT 系统上基本不可接受。

### 2.5 一个完整的测量宏

```c
#define LATENCY_PROBE(name, code_block) do {                   \
    uint64_t _t0 = rdtsc_start();                              \
    code_block;                                                \
    uint64_t _t1 = rdtsc_end();                                \
    hdr_record_value(g_hist_##name, (_t1 - _t0));              \
} while (0)

// 使用:
LATENCY_PROBE(order_encode, {
    encode_fix_message(&msg, buf);
});
```

把周期数直接喂给 HdrHistogram,**事后**再转换为纳秒展示——避免在热路径做浮点乘法。

---

## 3. 系统层调优:再精的表挡不住 OS 抖动

哪怕测量工具本身只有 5 ns 开销,一次时钟中断、一次内核线程抢占就能给你加上几十微秒尾延迟。HFT 系统必做的内核调优清单:

### 3.1 CPU 隔离

```bash
# /etc/default/grub 中添加
GRUB_CMDLINE_LINUX="isolcpus=2-15 nohz_full=2-15 rcu_nocbs=2-15 \
                    mitigations=off intel_idle.max_cstate=0 \
                    processor.max_cstate=0 idle=poll tsc=reliable"
```

- `isolcpus`:从调度器里拿走这些核,普通进程不会被调度上来。
- `nohz_full`:尽量让这些核进入 full tickless 模式,减少 1000 Hz 抖动;单 runnable 任务时仍可能保留 1 Hz 残余 tick。
- `rcu_nocbs`:把 RCU 回调卸载到其他核。
- `idle=poll` + `max_cstate=0`:禁止 CPU 进入节能状态,避免唤醒延迟(代价是功耗飙升,发热严重)。
- `mitigations=off`:关掉 Spectre/Meltdown 缓解(自行评估安全 vs 性能的权衡)。
- `tsc=reliable`:跳过开机 TSC 同步校验、关闭 clocksource watchdog,省去 watchdog 定时器带来的抖动;代价是 2.4 节"内核替你验证"这层保险没有了,同步真被破坏时无人报警。建议先在不带此参数的内核下确认 dmesg 干净,再加上它。

把交易热路径线程 pin 到这些隔离核:

```c
cpu_set_t mask;
CPU_ZERO(&mask);
CPU_SET(2, &mask);
pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask);
```

### 3.2 频率锁定

```bash
cpupower frequency-set -g performance
cpupower frequency-set -d 3.5GHz -u 3.5GHz   # 锁死频率,关 Turbo
```

锁频的意义不在于让 TSC 更准(invariant TSC 本来就恒频),而在于让**你的代码**每次都以同样的速度运行,消除基准测试噪声。

### 3.3 中断亲和性

把网卡中断 pin 到**非交易核**(通常是同 NUMA 的相邻核),避免 IRQ 抢断热路径:

```bash
echo 0 > /proc/irq/<nic_irq>/smp_affinity_list
```

如果行情/订单流量走 kernel bypass 并由用户态 poll 队列,IRQ 亲和性主要影响控制面和仍走内核栈的流量;热路径还要看 bypass 框架自己的队列/线程绑定。

### 3.4 大页与 NUMA

- 预分配 huge page,避免 TLB miss 和缺页中断带来的微秒级毛刺。
- 内存分配用 `numactl --membind`,保证数据和线程在同一 NUMA 节点。

### 3.5 关闭 THP(透明大页)

THP 的后台整理会导致不可预期的停顿,HFT 要么用显式 hugepage,要么全关:

```bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

---

## 4. 本机周期任务与超时判断

不是所有时间相关的代码都在测纳秒级延迟。HFT 系统里有一类常见需求:**"每 N 秒/分钟做一次某事"** 或 **"如果某事 X 秒内没发生就告警"**——比如每 5 分钟做一次持仓校对、每 30 秒发一次心跳、订单 100 ms 内未回报视为超时。

这类场景的核心规则只有一句:**用单调钟,绝不用墙钟**。

### 4.1 为什么不能用 `CLOCK_REALTIME`

墙钟会跳变。NTP 同步、管理员手动改时间、夏令时切换——任何一次跳变都会让你的"超时判断"出错:

- 时钟被往**回**拨 3 分钟:`now - last` 变小甚至变成负数,周期任务迟触发,或者干脆永远不触发。
- 时钟被往**未来**拨 3 分钟:`now - last` 突然变大,周期任务提前触发,超时判断也会误报。

这种 bug 在生产环境真的会发生,而且通常出现在凌晨某次 NTP 大幅修正之后,极难复现。

### 4.2 正确写法

```c
struct timespec last, now;
clock_gettime(CLOCK_MONOTONIC, &last);

while (running) {
    // ... 其他工作 ...
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (now.tv_sec - last.tv_sec >= 300) {    // 5 分钟
        do_periodic_task();
        last = now;
    }
}
```

各语言对应物记一句口诀:**"测间隔用 monotonic,打墙钟用 realtime"**。

| 语言 | 测间隔/超时 | 不要用 |
|------|------------|--------|
| C/C++ | `clock_gettime(CLOCK_MONOTONIC)`、`std::chrono::steady_clock` | `system_clock`、`time()` |
| Java | `System.nanoTime()` | `System.currentTimeMillis()` |
| Go | `time.Since(t)`(Go 1.9+ 自动用 monotonic) | 手动减 `time.Now().Unix()` |
| Python | `time.monotonic()` | `time.time()` |
| Rust | `std::time::Instant` | `SystemTime` |

### 4.3 进阶:`timerfd` 与事件循环整合

如果周期任务是程序的主要节奏,比 while-loop 轮询更优雅的方式是 `timerfd`,天生基于 `CLOCK_MONOTONIC`,可以挂到 `epoll` 上和网络 I/O 一起处理:

```c
int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
struct itimerspec its = {
    .it_interval = { .tv_sec = 300, .tv_nsec = 0 },  // 每 5 分钟
    .it_value    = { .tv_sec = 300, .tv_nsec = 0 },  // 首次 5 分钟后触发
};
timerfd_settime(tfd, 0, &its, NULL);

epoll_ctl(epfd, EPOLL_CTL_ADD, tfd, &ev);
// 事件循环里 tfd 可读时 read(tfd, ...) 然后执行任务
```

不占轮询 CPU,跟 epoll 事件驱动模型天然整合。HFT 系统的健康检查、定期 rebalance、session 心跳基本都是这个模式。

---

## 5. 端到端延迟:NIC 硬件时间戳

进程内的 `rdtsc` 测不到网卡收包到用户态这段——这段可能有几微秒的抖动。真正的 **tick-to-trade** 测量必须借助网卡硬件时间戳。

### 5.1 工作原理

支持 PTP 的网卡(Solarflare/Xilinx X2、Mellanox/NVIDIA ConnectX-4/5/6、Intel E810 等)在 MAC/PHY 层对每个收到的包打上一个硬件时间戳(来自网卡自带的 **PHC — PTP Hardware Clock**)。这个时间戳跟着 skb 走,最终通过 `recvmsg` 的 ancillary data(`SCM_TIMESTAMPING`)交给用户态。

### 5.2 启用方法

```c
// 还需要先对网卡下 SIOCSHWTSTAMP ioctl(或用 hwstamp_ctl/ethtool netlink)启用硬件打戳;
// ptp4l 常会代劳。只设置 socket option 时,网卡未启用会导致 ts[2] 一直为 0。
int flags = SOF_TIMESTAMPING_RX_HARDWARE
          | SOF_TIMESTAMPING_RAW_HARDWARE
          | SOF_TIMESTAMPING_TX_HARDWARE;
setsockopt(sock, SOL_SOCKET, SO_TIMESTAMPING, &flags, sizeof(flags));
```

收包时解析 cmsg:

```c
struct msghdr msg = {0};
char ctrl[512];
msg.msg_control = ctrl;
msg.msg_controllen = sizeof(ctrl);
recvmsg(sock, &msg, 0);

for (struct cmsghdr *cm = CMSG_FIRSTHDR(&msg); cm; cm = CMSG_NXTHDR(&msg, cm)) {
    if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_TIMESTAMPING) {
        struct scm_timestamping *ts = (struct scm_timestamping *)CMSG_DATA(cm);
        // ts->ts[2] 是硬件 raw timestamp
    }
}
```

对 TX 方向,可以启用 TX timestamp 让网卡在发出包的瞬间打戳,通过 error queue 返回——这样就能精确测量"订单从内存到线上"的耗时。

### 5.3 旁路方案

更激进的路线是直接绕过内核协议栈,用 **DPDK**、**Solarflare OpenOnload**、**Mellanox VMA/XLIO** 或 **ef_vi** 这类 kernel bypass 框架,时间戳同样由硬件提供,但用户态直接 poll 网卡队列,省去系统调用和中断开销。这是目前主流 HFT 的标准配置。

---

## 6. 日志绝对时间:与 UTC 对齐

测延迟用单调时钟;**打日志、给订单打时间戳**必须用可追溯到 UTC 的时钟。

### 6.1 选哪个时钟

- **`CLOCK_REALTIME`**:跟随系统墙钟,会被闰秒跳变影响,合规审计时需要小心。
- **`CLOCK_TAI`**:国际原子时,不含闰秒,适合内部日志避免 UTC 闰秒歧义。但 Linux 的 `CLOCK_TAI` 派生自系统墙钟和 TAI offset,管理员手动 step 或 PTP/NTP step 修正系统时钟时它也会跳变,不能拿来做超时/耗时判断。

从 Linux 3.10 起支持 `CLOCK_TAI`,前提是系统 TAI offset 已正确设置(`adjtimex(2)`,一般 PTP 守护进程会自动维护)。监管上报、交易所协议和对外时间戳通常仍要求 UTC,内部用 TAI 时必须在边界处显式转换。

### 6.2 PTP:如何让系统时钟精确对齐

NTP 在广域网下精度通常是毫秒级,HFT 场景完全不够用。**PTP (IEEE 1588)** 在局域网配合硬件时间戳可以做到亚微秒。

典型部署拓扑:

```
GPS/原子钟主源 → PTP Grandmaster → 交换机(Boundary/Transparent Clock) → 服务器 NIC(PHC)
                                                                          ↓
                                                                       系统时钟
```

软件栈(Linux 上通用):

- **`ptp4l`**(linuxptp):PTP 主从协议守护进程,让 NIC 的 PHC 与 Grandmaster 对齐。
- **`phc2sys`**:把 NIC PHC 的时间同步到系统 `CLOCK_REALTIME`。
- **`ts2phc`**:用 PPS 信号(比如 GPS 的 1PPS)校准 PHC。

配置示例:

```bash
# 让网卡 eth0 上的 PHC 跟随网络上的 Grandmaster
ptp4l -i eth0 -f /etc/ptp4l.conf -s &

# 把 PHC 时间每 1 秒同步到系统时钟
phc2sys -s eth0 -w -m &
```

验证精度:

```bash
pmc -u -b 0 'GET CURRENT_DATA_SET'
# 看 offsetFromMaster,期望在几百纳秒以内
```

### 6.3 MiFID II / RTS 25 合规

欧洲 MiFID II 对 HFT 参与者要求业务时钟与 UTC 偏差 ≤ **100 μs**,时间戳粒度 ≤ **1 μs**,并保留审计追溯链。国内监管对高频业务也有类似要求。实务做法:

- 机房内部署带 GPS/北斗接收机的 PTP Grandmaster。
- 服务器全部 PTP,`phc2sys` 持续监控偏移并告警。
- 日志使用 `CLOCK_TAI` 或 `CLOCK_REALTIME`,精度到纳秒,并记录当前 offset-from-master 作为审计证据。

### 6.4 日志时间戳的性能考量

即便 `clock_gettime` 走 vDSO 只要 20~30 ns,在 tick-to-trade 热路径上批量打日志依然是灾难。常见优化:

1. **热路径只写 TSC + 事件 ID**,异步线程落盘时再转换为 UTC 纳秒。
2. **Ring buffer + 批量 flush**:用 mmap 共享内存 ring buffer,热路径只做指针 bump + memcpy。
3. **二进制日志格式**:避免热路径做字符串格式化(snprintf 极其昂贵)。
4. **事后合并**:TSC 时间戳 + 启动时锚点(TSC_0, UTC_0)+ TSC 频率 ⇒ 精确的 UTC 时间。

---

## 7. 跨机器时间比较:从交易所时间戳到本地接收时刻

这是 HFT 里另一个高频出错的场景:**比较"包里带的外部时间戳"和"我收到的时刻"**——算 exchange-to-local 延迟、判断行情是否过期、检测网络突发慢链路、识别 stale order ack。

核心原则一句话:**比较时间的前提是两个时间在同一时间基准上**。如果不在,就必须先想办法拉到同一基准,否则减出来的"延迟"毫无意义。

### 7.1 谁的时间在哪个基准上

外部时间戳的常见来源:

| 来源 | 时间基准 | 典型精度 |
|------|---------|---------|
| 交易所行情 `SendingTime`(FIX/ITCH/OUCH) | UTC 墙钟(交易所 PTP/GPS) | μs ~ ns |
| 交易所撮合时间戳 | UTC 墙钟 | μs ~ ns(不同市场差异很大) |
| 上游网关打的时间戳 | 上游机器墙钟 | μs |
| NIC 硬件 RX 时间戳 | 本机 PHC(PTP 同步到 PTP timescale 或 UTC) | ns |
| 应用层 `clock_gettime(REALTIME/TAI)` | 本机系统钟(PTP 同步后按所选 clock 暴露) | ns |

跨机器比较的两边**必须都是 UTC 墙钟(或 TAI),且两端时钟偏差远小于你关心的延迟数量级**。这正是 HFT 必须部署 PTP 的根本理由——NTP 那种毫秒级偏差,根本测不准微秒级的链路延迟。

### 7.2 为什么这里反而要用 `CLOCK_REALTIME` / `CLOCK_TAI`

第 4 节强调"测耗时用 MONOTONIC",但**跨机器比较时间不行**——`CLOCK_MONOTONIC` 是每台机器从自己开机点算起的,A 机器和 B 机器的 monotonic clock 之间没有任何可比性。

唯一的公共基准是 UTC/TAI,所以跨机器时间比较只能用 `CLOCK_REALTIME` 或 `CLOCK_TAI`,**靠 PTP 保证它们对齐到同一个 Grandmaster**。

`REALTIME` 还是 `TAI`:

- 交易所和监管口径大多用 UTC、`SendingTime` 是 UTC → 用 `CLOCK_REALTIME` 或把本地 TAI 显式减去 UTC offset 后再比较。
- 少数外部系统若明确给 TAI 或私有 timescale → 用 `CLOCK_TAI` 或对应 timescale,避免闰秒带来的瞬间错乱。
- CME 的公开 leap second 处理不是 smear:它在正闰秒时重复 `23:59:59`,不发送 `23:59:60`,并会拒绝带 `23:59:60` 的 iLink 消息。
- **不管选哪个,两边必须一致**。如果交易所给 UTC、你存 TAI,中间差 37 秒——典型的灾难级 bug。

### 7.3 基本写法

```c
// 接收端:收到包瞬间打本地时间戳
struct timespec rx_time;
clock_gettime(CLOCK_REALTIME, &rx_time);

uint64_t exchange_ns = parse_sending_time(packet);
uint64_t rx_ns = (uint64_t)rx_time.tv_sec * 1000000000ULL + rx_time.tv_nsec;

int64_t latency_ns = (int64_t)(rx_ns - exchange_ns);
// exchange → local 单程延迟
```

### 7.4 更精准:用 NIC 硬件 RX 时间戳

应用层 `clock_gettime` 的时间点已经包含了内核协议栈开销(几微秒到几十微秒抖动)。要测真正的 wire-level 延迟,改用第 5 节启用的 NIC 硬件时间戳:

```c
struct scm_timestamping *ts = ...;            // 从 cmsg 取出
struct timespec hw_rx = ts->ts[2];            // raw hardware timestamp
uint64_t hw_rx_ns = hw_rx.tv_sec * 1000000000ULL + hw_rx.tv_nsec;
int64_t wire_latency = hw_rx_ns - exchange_sending_ns;
```

前提是 `hw_rx_ns` 和 `exchange_sending_ns` 已经在同一时间基准上。常见 linuxptp 部署里,`ptp4l` 会让 PHC 跟随 PTP timescale(TAI),`phc2sys -w` 同步到 `CLOCK_REALTIME` 时才按 `currentUtcOffset` 转成 UTC;如果直接拿 `ts->ts[2]` 的 raw PHC 时间戳去减交易所 UTC `SendingTime`,可能恒差 37 秒。实操时要么把 PHC 时间转换到 UTC,要么确认 Grandmaster/PHC 运行在 UTC/ARB timescale。这个 `wire_latency` 排除了协议栈抖动,是软件能测到的最干净的链路延迟。DPDK、ef_vi 等 kernel bypass 框架也都暴露硬件时间戳,API 不同但概念一样。

### 7.5 解读结果时的几个陷阱

**负延迟很常见,别慌**:

- **PTP 刚启动还没收敛**:初期偏差几十微秒到毫秒,减出来就是负数。生产系统要监控 `ptp4l` 的 `offsetFromMaster`,未收敛时数据不入库。
- **交易所打戳点 ≠ 实际发出点**:有些交易所的 `SendingTime` 是撮合时刻而非网卡发出时刻,中间还有几微秒。
- **时钟轻微抖动**:PTP 收敛后 offset 通常 ±100 ns 内波动,真实延迟若本来就是几百纳秒(同机房 colo),偶尔见到负值完全正常。

**统计上保留负值,看分布而不是单点**。HdrHistogram 不支持负数,常见处理是给所有值加一个足够大的 offset(比如 1 秒)再记录,展示时减回来。

**PTP 静默失步**。PTP 可能因交换机丢包、Grandmaster 切换、网络拥塞静默失步,而代码还傻傻地在减时间戳。**必须把 offset 监控起来并写入日志**,事后排查才有据可查。一个好做法是每条延迟样本都带上当时的 PTP offset:

```c
struct latency_sample {
    int64_t  measured_latency_ns;
    int64_t  ptp_offset_ns_at_sample;   // 从 pmc/ptp4l 读
    uint64_t exchange_seq_no;
};
```

**闰秒**。UTC 偶尔插入闰秒,那一秒可能被 leap smear、stop-clock 或跳变,取决于 OS 和 PTP/NTP 配置。真出闰秒时你可能看到几百毫秒的"诡异延迟"。规避方法是内部统一使用 `CLOCK_TAI` 或明确的私有 timescale,并在对外/监管边界转换回 UTC;不要把 TAI 当成单调计时器。

**消息里时间戳的单位和纪元**。每家交易所格式不同——CME MDP3 用 UTC nanos since epoch、Nasdaq ITCH 用当日 midnight 起的纳秒、上交所/深交所某些协议常见毫秒级 `YYYYMMDDHHMMSSmmm` 或快照时间字段。**读协议文档,别凭感觉**。这里的 bug 一旦发生,所有延迟统计都是废的。

---

## 8. 数据记录:HdrHistogram

测出来的延迟怎么存?答案在 HFT 圈子里几乎没有争议——**HdrHistogram**。

### 8.1 为什么不用 `mean ± stddev`

延迟分布几乎总是重尾的。均值和标准差对正态分布才有意义,对 HFT 延迟几乎是误导。真正要看的是 p50/p99/p99.9/p99.99/max——尾延迟才是赚钱/亏钱的地方。

### 8.2 HdrHistogram 关键特性

- 记录一个值 3~6 ns,热路径可用。
- 固定内存占用,不会因样本数爆炸。
- 跨数量级保持精度(1 ns 到 1 小时同时覆盖,3 位有效数字)。
- 可序列化、可合并,多线程多机直方图能汇总成全景图。
- 自带 Coordinated Omission 补偿(`recordValueWithExpectedInterval`)。

### 8.3 典型用法(C API)

```c
#include <hdr/hdr_histogram.h>

struct hdr_histogram *hist;
hdr_init(1,              // 最小可记录值 (1 ns)
         60L*1000*1000*1000,  // 最大 60 s
         3,              // 3 位有效数字
         &hist);

// 热路径
uint64_t ns = cycles_to_ns(t1 - t0);
hdr_record_value(hist, ns);

// 报告
int64_t p99  = hdr_value_at_percentile(hist, 99.0);
int64_t p999 = hdr_value_at_percentile(hist, 99.9);
```

### 8.4 Coordinated Omission

Gil Tene 反复强调的经典陷阱:如果系统卡住 100 ms,而你的测试程序是"发一个请求等一个响应"的模式,你只会记录到**一个** 100 ms 样本,而不是卡住期间本应发出的 100 个请求都经历了不同程度的延迟。结果 p99 被严重低估。

应对:

- 用 wrk2、Gatling 这类按**恒定发送速率**而非"回环速率"的压测工具。
- 用 `hdr_record_corrected_value(hist, ns, expected_interval_ns)` 让 HdrHistogram 自动补齐缺失样本。

---

## 9. 常见陷阱清单

一份浓缩的踩坑备忘:

1. **用 `CLOCK_REALTIME` 算耗时或定时**:NTP slew、跳变会让你得到负延迟、异常大值,或者周期任务永远不触发。耗时和定时永远用 `CLOCK_MONOTONIC` 或 TSC。
2. **裸 `rdtsc` 不加 fence**:CPU 乱序会让测量点漂移几十周期甚至更多。
3. **忘记 pin CPU**:健康裸机上跨核 TSC 本身可减(见 2.4),但线程迁移会引入微秒级调度噪声和缓存失效;虚拟机与 S3/热插拔等异常路径上,跨核偏移则是真实风险。热路径线程永远 pin 死。
4. **开 Turbo Boost 做基准**:频率浮动会让同一段代码的执行周期数每次不同。
5. **在热路径用 `printf`/`snprintf`**:一次格式化几微秒,瞬间毁掉所有埋点工作。
6. **用均值看延迟**:永远看百分位,且至少看到 p99.99。
7. **忽略 Coordinated Omission**:压测工具选错,结果再漂亮都是假的。
8. **没隔离 CPU、没禁中断**:OS 抖动(SMI、NMI、timer tick)会给你随机加上几十微秒。
9. **不监控 PTP offset**:PTP 可能静默失步,日志时间戳看上去正常但早已飘了,合规审计时炸锅。
10. **TSC 频率只标定一次就不管**:长时间运行后晶振温漂(ppm 级,1 ppm 约等于每秒 1 μs 误差)和初次标定精度有限,生产系统应定期重校或用内核/vDSO 参数。
11. **跨机器减 monotonic**:`CLOCK_MONOTONIC` 在不同机器之间没有可比性,跨机器比较只能用 `REALTIME`/`TAI` + PTP。
12. **混用 UTC 和 TAI**:交易所给 UTC 你存 TAI,差 37 秒;反过来一样灾难。两端时间基准必须显式约定。
13. **闰秒未处理**:UTC 闰秒可能引发"诡异几百毫秒延迟"。内部日志可统一用 `CLOCK_TAI`,但跨机器比较和对外字段必须显式约定 UTC/TAI 基准。

---

## 10. 推荐的一站式组合

面向一个典型的 HFT 交易节点,推荐以下时钟选择:

| 场景 | 方案 |
|------|------|
| 进程内函数级延迟 | `rdtsc` + `lfence`,线程 pin 到 `isolcpus` 核心,数据进 HdrHistogram |
| 进程内普通耗时(ms 级) | `clock_gettime(CLOCK_MONOTONIC)` 走 vDSO |
| **本机周期任务 / 超时判断** | **`CLOCK_MONOTONIC`,首选 `timerfd` 接入 epoll** |
| **跨机器时间比较(收包 vs 发包)** | **`CLOCK_REALTIME` 或 `CLOCK_TAI` + PTP,两端基准约定一致** |
| 网线到网线延迟(wire-to-wire) | NIC 硬件 TX/RX 时间戳(SO_TIMESTAMPING 或 DPDK/ef_vi) |
| 内部事件日志绝对时间 | 热路径只记 TSC + event_id,异步线程转换为 `CLOCK_TAI` |
| 系统时钟对齐 | 本地 GPS Grandmaster + `ptp4l` + `phc2sys`,offset 监控告警 |
| 合规审计(MiFID II 等) | 日志落盘同时记录 PTP offset 和 TAI 时间戳,保留一年以上 |
| 压测 | wrk2 或自研 open-loop 发送器,绝不用 closed-loop |
| 可视化 | HdrHistogramVisualizer 或 `hdr-plot` 画全百分位谱图 |

---

## 11. 延伸阅读

- Gil Tene, *"How NOT to Measure Latency"* — 任何做延迟测量的工程师都应该看的演讲。
- Intel, *"How to Benchmark Code Execution Times on Intel IA-32 and IA-64 Instruction Set Architectures"* 白皮书。
- Linux kernel 文档:`Documentation/timers/`、`Documentation/PTP/`。
- `linuxptp` 项目文档:https://linuxptp.sourceforge.net/
- HdrHistogram 官方仓库:https://github.com/HdrHistogram/HdrHistogram

**本站相关**

- {{< ref "2026-03-30-cpu_bindcore" >}} — isolcpus、nohz_full、CPU 隔离与 IRQ 亲和性的完整方案
- {{< ref "2026-03-17-net_proc" >}} — 从网线到用户态的完整收包路径,理解 NIC 时间戳打点位置
- {{< ref "2026-04-25-kernel_socket_vs_dpdk" >}} — kernel socket 与 DPDK 路径的纳秒级 A/B 实测
- {{< ref "2026-04-09-buffer" >}} — Buffer/队列与延迟尾部抖动的来源
- {{< ref "2026-04-17-iceoryx_ipc_benchmark" >}} — 同风格的 HFT 纳秒级选型分析

---

## 结语

HFT 的时间测量不是"调用个 API 就行"的事——它是一套贯穿硬件、内核、网卡、协议栈、应用代码的系统工程。把所有规则浓缩成几条:

1. **测纳秒级耗时用 TSC**,前提是 invariant TSC + clocksource 为 tsc;个位数纳秒精度需同核读数,生产线程照例 pin 死。
2. **本机间隔与超时用 `CLOCK_MONOTONIC`**,绝不用墙钟,否则 NTP 跳变会咬人。
3. **跨机器比较用 `CLOCK_REALTIME`/`CLOCK_TAI` + PTP**,两端时间基准必须显式约定一致。
4. **日志绝对时间用 `CLOCK_TAI` + PTP**,合规审计时同时记录 offset。
5. **测量开销必须远小于被测对象**,否则你测到的是测量本身。
6. **永远看百分位,永远警惕 Coordinated Omission**。

把这几条刻进肌肉记忆,剩下的就是耐心调优内核参数、标定 TSC、维护 PTP 的日常功夫。

---

*发布时间:2026-04-27;CC BY 4.0,转载请署名并保留链接。欢迎讨论和指正。*
