# 设计说明：原文曲线定量基准 + BLMS 严格 overlap-save

## 一、目标

1. 建立"原文曲线定量基准"框架：数字化参考数据 + log-BER RMSE + 最大 SNR 偏差 +
   排序一致率 + A/B/C 对应等级，作为后续所有公式改动的验收基线。
2. 将 BLMS 从"整块循环 FFT 更新"改为教材图 4-25 的严格分块频域自适应
   （overlap-save 线性卷积语义），并配独立参考测试与负向回归。

## 二、原文曲线定量基准

### 数据来源

- 教材扫描页 `book/*.png`（第 2-6 章 BER 曲线）逐点数字化；
- 现有 `paper_figure_218_reference`（第 2 章图 2-18）纳入同一格式；
- 新数字化数据存放 `papers/curve_reference/*.mat`，字段：
  `chapter / figure / method / snrDb / ber / source(页面) / digitizer / date`。

### 指标

| 指标 | 定义 |
|---|---|
| log-BER RMSE | `sqrt(mean((log10(ber_sim) - log10(ber_ref))^2))`（仅参考点存在的 SNR） |
| 最大 SNR 偏差 | 同方法同 BER 下，仿真曲线相对参考曲线沿 SNR 轴的最大水平距离（插值） |
| 排序一致率 | 同一 SNR 下方法排序（按 BER 升序）与参考一致的占比 |
| 分区误差 | 高/中/低 SNR 三段的 log-BER RMSE 分别报告 |

### 对应等级（验收标准）

- **A**：公式与参数一致，log-BER RMSE ≤ 0.15（同一条件集）
- **B**：核心公式一致，实验条件有替代（信道/编码数据），RMSE ≤ 0.30
- **C**：仅趋势与主要排序一致
- **D**：未实现

### 实现位置

- `papers/modules/+scfde/+equalizers/curve_benchmark.m`（包函数）：
  `benchmark = curve_benchmark(berSim, snrSim, reference, methodNames)`
  返回 `logRmse / maxSnrDeviation / orderAgreement / zoneRmse / grade`。
- `papers/curve_reference/`：数字化数据。
- 测试：`tests/test_curve_benchmark.m` 用构造数据验证指标计算。

## 三、BLMS 严格 overlap-save

### 教材原文（图 4-25，p.96 附近）

```
输入块：  y'_e(k) = [y((k-1)N-N_f+1) ... y((k-1)N)]^T     （重叠 N_f）
FFT：     长度 = N + 2*N_f
时域约束：G = blkdiag(I_{N_f}, 0_N, 0_{N_f})
输出选择：T = [0_{N_f}; I_{N_e}; 0_{N_f}]                  （前 N_f 污染丢弃）
误差：    e(k) = x(k) - x̂(k)             （训练段，kN ≤ L_train）
          e(k) = x̃(k) - x̂(k)             （判决段）
更新：    W(k+1) = W(k) + μ_f·F·G·F^H·R_c*(k) ⊙ E(k)
                          / (ε + R_c^H(k)·R_c(k))
```

### 实现（新包函数）

`papers/modules/+scfde/+equalizers/fblms_equalizer.m`：

```matlab
function [output, weights, trace] = fblms_equalizer(received, ...
    reference, trainLength, filterLength, blockLength, step, ...
    epsilon, useDecisionFeedback)
% FBLMS_EQUALIZER 教材图4-25 频域块自适应均衡（overlap-save）
%   blockLength N, filterLength N_f, FFT 长度 N+2N_f
```

要点：

1. **重叠缓存**：第 k 块输入 = 前一块末 N_f 样本 + 当前块 N 样本 + 后 N_f 样本
   （`y((k-1)N-N_f+1 : (k-1)N+N_f)`），保证 FFT 域乘积 = 线性卷积；
2. **时域约束 G**：频域权值更新后 `ifft` → 仅保留前 N_f 抽头 → `fft` 回频域；
3. **污染丢弃**：输出取块内第 N_f+1..N_f+N_e 样本（前 N_f 个循环污染丢弃）；
4. **误差**：训练段用 `reference`，判决段用硬判决 `x̃`；
5. **NLMS 归一化**：分母 `ε + |R_c|²`（频域逐 bin）；
6. **块间状态**：每块独立 FFT，权值跨块延续；输入缓存跨块延续。

### 与现有实现的关系

- 现有 `ch4_iterate_fd_blms_turbo` 是**Turbo 融合版**（整块循环 FFT 权重更新），
  保留用于 TF-Turbo 链路；
- 新增 `fblms_equalizer` 为独立 BLMS 自适应均衡器（教材图 4-25 语义），
  接入 `run_unified_equalizer`（`fblms-eq` 均衡器 ID）与第 4 章工程仿真；
- FORMULA_TRACEABILITY.md 中 BLMS 等级由 C → B（若曲线基准达标）或保持 C。

### 验收

| 项 | 方法 |
|---|---|
| 无噪声线性卷积一致 | 单位冲激信道下输出与 `conv(h, x)` 有效段逐样本一致（AbsTol 1e-8） |
| 无循环污染 | 块边界样本与线性卷积一致（旧循环块实现在此处失败） |
| 负向回归 | 旧循环块更新（无 G 约束/无重叠）在测试输入上 BER 明显更差或输出不匹配 |
| 曲线基准 | 第 4 章 BLMS 曲线对参考的 RMSE 不劣化 |

## 四、实施顺序

1. `curve_benchmark.m` 包函数 + 测试；
2. `fblms_equalizer.m` 包函数（overlap-save 核心）+ 独立参考测试；
3. 负向回归（旧循环块必败）；
4. 接入统一入口与第 4 章工程仿真；
5. 数字化第 4 章 BLMS 参考曲线（book 图 4-25 附近），计算基准；
6. 全量回归 + 提交。
