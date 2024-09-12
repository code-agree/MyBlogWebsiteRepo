+++
title = 'String_mmap'
date = 2024-09-12T15:23:23+08:00
draft = false
+++

# 故障复盘报告：内存映射文件中的 std::string 导致的段错误

## 1. 问题描述

在使用内存映射文件存储订单数据的过程中，程序在重启后出现段错误。具体表现为在尝试访问存储在内存映射文件中的 `Order` 结构体的 `id` 字段时，程序崩溃。

## 2. 错误信息

程序崩溃时的 GDB 调试信息如下：

```
Thread 2 "strategyandtrad" received signal SIGSEGV, Segmentation fault.
[Switching to Thread 0x7ffff6f4c6c0 (LWP 446582)]
__memcmp_sse2 () at ../sysdeps/x86_64/multiarch/memcmp-sse2.S:258
258     ../sysdeps/x86_64/multiarch/memcmp-sse2.S: No such file or directory.
(gdb) bt
#0  __memcmp_sse2 () at ../sysdeps/x86_64/multiarch/memcmp-sse2.S:258
#1  0x000055555556d79b in std::char_traits<char>::compare (__s1=0x7f4710000eb0 <error: Cannot access memory at address 0x7f4710000eb0>, 
    __s2=0x7fffe8000c80 "ORD-1726124231791862593", __n=23) at /usr/include/c++/12/bits/char_traits.h:385
#2  0x000055555559c599 in std::operator==<char> (__lhs=<error: Cannot access memory at address 0x7f4710000eb0>, __rhs="ORD-1726124231791862593")
    at /usr/include/c++/12/bits/basic_string.h:3587
#3  0x000055555561a7fa in MmapOrderBook::Impl::getOrder (this=0x555555776170, orderId="ORD-1726124231791862593")
    at /home/hft_trading_system/strategyandtradingwitheventbus/src/order_management/mmap_order_book_impl.cpp:211
...

(gdb) frame 3
#3  0x000055555561a7fa in MmapOrderBook::Impl::getOrder (this=0x555555776170, orderId="ORD-1726124231791862593")
    at /home/hft_trading_system/strategyandtradingwitheventbus/src/order_management/mmap_order_book_impl.cpp:211
211             if (m_orders[i].id == orderId) {
(gdb) print orderId
$1 = "ORD-1726124231791862593"
(gdb) print m_orders[i].id
$2 = <error: Cannot access memory at address 0x7f4710000eb0>
(gdb) print m_orders[i]
$3 = {id = <error: Cannot access memory at address 0x7f4710000eb0>, instId = <error: Cannot access memory at address 0x7f4710000ed0>, 
  price = 58126.699999999997, quantity = 100, status = 3}
```

3. 相关代码


```cpp
struct Order {
    std::string id;
    std::string instId;
    double price;
    double quantity;
    int status; // 0: pending, 1: filled, 2: cancelled
};
```
这个结构体直接在内存映射文件中使用，导致了我们遇到的问题。

## 4. 问题分析

通过分析错误信息和代码结构，我们发现：

1. 程序崩溃发生在比较 `m_orders[i].id` 和 `orderId` 时。
2. 无法访问 `m_orders[i].id` 的内存地址（0x7f4710000eb0）。
3. `Order` 结构体中的 `id` 和 `instId` 字段使用了 `std::string` 类型。

问题的根本原因是：`std::string` 是一个复杂对象，包含指向堆内存的指针。当程序退出后，这些指针所指向的内存不再有效。重新启动程序并尝试访问内存映射文件中的这些 `std::string` 对象时，就会导致段错误。

## 5. 解决方案

将 `Order` 结构体中的 `std::string` 类型替换为固定大小的字符数组：

```cpp
constexpr size_t MAX_ID_LENGTH = 64;
constexpr size_t MAX_INST_ID_LENGTH = 32;

struct Order {
    char id[MAX_ID_LENGTH];
    char instId[MAX_INST_ID_LENGTH];
    double price;
    double quantity;
    int status;

    // 构造函数和辅助方法...
};
```

同时，添加辅助方法来方便地设置和获取这些字段的值：

```cpp
void setId(const std::string& newId) {
    strncpy(id, newId.c_str(), MAX_ID_LENGTH - 1);
    id[MAX_ID_LENGTH - 1] = '\0';
}

std::string getId() const {
    return std::string(id);
}

// 类似地实现 setInstId 和 getInstId
```

## 6. 实施步骤

1. 修改 `Order` 结构体的定义。
2. 更新所有使用 `Order` 结构体的代码，使用新的 setter 和 getter 方法。
3. 删除旧的内存映射文件（如果存在），因为新的结构体布局与旧的不兼容。
4. 重新编译整个项目。
5. 运行测试，确保问题已解决且没有引入新的问题。

## 7. 经验教训

1. 在使用内存映射文件时，应避免直接存储包含指针或复杂对象（如 `std::string`）的结构体。
2. 对于需要持久化的数据结构，优先使用固定大小的数组或基本数据类型。
3. 在设计持久化数据结构时，考虑跨会话和跨进程的兼容性。
4. 增加更多的错误检查和日志记录，以便更容易地诊断类似问题。

## 8. 后续行动

1. 审查其他使用内存映射文件的代码，确保没有类似的潜在问题。
2. 考虑实现一个数据完整性检查机制，在程序启动时验证内存映射文件的内容。
3. 更新开发指南，强调在使用内存映射文件时应注意的事项。
4. 考虑实现一个版本控制机制，以便在未来需要更改数据结构时能够平滑迁移。
