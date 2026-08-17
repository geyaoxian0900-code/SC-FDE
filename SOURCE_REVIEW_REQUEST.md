# SOURCE_REVIEW_REQUEST — 需人工扫描复核项目

> 本文件列出**尚未由人工确认**、因此不能标 `BOOK-EXACT` 的公式与参数。
> 每项都标明了来源图片、待确认内容和当前状态。
> 人工复核完成前，对应状态必须保持 `BLOCKED-SOURCE-REVIEW` /
> `PARAM-UNRECOVERABLE`，不得凭当前代码输出反推原文。
>
> **2026-08-17 更新**：新获取高分辨率扫描页（`book/P60/P67/P68/P90/P133~P140.png`）
> 与参考文献（in-band pilots OFDM 信道估计 PDF）已入库，多项此前阻断的公式现已转写
> （见 `STRICT_FORMULA_SPEC.md`「恢复公式」节）；实现进度见 `FORMULA_TRACEABILITY.md`
> 与实施计划 `docs/superpowers/plans/2026-08-17-new-scans-strict-formula-upgrade.md`。

## 1. `book/P90.png` — FD-DFE 式 (4-57)/(4-58)（已转写，实现已验证）

- **待确认（原 book/21.png 版）**：反馈系数 `b_k^{(i)}` 与相关系数 `ρ^{(i)}` 的**精确
  分子、分母**及归一化量；零均值约束 (4-52) 之外的完整表达式。
- **2026-08-17 状态**：`book/P90.png` 已提供 (4-56)~(4-63) 转写，其中
  `(4-57) b_k=[λ(σ²+|h_k|²)−σ²]/[(σ²+|h_k|²)−ρ|h_k|²]`、
  `(4-58) λ=σ²Σ(1/d_k)/Σ((σ²+|h_k|²)/d_k)`；零和约束由 (4-58) 公式自身导出
  （不得用 `B−mean(B)` 投影）。Task 5 已实现并 oracle 验证；Task 9 认证更新：
  `fd-dfe` 升 **BOOK-EXACT**（注册 wrapper 用严格迭代核心）、`fd-turbo` 升
  **ALG-EQUIV**（系数已锁定；训练段 μ̂/σ̂² 估计器为工程放置，故不升 BOOK-EXACT）。
- **当前实现**：`ch4_fd_dfe_weights.m`/`ch4_iterate_fd_dfe.m`/`ch4_iterate_frequency_turbo.m`
  （Task 5 迁移，逐迭代 trace rho/lambda/W/B，sourcePages/sourceEquations 已记录）。

## 2. `book/P133.png`~`P137.png` — CCK-BiDFE / BiDFE2 初始化与执行次序（信号流已转写，实现已验证）

- **待确认（原 book/31.png、book/32.png 版）**：BiDFE-1 / BiDFE-2 的**初始化次序**、
  前向/反向支路的执行顺序、首块/尾块状态处理；式 (5-48)~(5-56) 的逐符号转录。
- **2026-08-17 状态**：`book/P133.png`~`P137.png` 提供 (5-41)~(5-59) 信号流级转写
  （CMF/复合冲激、块时反 (5-48)、反向 DFE (5-49)、BiDFE-1 系数 (5-50)/(5-51)、
  BiDFE-2 第二输出 (5-52)、双滤波方向 (5-53)/(5-54)、(5-57) 等权合并、(5-59) 迭代
  临时判决）。Task 6 已实现（`ch5_bidfe1_detect`/`ch5_bidfe2_detect`）并 oracle
  验证；Task 9 认证更新：`cck-bidfe`、`cck-bidfe2` 升 **ALG-EQUIV**——信号流已
  oracle 锁定（`test_new_scan_ch5_eq_5_41_69.m`），但 (5-48)~(5-56) 的逐式
  （per-symbol）转录仍待人工双人复核，故不升 BOOK-EXACT。
- **允许的中间认证**：前向/反向 DFE 子模块、等权合并层已单独 oracle 认证
  （`test_cck_tr_diversity_eq_5_57.m`、`test_ch5_cck_eq_5_11_80.m`）；TR-diversity
  分支已重挂为 BiDFE-2 内核（Task 6）。

## 3. `book/P67.png` — IBDFE 式 (3-86) `A_k`/Λ 完整表达式（已转写，实现待验证）

- **待确认（原 book/17.png 版）**：`A_k` 的完整表达式（含可靠度量与噪声项、`Σ^{-1}` 项）。
- **2026-08-17 状态**：`book/P67.png` 提供
  `(3-86) Λ_k^l=(H_k^(l-1))^H Σ^(l-1)/(‖H_k^(l-1)‖²Σ^(l-1)+Nσ_w²)` 与
  `(3-87) Γ=(1/N)Σ_k Λ_k^l H_k^(l-1)`（分母含 `N·σ_w²`，旧生产缺失该因子）。
  实现见 Task 2；实现并验证前 `sd-ibdfe` / `hd-ibdfe` 保持 BLOCKED-SOURCE-REVIEW。
- **当前实现**：`ch3_ibdfe_equalize.m`（H* 形 A_k，Task 2 迁移到
  `ch3_ibdfe_coefficients.m`）。

## 4. `book/P68.png` — 式 (3-92) 融合顺序（已确认）与两个方差的估计公式（仍阻断）

- **2026-08-17 已确认**：`book/P68.png` 转写为
  `H^l=(H^0 σ_0² + H_DFT^l σ_DFT²)/(σ_0²+σ_DFT²)`——**各自方差配各自估计**
  （取代此前 book/17.png 的交叉顺序读数，Task 3 修正生产）；`H_LS=R/X_D^0` 亦已确认。
- **仍待确认**：`σ_DFT²` 与 `σ_0²` 的**完整估计公式**。参考文献
  （in-band pilots OFDM 信道估计）提供 LS/MMSE/Wiener 估计器，但**未定义本式
  的两个标量方差估计器**。
- **影响**：`ice-sd-ibdfe` / `ice-hd-ibdfe` 在获得确切方差估计器（或来源数据显式
  方差）前保持 **BLOCKED-SOURCE-REVIEW**，不得虚假升级；残差能量方差仅可保留为
  显式 ENGINEERING 模式（`iceSigma0Squared`/`iceSigmaDftSquared` 严格显式模式，
  缺失抛 `SCFDE:BookParameterUnavailable`）。

## 5. `book/P60.png` — HTFDE 式 (3-61) λ 方向（已解决）

- **2026-08-17 已确认**：`book/P60.png` 转写为 `C_k≈(|λ|²H_k^H H_k+σ²I)^{-1}(λ H_k^H)`——
  标量分子为 `λ·H_k^H`（**λ 不取共轭**）。取代此前 SOURCE-INCONSISTENT 的“λ* 分子”
  分辨率（Task 4 用复数 λ 测试区分 `λ` 与 `conj(λ)` 后修正生产并移除
  SOURCE-INCONSISTENT 标注）。
- **剩余约束**：`htfde` 的实验参数（P/K、DPLL 增益、μ）PARAM-UNRECOVERABLE，
  `bookExperimentEquivalent=false` 保持。

## 6. 原文未公开参数（PARAM-UNRECOVERABLE）

| 项目 | 未公开内容 | 影响 |
| --- | --- | --- |
| HTFDE | N/M/P/K 数值、DPLL 增益、步长 μ | `htfde` 公式矩阵式实现已验证；实验复现不可认证 |
| FDDA | γ_f、γ_b 数值；实验信道；重叠窗口输出拼接规则 | `fdda-teq` 公式结构 BOOK-EXACT；`bookExperimentEquivalent=false` |
| 第 5 章 3 km 信道 | 逐径 taps | `ch5_long_uwa_channel` 为合成信道，非原 taps |
| CCK Turbo 外码 | 生成多项式、交织器、终止、码率 | 生产用重复码替代，标 ENGINEERING；(5-60)~(5-69) 仅锁检测器/LLR 层 |
| 第 3/4 章实验 | 帧长、迭代数、SNR 网格等实验配置 | 曲线复现标 TREND-ONLY / PARAM-UNRECOVERABLE |
| (3-92) 方差估计器 | `σ_DFT²`、`σ_0²` 具体估计公式 | ICE 两 ID 保持 BLOCKED-SOURCE-REVIEW（见第 4 项） |

## 复核完成后的动作

1. 更新 `FORMULA_TRACEABILITY.md` 对应行的 FormulaStatus；
2. 更新对应生产模块的 `trace.formulaStatus/formulaNote`；
3. 仅当全部扫描约束解除后才可将相关 ID 标 `BOOK-EXACT` 并宣称
   "原文公式结构严格实现"；实验参数恢复与曲线复现仍须另行评级。
