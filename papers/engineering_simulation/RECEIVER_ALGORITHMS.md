# Chapter 2/3 接收机算法与公式

本说明对应可执行入口：

- `simulate_chapter2_single_carrier_tde.m`：单载波时域均衡（SC-TDE）。
- `simulate_chapter3_scfde.m`：单载波频域均衡（SC-FDE）及同步、信道估计。

所有曲线和选择器均在仿真入口中生效；未选择的方法不会进入 `methodNames`、`names`、图例和结果矩阵。

## Chapter 2: SC-TDE

对于第 `k` 个 BPSK 符号，判决反馈均衡器的输入向量定义为

```math
\mathbf{u}_k = [r_{k+D},\ldots,r_{k+D-N_f+1},
 -\hat d_{k-1},\ldots,-\hat d_{k-N_b}]^T,
\quad z_k=\mathbf{w}_k^H\mathbf{u}_k,
\quad e_k=d_k-z_k.
```

其中 `D` 是判决延迟，`N_f` 和 `N_b` 分别为前馈和反馈抽头数；训练段采用已知 `d_k`，数据段采用硬判决 `hat d_k=sign(real(z_k))`。

| 稳定 ID | 方法 | 系数更新或核心操作 |
|---|---|---|
| `dfe` | 已知信道常规 DFE | 由卷积信道矩阵的正则化最小二乘解初始化前馈滤波器。 |
| `lms-dfe` | LMS 自适应 DFE | `w_(k+1)=w_k+mu u_k e_k^*`。 |
| `nlms-dfe` | NLMS 自适应 DFE | `w_(k+1)=w_k+mu u_k e_k^*/(u_k^H u_k+epsilon)`。 |
| `rls-dfe` | RLS 自适应 DFE | 见下方 RLS 递推。 |
| `dpll-dfe` | DPLL-DFE | 在 NLMS-DFE 前馈支路上进行二阶数字锁相。 |
| `mc-lms-dfe` | 常规多通道 LMS DFE | 将所有阵元前馈向量与共同反馈向量堆叠后使用 LMS。 |
| `mc-nlms-dfe` | 常规多通道 NLMS DFE | 将所有阵元前馈向量与共同反馈向量堆叠后使用 NLMS。 |
| `mc-rls-dfe` | 常规多通道 RLS DFE | 将所有阵元前馈向量与共同反馈向量堆叠后使用 RLS。 |
| `ptr-dfe` | 被动时反转 DFE | 先经时反转滤波，再使用已知等效信道的 DFE。 |
| `subband-ptr-dfe` | 子带被动时反转 DFE | 在每个频带执行 `Y(f)H*(f)/(|H(f)|^2+delta)`，再送入 DFE。 |

RLS 使用遗忘因子 `lambda` 和逆相关矩阵 `P_k`：

```math
\mathbf{k}_k=\frac{\mathbf{P}_{k-1}\mathbf{u}_k}
 {\lambda+\mathbf{u}_k^H\mathbf{P}_{k-1}\mathbf{u}_k},
\quad \mathbf{w}_k=\mathbf{w}_{k-1}+\mathbf{k}_k e_k^*,
\quad \mathbf{P}_k=\frac{\mathbf{P}_{k-1}-\mathbf{k}_k\mathbf{u}_k^H\mathbf{P}_{k-1}}{\lambda}.
```

DPLL-DFE 的相位鉴别器和二阶环路为

```math
e_{phi,k}=angle(hat d_k z_k^*),
\quad omega_(k+1)=omega_k+K_i e_{phi,k},
\quad theta_(k+1)=theta_k+omega_(k+1)+K_p e_{phi,k}.
```

前馈接收样本使用 `exp(-j theta_k)` 旋转后进入 DFE；`phase` 与 `frequency` 轨迹保存在 `equalizerTraces` 中。为兼容早期脚本，`pll-dfe` 自动映射为 `dpll-dfe`，`mcdfe` 自动映射为 `mc-nlms-dfe`。

示例：

```matlab
tde = simulate_chapter2_single_carrier_tde(struct( ...
    "methods", ["lms-dfe", "rls-dfe", "dpll-dfe", "mc-rls-dfe"], ...
    "makePlot", true));
```

## Chapter 3: SC-FDE 同步、信道估计与均衡

接收信号的离散等效模型为

```math
r[n]=exp(j(phi_0+2pi Delta f n/F_s)) (h circleast x)[n]+w[n].
```

`Residual-Doppler-PN` 使用重复 PN 块。令第 `q` 个 PN 块为 `y_q[n]`，其与首块的相关量为

```math
C_q=sum_n y_q[n]y_0^*[n],
\qquad \hat{Delta f}=F_s/(2pi) times slope(angle(C_q),qL_p).
```

补偿后为 `r_c[n]=r[n]exp(-j2pi hat(Delta f)n/F_s)`。`Initial-Phase-PN` 对补偿后的训练块做 LS 估计，取截断冲激响应首径的相位：

```math
hat phi_0=angle(hat h_LS[0]),
\qquad r_p[n]=r_c[n]exp(-j hat phi_0).
```

该初相估计以仿真中的直达径 `h[0]` 为零相位参考。若信道整体相位未知，则 `phi_0` 与信道整体相位不可单独辨识，必须引入该参考、额外导频或外部同步信息。

在补偿后的训练块频域中，令 `Y_p[k]` 和 `X_p[k]` 分别为接收和已知训练谱，则两种可选信道估计器为：

```math
hat H_LS[k]=Y_p[k]X_p^*[k]/(|X_p[k]|^2+epsilon),
```

```math
hat H_MMSE[k]=sigma_H^2 X_p^*[k]Y_p[k]/
 (sigma_H^2|X_p[k]|^2+N sigma_w^2).
```

两者均在时域截断到 `channelEstimateLength` 后再变换回频域。`sigma_H^2` 默认由截断 LS 估计的频域平均能量给出，也可由 `channelPriorVariance` 显式指定。

| 选择器 | 可选值 | 用途 |
|---|---|---|
| `methods` | `ZF-SC-FDE`, `MMSE-SC-FDE`, `HTFDE`, `SD-IBDFE`, `HD-IBDFE`, `ICE-SD-IBDFE`, `ICE-HD-IBDFE` | 选择频域均衡器。 |
| `guardMethods` | `CP-SC`, `ZP-SC`, `UW-SC` | 选择保护间隔结构比较。 |
| `estimationMethods` | `Residual-Doppler-PN`, `Initial-Phase-PN`, `LS-CE`, `MMSE-CE` | 选择需要展示的同步/信道估计结果。 |
| `channelEstimator` | `LS-CE`, `MMSE-CE` | 选择实际送入均衡器的初始信道响应。 |

SC-FDE 的频域均衡器仍可独立选择。基本 MMSE 系数为

```math
hat X[k]=Y[k]H^*[k]/(|H[k]|^2+sigma_w^2).
```

示例：

```matlab
fde = simulate_chapter3_scfde(struct( ...
    "methods", ["MMSE-SC-FDE", "ICE-SD-IBDFE"], ...
    "estimationMethods", "all", ...
    "channelEstimator", "MMSE-CE", ...
    "makePlot", true));
disp(fde.estimationMse)
```

设置 `makePlot=true` 后，原有均衡器图之外还会生成 `results/chapter3_scfde_estimation.png`，其中文面板依次呈现残余多普勒 MSE、初始相位 MSE、LS-CE NMSE 和 MMSE-CE NMSE。
