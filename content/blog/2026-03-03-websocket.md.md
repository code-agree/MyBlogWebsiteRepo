+++
title = '高频交易中的 WebSocket 架构设计：从阻塞 IO 到事件驱动'
date = 2026-03-03T23:38:37+08:00
draft = false
tags = ["Network", "HFT"]
+++

> 本文以一个真实的 OKX Fill Receiver 实现为切入点，深入探讨 HFT 场景下 WebSocket 客户端的架构设计，涵盖 Socket 编程基础、epoll 事件驱动模型、Connection/Socket/Thread 的关系，以及面向超低延迟的工程优化。

---

## 一、Socket 编程基础：从 fd 到 Connection

### 1.1 文件描述符 (File Descriptor) 是一切的起点

在 Unix/Linux 中，**一切皆文件**。网络连接也不例外——一个 TCP 连接在内核中对应一个 `struct socket`，在用户态通过一个整数 **文件描述符 (fd)** 来引用。

一个 TCP 连接的建立过程：

```
客户端:                              服务端:
  fd = socket(AF_INET, SOCK_STREAM, 0)   listen_fd = socket(...)
  connect(fd, server_addr, ...)           bind(listen_fd, addr, ...)
        │                                listen(listen_fd, backlog)
        │── SYN ──────────────────►       │
        │◄─────────────── SYN+ACK ──      │
        │── ACK ──────────────────►       conn_fd = accept(listen_fd, ...)
        │                                 │
     fd 可读可写                        conn_fd 可读可写
```

关键事实：

- **一个 connection = 一个 fd**。这是一一对应的关系。
- `socket()` 创建一个未连接的 fd。
- `connect()` 将 fd 与远端地址绑定，完成三次握手后，fd 代表一条完整的 TCP 连接。
- fd 只是一个整数索引，指向内核中的 `struct file → struct socket → struct sock`。

### 1.2 TCP 连接的内核数据结构

```
用户态:
  int fd = 5;   ← 只是一个数字

内核态:
  进程 fd 表:  [0:stdin, 1:stdout, 2:stderr, ..., 5:socket_file]
                                                      │
                                                      ▼
                                               struct socket {
                                                   struct sock *sk;  ← TCP 状态机
                                                   // ...
                                               }
                                                      │
                                                      ▼
                                               struct tcp_sock {
                                                   // 发送缓冲区 (sk_write_queue)
                                                   // 接收缓冲区 (sk_receive_queue)
                                                   // TCP 状态 (ESTABLISHED, CLOSE_WAIT, ...)
                                                   // 窗口大小、拥塞控制、RTT 估计...
                                               }
```

当 `SSL_read()` / `read()` 被调用时，实际上是从 `sk_receive_queue`（内核接收缓冲区）中拷贝数据到用户态 buffer。

### 1.3 HFT 必须设置的 Socket 选项

```cpp
// 1. TCP_NODELAY — 禁用 Nagle 算法
//    Nagle: 将小包攒成大包一起发，减少网络包数量
//    HFT 场景: 每一个字节都要立刻发出，不能等
int one = 1;
setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

// 2. TCP_QUICKACK — 禁用 Delayed ACK
//    Delayed ACK: 收到数据后等 40ms 看能不能搭便车发 ACK
//    HFT 场景: 立刻回 ACK，让对端尽快发下一个数据包
setsockopt(fd, IPPROTO_TCP, TCP_QUICKACK, &one, sizeof(one));
// 注意: TCP_QUICKACK 不是持久设置，每次 read 后可能需要重新设置

// 3. SO_BUSY_POLL — 内核忙轮询
//    普通模式: NIC 收到包 → 中断 → 内核处理 → 唤醒阻塞的 read()
//    Busy poll: 在 read()/epoll_wait() 中主动轮询 NIC，绕过中断延迟
//    典型节省: 5-20µs 的中断延迟
int us = 50; // 忙轮询 50 微秒
setsockopt(fd, SOL_SOCKET, SO_BUSY_POLL, &us, sizeof(us));

// 4. SO_TIMESTAMPING — 内核级收包时间戳
//    普通 clock_gettime(): 在用户态 read() 返回后才打时间戳
//    SO_TIMESTAMPING: 内核在 NIC 驱动层就打时间戳，精度高得多
int flags = SOF_TIMESTAMPING_RX_SOFTWARE | SOF_TIMESTAMPING_SOFTWARE;
setsockopt(fd, SOL_SOCKET, SO_TIMESTAMPING, &flags, sizeof(flags));
```

---

## 二、IO 模型演进：从阻塞到事件驱动

### 2.1 阻塞 IO — Thread-per-Connection 模型

这是最直观的模型，也是 `okex_fill_receiver` 当前使用的模型：

```
线程1: while(1) { n = read(fd1, buf, ...); process(buf); }  ← 阻塞在 fd1
线程2: while(1) { n = read(fd2, buf, ...); process(buf); }  ← 阻塞在 fd2
线程3: while(1) { n = read(fd3, buf, ...); process(buf); }  ← 阻塞在 fd3
```

**每个连接独占一个线程**，线程的生命周期就是不断地 `read() → 处理 → read() → ...`

优点：
- 编程模型简单，代码线性，易于理解
- 每个连接的处理逻辑独立，互不干扰

缺点：
- **线程资源开销**：每个线程占用 ~8MB 栈空间（默认），1000 个连接就是 8GB
- **上下文切换**：线程多了之后，OS 调度器的 context switch 开销显著（每次 1-5µs）
- **跨线程协调困难**：如果需要"收到 fd1 的行情后在 fd2 上下单"，需要线程间通信（锁、队列），引入额外延迟
- **无法共享 SSL 对象**：OpenSSL 的 `SSL*` 对象不支持一个线程 read 另一个线程同时 write，除非用特定配置

这就是经典的 **C10K 问题**（1999 年 Dan Kegel 提出）：当连接数达到 10,000 时，thread-per-connection 模型崩溃。

### 2.2 非阻塞 IO + select/poll

解决 C10K 的第一步：不为每个连接分配线程，而是让一个线程同时监听多个 fd。

```cpp
// 设置 fd 为非阻塞
int flags = fcntl(fd, F_GETFL, 0);
fcntl(fd, F_SETFL, flags | O_NONBLOCK);

// 非阻塞 read: 没有数据时立刻返回 EAGAIN，不会阻塞
int n = read(fd, buf, sizeof(buf));
if (n < 0 && errno == EAGAIN) {
    // 没有数据，稍后再试
}
```

但是，只有非阻塞 fd 还不够——你需要一种机制来知道**哪些 fd 有数据可读**。这就是 `select` 和 `poll`：

```cpp
// select: 传入一组 fd，返回哪些 fd 就绪了
fd_set readfds;
FD_ZERO(&readfds);
FD_SET(fd1, &readfds);
FD_SET(fd2, &readfds);
select(max_fd + 1, &readfds, NULL, NULL, &timeout);
// 问题: 每次调用都要把整个 fd_set 从用户态拷贝到内核态
// 内核要线性扫描所有 fd 检查是否就绪 → O(n)
```

`select` 和 `poll` 的性能瓶颈在于 **每次调用都是 O(n)**——即使只有 1 个 fd 就绪，内核也要遍历所有被监听的 fd。当 fd 数量达到上万时，这个开销无法接受。

### 2.3 epoll — Linux 的终极 IO 多路复用

epoll 是 Linux 2.6 引入的 IO 多路复用机制，专门为解决 select/poll 的 O(n) 问题而设计。

#### epoll 的三个系统调用

```cpp
// 1. 创建 epoll 实例 — 返回一个 epoll fd
int epfd = epoll_create1(0);
// 内核创建一个 eventpoll 结构体：
//   - 红黑树 (rbr): 存储所有被监听的 fd
//   - 就绪链表 (rdllist): 存储已就绪的 fd

// 2. 注册/修改/删除监听的 fd
struct epoll_event ev;
ev.events = EPOLLIN | EPOLLET;  // 监听可读事件，边缘触发
ev.data.fd = fd;
epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
// 将 fd 插入红黑树 — O(log n)
// 同时在 fd 对应的 socket 上注册一个回调函数

// 3. 等待事件
struct epoll_event events[MAX_EVENTS];
int nfds = epoll_wait(epfd, events, MAX_EVENTS, timeout_ms);
// 只返回就绪的 fd — O(1)（不需要扫描所有 fd）
for (int i = 0; i < nfds; i++) {
    if (events[i].events & EPOLLIN) {
        handle_read(events[i].data.fd);
    }
}
```

#### epoll 为什么是 O(1) 的

核心在于**回调驱动**的设计：

```
                  内核态
                  ┌──────────────────────────────────────┐
                  │  struct eventpoll {                   │
                  │      红黑树 (rbr):                    │
                  │          fd1 ──→ epitem1              │
                  │          fd2 ──→ epitem2              │
                  │          fd3 ──→ epitem3              │
                  │                                      │
NIC 收到 fd2     │      就绪链表 (rdllist):              │
的数据包 ────►    │          [空]                         │
                  │              ↓                        │
内核网络栈处理    │      fd2 的回调被触发:                 │
数据到达 socket   │          ep_poll_callback(fd2)        │
接收缓冲区 ──►    │              ↓                        │
                  │      将 epitem2 加入 rdllist:         │
                  │          [epitem2]                    │
                  │              ↓                        │
                  │      唤醒阻塞在 epoll_wait 的线程     │
                  └──────────────────────────────────────┘
                                 │
                                 ▼
用户态:  epoll_wait() 返回, nfds=1, events[0].fd = fd2
```

对比 select/poll：
- **select/poll**：每次调用，内核遍历所有 n 个 fd，检查每个 fd 的接收缓冲区是否有数据 → O(n)
- **epoll**：内核只需检查就绪链表是否为空 → O(1)。fd 就绪时，是通过**回调**主动加入链表的。

#### 水平触发 (LT) vs 边缘触发 (ET)

```
                          数据到达
                             │
时间轴: ─────────────────────┼───────────────────────────────►
                             │
内核接收缓冲区:               ████████████
                             │          │
                             │    第一次 read: 读了一部分
                             │          │
                             │          ████████  ← 还有剩余数据
                             │
LT 模式 (默认):
  epoll_wait → 就绪           (只要缓冲区有数据，每次 epoll_wait 都报告就绪)
  epoll_wait → 就绪
  epoll_wait → 就绪
  ...直到数据读完

ET 模式 (EPOLLET):
  epoll_wait → 就绪           (只在"状态变化"时通知一次)
  epoll_wait → 不报告          (即使缓冲区还有数据)
  ...直到新数据到达才再次触发
```

**HFT 通常使用 ET 模式**：
- 减少 `epoll_wait` 返回的次数，降低系统调用开销
- 但要求每次必须 `read()` 直到返回 `EAGAIN`，否则会丢数据
- 对编程要求更高，但性能更好

### 2.4 三种 IO 模型的延迟对比

```
                    阻塞 IO          非阻塞 + poll        非阻塞 + epoll
                  ┌──────────┐     ┌──────────────┐     ┌──────────────┐
数据到达 NIC      │          │     │              │     │              │
    │             │ 中断     │     │ 中断         │     │ 中断         │
    │ ~1-5µs      │ 唤醒线程 │     │ 唤醒poll     │     │ 回调加入     │
    ▼             │          │     │              │     │ rdllist      │
内核处理          │ read()   │     │ 遍历所有fd   │     │ epoll_wait   │
    │             │ 返回数据 │     │ O(n) 找到fd  │     │ O(1) 返回fd  │
    ▼             │          │     │ read()       │     │ read()       │
用户态处理        │ 处理     │     │ 处理         │     │ 处理         │
                  └──────────┘     └──────────────┘     └──────────────┘

线程利用率:         1 连接/线程       N 连接/线程          N 连接/线程
每次等待开销:       ~0 (直接唤醒)     O(n) 扫描            O(1)
适用连接数:         < 100              < 1,000              > 100,000
```

---

## 三、Connection / Socket / Thread 的关系

### 3.1 三者的映射关系不是固定的

很多初学者误以为"一个连接必须对应一个线程"，实际上它们的关系是灵活的：

```
模型1: Thread-per-Connection (一对一)
  Thread_1 ──── fd_1 (conn_1)
  Thread_2 ──── fd_2 (conn_2)
  Thread_3 ──── fd_3 (conn_3)

模型2: Single-Thread Reactor (一对多)
  Thread_1 ──┬─ fd_1 (conn_1)
             ├─ fd_2 (conn_2)
             ├─ fd_3 (conn_3)
             └─ fd_4 (conn_4)

模型3: Multi-Thread Reactor (多对多)
  Thread_1 ──┬─ fd_1 (conn_1)    Thread_2 ──┬─ fd_3 (conn_3)
             └─ fd_2 (conn_2)               └─ fd_4 (conn_4)
```

**HFT 场景下最常用的是模型2（单线程 Reactor）**——一个绑核的 IO 线程通过 epoll 管理所有连接。这样做的优势：

1. **所有 IO 逻辑在一个线程**：不需要锁，因为不存在并发访问
2. **cache 最热**：一个核只做 IO，L1/L2 cache 中全是相关数据
3. **跨连接协调零开销**：收到行情后，直接在同一线程中构建订单发到另一条连接上，无需跨线程通信

### 3.2 WebSocket 的 Ping-Pong 只能在对应的连接上维护

WebSocket 协议的 ping/pong 是**协议层面的 per-connection 心跳**：

```
RFC 6455 §5.5.2:
  A Ping frame may be sent at any time after the connection is
  established and before the connection is closed.

RFC 6455 §5.5.3:
  A Pong frame sent in response to a Ping frame must have identical
  Application Data as found in the Ping frame being replied to.
```

每条连接有独立的 WebSocket 状态机，ping 必须在哪条连接上收到就在哪条连接上回 pong。不能在连接 A 上收到 ping 后在连接 B 上回 pong。

但这并不意味着每条连接需要一个线程——在事件驱动模型下：

```cpp
// 一个线程管理 N 条 WebSocket 连接
while (true) {
    int nfds = epoll_wait(epfd, events, MAX_EVENTS, 100 /*ms*/);
    for (int i = 0; i < nfds; i++) {
        WsConn* conn = (WsConn*)events[i].data.ptr;
        conn->on_readable();  // 内部处理: 如果是 ping，直接在这条连接上回 pong
    }
    // 检查定时器: 给所有连接发 keepalive ping
    check_keepalive_timers();
}
```

---

## 四、HFT WebSocket 架构设计

### 4.1 阻塞式实现的局限性 (当前 okex_fill_receiver)

当前实现的线程模型：

```
┌─────────────────────┐    ┌──────────────────────┐
│   IO Thread          │    │   Keepalive Thread    │
│                      │    │                       │
│ while(running) {     │    │ while(running) {      │
│   SSL_read(ssl, ...) │    │   sleep(1s)           │
│   // 阻塞等待        │    │   if (tick++ >= 20)   │
│   now_us()           │    │     lock(send_mtx_)   │
│   parse_frames()     │    │     SSL_write("ping") │
│   on_message()       │    │     unlock()          │
│ }                    │    │ }                     │
└─────────────────────┘    └──────────────────────┘
         │                            │
         └───── 共享 SSL* + mutex ────┘
```

这个模型用于"单连接收数据测延迟"完全够用，但无法扩展到 HFT 完整交易链路的需求：

| 限制 | 影响 |
|------|------|
| 一个连接一个线程 | 10 条连接需要 10 个 IO 线程 + keepalive 线程 |
| SSL_read 阻塞 | 线程无法同时做其他事（如检查发送队列） |
| send_mtx_ 互斥 | IO 线程回 pong 和 keepalive 线程发 ping 可能冲突 |
| 跨连接需要跨线程 | "收到行情立刻下单"需要通过锁或队列传递，增加延迟 |

### 4.2 事件驱动架构 (HFT 标准做法)

```
┌────────────────────────────────────────────────────────────┐
│                    IO Thread (绑核, 独占一个 CPU core)       │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              epoll 事件循环                            │  │
│  │                                                      │  │
│  │  epoll_wait(epfd, events, MAX, timeout)               │  │
│  │       │                                              │  │
│  │       ├─ fd1 可读 → SSL_read(conn1) → 解析行情       │  │
│  │       │                 → 写入 SHM 给策略             │  │
│  │       │                                              │  │
│  │       ├─ fd2 可读 → SSL_read(conn2) → 解析 fill      │  │
│  │       │                 → 写入 SHM 给策略             │  │
│  │       │                                              │  │
│  │       ├─ fd3 可写 → SSL_write(conn3) → 发送订单      │  │
│  │       │       ↑                                      │  │
│  │       │    SPSC queue                                │  │
│  │       │    有数据时注册                                │  │
│  │       │    EPOLLOUT                                   │  │
│  │       │                                              │  │
│  │       └─ timerfd 到期 → 给所有连接发 ping             │  │
│  │                       → 检查超时连接                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  所有 SSL_read / SSL_write 都在同一个线程                    │
│  → 不需要 mutex                                            │
│  → SSL* 对象无并发访问风险                                   │
│  → cache 始终是热的                                         │
└────────────────────────────────────────────────────────────┘
                         ▲
                         │ SPSC queue (lock-free)
                         │
┌────────────────────────┴───────────────────────────────────┐
│                  Strategy Thread (绑另一个核)                │
│                                                            │
│    收到 SHM 行情 → 计算信号 → 构建订单 → push to queue     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

#### 关键设计要点

**1. timerfd 替代 keepalive 线程**

```cpp
// 创建一个 20 秒周期的定时器 fd
int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
struct itimerspec its = {};
its.it_value.tv_sec    = 20;  // 首次触发
its.it_interval.tv_sec = 20;  // 周期
timerfd_settime(tfd, 0, &its, NULL);

// 注册到 epoll
epoll_ctl(epfd, EPOLL_CTL_ADD, tfd, &timer_event);

// 在事件循环中处理
if (events[i].data.fd == tfd) {
    uint64_t expirations;
    read(tfd, &expirations, sizeof(expirations));
    for (auto& conn : connections)
        conn->send_ping();
}
```

不需要额外线程，keepalive 逻辑融入事件循环。

**2. SPSC 队列桥接策略线程和 IO 线程**

```cpp
// 策略线程: 推送订单到队列
struct OrderMsg {
    int    conn_id;
    char   payload[512];
    size_t len;
};

SPSCQueue<OrderMsg> order_queue;  // lock-free, ~5ns per push/pop

// 策略线程:
order_queue.push({conn_id, serialized_order, len});

// IO 线程: 在事件循环中检查队列
OrderMsg msg;
while (order_queue.pop(msg)) {
    connections[msg.conn_id]->ssl_write(msg.payload, msg.len);
}
```

**3. 非阻塞 SSL 与 epoll 的配合**

```cpp
// 设置底层 fd 为非阻塞
fcntl(fd, F_SETFL, O_NONBLOCK);

// SSL_read 在非阻塞 fd 上的行为:
int n = SSL_read(ssl, buf, sizeof(buf));
if (n > 0) {
    // 成功读到数据
} else {
    int err = SSL_get_error(ssl, n);
    if (err == SSL_ERROR_WANT_READ) {
        // 没有数据，重新注册 EPOLLIN，等下次 epoll_wait 通知
    } else if (err == SSL_ERROR_WANT_WRITE) {
        // TLS 重协商需要写，注册 EPOLLOUT
    }
}
```

### 4.3 多连接管理与延迟优化

#### DNS 解析与延迟探测

HFT 系统不会简单地 `getaddrinfo()` 取第一个 IP 连接。正确做法：

```cpp
// 1. 解析所有 IP
struct addrinfo *res, *rp;
getaddrinfo("ws.okx.com", "8443", &hints, &res);

// 2. 对每个 IP 做 TCP 连接延迟探测
std::vector<std::pair<sockaddr_in, double>> ip_latencies;
for (rp = res; rp != NULL; rp = rp->ai_next) {
    auto start = now_us();
    int probe_fd = socket(...);
    fcntl(probe_fd, F_SETFL, O_NONBLOCK);
    connect(probe_fd, rp->ai_addr, rp->ai_addrlen);
    // epoll_wait 等待连接完成
    auto elapsed = now_us() - start;
    ip_latencies.push_back({*(sockaddr_in*)rp->ai_addr, elapsed});
    close(probe_fd);
}

// 3. 按延迟排序，选最快的 IP
std::sort(ip_latencies.begin(), ip_latencies.end(),
          [](auto& a, auto& b) { return a.second < b.second; });
```

#### Round-Robin 发单与最快连接选择

```cpp
// 多条连接轮询发单 — 分摊交易所频率限制
void send_round_robin(std::string&& order) {
    int idx = rr_counter_.fetch_add(1, std::memory_order_relaxed) % n_conns_;
    connections_[idx]->send(std::move(order));
}

// 动态选择最快连接发单 — 基于延迟统计
void send_fastest(std::string&& order) {
    int fid = fastest_id_.load(std::memory_order_relaxed);
    connections_[fid]->send(std::move(order));
}
```

### 4.4 发送路径优化：预模板化订单

HFT 发单的热路径上不能做 JSON DOM 构建。正确做法是**预模板化**：

```cpp
// 启动时: 预构建订单模板
class OrderTemplate {
    // 固定部分 (编译期确定):
    // {"op":"order","args":[{"instIdCode":"","side":"","ordType":"limit","px":"","sz":""}]}
    char template_[512];
    size_t px_offset_, px_len_;    // price 字段在 template 中的偏移和长度
    size_t sz_offset_, sz_len_;    // size 字段
    size_t side_offset_;

public:
    // 热路径: 只填入变化的字段，不做 JSON 构建
    size_t fill(char* out, const char* price, const char* size, char side) {
        memcpy(out, template_, template_len_);
        memcpy(out + px_offset_, price, strlen(price));
        memcpy(out + sz_offset_, size, strlen(size));
        out[side_offset_] = side;  // 'b' or 's'
        return template_len_;
    }
};

// 热路径: 填模板 → 构建 WS 帧 → SSL_write
// 整个过程零 malloc, 零 JSON 解析
```

### 4.5 WebSocket 帧构建优化

```cpp
class WsFrameBuilder {
    uint8_t buf_[1024];  // 预分配，不 malloc
    uint32_t mask_state_; // xorshift PRNG 状态

    // 快速 PRNG — WebSocket mask 不需要密码学安全
    uint32_t next_mask() {
        mask_state_ ^= mask_state_ << 13;
        mask_state_ ^= mask_state_ >> 17;
        mask_state_ ^= mask_state_ << 5;
        return mask_state_;
    }

public:
    // 构建帧: 零 malloc, ~10ns
    std::pair<uint8_t*, size_t> build(const uint8_t* payload, size_t len, uint8_t opcode) {
        size_t pos = 0;
        buf_[pos++] = 0x80 | opcode;

        uint32_t mask = next_mask();  // ~1ns, 不是 RAND_bytes 的 ~1-3µs

        if (len < 126) {
            buf_[pos++] = 0x80 | (uint8_t)len;
        } else {
            buf_[pos++] = 0x80 | 126;
            buf_[pos++] = (len >> 8) & 0xFF;
            buf_[pos++] = len & 0xFF;
        }

        memcpy(buf_ + pos, &mask, 4); pos += 4;

        // 用 SIMD 做 mask XOR (AVX2 可以一次处理 32 字节)
        const uint8_t* m = (const uint8_t*)&mask;
        for (size_t i = 0; i < len; i++)
            buf_[pos + i] = payload[i] ^ m[i & 3];
        pos += len;

        return {buf_, pos};
    }
};
```

---

## 五、完整的 HFT WebSocket 数据流

从网卡到策略、从策略到交易所的完整链路：

```
                         ═══ 接收路径 (行情/成交回报) ═══

NIC 收到数据包
    │ (~0ns, 硬件)
    ▼
内核网络栈处理, 放入 socket 接收缓冲区
    │ (~1-5µs, 取决于中断 or busy poll)
    ▼
epoll_wait 返回, fd 就绪
    │ (~0.1µs)
    ▼
SSL_read: TLS 解密
    │ (~5-30µs, 取决于数据大小和密码套件)
    ▼
WebSocket 帧解析 (零拷贝, 用偏移量而非 vector::erase)
    │ (~0.1µs)
    ▼
消息解析 (SAX JSON / SBE binary)
    │ (~0.5-2µs)
    ▼
写入 SHM (lock-free ring buffer)
    │ (~0.05µs)
    ▼
策略进程通过 SHM 读取
    │ (~0.05µs)
    ▼
策略计算完成


                         ═══ 发送路径 (下单) ═══

策略决策完成, 填充预模板化订单
    │ (~0.1µs)
    ▼
SPSC queue push
    │ (~0.005µs, lock-free)
    ▼
IO 线程 epoll_wait 返回, 检查 queue
    │ (~0.1µs, 取决于 epoll_wait timeout)
    ▼
构建 WebSocket 帧 (预分配 buffer, xorshift mask)
    │ (~0.01µs)
    ▼
SSL_write: TLS 加密 + write 系统调用
    │ (~5-20µs)
    ▼
内核发送到 NIC → 网络传输
```

---

## 六、超越 epoll：io_uring 与内核旁路

### 6.1 io_uring (Linux 5.1+)

epoll 的问题：每次 `epoll_wait` + `read` 至少是 2 次系统调用。`io_uring` 通过共享内存环形缓冲区减少系统调用：

```
用户态                            内核态
┌─────────────┐                  ┌──────────────┐
│  SQ Ring     │ ──── 提交 ────► │  处理请求     │
│  (提交队列)   │                  │              │
└─────────────┘                  └──────┬───────┘
                                        │
┌─────────────┐                         │
│  CQ Ring     │ ◄─── 完成 ────────────┘
│  (完成队列)   │
└─────────────┘

// 不需要系统调用! 用户态直接写 SQ，内核直接写 CQ
// 通过 mmap 的共享内存交互
```

### 6.2 内核旁路 (DPDK / Solarflare OpenOnload)

最极致的做法是完全绕过内核网络栈：

```
普通路径:  NIC → 内核驱动 → 内核网络栈 → socket 缓冲区 → read() → 用户态
DPDK:     NIC → 用户态驱动 → 用户态网络栈 → 应用层     (零拷贝, 零系统调用)
```

这在 sub-microsecond 级别的 HFT 中才需要，对于 OKX 这类通过公网接入的加密货币交易所，epoll 已经足够。

---

## 七、总结：不同场景的技术选择

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 单连接收数据/测延迟 | 阻塞 IO | 简单、正确，开发成本低 |
| 多连接行情接收 | epoll + 非阻塞 SSL | 一个线程管所有连接，延迟低 |
| 行情接收 + 下单一体化 | epoll 事件循环 + SPSC 队列 | 收发同线程，跨连接零延迟 |
| 需要 SHM 发布给策略 | 上述 + lock-free ring buffer | 进程间通信零拷贝 |
| Sub-µs 极致延迟 | DPDK / io_uring + kernel bypass | 绕过内核，用户态直接操作 NIC |

**架构设计的核心原则**：减少数据从产生到消费之间经过的线程数、锁数、内存拷贝数和系统调用数。每多一次跨线程通信，就多一次不可控的延迟；每多一次内存分配，就多一次可能的 cache miss。HFT 的本质是用确定性换取速度——让每一条代码路径的延迟都是可预测的。
