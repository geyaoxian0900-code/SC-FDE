# 第 4 章迭代均衡算法与公式

执行入口为 `simulate_chapter4_iterative_equalization.m`。入口调用模块
`+scfde/run_chapter4_turbo_suite.m`，因此均衡器分支、SISO BCJR 译码器和图形输出彼此独立，可按 `methods` 与 `decoderMethods` 选择。

## 统一信号模型

卷积编码、随机交织和 BPSK 映射后，循环块信道的频域模型为：

```math
Y_k = H_k X_k + W_k,
\qquad L_{E,k} = 2 Re{hat X_k} / sigma_w^2.
```

`L_E` 是均衡器传给 SISO 译码器的编码位对数似然比（LLR）。译码器输出编码位后验 LLR `L_D`，再转换为软符号反馈：

```math
m_k = tanh(L_{D,k}/2),
\qquad 0 <= rho = mean(|m_k|^2) < 1.
```

该软反馈进入下一次均衡，构成截图第 4.1 节所示的 Turbo 迭代闭环。`turboDamping` 控制新旧软符号的加权，默认值为 `0.75`。

## SISO BCJR 译码器

对卷积码状态 `s`、输入比特 `u` 和分支度量 `gamma_k(s,u)`，MAP 后验 LLR 为：

```math
L(u_k) = log(
  sum_{(s,u=0)} alpha_{k-1}(s) gamma_k(s,0) beta_k(s') /
  sum_{(s,u=1)} alpha_{k-1}(s) gamma_k(s,1) beta_k(s') ).
```

实现提供三种与第 4.1.4、4.1.5 节对应的 BCJR 近似：

| `decoderMethods` ID | 实现 | 说明 |
|---|---|---|
| `MAP` | 概率域前向/后向递推 | 直接计算并逐时刻归一化，作为参考。 |
| `Log-MAP` | 对数域 `max*` 递推 | `max*(a,b)=max(a,b)+log(1+exp(-|a-b|))`。 |
| `Max-Log-MAP` | 对数域最大值递推 | `max*(a,b) approx max(a,b)`，复杂度最低。 |

三者均输出信息位 LLR 与编码位后验 LLR；后者是 Turbo 均衡器的软判决反馈来源，而非仅用硬判决重新编码。

## 可选迭代均衡器

| `methods` ID | 对应章节算法 | 核心步骤 |
|---|---|---|
| `TD-Turbo-MAP` | 时域 Turbo + MAP | 时域 LMMSE 均衡器与概率域 BCJR 交换软信息。 |
| `TD-Turbo-Log-MAP` | 时域 Turbo + LOG-MAP | 时域 LMMSE 均衡器与 Log-MAP BCJR 交换软信息。 |
| `TD-Turbo-Max-Log-MAP` | 时域 Turbo + MAX-LOG-MAP | 时域 LMMSE 均衡器与 Max-Log-MAP BCJR 交换软信息。 |
| `FD-DFE` | 频域判决反馈均衡器 | 单次频域前馈/判决反馈基线，不做 Turbo 反馈。 |
| `FD-Turbo-Log-MAP` | 频域 Turbo 均衡 | 频域软干扰抵消与 Log-MAP BCJR 反馈。 |
| `FD-Turbo-Max-Log-MAP` | 频域 Turbo 均衡 | 频域软干扰抵消与 Max-Log-MAP BCJR 反馈。 |
| `TF-Turbo-Log-MAP` | 时频域 Turbo 均衡 | 时域和频域软估计等权融合。 |
| `BiTF-Turbo-Log-MAP` | 双向时频域 Turbo 均衡 | 在时频融合基础上增加反向支路，并融合前反向估计。 |
| `BLMS-TF-Turbo` | BLMS 时频域 Turbo 均衡 | 时频融合、Log-MAP 反馈与块 LMS 信道更新。 |

### 时域 Turbo 均衡

令 `C` 为循环卷积矩阵，`m` 为译码器反馈的软符号，则时域 LMMSE 估计为：

```math
W_T = (C^H C + sigma_w^2 I)^(-1) C^H,
\qquad hat x_T = m + W_T (y - C m).
```

### 频域 FD-DFE 与频域 Turbo

频域前馈和反馈系数按第 4.2 节公式 (4-56)~(4-58) 计算：

```math
w_k = h_k^*(1+b_k) / (\sigma^2 + |h_k|^2),
\qquad
b_k = [\lambda(\sigma^2+|h_k|^2)-\sigma^2] / [(\sigma^2+|h_k|^2)-\rho|h_k|^2],
```

其中 `lambda` 由约束 `sum_k b_k = 0`（书式 3-68/4-58）确定：

```math
\lambda = \sigma^2 \frac{\sum_k 1/D_k}{\sum_k (\sigma^2+|h_k|^2)/D_k},
\qquad D_k = (\sigma^2+|h_k|^2)-\rho|h_k|^2,
```

`rho = mean(|m_k|^2)`（书式 4-55）是译码器软反馈可靠度。频域判决反馈输出与频域 Turbo 软输出统一写作：

```math
hat X_k = w_k Y_k - b_k M_k,
```

其中 FD-DFE 的 `M_k` 来自一次硬判决；频域 Turbo 的 `M_k=FFT(m)` 来自译码器软反馈并在每轮更新。

### 时频、双向与 BLMS 分支

时频 Turbo 融合为：

```math
hat x_TF = 0.5 hat x_T + 0.5 hat x_F.
```

双向分支将时间反向的 LMMSE 支路恢复到原顺序后，与前向时频估计等权融合。BLMS 时频 Turbo 则在每一轮利用软符号更新频响：

```math
H_k^(i+1) = H_k^(i) + mu Xbar_k^* (Y_k - H_k^(i) Xbar_k) /
  (|Xbar_k|^2 + N sigma_w^2).
```

仿真把该更新的 NMSE 与软符号可靠度一同画出，避免只比较最终 BER 而无法检查迭代过程。

## 调用与兼容名称

```matlab
result = simulate_chapter4_iterative_equalization(struct( ...
    "methods", ["TD-Turbo-MAP", "FD-DFE", "FD-Turbo-Log-MAP", ...
        "BiTF-Turbo-Log-MAP", "BLMS-TF-Turbo"], ...
    "decoderMethods", ["MAP", "Log-MAP", "Max-Log-MAP"], ...
    "iterations", 5, ...
    "makePlot", true));
```

旧名称仍可调用：`Time Turbo` 映射到 `TD-Turbo-Log-MAP`，`Frequency DFE` 映射到 `FD-DFE`，`TF Turbo` 映射到 `TF-Turbo-Log-MAP`，`Bidirectional TF` 映射到 `BiTF-Turbo-Log-MAP`，`BLMS TF Turbo` 映射到 `BLMS-TF-Turbo`。

设置 `makePlot=true` 会在 `results/` 下生成：

- `chapter4_iterative_equalization.png`：已选算法 BER、单帧迭代收敛、MAP 系列译码比较和 BLMS 信道更新。
- `chapter4_turbo_soft_information.png`：首轮和末轮的均衡器/译码器 LLR、软反馈可靠度和 LLR 分布。
