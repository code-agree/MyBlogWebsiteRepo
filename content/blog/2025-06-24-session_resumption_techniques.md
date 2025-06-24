+++
title = 'TLS会话恢复（Session Resumption）'
date = 2025-03-07T19:24:12+08:00
draft = false
tags = ["Http"]
+++

---
## 1. 会话恢复简介

### 什么是会话恢复？
TLS会话恢复是TLS协议的一项优化特性，允许客户端和服务器基于之前建立的安全会话快速恢复通信，跳过完整的握手过程。在TLS 1.3中，会话恢复主要通过**PSK（Pre-Shared Key，预共享密钥）**机制实现，而在TLS 1.2及更早版本中，也可以通过Session ID或Session Ticket实现。

### 为什么需要会话恢复？
- **性能优化**：
  - 完整握手（TLS 1.3）：1-RTT
  - 会话恢复：1-RTT（或0-RTT）
  - 显著减少连接建立时间
- **资源节省**：
  - 降低CPU开销（避免重复密钥交换）
  - 减少网络带宽占用

---

## 2. TLS 1.3中的会话恢复机制

### 工作流程对比

#### 完整握手（TLS 1.3）
```plaintext
Client                Server
  |   ClientHello       |
  |-------------------->|
  |   ServerHello       |
  |   EncryptedExt      |
  |   Certificate       |
  |   CertVerify        |
  |   Finished         |
  |<--------------------|
  |   Finished         |
  |-------------------->|
  |   NewSessionTicket  |
  |<--------------------|
```
- RTT：1次往返
- 服务器在握手后发送`NewSessionTicket`，包含PSK和有效期信息。

#### 会话恢复（1-RTT）
```plaintext
Client                Server
  |   ClientHello       |
  |   (with PSK)        |
  |-------------------->|
  |   ServerHello       |
  |   Finished         |
  |<--------------------|
  |   Finished         |
  |-------------------->|
```
- RTT：1次往返
- 客户端使用之前保存的PSK直接恢复会话。

#### 0-RTT（可选）
```plaintext
Client                Server
  |   ClientHello       |
  |   (with PSK + Early Data) |
  |-------------------->|
  |   ServerHello       |
  |   Finished         |
  |<--------------------|
  |   Finished         |
  |-------------------->|
```
- RTT：0次往返（早期数据随首次请求发送）
- 注意：0-RTT有重放攻击风险，仅适用于幂等请求。

---

## 3. 实现示例（基于picotls）

### 数据结构
```c
typedef struct {
    ptls_iovec_t session_ticket;    // 会话ticket（包含PSK）
    ptls_save_ticket_t ticket_cb;   // ticket保存回调
    int is_resumption;              // 是否恢复会话
    time_t ticket_received_time;    // ticket接收时间
} tls_context_t;
```

### 保存会话Ticket
```c
static int save_ticket_cb(ptls_save_ticket_t* self, ptls_t* tls, ptls_iovec_t ticket) {
    tls_context_t* ctx = container_of(self, tls_context_t, ticket_cb);
    
    // 释放旧ticket
    if (ctx->session_ticket.base) {
        free(ctx->session_ticket.base);
    }
    // 保存新ticket
    ctx->session_ticket.base = malloc(ticket.len);
    if (!ctx->session_ticket.base) return -1; // 内存分配失败
    memcpy(ctx->session_ticket.base, ticket.base, ticket.len);
    ctx->session_ticket.len = ticket.len;
    ctx->ticket_received_time = time(NULL);
    
    return 0;
}
```

### 尝试会话恢复
```c
ptls_handshake_properties_t props = {0};
if (conn->tls_ctx.session_ticket.base) {
    // 检查ticket是否过期（假设有效期24小时）
    if (time(NULL) - conn->tls_ctx.ticket_received_time < 24 * 3600) {
        props.client.session_ticket = conn->tls_ctx.session_ticket;
        props.client.max_early_data_size = 16384; // 支持0-RTT
        conn->session_info.resumption_attempted = 1;
    }
}
ptls_handshake(conn->tls, &props);
```

### 验证恢复结果
```c
if (conn->session_info.resumption_attempted) {
    conn->session_info.resumption_succeeded = ptls_is_psk_handshake(conn->tls);
    if (!conn->session_info.resumption_succeeded) {
        // 恢复失败，清理ticket
        free(conn->tls_ctx.session_ticket.base);
        conn->tls_ctx.session_ticket.base = NULL;
        conn->tls_ctx.session_ticket.len = 0;
    }
}
```

---

## 4. 在连接池中的应用

### 场景
- **复用连接**：检查ticket有效性，优先尝试恢复，失败则完整握手。
- **新建连接**：使用已有ticket尝试恢复，保存新ticket。
- **连接维护**：跟踪ticket有效期，清理过期ticket，统计恢复率。

### 示例逻辑
```c
if (pool->ticket.base && time(NULL) - pool->ticket_time < pool->ticket_lifetime) {
    // 尝试恢复
    props.client.session_ticket = pool->ticket;
    if (ptls_handshake(conn->tls, &props) == 0 && ptls_is_psk_handshake(conn->tls)) {
        pool->stats.resumption_success++;
    } else {
        pool->stats.resumption_fail++;
        ptls_handshake(conn->tls, NULL); // 回退完整握手
    }
} else {
    // 完整握手并保存新ticket
    ptls_handshake(conn->tls, NULL);
}
```

---

## 5. 注意事项

### 安全性
- **有效期限制**：ticket通常有效数小时，由服务器指定。
- **存储安全**：避免明文保存ticket，建议加密存储。
- **0-RTT风险**：防范重放攻击，仅用于安全场景。

### 性能优化
- **ticket管理**：避免过度保存，定期清理无效ticket。
- **服务器负载**：减少频繁发送`NewSessionTicket`。
- **监控指标**：记录恢复成功率，优化策略。

### 错误处理
- **优雅降级**：恢复失败时切换完整握手。
- **日志记录**：保存失败原因（如ticket过期或拒绝）。

---

## 6. 总结

TLS会话恢复通过PSK机制显著提升连接效率，尤其在高并发场景（如连接池）中效果明显。正确实现需要平衡安全性与性能，关注ticket管理、错误处理和监控。通过1-RTT或0-RTT，客户端和服务器可在毫秒内恢复安全通信，是现代网络优化的关键技术。

---

### 改进亮点
1. **TLS 1.3准确性**：流程图和术语基于TLS 1.3标准。
2. **0-RTT补充**：增加了0-RTT的说明和风险提示。
3. **代码健壮性**：加入内存分配检查和ticket过期逻辑。
4. **结构优化**：分为简介、机制、实现、应用和注意事项，逻辑更清晰。

如果需要进一步调整（如更深入的代码细节或特定场景分析），请告诉我！