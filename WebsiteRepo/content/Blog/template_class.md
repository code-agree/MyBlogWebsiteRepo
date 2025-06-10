+++
title = '模版'
date = 2025-06-10T22:48:21+08:00
draft = false
+++


# c++ 模版

## 1. 分类
有三种不同的模版类型，
- Function templates
- class templates
- Variable templates

### 1.1. function templates

```cpp
template<typename T>
T max(T a, T b) {
    return (a > b) ? a : b;
}

// 使用：编译器自动推导类型
int x = max(3, 7);        // T = int
double y = max(3.14, 2.71); // T = double

```

- 多参数模版

```cpp
template<typename T, typename U>
auto add(T a, U b) {
    return a + b;
}
```

- 函数模板的显式实例化

```cpp
// 声明模板函数
template<typename T>
void process(T value) {
    // 实现...
}

// 显式实例化特定类型版本
template void process<int>(int);  // 显式实例化int版本
template void process<double>(double);  // 显式实例化double版本
```

- 可变参数模板函数

```cpp
// 递归终止条件
void print() {
    std::cout << std::endl;
}

// 可变参数模板 (C++11)
template<typename T, typename... Args>
void print(T first, Args... rest) {
    std::cout << first << " ";
    print(rest...);  // 递归调用处理剩余参数
}

// 使用折叠表达式 (C++17)
template<typename... Args>
void printAll(Args... args) {
    (std::cout << ... << args) << '\n';  // 折叠表达式
}

// 使用
print(1, "hello", 3.14, 'c');  // 输出: 1 hello 3.14 c
printAll(1, "hello", 3.14, 'c');  // 输出: 1hello3.14c
```

- 约束与概念 (C++20)

```cpp
// 使用requires表达式
template<typename T>
requires std::integral<T>
T gcd(T a, T b) {
    if (b == 0) return a;
    return gcd(b, a % b);
}

// 使用概念的简写形式
template<std::integral T>
T lcm(T a, T b) {
    return (a / gcd(a, b)) * b;
}

// 使用auto参数简写 (C++20)
auto sum(std::integral auto a, std::integral auto b) {
    return a + b;
}
```

- SFINAE与类型特性

```cpp
// 使用std::enable_if进行SFINAE (C++11)
template<typename T, 
         typename = std::enable_if_t<std::is_arithmetic_v<T>>>
T square(T x) {
    return x * x;
}

// 使用tag dispatching区分类型处理
template<typename Iterator>
void advance_impl(Iterator& it, int n, std::random_access_iterator_tag) {
    // 随机访问迭代器可以直接跳跃
    it += n;
}

template<typename Iterator>
void advance_impl(Iterator& it, int n, std::bidirectional_iterator_tag) {
    // 双向迭代器需要循环移动
    if (n > 0) {
        while (n--) ++it;
    } else {
        while (n++) --it;
    }
}

template<typename Iterator>
void advance(Iterator& it, int n) {
    advance_impl(it, n, typename std::iterator_traits<Iterator>::iterator_category());
}
```

- 实际应用案例：通用算法实现

```cpp
// 泛型快速排序实现
template<typename RandomIt>
void quicksort(RandomIt first, RandomIt last) {
    if (first < last) {
        auto pivot = *std::next(first, std::distance(first, last) / 2);
        
        auto middle1 = std::partition(first, last, 
            [pivot](const auto& em) { return em < pivot; });
            
        auto middle2 = std::partition(middle1, last, 
            [pivot](const auto& em) { return !(pivot < em); });
            
        quicksort(first, middle1);
        quicksort(middle2, last);
    }
}

// 使用
std::vector<int> v = {5, 2, 9, 1, 7, 6, 3};
quicksort(v.begin(), v.end());  // v现在已排序
```


### 1.2. class templates
- 基础语法
```cpp
template<typename T>
class Vector {
private:
    T* data;
    size_t size_;
    
public:
    Vector() : data(nullptr), size_(0) {}
    
    void push_back(const T& value) {
        // 实现...
    }
    
    T& operator[](size_t index) {
        return data[index];
    }
};

// 使用：必须明确指定类型
Vector<int> int_vec;
Vector<string> str_vec;
```

- 非类型模版参数
```cpp
template<typename T, size_t N>
class Array {
    T data[N];  // 编译时确定大小
public:
    size_t size() const { return N; }
};

Array<int, 10> arr;  // 大小为10的int数组
```

### 1.3. 模版特化
- 函数模版特化
```cpp
// 通用版本
template<typename T>
void print(T value) {
    cout << value;
}

// 特化版本
template<>
void print<const char*>(const char* value) {
    cout << "String: " << value;
}
```

- 类模版特化
```cpp
// 通用版本
template<typename T>
class Storage {
    T data;
};

// 针对bool的特化
template<>
class Storage<bool> {
    // 特殊的bool存储实现
};
```

> 编译机制 
> 模版是编译时生成代码，不是运行时多态,每种类型都会生成对应的代码实例



# C++模板类用法详解 - 以LockFreeRingBuffer为例

C++模板类是一种强大的编程工具，允许我们编写通用代码，同时保持类型安全和高性能。我将结合`LockFreeRingBuffer`这个实际例子来详细讲解。


```cpp
#pragma once
#include <atomic>
#include <array>

template<typename T, size_t Size>
class LockFreeRingBuffer {
    static_assert((Size & (Size - 1)) == 0, "Size must be power of 2");
    
    struct alignas(64) Item {  // 避免false sharing
        std::atomic<bool> valid{false};
        T data;
    };

    static constexpr size_t MASK = Size - 1;
    std::array<Item, Size> buffer;
    alignas(64) std::atomic<size_t> write_index{0};
    alignas(64) std::atomic<size_t> read_index{0};

public:
    bool try_push(const T& item) noexcept {
        const size_t current = write_index.load(std::memory_order_relaxed);
        const size_t next = (current + 1) & MASK;
        
        if (next == read_index.load(std::memory_order_acquire)) {
            return false;  // buffer is full
        }
        
        buffer[current].data = item;
        buffer[current].valid.store(true, std::memory_order_release);
        write_index.store(next, std::memory_order_release);
        return true;
    }

    bool try_pop(T& item) noexcept {
        const size_t current = read_index.load(std::memory_order_relaxed);
        
        if (current == write_index.load(std::memory_order_acquire)) {
            return false;  // buffer is empty
        }
        
        if (!buffer[current].valid.load(std::memory_order_acquire)) {
            return false;  // data not ready
        }
        
        item = std::move(buffer[current].data);
        buffer[current].valid.store(false, std::memory_order_release);
        read_index.store((current + 1) & MASK, std::memory_order_release);
        return true;
    }
};

// 实例化
Common::LockFreeRingBuffer<AggTradeQueueData, QUEUE_SIZE> aggTrade_queue;

```

## 1. 模板类的定义

```cpp
template<typename T, size_t Size>
class LockFreeRingBuffer {
    // 类的实现...
};
```

这个声明有两个模板参数：
- `typename T`：类型参数，表示缓冲区中存储的数据类型
- `size_t Size`：非类型参数，表示缓冲区的大小（必须是编译时常量）

## 2. 模板类的实例化

在实际使用中，通过指定具体的类型和值来创建特定的缓冲区：

```cpp
// 创建存储AggTradeQueueData类型数据的缓冲区，大小为8192
Common::LockFreeRingBuffer<AggTradeQueueData, QUEUE_SIZE> aggTrade_queue;

// 创建存储TickerQueueData类型数据的缓冲区，大小为8192
Common::LockFreeRingBuffer<TickerQueueData, QUEUE_SIZE> ticker_queue;
```

编译器会为每种不同的模板参数组合生成不同的类代码。

## 3. 内部数据结构的适配

模板使得内部数据结构可以根据类型自动适配：

```cpp
struct alignas(64) Item {
    std::atomic<bool> valid{false};
    T data;  // 这里的T会被替换为实际类型
};

std::array<Item, Size> buffer;  // Size会被替换为实际大小
```

当使用`LockFreeRingBuffer<AggTradeQueueData, 8192>`时，编译器生成的代码相当于：

```cpp
struct Item {
    std::atomic<bool> valid{false};
    AggTradeQueueData data;  // T被替换为AggTradeQueueData
};

std::array<Item, 8192> buffer;  // Size被替换为8192
```


## 4. 模板特化的高级用法

虽然在这个例子中没有使用，但模板还支持特化，为特定类型提供优化的实现：

```cpp
// 主模板
template<typename T, size_t Size>
class LockFreeRingBuffer { /*...*/ };

// 为特定类型的特化版本
template<size_t Size>
class LockFreeRingBuffer<int, Size> { /*针对int类型的优化实现*/ };
```

## 8. 模板的优势

从`LockFreeRingBuffer`的例子可以看出模板的优势：

1. **代码复用**：同一套缓冲区逻辑用于多种数据类型
2. **类型安全**：编译时类型检查避免运行时错误
3. **零开销抽象**：模板在编译时展开，没有运行时开销
4. **灵活性**：可以处理任何符合接口的数据类型
5. **性能优化**：编译器可以为特定类型生成优化代码

总结：C++模板类允许我们编写一次代码，适用于多种数据类型，同时保持类型安全和高性能。在高性能系统如交易系统中，这种能力尤为重要。



