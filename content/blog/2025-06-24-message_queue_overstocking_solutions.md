+++
title = 'WebSocket消息处理线程CPU亲和性导致的消息阻塞故障分析'
date = 2024-12-13T05:15:51+08:00
draft = false
+++

## 一、故障现象

### 1.1 单endpoint模式故障
- 单个WebSocket连接时消息接收完全阻塞
- 日志显示消息处理线程启动后无法接收新消息
```log
[2024-12-12 20:31:29.455] [error] [setThreadAffinity] Error calling pthread_setaffinity_np: 22
[2024-12-12 20:31:29.697] [info] Message thread started for endpoint: OkxPublic
// 之后无消息接收日志
```


### 1.2 多endpoint模式部分正常
- 多个WebSocket连接时只有一个线程能正常接收消息
- 日志显示消息处理情况：
```log
[20:54:50.542] [thread 91374] Processing message for OkxPublic
[20:54:50.640] [thread 91374] Processing message for OkxPublic
// 只有一个线程在持续处理消息
```


## 二、系统架构分析

### 2.1 WebSocket消息接收机制
```cpp
void WebSocketClient::receiveMessages(const MessageHandler& handler) {
    while (true) {
        try {
            // 1. 阻塞式接收WebSocket消息
            int n = ws_->receiveFrame(buffer.data(), buffer.size(), flags);
            
            // 2. 同步回调处理消息
            if (n > 0) {
                handler(buffer.data(), n);
            }
        } catch (const std::exception& e) {
            break;
        }
    }
}
```


### 2.2 关键技术点
1. **阻塞式WebSocket接收**
   - `receiveFrame`是阻塞调用
   - 直到收到消息才会返回
   - 高频交易场景下需要快速响应

2. **同步消息处理**
   - 接收和处理在同一线程中
   - 处理耗时会直接影响下一条消息的接收
   - 适合高频交易的低延迟要求

3. **CPU亲和性设置**
```cpp
void ConnectionPool::setupRealtime(int cpu_core) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu_core, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
    
    struct sched_param param;
    param.sched_priority = sched_get_priority_max(SCHED_FIFO);
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &param);
}
```


## 三、问题分析

### 3.1 单endpoint阻塞原因
1. **CPU亲和性限制**：
- 线程被强制绑定到特定CPU核心
- 当该核心被其他任务占用时，无法切换到其他核心
- 导致消息处理线程无法获得CPU时间

2. **阻塞式接收影响**：
- `receiveFrame`阻塞等待新消息
- CPU亲和性限制导致线程无法及时获得CPU时间
- 即使有新消息也无法及时处理

### 3.2 多endpoint场景分析
1. **为什么只有一个线程正常**：
- 多个线程竞争CPU资源
- 获得CPU时间片的线程能正常处理消息
- 其他线程由于CPU亲和性限制无法切换核心，导致阻塞

2. **日志证据**：
```log
[20:54:50.542] [thread 91374] OkxPublic message processed
[20:54:50.640] [thread 91374] OkxPublic message processed
// 只有thread 91374持续工作
```


## 四、解决方案

### 4.1 移除CPU亲和性限制
```cpp
void ConnectionPool::setupMessageHandler(context) {
    context->message_thread = std::thread([this, context]() {
        // 移除CPU亲和性设置
        // 让系统自动进行线程调度
        while (running_) {
            context->client->receiveMessages(...);
        }
    });
}
```


### 4.2 优化性能监控
```cpp
struct ThreadMetrics {
    std::atomic<uint64_t> messages_processed{0};
    std::atomic<uint64_t> processing_time_us{0};
    std::atomic<uint64_t> max_processing_time_us{0};
    std::atomic<int> current_cpu{-1};
};
```


## 五、经验总结

1. **高频交易系统特点**
- 需要低延迟处理
- 同步处理模式更适合
- 系统调度策略需要谨慎

2. **CPU亲和性使用原则**
- 避免不必要的限制
- 让操作系统进行自然调度
- 需要时要充分测试验证

3. **故障诊断要点**
- 分析线程行为模式
- 对比不同场景的表现
- 理解底层技术机制

4. **性能优化方向**
- 保持消息处理的低延迟
- 添加性能监控指标
- 系统调度最优化
