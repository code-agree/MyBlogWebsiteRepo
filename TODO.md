# 技术文章待做清单

> 基于现有 ~80 篇技术文章的体系分析，梳理需要深入研究和撰写的方向。  
> 创建日期：2026-04-10  
> 核心主线：**高频交易系统的低延迟 C++ 工程**

---

## 技术体系全景

```
                        ┌─────────────────────────────────┐
                        │     HFT 低延迟系统（核心主线）      │
                        └──────────────┬──────────────────┘
           ┌───────────────┬───────────┼───────────┬────────────────┐
           ▼               ▼           ▼           ▼                ▼
    ┌──────────┐   ┌──────────┐ ┌──────────┐ ┌──────────┐   ┌──────────┐
    │ CPU/硬件  │   │ 内存管理  │ │ 并发编程  │ │ 网络I/O  │   │ 交易业务  │
    │ 微架构    │   │          │ │          │ │          │   │ 系统设计  │
    └────┬─────┘   └────┬─────┘ └────┬─────┘ └────┬─────┘   └────┬─────┘
         │              │            │             │              │
    ┌────┴────┐   ┌─────┴────┐ ┌────┴─────┐ ┌────┴─────┐  ┌─────┴─────┐
    │缓存/流水线│   │HugePage  │ │ 原子操作  │ │TCP优化   │  │ OrderBook │
    │分支预测  │   │NUMA      │ │ 内存序    │ │DPDK      │  │ 做市模型  │
    │False     │   │Page Table│ │ Lock-Free │ │io_uring  │  │ 订单管理  │
    │Sharing   │   │mmap/COW  │ │ Mutex演进 │ │epoll     │  │ 背压机制  │
    │MESI协议  │   │栈/堆管理  │ │ EventBus │ │WebSocket │  │ 批量处理  │
    └─────────┘   └──────────┘ └──────────┘ │Aeron IPC │  └───────────┘
                                            │Raw Socket│
         ┌──────────┐    ┌──────────┐       └──────────┘
         │ C++ 语言  │    │ 调试工具  │
         │          │    │          │
         ├──────────┤    ├──────────┤
         │模板/CRTP  │    │perf 全栈 │
         │C++17特性  │    │strace    │
         │位域压缩   │    │coredump  │
         │容器选型   │    │GDB/addr2l│
         │编译器优化  │    │vmstat    │
         └──────────┘    └──────────┘
```

---

## 各领域深度评估

| 领域 | 文章数 | 覆盖度 | 深度 | 评价 |
|------|-------|--------|------|------|
| 并发编程（原子/内存序/Lock-Free） | 10 | ★★★★★ | ★★★★☆ | 最强领域，从硬件指令到队列实现有完整链路 |
| 网络 I/O（TCP/DPDK/epoll/io_uring/WS） | 18 | ★★★★★ | ★★★★☆ | 覆盖最广，收包全路径文章达到专家级 |
| CPU 微架构（缓存/分支/流水线） | 6 | ★★★★☆ | ★★★★☆ | 分支预测文章达专家级，MESI/False Sharing 深入 |
| 内存管理（NUMA/HugePage/TLB/mmap） | 7 | ★★★★☆ | ★★★★☆ | NUMA 文章达专家级，HugePage+DPDK 链路完整 |
| 崩溃调试（coredump/SEGV/竞态） | 6 | ★★★★☆ | ★★★★★ | 最有实战深度，无 coredump 下的静态分析能力突出 |
| C++ 语言特性与容器 | 12 | ★★★★☆ | ★★★☆☆ | 覆盖广但多为中级，缺少 C++20/23 现代特性 |
| 性能分析工具（perf/strace） | 5 | ★★★☆☆ | ★★★★☆ | perf 全栈用法深入，但缺少 eBPF 等现代工具 |
| 交易系统设计（OrderBook/做市/订单） | 8 | ★★★☆☆ | ★★★☆☆ | 有框架设计但实现细节和实测数据偏少 |
| 编译器优化 | 2 | ★★☆☆☆ | ★★★☆☆ | O0-O3 原理深入，但 PGO/LTO 等实战缺失 |
| 区块链（Solana） | 2 | ★★☆☆☆ | ★★☆☆☆ | 中级实践，RPC 订阅层面 |

---

## P0 — 关键缺口（直接影响系统正确性/性能）

### [ ] 1. 无锁编程的内存回收

- **现状**: 多篇文章实现了 lock-free 数据结构，但几乎没有讨论安全内存回收
- **需要覆盖**:
  - Hazard Pointer 原理与实现
  - Epoch-Based Reclamation (EBR)
  - RCU userspace (liburcu)
  - ABA 问题的系统性分析与解决方案
- **为什么重要**: ABA 问题是 lock-free 编程中最常见的生产事故根因；现有 Michael-Scott 队列和 CAS-based free list 都受此影响
- **目标深度**: 专家级 — 实现一个带 hazard pointer 的 lock-free queue 并 benchmark
- **关联文章**: `lockfree_programming_techniques.md`、`lockfree_eventbus_performance_analysis.md`、`memory_ordering_in_cpp.md`

### [ ] 2. eBPF/XDP 内核可观测性与网络加速

- **现状**: 性能分析依赖 perf/strace，网络加速只覆盖 DPDK
- **需要覆盖**:
  - BPF CO-RE (Compile Once, Run Everywhere) 基础
  - bpftrace 单行脚本实战（替代 strace/perf 的场景）
  - XDP 收包加速原理与实现
  - AF_XDP socket — 不需要独占网卡的内核旁路方案
  - libbpf C 语言编程接口
  - 与 DPDK 的优劣对比
- **为什么重要**: eBPF 是 Linux 性能工程的未来方向；XDP 是 DPDK 之外唯一成熟的内核旁路方案
- **目标深度**: 深入原理 — 从 kprobe 到 XDP redirect 的实战
- **关联文章**: `how_to_use_perf.md`、`strace.md`、`dpdk_application.md`、`net_proc.md`

### [ ] 3. 编译器工具链深度（PGO + LTO + Sanitizers）

- **现状**: 编译器优化只覆盖 O0-O3 的原理，实战工具链缺失
- **需要覆盖**:
  - **PGO**: 对 HFT 热路径的分支布局和内联决策的影响，建立 profile 采集 pipeline
  - **LTO**: 跨翻译单元内联，对模块化 HFT 系统的编译产出影响
  - **ThinLTO**: 大型项目中 Full LTO 的可扩展替代
  - **Sanitizers 实战**: ASan（内存越界）、TSan（数据竞争）、UBSan（未定义行为）
  - `-march=native` 与 CPU dispatch 策略
- **为什么重要**: 分支预测文章已达专家级，但缺少把认知转化为编译产出的最后一环
- **目标深度**: 中级实践 — 建立 HFT 项目的 PGO pipeline 并量化延迟改善
- **关联文章**: `compile_perf.md`、`if_pre.md.md`、`inline_function_optimization.md`

### [ ] 4. 发包路径（TX Path）优化

- **现状**: `net_proc.md` 详细覆盖了收包全路径（RX），发包路径完全空白
- **需要覆盖**:
  - `dev_queue_xmit` 内核发包流程
  - qdisc 层（Traffic Control）及其锁竞争问题
  - TSO/GSO 硬件卸载原理
  - `sendmmsg` / `io_uring` 批量发送
  - Busy polling 双向（收发同核轮询）
  - 与收包路径的对称分析
- **为什么重要**: HFT 的订单发送延迟同样关键，qdisc 锁竞争是已知瓶颈
- **目标深度**: 专家级 — 补全收发包的对称分析
- **关联文章**: `net_proc.md`、`network_queue.md`、`ws_send.md`

---

## P1 — 体系完整性提升

### [ ] 5. C++20/23 现代特性在 HFT 中的应用

- **现状**: C++ 语言覆盖停留在 C++17
- **需要覆盖**:
  - **Coroutines (C++20)**: 异步 I/O 的零开销抽象，替代回调地狱；与 io_uring 的协程封装
  - **std::expected (C++23)**: 比 optional 更完整的错误处理（try_catch 文章的自然延伸）
  - **Ranges/Views (C++20)**: 惰性求值管道，数据处理链的零拷贝组合
  - **Modules (C++20)**: 编译速度改善与封装性提升
  - **Deducing this (C++23)**: CRTP 的现代替代
- **目标深度**: 深入原理 — 写一篇 "C++20/23 for HFT" 的实战评估
- **关联文章**: `c++17_new_feature.md`、`try_catch.md`、`c++_basic_usage.md`（CRTP）

### [ ] 6. Linux 调度器与实时性

- **现状**: 进程线程文章为入门级，调度器部分空白
- **需要覆盖**:
  - CFS（完全公平调度器）原理 — 红黑树、虚拟运行时间
  - SCHED_FIFO / SCHED_DEADLINE 实时调度策略
  - isolcpus + nohz_full 全核隔离方案
  - PREEMPT_RT 实时内核补丁
  - irqbalance 调优与手动 IRQ 亲和性
  - cgroup cpuset 隔离
- **为什么重要**: 多篇文章提到 CPU 绑核和实时调度，但底层调度器行为未理解透彻（如 SCHED_FIFO 导致饥饿的问题）
- **目标深度**: 深入原理
- **关联文章**: `process_and_thread_management.md`、`message_queue_overstocking_solutions.md`、`numa.md`

### [ ] 7. FPGA 网络加速基础

- **现状**: 多篇文章在"未来方向"中提到 FPGA，但从未展开
- **需要覆盖**:
  - FPGA 在 HFT 中的三种模式（NIC offload / 协议栈卸载 / 全硬件策略）
  - HLS (High-Level Synthesis) 基础 — 用 C++ 描述硬件逻辑
  - Xilinx Alveo / Intel Stratix 生态
  - SmartNIC vs FPGA 的定位区别
  - 延迟对比：软件 vs DPDK vs FPGA
- **目标深度**: 入门介绍 → 中级实践
- **关联文章**: `dpdk_application.md`、`net_proc.md`

### [ ] 8. 形式化验证与正确性保证

- **现状**: 无锁算法的正确性依赖人工 review
- **需要覆盖**:
  - CDSChecker — C++ 内存模型下的并发测试
  - Relacy Race Detector — 模拟各种内存序排列
  - SPIN model checker — 协议/算法的模型检查
  - ThreadSanitizer (TSan) 实战集成
- **为什么重要**: 勘误中多处并发正确性错误（SPMC queue、CAS memory order）说明纯人工 review 不够
- **目标深度**: 中级实践
- **关联文章**: `memory_ordering_in_cpp.md`、`lock_free_queue_implementation.md`

---

## P2 — 纵深扩展（长期知识投资）

### [ ] 9. ARM 架构与弱内存模型实战

- **现状**: 所有底层分析聚焦 x86-64，ARM 仅作为对比提及
- **需要覆盖**:
  - ARMv8 内存模型（与 x86 TSO 的差异）
  - ldar/stlr 指令语义
  - 在 ARM (AWS Graviton / Apple Silicon) 上复现 memory ordering 实验
  - ARM 上 lock-free 数据结构的额外注意事项
  - DMB/DSB/ISB 屏障指令对比 x86 MFENCE
- **目标深度**: 深入原理
- **关联文章**: `mutext.md`（已有 ARM 对照表）、`memory_order_performance_analysis.md`

### [ ] 10. 内核网络栈调优（非旁路方案）

- **现状**: 网络优化主要关注 DPDK（旁路）和应用层
- **需要覆盖**:
  - `SO_BUSY_POLL` 深入 — 用户态轮询内核 socket 的原理与参数
  - `TCP_NODELAY` + `TCP_QUICKACK` 组合策略
  - `net.core.busy_read` / `net.core.busy_poll` sysctl 调优
  - 网卡 coalescing 参数（`ethtool -C`）对延迟的影响
  - GRO/LRO 对低延迟系统的负面影响量化
  - 非 DPDK 场景下的极致调优指南
- **目标深度**: 深入原理
- **关联文章**: `tcp_perf.md`、`network_queue.md`、`websocket.md.md`

### [ ] 11. 性能回归测试框架

- **现状**: 多篇文章有性能数据但测试方法论不系统
- **需要覆盖**:
  - Google Benchmark / nanobench 微基准框架
  - CI 中的延迟回归检测 pipeline
  - 统计显著性分析（p-value、effect size、置信区间）
  - perf counter 自动化采集与报告
  - 消除噪声：CPU frequency scaling、thermal throttling、NUMA 干扰
- **目标深度**: 中级实践
- **关联文章**: `perf_tool_usage_guide.md`、`cycles.md`

### [ ] 12. 存储层与时序数据

- **现状**: 交易系统设计中完全未涉及持久化/存储层
- **需要覆盖**:
  - 行情历史数据存储方案选型
  - 时序数据库对比（QuestDB / InfluxDB / DuckDB / ClickHouse）
  - mmap-based WAL (Write-Ahead Log) 设计
  - 内存映射持久化与崩溃恢复
  - 列式存储与 SIMD 查询加速
- **目标深度**: 中级实践
- **关联文章**: `zero_copy_optimization.md`（mmap 基础）、`string_memory_mapping_techniques.md`

---

## 现有文章的维护项

### [ ] 内容去重

- `lockfree_programming_techniques.md` 与 `lock_free_queue_implementation.md` 内容完全相同，合并或删除其一
- `queue_usage_patterns.md` 与 `advanced_queue_usage_patterns.md` 大量重叠，合并

### [ ] 草稿补完

- `cpu_data_structures.md` — "Cache" 和 "程序调度" 章节空白
- `process_and_thread_management.md` — "程序调度" 章节空白，中断上下文未展开
- `perf_case_study.md` — 仅 3 行，草稿状态
- `orderbook.md` — 纯 perf 输出数据，缺少分析文字

### [ ] 补实测数据

以下文章偏理论设计，需要补充 benchmark 验证：
- `backpress.md` — 性能数据全为"预期/理论值"
- `high_performance_computing_principles.md` — 只有类声明壳子
- `orderbook_implementation.md` — 缺少性能对比数据
- `batch_order_processing.md` — 缺少吞吐量/延迟测试

---

## 写作路线图

```
近期（1-2 篇）                    中期（3-5 篇）                   长期（持续）
─────────────                    ──────────────                  ───────────
① Hazard Pointer                 ④ C++20 Coroutines for HFT      ⑧ ARM 弱内存模型实战
   + Epoch-Based Reclamation        + io_uring 协程封装
② eBPF/XDP 收包加速              ⑤ Linux 调度器 + 全核隔离        ⑨ 性能回归 CI 框架
   + 对比 DPDK                      SCHED_DEADLINE 实战
③ PGO/LTO 实战                   ⑥ 发包路径全解析                 ⑩ FPGA NIC 入门
   + HFT 编译 pipeline             ⑦ 形式化验证工具实战
```

---

*最后更新：2026-04-10*
