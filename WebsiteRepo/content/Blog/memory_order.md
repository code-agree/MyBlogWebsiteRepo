+++
title = 'Memory_order'
date = 2025-06-11T02:15:43+08:00
draft = false

+++

```cpp
#pragma once
#include <atomic>
#include <array>
#include <optional>
#include <memory>
#include <vector>

namespace LockFreeQueues {

// ============================================================================
// 1. 内存序详细演示
// ============================================================================

class MemoryOrderingDemo {
private:
    std::atomic<int> data{0};
    std::atomic<bool> flag{false};
    
public:
    // 演示不同内存序的行为差异
    void demonstrateRelaxed() {
        // relaxed: 只保证原子性，允许重排序
        data.store(42, std::memory_order_relaxed);
        flag.store(true, std::memory_order_relaxed);
        // 编译器/CPU可能重排这两个操作的顺序！
    }
    
    void demonstrateAcquireRelease() {
        // release: 确保之前的操作不会重排到此操作之后
        data.store(42, std::memory_order_relaxed);  // 这个不会被重排到下面
        flag.store(true, std::memory_order_release); // 释放操作
    }
    
    bool readWithAcquire() {
        // acquire: 确保后续操作不会重排到此操作之前
        if (flag.load(std::memory_order_acquire)) {  // 获取操作
            int value = data.load(std::memory_order_relaxed); // 这个不会被重排到上面
            return value == 42; // 保证能看到data的修改
        }
        return false;
    }
    
    void demonstrateSeqCst() {
        // seq_cst: 最强的内存序，全局一致的顺序
        data.store(42, std::memory_order_seq_cst);
        flag.store(true, std::memory_order_seq_cst);
        // 所有线程看到的这些操作顺序都是一致的
    }
};

// ============================================================================
// 2. 单生产者单消费者队列 (SPSC) - 基础版本
// ============================================================================

template<typename T, size_t Capacity>
class SPSCQueue {
private:
    std::array<T, Capacity> buffer;
    
    // 关键：head和tail分别只被一个线程修改
    alignas(64) std::atomic<size_t> head{0};  // 只被消费者修改
    alignas(64) std::atomic<size_t> tail{0};  // 只被生产者修改
    
public:
    bool push(T item) {
        const size_t current_tail = tail.load(std::memory_order_relaxed);
        const size_t next_tail = (current_tail + 1) % Capacity;
        
        // acquire: 确保看到消费者的最新head值
        if (next_tail == head.load(std::memory_order_acquire)) {
            return false; // 队列满
        }
        
        buffer[current_tail] = std::move(item);
        
        // release: 确保数据写入完成后，消费者才能看到新的tail
        tail.store(next_tail, std::memory_order_release);
        return true;
    }
    
    std::optional<T> pop() {
        const size_t current_head = head.load(std::memory_order_relaxed);
        
        // acquire: 确保看到生产者的最新tail值  
        if (current_head == tail.load(std::memory_order_acquire)) {
            return std::nullopt; // 队列空
        }
        
        T item = std::move(buffer[current_head]);
        
        // release: 确保数据读取完成后，生产者才能看到新的head
        head.store((current_head + 1) % Capacity, std::memory_order_release);
        return item;
    }
};

// ============================================================================
// 3. 单生产者多消费者队列 (SPMC)
// ============================================================================

template<typename T, size_t Capacity>
class SPMCQueue {
private:
    struct alignas(64) Element {
        std::atomic<T*> data{nullptr};
        std::atomic<size_t> sequence{0};
    };
    
    std::array<Element, Capacity> buffer;
    alignas(64) std::atomic<size_t> tail{0};  // 生产者索引
    
    // 每个消费者需要自己的head指针
    static thread_local size_t consumer_head;
    
public:
    SPMCQueue() {
        // 初始化序列号
        for (size_t i = 0; i < Capacity; ++i) {
            buffer[i].sequence.store(i, std::memory_order_relaxed);
        }
    }
    
    bool push(T item) {
        const size_t pos = tail.load(std::memory_order_relaxed);
        Element& element = buffer[pos % Capacity];
        
        // 等待这个位置可用（序列号匹配）
        const size_t expected_seq = pos;
        if (element.sequence.load(std::memory_order_acquire) != expected_seq) {
            return false; // 队列满或位置未就绪
        }
        
        // 分配内存并存储数据
        T* data_ptr = new T(std::move(item));
        element.data.store(data_ptr, std::memory_order_relaxed);
        
        // 更新序列号，通知消费者数据就绪
        element.sequence.store(expected_seq + 1, std::memory_order_release);
        
        // 推进tail
        tail.store(pos + 1, std::memory_order_relaxed);
        return true;
    }
    
    std::optional<T> pop() {
        Element& element = buffer[consumer_head % Capacity];
        
        // 检查数据是否就绪
        const size_t expected_seq = consumer_head + 1;
        if (element.sequence.load(std::memory_order_acquire) != expected_seq) {
            return std::nullopt; // 数据未就绪
        }
        
        // 获取数据
        T* data_ptr = element.data.load(std::memory_order_relaxed);
        T result = std::move(*data_ptr);
        delete data_ptr;
        
        element.data.store(nullptr, std::memory_order_relaxed);
        
        // 更新序列号，通知生产者位置可用
        element.sequence.store(consumer_head + Capacity, std::memory_order_release);
        
        ++consumer_head;
        return result;
    }
};

template<typename T, size_t Capacity>
thread_local size_t SPMCQueue<T, Capacity>::consumer_head = 0;

// ============================================================================
// 4. 多生产者单消费者队列 (MPSC) - 使用CAS
// ============================================================================

template<typename T, size_t Capacity>
class MPSCQueue {
private:
    struct Node {
        std::atomic<T*> data{nullptr};
        std::atomic<Node*> next{nullptr};
        
        Node() = default;
        ~Node() { 
            T* ptr = data.load(std::memory_order_relaxed);
            delete ptr; 
        }
    };
    
    alignas(64) std::atomic<Node*> head;  // 消费者读取点
    alignas(64) std::atomic<Node*> tail;  // 生产者写入点
    
public:
    MPSCQueue() {
        Node* dummy = new Node;
        head.store(dummy, std::memory_order_relaxed);
        tail.store(dummy, std::memory_order_relaxed);
    }
    
    ~MPSCQueue() {
        while (Node* old_head = head.load(std::memory_order_relaxed)) {
            head.store(old_head->next.load(std::memory_order_relaxed), 
                      std::memory_order_relaxed);
            delete old_head;
        }
    }
    
    void push(T item) {
        Node* new_node = new Node;
        T* data_ptr = new T(std::move(item));
        new_node->data.store(data_ptr, std::memory_order_relaxed);
        
        // 多生产者需要用CAS来原子地更新tail
        Node* prev_tail = tail.exchange(new_node, std::memory_order_acq_rel);
        
        // 链接前一个节点到新节点
        prev_tail->next.store(new_node, std::memory_order_release);
    }
    
    std::optional<T> pop() {
        Node* current_head = head.load(std::memory_order_relaxed);
        Node* next = current_head->next.load(std::memory_order_acquire);
        
        if (next == nullptr) {
            return std::nullopt; // 队列空
        }
        
        // 获取数据
        T* data_ptr = next->data.load(std::memory_order_relaxed);
        T result = std::move(*data_ptr);
        delete data_ptr;
        next->data.store(nullptr, std::memory_order_relaxed);
        
        // 移动head指针
        head.store(next, std::memory_order_release);
        delete current_head;
        
        return result;
    }
};

// ============================================================================
// 5. 多生产者多消费者队列 (MPMC) - 最复杂的实现
// ============================================================================

template<typename T, size_t Capacity>
class MPMCQueue {
private:
    struct Cell {
        std::atomic<T*> data{nullptr};
        std::atomic<size_t> sequence{0};
    };
    
    static constexpr size_t CACHELINE_SIZE = 64;
    
    // 缓存行对齐，避免伪共享
    alignas(CACHELINE_SIZE) std::array<Cell, Capacity> buffer;
    alignas(CACHELINE_SIZE) std::atomic<size_t> enqueue_pos{0};
    alignas(CACHELINE_SIZE) std::atomic<size_t> dequeue_pos{0};
    
public:
    MPMCQueue() {
        // 初始化序列号
        for (size_t i = 0; i < Capacity; ++i) {
            buffer[i].sequence.store(i, std::memory_order_relaxed);
        }
    }
    
    bool push(T item) {
        Cell* cell;
        size_t pos = enqueue_pos.load(std::memory_order_relaxed);
        
        for (;;) {
            cell = &buffer[pos % Capacity];
            size_t seq = cell->sequence.load(std::memory_order_acquire);
            intptr_t diff = (intptr_t)seq - (intptr_t)pos;
            
            if (diff == 0) {
                // 尝试占用这个位置
                if (enqueue_pos.compare_exchange_weak(pos, pos + 1, 
                                                     std::memory_order_relaxed)) {
                    break;
                }
            } else if (diff < 0) {
                return false; // 队列满
            } else {
                pos = enqueue_pos.load(std::memory_order_relaxed);
            }
        }
        
        // 存储数据
        T* data_ptr = new T(std::move(item));
        cell->data.store(data_ptr, std::memory_order_relaxed);
        
        // 通知消费者数据就绪
        cell->sequence.store(pos + 1, std::memory_order_release);
        return true;
    }
    
    std::optional<T> pop() {
        Cell* cell;
        size_t pos = dequeue_pos.load(std::memory_order_relaxed);
        
        for (;;) {
            cell = &buffer[pos % Capacity];
            size_t seq = cell->sequence.load(std::memory_order_acquire);
            intptr_t diff = (intptr_t)seq - (intptr_t)(pos + 1);
            
            if (diff == 0) {
                // 尝试占用这个位置
                if (dequeue_pos.compare_exchange_weak(pos, pos + 1,
                                                     std::memory_order_relaxed)) {
                    break;
                }
            } else if (diff < 0) {
                return std::nullopt; // 队列空
            } else {
                pos = dequeue_pos.load(std::memory_order_relaxed);
            }
        }
        
        // 获取数据
        T* data_ptr = cell->data.load(std::memory_order_relaxed);
        T result = std::move(*data_ptr);
        delete data_ptr;
        cell->data.store(nullptr, std::memory_order_relaxed);
        
        // 通知生产者位置可用
        cell->sequence.store(pos + Capacity, std::memory_order_release);
        return result;
    }
};

// ============================================================================
// 6. 使用示例和性能对比
// ============================================================================

class QueueBenchmark {
public:
    static void demonstrateUsage() {
        // SPSC队列 - 最快，适用于单线程生产消费
        SPSCQueue<int, 1024> spsc_queue;
        spsc_queue.push(42);
        auto result1 = spsc_queue.pop();
        
        // MPSC队列 - 多个生产者，一个消费者
        MPSCQueue<int, 1024> mpsc_queue;
        mpsc_queue.push(42);
        auto result2 = mpsc_queue.pop();
        
        // MPMC队列 - 最通用但最复杂
        MPMCQueue<int, 1024> mpmc_queue;
        mpmc_queue.push(42);
        auto result3 = mpmc_queue.pop();
    }
    
    // 性能特征说明：
    // SPSC: ~10-20ns 延迟，最高吞吐量
    // SPMC: ~50-100ns 延迟，适中吞吐量  
    // MPSC: ~100-200ns 延迟，需要CAS操作
    // MPMC: ~200-500ns 延迟，最复杂的同步
};

} // namespace LockFreeQueues

/*
内存序使用原则总结：

1. memory_order_relaxed: 
   - 只保证原子性，无同步语义
   - 用于计数器、统计等场景

2. memory_order_acquire/release:
   - 形成同步点，建立happens-before关系
   - acquire防止后续操作前移
   - release防止之前操作后移
   - 配对使用实现线程间同步

3. memory_order_acq_rel:
   - 同时具有acquire和release语义
   - 用于read-modify-write操作

4. memory_order_seq_cst:
   - 最强的内存序，全局一致顺序
   - 性能开销最大，但最容易理解

选择内存序的关键是理解数据依赖关系和同步需求！
*/
```