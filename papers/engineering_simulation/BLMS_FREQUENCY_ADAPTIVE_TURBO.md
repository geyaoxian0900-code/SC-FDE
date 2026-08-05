# 第 4.5 节：基于 BLMS 的频域自适应 Turbo 均衡

本说明对应论文第 4.5 节“基于 BLMS 的频域自适应 Turbo 均衡”。实现位于
`papers/modules/+scfde/run_chapter4_turbo_suite.m`，通过原有入口
`simulate_chapter4_iterative_equalization` 调用。

## 与既有 BLMS 分支的区别

此前的 `BLMS-TF-Turbo` 是“时频 Turbo 均衡后，用 BLMS 更新信道频响”的分支。第 4.5 节新增的三条链路更新的是**均衡器前馈系数**，不是信道响应：

| 方法 ID | 原文比较角色 | 自适应对象 |
|---|---|---|
| `TDDA-TEQ` | 时域直接自适应 Turbo 均衡基线 | 时域 NLMS 前馈抽头。 |
| `FDDA-TEQ` | 频域直接自适应 Turbo 均衡 | 频域 BLMS/NLMS 前馈系数 `W_k`。 |
| `FDDA-DFE-TEQ` | 频域自适应判决反馈 Turbo 均衡 | `W_k` 与频域反馈项 `B_k`。 |

## 块频域模型

原文用重叠保存和选择矩阵保留线性卷积的有效样本。当前工程的 SC-FDE 测试帧已采用循环块模型，因此以一个 `N` 点循环块作为等效表示：

```math
Y_k = FFT(y_k),
\qquad Xbar_k = FFT(m_k),
\qquad m_k = tanh(L_{D,k}/2).
```

`m_k` 为译码器在第 `k` 次 Turbo 迭代后的软符号，`L_D` 是编码位后验 LLR。若替换为原文的线性卷积数据，只需在 FFT/IFFT 前后加入重叠保存的输入块重排和有效样本选择矩阵；BLMS 更新式及 Turbo 接口保持不变。

## 直接频域自适应 Turbo 均衡

频域直接自适应分支的输出为：

```math
Xhat_k = IFFT(W_k odot Y),
\qquad L_{E,k}=2 Re{Xhat_k}/sigma_w^2.
```

经过交织/去交织和 Log-MAP SISO 译码后，得到软目标 `m_k`。令：

```math
e_k = m_k - xhat_k,
\qquad E_k = FFT(e_k),
```

则本工程使用的泄漏归一化块 LMS 更新为：

```math
W_(k+1) = (1-gamma) W_k + mu Y^* odot E_k /
  (|Y|^2 + delta).
```

其中 `mu=blmsStep`，`gamma=blmsLeakage`，`delta=blmsRegularization`。这是原文式 (4-70)--(4-73) 在循环块频域模型下的逐频点等效写法：FFT 将卷积矩阵对角化，`Y^* odot E` 即块梯度项。

## 频域自适应 DFE-Turbo

判决反馈分支在频域同时使用前馈和软反馈：

```math
B_k = W_k odot Hhat - 1,
\qquad Xhat_k = IFFT(W_k odot Y - B_k odot Xbar_k).
```

其中 `Hhat` 为初始训练/先验得到的频响。`B_k` 抵消由上一轮软符号产生的后游标 ISI；其余 Turbo 译码、软符号反馈及 BLMS 梯度更新与 `FDDA-TEQ` 相同。该结构对应原文图 4-25 至图 4-27 的频域自适应 Turbo/DFE-Turbo 支路。

## 时域自适应对照

`TDDA-TEQ` 用于验证频域块更新的收益。对第 `n` 个时域样本，输入向量为 `u_n`、软目标为 `m_n`：

```math
xhat_n = w_n^H u_n,
\qquad e_n=m_n-xhat_n,
\qquad w_(n+1)=w_n+mu_T u_n e_n^*/(u_n^H u_n+delta).
```

`tdNlmsStep` 和 `tdAdaptiveTaps` 分别控制时域 NLMS 步长与抽头数。

## 调用与图形

```matlab
result = simulate_chapter4_iterative_equalization(struct( ...
    "methods", ["TDDA-TEQ", "FDDA-TEQ", "FDDA-DFE-TEQ"], ...
    "iterations", 5, ...
    "blmsStep", 0.06, ...
    "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, ...
    "makePlot", true));
```

生成的 `results/chapter4_blms_frequency_adaptive_turbo.png` 包括：

1. 三种自适应 Turbo 均衡器的 BER-SNR 对比。
2. 单帧 Turbo 迭代收敛曲线。
3. 最终频域前馈系数幅度。
4. 判决导向块均方残差。

选择其他 `methods` 时不会绘制这张专项图；三种 BLMS 自适应方法可与 `TD-Turbo-*`、`FD-Turbo-*`、`TF-Turbo-*` 和 `BLMS-TF-Turbo` 在同一 BER 图中联合比较。
