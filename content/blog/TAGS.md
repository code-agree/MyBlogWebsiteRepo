# 博客 Tags 规划

## 一、现状

- **格式不统一**：有的用 `tags = [...]`，有的用 `tag = ...`（单数），有的为字符串有的为数组。
- **拼写/规范**：如 `"Memeoy"`、`" Tools "`（首尾空格）、`"project management"` 与 `"Blog"` 等混用。
- **覆盖不全**：多数文章没有 tags，不利于分类与检索。

## 二、统一约定

- **字段**：一律使用 `tags`（复数），TOML 数组格式：`tags = ["Tag1", "Tag2"]`。
- **无 tag 时**：`tags = []` 或按内容补全 1～3 个 tag。
- **大小写**：英文 tag 首字母大写，如 `C++`、`HFT`、`Linux`。

## 三、Tag 体系（按主题）

| Tag | 含义 | 典型文章 |
|-----|------|----------|
| **HFT** | 高频交易系统设计、订单、做市、行情、背压、配置、延迟优化 | 订单本地内存、OrderBook、多 WS、队列、锁分析、重连、位域、配置管理、数据读取、大吞吐订单、做市模型 |
| **C++** | 语言特性、标准库、模板、内存模型、容器、异常/optional | 内存序、inline、模板、虚函数、map/unordered_map、array/vector、flat_hash_map、optional/异常、SPSC DTO |
| **Performance** | 性能分析、perf、编译器优化、CPU/缓存/NUMA、cycles、分支预测 | perf 指南、编译优化、False Sharing、mutex 性能、NUMA、hugepage、cycles、热路径 if、CPU 调试 |
| **Concurrency** | 无锁、锁、mutex、原子、内存序、False Sharing、EventBus | 无锁队列、内存序、原子重连、LockFree EventBus、mutex 剖析 |
| **Memory** | 内存管理、hugepage、mmap、零拷贝、栈、TLB | mmap/零拷贝、string mmap 故障、hugepage、DPDK hugepage、栈溢出、array/vector 内存 |
| **Network** | 网络编程、Asio、io_uring、TCP、WebSocket、DPDK、Socket | Asio、BIO/NIO、Beast、DPDK、raw socket、WebSocket 架构、TCP 缓冲、UDP 丢包、Aeron、network queue |
| **Linux** | 系统编程、系统调用、进程/线程、fork、strace | fork、strace、进程与线程 |
| **Debug** | 调试、coredump、段错误、负载分析、故障定位 | coredump 指南、SEGV 排查、core 分析、cordump、系统负载定位 |
| **Blockchain** | 区块链 / Solana | Solana 监控、Solana 链上分析 |
| **Tooling** | 博客、协作、代理、远程、运维工具 | 发布博客、GitHub 协作、Tailscale、代理 squid |
| **Other** | 杂项、非技术笔记 | 付鹏 HSBC、First Post 等 |

## 四、每篇文章的 Tag 映射（文件名 → tags）

以下为按文件名整理的推荐 tags，便于批量修改与复查。

| 文件 | 推荐 tags |
|------|-----------|
| 2025-06-11-orderbook.md | `["HFT", "Performance"]` |
| 2025-06-18-how_to_use_perf.md | `["Performance", "Linux"]` |
| 2025-06-19-compile_perf.md | `["Performance", "C++"]` |
| 2025-06-19-how_to_design_order_inlocalmemory.md | `["HFT", "C++", "Performance"]` |
| 2025-06-19-perf_case_study.md | `["Performance", "HFT"]` |
| 2025-06-20-lockfree_eventbus_performance_analysis.md | `["Concurrency", "HFT", "Performance"]` |
| 2025-06-21-memory_order_performance_analysis.md | `["Concurrency", "C++"]` |
| 2025-06-23-cache_false_sharing_analysis.md | `["Performance", "Concurrency", "C++"]` |
| 2025-06-23-cpu_data_structures.md | `["Performance", "C++"]` |
| 2025-06-24-advanced_queue_usage_patterns.md | `["HFT", "Network"]` |
| 2025-06-24-atomic_operations_reconnection_mechanism.md | `["HFT", "Concurrency"]` |
| 2025-06-24-avellaneda_stoikov_market_making.md | `["HFT"]` |
| 2025-06-24-batch_order_processing.md | `["HFT"]` |
| 2025-06-24-bit_field_compression_techniques.md | `["HFT", "C++", "Performance"]` |
| 2025-06-24-config_management_in_hft_systems.md | `["HFT"]` |
| 2025-06-24-cpp_template_class_guide.md | `["C++"]` |
| 2025-06-24-datareader_design_patterns.md | `["HFT", "Performance"]` |
| 2025-06-24-efficient_reading_techniques.md | `["HFT", "Performance"]` |
| 2025-06-24-fix_shared_page_position.md | `["Memory", "Concurrency", "HFT"]` |
| 2025-06-24-fork_system_call_analysis.md | `["Linux"]` |
| 2025-06-24-fupeng_trading_system.md | `["Other"]` |
| 2025-06-24-getting_started_guide.md | `["Other"]` |
| 2025-06-24-high_performance_computing_principles.md | `["HFT", "Performance"]` |
| 2025-06-24-how_to_publish_new_blog.md | `["Tooling"]` |
| 2025-06-24-inline_function_optimization.md | `["C++", "Performance"]` |
| 2025-06-24-io_uring_basics.md | `["Network", "Memory"]` |
| 2025-06-24-io_uring_mechanism_details.md | `["Network", "HFT"]` |
| 2025-06-24-lock_free_queue_implementation.md | `["Concurrency", "C++"]` |
| 2025-06-24-lockfree_programming_techniques.md | `["Concurrency", "HFT"]` |
| 2025-06-24-memory_ordering_in_cpp.md | `["Concurrency", "C++"]` |
| 2025-06-24-message_queue_overstocking_solutions.md | `["HFT", "Network", "Performance"]` |
| 2025-06-24-multi_quote_data_processing.md | `["HFT", "Network"]` |
| 2025-06-24-mutex_performance_analysis.md | `["HFT", "Concurrency"]` |
| 2025-06-24-order_sending_optimization.md | `["HFT"]` |
| 2025-06-24-orderbook_implementation.md | `["HFT", "C++"]` |
| 2025-06-24-perf_tool_usage_guide.md | `["HFT", "Performance"]` |
| 2025-06-24-process_and_thread_management.md | `["Linux"]` |
| 2025-06-24-project_management_best_practices.md | `["Tooling"]` |
| 2025-06-24-queue_usage_patterns.md | `["HFT"]` |
| 2025-06-24-screen_sharing_techniques.md | `["Tooling"]` |
| 2025-06-24-session_resumption_techniques.md | `["Network"]` |
| 2025-06-24-solana_blockchain_analysis.md | `["Blockchain"]` |
| 2025-06-24-solana_monitoring_system.md | `["Blockchain"]` |
| 2025-06-24-string_memory_mapping_techniques.md | `["Memory", "C++", "HFT"]` |
| 2025-06-24-zero_copy_optimization.md | `["Memory", "HFT"]` |
| 2025-07-01-tcp_perf.md | `["Network", "HFT", "Performance"]` |
| 2025-07-03-beast_asio.md | `["Network", "C++"]` |
| 2025-07-03-dpdk_check.md | `["Network", "Performance"]` |
| 2025-07-03-strace.md | `["Linux", "Debug"]` |
| 2025-07-05-dpdk_application.md | `["Network", "Memory", "Debug"]` |
| 2025-07-09-asio.md | `["Network", "C++"]` |
| 2025-07-09-bio_nio.md | `["Network"]` |
| 2025-07-15-backpress.md | `["HFT"]` |
| 2025-07-16-cpu_freq_memory_size.md | `["HFT", "Performance"]` |
| 2025-07-17-c++17_new_feature.md | `["C++"]` |
| 2025-07-17-c++_basic_usage.md | `["C++"]` |
| 2025-07-17-c++origin_array.md | `["C++"]` |
| 2025-07-17-map_unordered_map.md | `["C++"]` |
| 2025-07-21-hugepage.md | `["Memory", "Performance"]` |
| 2025-07-21-hugepage_indpdk.md | `["Memory", "Network"]` |
| 2025-07-23-memory.md | `["Memory", "C++", "Debug"]` |
| 2025-07-27-network_buffer.md | `["Network", "Performance"]` |
| 2025-07-30-proxy.md | `["Tooling", "Network"]` |
| 2025-08-08-raw_socket.md | `["Network", "HFT"]` |
| 2025-08-15-aeron.md | `["Network", "HFT"]` |
| 2025-08-15-array_vector.md | `["C++", "Memory", "HFT"]` |
| 2025-08-18-network_queue.md | `["Network", "Performance", "HFT"]` |
| 2025-09-08-ws_send.md | `["Network", "HFT"]` |
| 2025-09-18-cycles.md | `["Performance"]` |
| 2025-11-08-default.md | `["C++", "Concurrency", "HFT"]` |
| 2025-12-04-cpu_debug.md | `["Debug", "Linux", "Performance"]` |
| 2025-12-24-flat_hash_map.md | `["C++", "Performance"]` |
| 2025-12-26-if_pre.md.md | `["Performance", "HFT", "C++"]` |
| 2025-12-26-various_map.md | `["C++", "Performance"]` |
| 2026-01-15-debug_procedure.md | `["Debug", "Linux"]` |
| 2026-01-15-debug_procedure2.md | `["Debug", "Linux"]` |
| 2026-01-19-core_ana.md.md | `["Debug", "C++"]` |
| 2026-01-23-corddump.md | `["Debug", "HFT"]` |
| 2026-03-01-numa.md | `["Performance", "HFT"]` |
| 2026-03-03-mutext.md | `["Concurrency", "C++", "Performance"]` |
| 2026-03-03-websocket.md.md | `["Network", "HFT"]` |
| 2026-03-04-try_catch.md | `["C++", "HFT"]` |
| 2026-03-11-agent-setup.md | `["Tooling"]` |
| 2026-03-17-net_proc.md | `["Network", "Linux", "HFT"]` |
| 2026-03-30-cpu_bindcore.md | `["Linux", "Performance", "Network"]` |
| 2026-04-09-buffer.md | `["Network", "HFT", "Performance"]` |
| 2026-04-17-iceoryx_ipc_benchmark.md | `["IPC", "Performance", "SharedMemory", "HFT", "C++", "LockFree"]` |
| 2026-04-25-kernel_socket_vs_dpdk.md | `["Network", "HFT", "Performance", "Linux"]` |

## 五、后续维护

- 新文章：在 frontmatter 中至少填写 1 个 tag，优先从上述体系中选择。
- 若新增常用主题，可在本表中增加新 tag 并在本文档“Tag 体系”中补充说明。
