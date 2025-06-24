+++
title = 'MmAvellaneda Stoikov'
date = 2025-05-19T13:38:50+08:00
draft = false
+++


这篇论文 **《Optimal High-Frequency Market Making》** 实现并分析了 Avellaneda-Stoikov (2008) 的高频做市定价模型，并引入了一个动态库存控制模块，用于优化限价单的挂单量，以在保证盈利的同时控制库存风险。下面是详细解读：

---

## 📌 一、研究背景与动机

高频做市商（HFT market makers）通过在订单簿中持续挂出买卖限价单来提供流动性，赚取 **买卖价差（spread）** 和 **交易所提供的挂单返利（rebate）**。但这同时会产生**库存风险（inventory risk）**，即买入或卖出过多后，价格波动带来的风险。

Avellaneda-Stoikov 模型是其中一个经典的高频做市定价框架，它在假设股票价格服从布朗运动的基础上，通过求解最优控制问题得出**最优报价策略**。

---

## 📌 二、模型框架

### 2.1 定价模型（Pricing）

基于 Avellaneda & Stoikov (2008)：

* 股票价格服从布朗运动： $dS_t = \sigma dW_t$
* 市场深度与成交概率关系：$\lambda(\delta) = A e^{-\kappa \delta}$
* 做市商目标是最大化终端时刻 $T$ 时的指数效用函数：

$$
\max_{\delta_a, \delta_b} \mathbb{E}[-e^{-\gamma (X_T + q_T S_T)}]
$$

推导结果是：

* **中间价（Indifference Price）**：

$$
r(s, t) = s - q\gamma\sigma^2(T - t)
$$

* **最优总挂单价差（Spread）**：

$$
\delta_a + \delta_b = \gamma\sigma^2(T - t) + \ln\left(1 + \frac{\gamma}{\kappa} \right)
$$

👉 这个模型体现了：

* 离市场收盘越近，价差越小（为了减少隔夜风险，变得更激进）
* 持有的库存 $q$ 越大，中间价越偏离市场中价

---

### 2.2 库存控制模型（Inventory Control）

为解决 Avellaneda-Stoikov 模型中“不限制库存大小”的问题，作者引入了一个动态调节挂单数量的模型：

$$
\begin{cases}
\phi_{\text{bid}}^t = \phi_{\text{max}}^t & \text{if } q_t < 0 \\
\phi_{\text{bid}}^t = \phi_{\text{max}}^t e^{-\eta q_t} & \text{if } q_t > 0
\end{cases}
\quad
\begin{cases}
\phi_{\text{ask}}^t = \phi_{\text{max}}^t & \text{if } q_t > 0 \\
\phi_{\text{ask}}^t = \phi_{\text{max}}^t e^{-\eta q_t} & \text{if } q_t < 0
\end{cases}
$$

这个设计逻辑是：

* 当前若持有过多某一方向的头寸（如多头），则减少挂出同方向单的数量
* 达到库存中性目标（inventory mean-reversion）

---

### 2.3 算法流程

策略遵循以下流程：

1. 若订单簿中无挂单，挂出最优买卖报价；
2. 若仅一边挂单被成交，则等待 5 秒，若未成交另一边则取消并重新挂单；
3. 若两边都在订单簿中，每隔 1 秒刷新一次报价；

---

## 📌 三、交易模拟器设计

构建了一个简化的交易环境用于模拟：

* 市场订单到达遵循时间非齐次泊松过程，强度：

$$
\lambda(t, \xi) = \alpha_t e^{-\mu \xi}
$$

其中 $\alpha_t$ 是随时间变化的成交活跃度（“浴缸曲线”），$\xi$ 是订单簿深度。

* 成交事件模拟使用贝努利分布 $Ber(\lambda(t, \xi)\Delta)$，部分成交使用 Gamma 分布模拟。

---

## 📌 四、实证结果与对比

对 S\&P500 中具有不同特性的五只股票（如 AAPL, AMZN, GE）进行实验，比较**本文策略（optimal）**与**基线策略（baseline，始终挂在最优买卖价）**：

### 🔸 核心结论：

* 本文策略在多数股票上有 **更高或相近的利润**；
* **库存控制更稳定**（位置更接近 0，方差更小）；
* 使用更少的挂单次数完成相似或更优的成交；
* **盈利方差更小，收益更稳健**；

### 🔸 样例结果（以 AAPL 为例）：

| 策略       | 平均每日 PnL | 平均每日库存 | PnL 方差 | 库存方差   |
| -------- | -------- | ------ | ------ | ------ |
| Optimal  | -988.54  | 0.86   | 289.82 | 63.66  |
| Baseline | -1093.60 | 7.53   | 357.66 | 112.20 |

---

## 📌 五、马尔可夫链分析

将做市过程建模为马尔可夫过程，状态空间为：

* `Quoting`: 正常挂单；
* `Waiting`: 一侧成交，另一侧等待；
* `Spread`: 成功赚到买卖价差；

引入两个性能指标：

* **成功捕获价差的概率** $p^*$
* **单边成交（未对冲）概率** $q^*$

| 股票   | Optimal $p^*$ | Baseline $p^*$ | Optimal $q^*$ | Baseline $q^*$ |
| ---- | ------------- | -------------- | ------------- | -------------- |
| AAPL | 2.6%          | 5.1%           | 0.8%          | 0.9%           |
| AMZN | 19.3%         | 4.7%           | 1.9%          | 1.0%           |

👉 虽然 Baseline 策略挂得更激进，捕获价差的概率更高，但 Optimal 策略的单边成交概率更低，说明**更有效地控制了库存风险**。

---

## ✅ 结论总结

* 本文将 Avellaneda-Stoikov 的模型扩展为一个 **可实际运行的高频做市策略**；
* 通过库存控制模块，使策略能在不停止交易的前提下控制风险；
* 实验结果验证其在多个维度优于基准策略；
* 提出进一步改进方向：引入对中间价变化与订单到达的预测。

## ref
https://stanford.edu/class/msande448/2018/Final/Reports/gr5.pdf
