---
title: "技术文章勘误记录"
date: 2026-04-10
draft: true
---

# 技术文章勘误记录

> 本文档记录了博客中技术文章的原理性错误修正历史。  
> 审查日期：2026-04-10  
> 共审查约 80 篇技术文章，发现并修正 61 处技术原理性错误。

---

## 严重错误（并发正确性 / 不存在的指令或API）

### 1. SPMC 队列使用 thread_local head 导致重复消费
- **文件**: `2025-06-24-memory_ordering_in_cpp.md`
- **原文**: `static thread_local size_t consumer_head` — 每个消费者线程独立维护 head 指针
- **问题**: 多消费者会从 0 开始独立递增 head，导致重复消费同一元素
- **修正**: 改为共享的 `std::atomic<size_t> head`，pop 方法使用 `compare_exchange_weak` CAS 竞争

### 2. x86 汇编中使用不存在的 `lock mov` 指令
- **文件**: `2025-06-23-cache_false_sharing_analysis.md`
- **原文**: `lock mov %eax, (%rdi)` 用于描述 relaxed atomic store
- **问题**: x86 的 LOCK 前缀只能用于 RMW 指令（lock xadd, lock cmpxchg 等），`lock mov` 会产生 #UD 异常
- **修正**: relaxed atomic store 改为普通 `mov`；seq_cst store 使用 `xchg`；RMW 操作使用 `lock xadd`

### 3. 使用不存在的 `tbb::concurrent_map` + asks 排序方向错误
- **文件**: `2025-06-24-orderbook_implementation.md`
- **原文**: `tbb::concurrent_map<double, PriceLevel, std::greater<>>` 同时用于 bids 和 asks
- **问题**: TBB 无 `concurrent_map`；asks 用 `std::greater<>` 导致最优卖价查询错误
- **修正**: 改为 `tbb::concurrent_ordered_map`；asks 使用 `std::less<>`（升序）

### 4. 声称编译器可将 atomic relaxed load 提升到循环外
- **文件**: `2025-06-19-compile_perf.md`
- **原文**: "-O3可能进一步优化为：循环外加载一次...定期重新检查running值"
- **问题**: C++ 标准禁止此优化，每次 atomic load 必须从缓存一致性域读取
- **修正**: 说明 relaxed 只放松排序约束，不影响可见性保证；每次迭代仍执行 load

### 5. SPSC 环形缓冲区被呈现为通用 lock-free 结构（2处）
- **文件**: `2025-06-24-queue_usage_patterns.md`、`2025-06-24-advanced_queue_usage_patterns.md`
- **原文**: `LockFreeRingBuffer` 无并发安全说明
- **问题**: 多生产者可能读到相同 tail 值，写入同一位置导致数据丢失
- **修正**: 添加注释说明仅适用于 SPSC 场景

### 6. 做市策略库存控制公式方向错误
- **文件**: `2025-06-24-avellaneda_stoikov_market_making.md`
- **原文**: `φ_ask = φ_max * e^{-η * q_t}` when q_t < 0
- **问题**: q_t < 0 时指数为正，ask 挂单量反而增大，与减少同方向风险的设计意图矛盾
- **修正**: 改为 `e^{η * q_t}`，q_t < 0 时指数为负，正确减少 ask 挂单量

### 7. CAS 操作内存序不足
- **文件**: `2025-06-24-lock_free_queue_implementation.md`
- **原文**: `deallocate`/`allocate` 中 CAS 使用 `memory_order_release`
- **问题**: CAS 失败路径的读操作需要 acquire 语义，在 ARM 等弱内存序架构上会导致数据竞争
- **修正**: 改为 `memory_order_acq_rel`

### 8. 位域掩码重叠
- **文件**: `2025-06-24-bit_field_compression_techniques.md`
- **原文**: `QUANTITY_MASK 0xFFFFF8` 覆盖 bit 3-23（21 bits）
- **问题**: 与 `PRICE_MASK`（bit 20 起）重叠，写入 Quantity 会覆盖 Price 低位
- **修正**: 改为 `0x000FFFF8`（bit 3-19，17 bits）

### 9. 虚构的 Linux 内核参数
- **文件**: `2025-07-01-tcp_perf.md`
- **原文**: `sysctl -w net.ipv4.tcp_use_hugepages=1`
- **问题**: 此参数不存在，TCP 栈的 sk_buff 不支持大页
- **修正**: 替换为说明性注释，指出需要 DPDK 等内核旁路方案

---

## 中等错误（概念性错误）

### 10. Cache line 大小单位错误
- **文件**: `2025-06-23-cpu_data_structures.md`
- **原文**: "cache line = 64kb"
- **修正**: 改为 "64字节(Bytes)"（差 1024 倍）

### 11. TCP 头部大小写成 UDP 头部大小
- **文件**: `2025-08-08-raw_socket.md`
- **原文**: "1000数据 + 20IP + 8TCP = 1028字节"
- **修正**: TCP 头部 20 字节，总计 1040 字节

### 12. RSS 多队列机制误解
- **文件**: `2025-08-18-network_queue.md`
- **原文**: "同一连接的不同数据包可能被分配到不同队列"
- **修正**: RSS 基于四元组哈希，同一连接的包始终进入同一队列

### 13. 单核 false sharing 机制描述错误
- **文件**: `2025-06-23-cache_false_sharing_analysis.md`
- **原文**: 单核场景下描述为"写回主存再重新加载"
- **修正**: 单核只有一个 L1 cache，上下文切换不会失效缓存行

### 14. relaxed atomic store 开销描述错误
- **文件**: `2025-06-23-cache_false_sharing_analysis.md`
- **原文**: "即使 relaxed 也仍可能触发 LOCK 指令"
- **修正**: x86 上 relaxed store/load 就是普通 `mov`，无 LOCK

### 15. 红黑树旋转次数错误
- **文件**: `2025-12-24-flat_hash_map.md`
- **原文**: "最多需要 O(log n) 次旋转操作"
- **修正**: 插入最多 2 次旋转（O(1)），O(log n) 是重着色次数

### 16. Swiss Table control bytes 存储位置错误
- **文件**: `2025-12-24-flat_hash_map.md`
- **原文**: control byte 画在 Slot 结构体内部
- **修正**: control bytes 是独立的数组

### 17. 探测策略描述不准确
- **文件**: `2025-12-24-flat_hash_map.md`
- **原文**: "线性探测/二次探测"
- **修正**: absl 只使用二次探测（三角数序列）

### 18. Swiss Table H₂ 哈希位错误
- **文件**: `2025-12-26-various_map.md`
- **原文**: "H₂，哈希值的低 7 位"
- **修正**: H₂ 使用高 7 位（低位用于桶定位）

### 19. Swiss Table kDeleted 值错误
- **文件**: `2025-12-26-various_map.md`
- **原文**: "129：已删除槽（kTombstone）"
- **修正**: kDeleted = -2（0xFE），不是 129

### 20. TLB 条目数假设错误（2处）
- **文件**: `2025-07-21-hugepage.md`、`2025-07-21-hugepage_indpdk.md`
- **原文**: 假设全部 64 个 L1 TLB 条目都可用于 hugepage
- **修正**: 说明不同页面大小有独立 TLB 条目池（如 Skylake: 2MB 页约 32 条目）

### 21. Hugepage 性能提升极端夸大
- **文件**: `2025-07-21-hugepage_indpdk.md`
- **原文**: "99.8倍性能提升"
- **修正**: 标注为理论极限值，实际提升通常 2-10 倍

### 22. IOMMU 与 DPDK 关系描述错误
- **文件**: `2025-07-21-hugepage_indpdk.md`
- **原文**: "IOMMU...与DPDK的零开销设计理念冲突"
- **修正**: 现代 DPDK 推荐 vfio-pci（基于 IOMMU）

### 23. Hugepage 跨页物理连续性错误暗示
- **文件**: `2025-07-21-hugepage_indpdk.md`
- **原文**: 示例暗示多个 hugepage 物理地址连续
- **修正**: 添加说明只保证单个 hugepage 内部物理连续

### 24. DMA 控制器描述过于绝对
- **文件**: `2025-07-21-hugepage_indpdk.md`
- **原文**: "DMA控制器只理解物理地址"
- **修正**: 添加 IOMMU 提供 DMA 地址转换的说明

### 25. io_uring 被错误描述为"零拷贝"（2处）
- **文件**: `2025-06-24-io_uring_basics.md`、`2025-07-09-asio.md`
- **原文**: "零拷贝 I/O"
- **修正**: io_uring 核心优势是减少系统调用，标准 read/write 仍有数据拷贝

### 26. x86-64 内存序性能开销数据不准确
- **文件**: `2025-06-24-lock_free_queue_implementation.md`
- **原文**: acquire ~1-2 cycles, release ~1-2 cycles, acq_rel ~2-3 cycles
- **修正**: x86-64 上 relaxed/acquire/release 的 load/store 都是普通 mov（~1 cycle）

### 27. ARM64 seq_cst store 指令错误
- **文件**: `2026-03-03-mutext.md`
- **原文**: `stlr + dmb ish`
- **修正**: 只需 `stlr`

### 28. relaxed 操作通用说明误导性
- **文件**: `2026-03-03-mutext.md`
- **原文**: 将 LOCK XADD 描述为 relaxed 的通用开销
- **修正**: 区分 RMW 操作（LOCK XADD）和 store/load（普通 MOV）

### 29. mmap 绕过 page cache 的错误暗示
- **文件**: `2025-06-24-zero_copy_optimization.md`
- **原文**: "数据直接从磁盘到用户可访问的内存"
- **修正**: 数据仍经过 page cache，mmap 将用户空间虚拟地址映射到 page cache 物理页

### 30. C++ 语境中提及 GC 压力
- **文件**: `2025-06-24-perf_tool_usage_guide.md`
- **原文**: "减轻了 GC 压力"
- **修正**: C++ 无 GC，改为"减少了内存分配/释放的开销"

### 31. cpu-clock 事件描述错误
- **文件**: `2025-06-18-how_to_use_perf.md`
- **原文**: "cpu-clock: CPU时钟周期"
- **修正**: cpu-clock 是软件定时器事件，cycles 才是硬件时钟周期计数器

### 32. DDR 预取宽度错误
- **文件**: `2025-07-16-cpu_freq_memory_size.md`
- **原文**: DDR4 = 16bit, DDR5 = 32bit
- **修正**: DDR4 = 8n, DDR5 = 16n

### 33. DDR 频率/数据率范围超出 JEDEC 标准
- **文件**: `2025-07-16-cpu_freq_memory_size.md`
- **原文**: DDR4 上限 6400 MT/s
- **修正**: DDR4 JEDEC 标准上限 3200 MT/s

### 34. 内存延迟公式自相矛盾
- **文件**: `2025-07-16-cpu_freq_memory_size.md`
- **原文**: "(CL × 时钟周期) / 2"
- **修正**: 正确公式 CL / 基础频率 = CL × 2 / 数据率

### 35. CPU 功耗增长描述为"指数增长"
- **文件**: `2025-07-16-cpu_freq_memory_size.md`
- **原文**: "功耗和发热呈指数增长"
- **修正**: P = CV²f，多项式关系，改为"超线性增长"

### 36. ulimit 软/硬限制混淆
- **文件**: `2026-01-15-debug_procedure.md`
- **原文**: "父进程 ulimit -c 为 0 则子进程无法生成 coredump"
- **修正**: 区分软限制（可提升至硬限制）和硬限制

### 37. Page fault error code 位域解释错误
- **文件**: `2026-01-23-corddump.md`
- **原文**: "Bit 2 (U/S)：0 = 用户态访问"
- **修正**: 错误码 4 = 0b100，Bit 2 = 1 = 用户态访问

### 38. 哈希表失败查找探测次数公式错误
- **文件**: `2025-07-17-map_unordered_map.md`
- **原文**: 失败查找期望 = α
- **修正**: 1 + α（包含访问桶本身的一次）

### 39. 摊销分析数学表达式错误
- **文件**: `2025-07-17-map_unordered_map.md`
- **原文**: "log(n) × O(n) = O(n)"（数学上得 O(n log n)）
- **修正**: 几何级数求和 1+2+4+...+n = O(n)

### 40. 原生数组不可赋值的根因分析错误
- **文件**: `2025-07-17-c++origin_array.md`
- **原文**: "编译器无法确定复制边界"
- **修正**: C++ 语言标准规定数组不可赋值，与编译器能力无关

### 41. 原生数组模板推导能力低估
- **文件**: `2025-07-17-c++origin_array.md`
- **原文**: "原生数组在模板上下文中无法保持大小信息"
- **修正**: `template<T, size_t N> void f(T (&)[N])` 完美保留大小

### 42. mmap 代码注释与实际不符
- **文件**: `2025-06-24-multi_quote_data_processing.md`
- **原文**: "使用大页内存和内存锁定"（代码无 MAP_HUGETLB）
- **修正**: 改为"使用内存锁定（mlock防止换出到swap）"

### 43. 百万级数组标注为可放在栈上
- **文件**: `2025-06-19-how_to_design_order_inlocalmemory.md`
- **原文**: "栈或静态内存"
- **修正**: "静态内存或堆内存（数组过大不适合放在栈上）"

### 44. HFT 系统中使用 atomic\<double\>
- **文件**: `2025-06-19-how_to_design_order_inlocalmemory.md`
- **原文**: `std::atomic<double> filled;`
- **修正**: 添加注释说明 C++20 前不保证 lock-free，建议 HFT 使用定点整数

### 45. Solana logsSubscribe 参数错误
- **文件**: `2025-06-24-solana_blockchain_analysis.md`
- **原文**: logsSubscribe 配置中包含 dataSize/memcmp 过滤器
- **修正**: 移除错误过滤器，添加说明 logsSubscribe 仅支持 mentions 和 commitment

### 46. Solana mentions 过滤器描述不准确
- **文件**: `2025-06-24-solana_monitoring_system.md`
- **原文**: "只能捕获在日志中明确提到目标地址的交易"
- **修正**: mentions 匹配交易 accountKeys 列表中的地址，非日志文本

---

## 轻度错误（表述不精确或易误导）

### 47. 直接函数调用 pipeline flush 描述夸大
- **文件**: `2025-06-24-inline_function_optimization.md`
- **原文**: 直接 `call` 指令笼统说会导致 pipeline flush
- **修正**: 现代 CPU 对直接调用预测几乎 100% 准确，主要开销在 call/ret 和 I-Cache miss

### 48. 使用过时的 x86-32 调用约定说明开销
- **文件**: `2025-06-24-inline_function_optimization.md`
- **原文**: 伪汇编使用 push 参数入栈的 cdecl 约定
- **修正**: 添加说明这是 x86-32 约定，x86-64 通过寄存器传参开销更小

### 49. unsigned int 取反注释使用补码负数
- **文件**: `2025-06-24-bit_field_compression_techniques.md`
- **原文**: "(-6 in 2's complement)"
- **修正**: 无符号类型结果为 4294967290

### 50. 位域校验条件排除合法值
- **文件**: `2025-06-24-bit_field_compression_techniques.md`
- **原文**: `if (new_offset < 3 && new_offset > 0)` 排除 0 和 3
- **修正**: `if (new_offset <= 3)` 允许完整 2-bit 范围

### 51. 共享锁描述产生误导
- **文件**: `2025-06-24-efficient_reading_techniques.md`
- **原文**: "共享锁可能导致并发读取的性能下降"
- **修正**: 共享锁允许并发读取，开销在于原子操作本身

### 52. strace -C 描述错误
- **文件**: `2025-07-03-strace.md`
- **原文**: "-C: 只计数，不显示详细调用"
- **修正**: -C 同时输出详细跟踪和汇总统计（-c 才是只计数）

### 53. strace -F 废弃未说明
- **文件**: `2025-07-03-strace.md`
- **原文**: -F 单独列出暗示与 -f 不同
- **修正**: 标注 -F 已废弃，-f 已覆盖 fork/vfork/clone

### 54. memory_order 枚举值拼写错误
- **文件**: `2025-06-19-perf_case_study.md`
- **原文**: `running.load(released)`
- **修正**: `running.load(std::memory_order_relaxed)`

### 55. 状态转换表大小和 cache line 大小双重错误
- **文件**: `2025-12-26-if_pre.md.md`
- **原文**: "256 字节，单 cache line"
- **修正**: 4×6 uint8_t = 24 字节，可放入 64 字节 cache line

### 56. fork 时代码段描述为"被复制"
- **文件**: `2025-06-24-fork_system_call_analysis.md`
- **原文**: "新进程是父进程的副本,包括代码段"
- **修正**: 代码段只读，父子进程始终共享同一物理页

### 57. 寄存器访问速度描述不准确
- **文件**: `2025-06-23-cpu_data_structures.md`
- **原文**: "半个CPU cycle"
- **修正**: 0-1 个 cycle（内嵌在流水线指令发射阶段）

### 58. vector 小分配开销夸大
- **文件**: `2025-08-15-array_vector.md`
- **原文**: "可能涉及系统调用"
- **修正**: 现代 malloc 小分配在用户态完成，通常不涉及系统调用

### 59. UDP PPS 计算未考虑协议开销
- **文件**: `2025-07-27-network_buffer.md`
- **原文**: "100 Mbps / (64×8 bits) ~ 195,312包/秒"（仅计算载荷）
- **修正**: 添加注释说明实际线上帧包含以太网头/IP/UDP/FCS 等开销

---

## 2026-04-10 追加修正：RSS 四元组 & NIC On-Chip Buffer

### 60. RSS 哈希输入误写为"五元组"（3 篇文章）
- **文件**: `2025-08-18-network_queue.md`、`2026-03-17-net_proc.md`
- **原文**: "RSS 基于五元组（源IP、目的IP、源端口、目的端口、协议）进行哈希计算"；哈希公式写为 `rss_hash_function(源IP + 目标IP + 源端口 + 目标端口 + 协议类型)`，队列选择写为 `hash % 队列数量`
- **问题**: 协议号（TCP=6, UDP=17）不参与哈希计算，而是用于选择哈希模式（四元组 or 二元组）。哈希算法是 Toeplitz，队列选择通过 Indirection Table（RETA）而非简单取模
- **修正**: 全部改为"四元组"；哈希公式改为 `Toeplitz_hash(src_ip, dst_ip, src_port, dst_port)`；队列选择改为 `indirection_table[hash & mask]`；示例中的 `5-tuple` 改为 `4-tuple`

### 61. 收包路径缺少 NIC On-Chip SRAM 环节（2 篇文章）
- **文件**: `2026-03-17-net_proc.md`、`2025-08-18-network_queue.md`
- **原文**: 收包路径从 PHY → MAC 直接跳到 DMA 写入主存 Ring Buffer，未提及包在网卡芯片内部 SRAM 的暂存步骤
- **问题**: 包通过 MAC 校验后，先暂存在 NIC 片上 SRAM（所有 Queue 共享），等待 RSS 分流和 DMA 搬运。这块共享 SRAM 是同一网卡多 Queue 之间的硬件级共享瓶颈，也是 HFT 场景需要分网卡做物理隔离的根因之一
- **修正**:
  - `2026-03-17-net_proc.md`: 新增 2.2 节"NIC On-Chip Buffer"，补全收包路径；更新全景概览图和完整时序图（插入 t2 暂存步骤）；修正 RSS 图中 protocol 参与哈希的错误
  - `2026-04-09-buffer.md`: 扩展 3.4 节"共享资源的边界"为完整的 On-Chip SRAM 讲解，含收包流程图、SRAM 特性、共享资源全景图
  - `2025-08-18-network_queue.md`: 新增 2.4 节"NIC Buffer与多队列的硬件隔离"，含两层 buffer 架构对比和 HFT 分网卡原因分析
  - 三篇文章之间建立交叉链接

---

*本勘误记录随文章修正同步更新。*
