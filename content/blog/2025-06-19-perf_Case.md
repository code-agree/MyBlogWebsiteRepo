+++
title = '2025 06 19 Perf_Case'
date = 2025-06-19T04:35:36+08:00
draft = true
+++

1. 使用perf 检查出CPU热点，进行优化。
- 批处理，避免频繁的原子操作
- while (atomic<bool> running) 与 while (running.load(released))的区别，前者是默认更严格的内存序同步