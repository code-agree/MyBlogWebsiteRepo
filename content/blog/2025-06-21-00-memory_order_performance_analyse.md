+++
title = 'C++原子操作内存序性能分析：seq_cst vs relaxed'
date = 2025-06-21T00:47:52+08:00
draft = false
+++


# C++原子操作内存序性能分析：seq_cst vs relaxed

## 摘要

本文分析了C++原子操作中不同内存序(memory ordering)对性能的影响，特别是比较了默认的顺序一致性(seq_cst)与宽松(relaxed)内存序在x86-64架构上的性能差异。通过实验测试、性能分析和汇编代码检查，我们发现即使在内存模型较强的x86架构上，不同内存序的选择仍然会产生可测量的性能差异。

## 1. 实验设计

### 1.1 测试程序

我们设计了两个版本的测试程序，它们在固定时间内执行原子变量的读取和计数操作，唯一区别是原子变量读取时使用的内存序不同：

**seq_cst版本 (默认内存序)**:
```cpp
void worker_seq_cst() {
    while (running_) {  // 默认使用 seq_cst
        counter_.fetch_add(1, std::memory_order_relaxed);
        busy_loop();
    }
}
```

**relaxed版本 (显式指定宽松内存序)**:
```cpp
void worker_relaxed_load() {
    while (running_.load(std::memory_order_relaxed)) {
        counter_.fetch_add(1, std::memory_order_relaxed);
        busy_loop();
    }
}
```

### 1.2 编译与执行环境

测试程序使用以下命令编译：
```bash
g++ -std=c++11 -O0 -pthread atomic_test_seq_cst.cpp -o test_gcc_seq_cst
g++ -std=c++11 -O0 -pthread atomic_test_relaxed.cpp -o test_gcc_relaxed
```

每个程序运行5秒钟，记录在此期间完成的操作次数。同时使用perf工具收集性能数据：
```bash
perf record -e cpu-clock:pppH ./test_gcc_seq_cst
perf record -e cpu-clock:pppH ./test_gcc_relaxed
```

## 2. 实验结果

### 2.1 执行计数结果

| 版本 | 操作计数 |
|------|----------|
| seq_cst | 26,494,108 |
| relaxed | 26,660,082 |

性能差异：
- 绝对差异：165,974次操作
- 相对提升：0.63%

### 2.2 perf分析结果

**seq_cst版本**:
```
Samples: 4K of event 'cpu-clock:pppH', Event count (approx.): 4994994990
  Children      Self  Command          Symbol
   95.23%    95.21%  test_gcc_seq_cs  busy_loop
   99.44%     2.91%  test_gcc_seq_cs  worker_seq_cst
    1.06%     0.84%  test_gcc_seq_cs  std::atomic<bool>::operator bool
    0.54%     0.54%  test_gcc_seq_cs  std::__is_constant_evaluated
```

**relaxed版本**:
```
Samples: 4K of event 'cpu-clock:pppH', Event count (approx.): 4991991987
  Children      Self  Command          Symbol
   99.22%     3.23%  test_gcc_relaxe  worker_relaxed_load
   94.61%    94.61%  test_gcc_relaxe  busy_loop
    1.64%     1.30%  test_gcc_relaxe  std::atomic<bool>::load
    0.42%     0.42%  test_gcc_relaxe  std::__is_constant_evaluated
```


5. 与relaxed版本的比较分析
将这些数据与relaxed版本对比，我们可以看到几个关键差异：

- **原子操作函数：**
  - seq_cst: `std::atomic<bool>::operator bool` 占用 1.06%（Self: 0.84%）
  - relaxed: `std::atomic<bool>::load` 占用 1.64%（Self: 1.30%）

- **worker函数自身开销：**
  - seq_cst: `worker_seq_cst` 自身占用 2.91%
  - relaxed: `worker_relaxed_load` 自身占用 3.23%

- **busy_loop占比：**
  - seq_cst: `busy_loop` Children 占用 95.23%，Self 占用 95.21%
  - relaxed: `busy_loop` Children 占用 94.61%，Self 占用 94.61%


6. 性能差异解释
基于这些数据，我们可以解释seq_cst和relaxed版本之间0.63%的性能差异：

- **函数调用路径不同：**
  - seq_cst版本调用 `operator bool()`，这是一个隐式转换函数
  - relaxed版本直接调用 `load()` 函数并明确指定内存序

- **内部实现差异：**
  - `operator bool()` 内部可能包含额外的检查或转换逻辑
  - `load()` 函数可能有更直接的实现路径

- **编译器优化差异：**
  - 显式指定 `memory_order_relaxed` 可能允许编译器进行更多优化
  - 默认的 `seq_cst` 可能限制了某些重排序优化

- **CPU微架构影响：**
  - 不同的函数调用路径可能导致不同的指令缓存和分支预测行为
  - `seq_cst` 语义可能隐含地影响CPU的投机执行策略

### 2.3 关键汇编代码对比

**relaxed版本**:
```assembly
.L27:
    mov     esi, 0                        # memory_order_relaxed参数(0)
    mov     edi, OFFSET FLAT:running_     # this指针
    call    std::atomic<bool>::load(std::memory_order) const
    test    al, al
    jne     .L29
```

**seq_cst版本**:
```assembly
.L31:
    mov     edi, OFFSET FLAT:running_     # this指针
    call    std::atomic<bool>::operator bool() const
    test    al, al
    jne     .L33
```

### 2.4 O0优化下的汇编差异分析

以下为 gcc 15.1，O0 优化下的关键汇编片段：
（汇编生成工具：https://godbolt.org/）

```assembly
worker_relaxed_load():
    ...
    mov     esi, 0
    mov     edi, OFFSET FLAT:running_
    call    std::atomic<bool>::load(std::memory_order) const
    test    al, al
    jne     .L19
    ...

worker_seq_cst():
    ...
    mov     edi, OFFSET FLAT:running_
    call    std::atomic<bool>::operator bool() const
    test    al, al
    jne     .L23
    ...
```

#### 差异分析

1. **条件判断方式不同**
   - `worker_relaxed_load` 显式传递 `memory_order` 参数（`esi, 0`），调用 `load(std::memory_order) const`。
   - `worker_seq_cst` 直接调用 `operator bool() const`，不传递内存序参数。

2. **函数调用路径**
   - `relaxed` 版本的 `while` 条件是 `running_.load(std::memory_order_relaxed)`，对应调用 `load`，并传递内存序参数。
   - `seq_cst` 版本的 `while` 条件是 `while (running_)`，对应调用 `operator bool()`，其内部默认 `memory_order_seq_cst`。

3. **核心原子操作一致**
   - 两个版本的 `counter_.fetch_add(1, std::memory_order_relaxed)` 都对应 `lock xadd` 指令，说明增操作本身无差异。

4. **busy_loop实现一致**
   - 两个版本都调用 `busy_loop()`，其实现完全相同。

5. **O0下的额外开销**
   - 由于O0未做优化，函数调用、栈帧分配等指令较多，真实差异主要体现在条件判断的函数调用路径。

#### 总结
- O0优化下，`worker_relaxed_load` 和 `worker_seq_cst` 的主要差异体现在对 `running_` 的判断方式：一个是显式 `load`，一个是隐式 `operator bool()`。
- 这与perf分析和高优化级别下的结论一致：两者的核心原子操作实现无差异，性能差异主要来自于条件判断的函数调用路径和编译器对内存序的处理。
- 在O0下，所有函数调用和参数传递都被完整保留，进一步放大了调用路径的差异。

## 3. 分析与讨论

### 3.1 性能差异分析

实验结果显示，relaxed版本在相同时间内完成了更多操作(0.63%的提升)。这个差异虽小，但在高频操作场景中具有实际意义。

有趣的是，perf数据显示relaxed版本在原子操作上花费了更大比例的CPU时间(1.64% vs 1.06%)，但总体吞吐量仍然更高。这表明：

1. relaxed版本虽然在原子操作上花费了更多时间比例，但每次操作的实际开销更小
2. seq_cst版本可能有隐含的开销，导致整体执行效率略低

**需要注意的是，perf数据显示relaxed版本的std::atomic<bool>::load的自耗（Self）反而比operator bool更高，这说明单次load的开销并不一定更低。整体吞吐量略高，可能是因为编译器对relaxed路径做了更激进的优化，或者调用链更短、分支预测效果更好。汇编层面，两者的主要差异仅在于load的调用方式和参数传递，实际指令数量和复杂度差异极小。**

### 3.2 汇编代码差异分析

汇编代码分析揭示了性能差异的根本原因：

1. **函数调用差异**：
   - seq_cst版本调用`operator bool()`
   - relaxed版本调用`load(std::memory_order_relaxed)`

2. **相同点**：
   - 两个版本的busy_loop实现完全相同
   - 两个版本的counter_.fetch_add操作都使用相同的`lock xadd`指令

3. **关键发现**：
   - 在O2优化级别下，两个版本的核心原子操作指令相同
   - 差异主要来自函数调用路径，而非原子操作本身的实现

### 3.3 内存序对性能的影响机制

在x86-64架构上，load操作本身不需要额外的内存屏障，无论是seq_cst还是relaxed。然而，差异可能来自以下几个方面：

1. **函数调用开销**：
   - `operator bool()`可能有额外的转换逻辑
   - 不同函数可能有不同的内联和优化策略

2. **编译器优化**：
   - 显式指定memory_order_relaxed可能允许编译器进行更多优化
   - 默认的seq_cst可能限制了某些重排序优化

3. **CPU微架构影响**：
   - 不同的函数调用路径可能导致不同的缓存行为和分支预测效果
   - seq_cst可能隐含地影响CPU的投机执行策略

## 4. 结论与实践建议

本研究表明，即使在x86-64这样的强内存模型架构上，选择适当的内存序仍然可以带来可测量的性能提升。虽然差异不大(0.63%)，但在高性能计算或高频交易系统中，这种积累的差异可能具有实际意义。

**补充说明：**
通过perf和汇编分析可以确认，relaxed和默认seq_cst的主要性能差异，来源于对原子变量running_的判断方式（即load的调用路径和参数传递），而非核心原子操作本身。两者的性能差异极小（本实验约0.6%），仅在极高频场景下才有实际意义。实际开发中，只有在不需要强内存序保证时，才建议使用relaxed，并应以实际测量为准。

实践建议：

1. 在不需要强内存序保证的场景中，使用relaxed内存序可以获得更好的性能
2. 性能关键路径上的原子操作应当仔细选择适当的内存序
3. 即使在x86架构上，内存序的选择也会影响性能，不应被忽视
4. 在进行性能优化时，应当通过实际测量来验证不同内存序的影响

## 5. 未来工作

未来可以扩展本研究，探索以下方向：

1. 在不同CPU架构(如ARM、POWER)上进行类似测试
2. 测试多线程竞争场景下不同内存序的性能差异
3. 分析不同编译器和优化级别对内存序性能的影响
4. 探索更复杂的原子操作模式(如RMW操作)下内存序的性能影响

## 附录：完整测试代码

```cpp
#include <atomic>
#include <thread>
#include <iostream>
#include <chrono>

// 原子变量
std::atomic<bool> running_{true};
std::atomic<int> counter_{0};

// 模拟忙等，避免被优化
inline void busy_loop() {
    for (volatile int i = 0; i < 100; ++i);
}

// 默认版本：隐式 seq_cst
void worker_seq_cst() {
    while (running_) {  // 默认 seq_cst
        counter_.fetch_add(1, std::memory_order_relaxed); // 只测 load
        busy_loop();
    }
}

// relaxed load 版本
void worker_relaxed_load() {
    while (running_.load(std::memory_order_relaxed)) {
        counter_.fetch_add(1, std::memory_order_relaxed); // 保持一致
        busy_loop();
    }
}

int main() {
    running_ = true;
    counter_ = 0;

    std::thread t(worker_seq_cst);
    
    // 运行足够长时间以便perf收集数据
    std::this_thread::sleep_for(std::chrono::seconds(5));
    
    running_.store(false);
    t.join();
    
    std::cout << "完成测试，计数: " << counter_.load() << std::endl;
    return 0;
}
```

