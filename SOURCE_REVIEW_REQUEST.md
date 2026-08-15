# SOURCE_REVIEW_REQUEST — 需人工扫描复核项目

> 本文件列出**尚未由人工确认**、因此不能标 `BOOK-EXACT` 的公式与参数。
> 每项都标明了来源图片、待确认内容和当前状态。
> 人工复核完成前，对应状态必须保持 `BLOCKED-SOURCE-REVIEW` /
> `PARAM-UNRECOVERABLE`，不得凭当前代码输出反推原文。

## 1. `book/21.png` — FD-DFE 式 (4-57)/(4-58)

- **待确认**：反馈系数 `b_k^{(i)}` 与相关系数 `ρ^{(i)}` 的**精确分子、分母**
  及归一化量；零均值约束 (4-52) 之外的完整表达式。
- **影响**：`fd-dfe`（注册 ID）当前标 **ALG-EQUIV**；`fd-turbo` 标
  **BOOK-EXACT-STRUCTURE**（系数形式待复核）。
- **当前实现**：`ch4_fd_ibdfe_weights.m`（现有构造 + 显式零均值约束）。

## 2. `book/31.png`、`book/32.png` — CCK-BiDFE / BiDFE2 初始化与执行次序

- **待确认**：BiDFE-1 / BiDFE-2 的**初始化次序**、前向/反向支路的执行顺序、
  首块/尾块状态处理；式 (5-48)~(5-56) 的逐符号转录。
- **影响**：`cck-bidfe`、`cck-bidfe2` 当前标 **BLOCKED-SOURCE-REVIEW**，
  现有执行次序为显式 **ENGINEERING** 选择。
- **允许的中间认证**：前向/反向 DFE 子模块、等权合并层已单独 oracle 认证
  （`test_cck_tr_diversity_eq_5_57.m`、`test_ch5_cck_eq_5_11_80.m`）。

## 3. 第 3 章式 (3-86) — IBDFE `A_k` 完整表达式

- **待确认**：`A_k` 的完整表达式（含可靠度量与噪声项、`Σ^{-1}` 项）。
- **影响**：`sd-ibdfe` / `hd-ibdfe` 的 C/A/Γ/B 结构与 unit-gain 已
  BOOK-EXACT；`A_k` 具体形式仍受 (3-86) 复核限制。
- **当前实现**：`ch3_ibdfe_equalize.m` 采用 H* 形 A_k 并记录。

## 4. `book/17.png` — 式 (3-92) 两个方差的估计公式

- **已确认（无需再核）**：`H_LS = R / X_D^0`（复数安全除法已实现）；
  (3-92) 的**权重排列** `(σ_DFT²·H_old + σ_old²·H_DFT)/(σ_old²+σ_DFT²)`。
- **待确认**：`σ_DFT²` 与 `σ_old²` 的**完整估计公式**（当前为残差能量
  `mean|H_LS−H_DFT|²`、`mean|H_old−H_LS|²`，属 ENGINEERING 估计）。
- **影响**：`ice-sd-ibdfe` / `ice-hd-ibdfe` 的 (3-92) 标 **ENGINEERING-BLOCKED**。

## 5. 原文未公开参数（PARAM-UNRECOVERABLE）

| 项目 | 未公开内容 | 影响 |
| --- | --- | --- |
| HTFDE | N/M/P/K 数值、DPLL 增益、步长 μ | `htfde` 公式核心已验证；BOOK 模式缺 P/K 抛 `SCFDE:BookParameterUnavailable`；实验复现不可认证 |
| FDDA | γ_f、γ_b 数值；实验信道；重叠窗口输出拼接规则 | `fdda-teq` 公式结构 BOOK-EXACT；`bookExperimentEquivalent=false` |
| 第 5 章 3 km 信道 | 逐径 taps | `ch5_long_uwa_channel` 为合成信道，非原 taps |
| CCK Turbo 外码 | 生成多项式、交织器 | 生产用重复码替代，标 ENGINEERING |
| 第 3/4 章实验 | 帧长、迭代数、SNR 网格等实验配置 | 曲线复现标 TREND-ONLY / PARAM-UNRECOVERABLE |

## 复核完成后的动作

1. 更新 `FORMULA_TRACEABILITY.md` 对应行的 FormulaStatus；
2. 更新对应生产模块的 `trace.formulaStatus/formulaNote`；
3. 仅当全部扫描约束解除后才可将相关 ID 标 `BOOK-EXACT` 并宣称
   "原文公式结构严格实现"；实验参数恢复与曲线复现仍须另行评级。
