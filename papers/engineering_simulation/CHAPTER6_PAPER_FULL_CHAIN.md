# 第六章原文公式全链路仿真

入口为 `simulate_chapter6_formula_complete.m`。默认使用原文第 6.3 节的
核心仿真尺度：500 帧、每用户每帧 40 个 CSK 符号、扩频因子 256、最大
循环移位数 32，以及 3 次 ESE 内迭代和 3 次 CSK 软 MAP 外迭代。

## 公式映射

| 原文公式 | 实现模块 | 作用 |
|---|---|---|
| (6-20)--(6-21) | `time_varying_uwa_channel`、`transmit_frame` | 每用户多径卷积叠加与 AWGN |
| (6-22)--(6-23) | `csk_idma_turbo_detector` | ESE 码片均值和方差 |
| (6-24)--(6-36) | `csk_idma_turbo_detector` | ESE 外信息、交织/解交织与反馈 |
| (6-37)--(6-40) | `ptr_front_end` | 用户特定 PTR 与等效交叉信道 |
| (6-41)--(6-46) | `csk_idma_turbo_detector` | PTR 域 ESE 均值、方差与 LLR |
| (6-51)--(6-64) | `csk_soft_map` | CSK 码字概率、MAP 判决和外信息 |

原文第 6.3 节是以 CSK 软译码器作为 `DEC`，而不是交织重复码。每个信息
符号映射到一个循环移位 CSK 码字；译码器使用全部码片 LLR 计算码字后验，
并从每个码片的码约束中扣除先验 LLR，得到返回 ESE 的外信息。

## 信道与同步

原文仿真采用帧内准静止、帧间独立的随机水声多径。本实现对每一帧、每一
用户生成独立五径复多径，最大时延为 40 个码片；帧内保持不变，下一帧重新
抽取路径时延和增益。

第六章的仿真推导假设用户同步。为形成完整可运行收发链路，额外增加了以下
工程前端，它们不应被误称为第 6 章公式本身：

- Zadoff-Chu 前导的匹配相关帧定时；
- 两个重复 UW 的残余频偏估计与补偿；
- 每用户时分 PN 训练序列；
- LS 或 MMSE 多径信道估计，供 PTR 使用。

同步、频偏和信道估计误差均写入结果结构的 `idma.sync` 与
`idma.diagnostic.sync`，不会被理想信道替代。

## 运行

原文尺度完整仿真：

```matlab
result = simulate_chapter6_formula_complete();
```

该设置包含 500 帧、用户负载和 DSSS/CSK 对照，运行时间较长。开发验证可
显式缩小尺寸，不能将该结果称为原文统计复现：

```matlab
result = simulate_chapter6_formula_complete(struct( ...
    "frameCount", 1, "symbolsPerFrame", 4, ...
    "codeLength", 32, "cskOrder", 8, "idmaUsers", 2, ...
    "runLoadStudy", false, "runComparison", false));
```

默认结果目录为 `papers/chapter6_paper_full_chain/results/`，包含迭代 BER/MSE、
同步与信道诊断、用户负载/体制对照图、MAT 结果包和 UTF-8 CSV 误码率表。
