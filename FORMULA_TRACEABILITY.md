# 公式追踪矩阵（FORMULA TRACEABILITY）

本文件记录"原文公式 → 代码函数 → 参数映射 → 单元测试 → 仿真图 → 对应等级"的完整证据链。
对应等级：

- **A**：代数等价、参数一致、边界条件一致（有独立参考测试）
- **B**：核心公式一致，但信道/编码数据被替代（如数字化信道、合成信道）
- **C**：工程近似，仅复现趋势（如经验缩放、循环块替代 overlap-save）
- **D**：尚未实现

表中"测试"指向 `papers/tests/` 下的单元测试；"审计状态"指向 README 审计说明中的轮次。

## 第 1 章（绪论）

| 公式/内容 | 说明 |
|---|---|
| — | 纯理论章节（水声信道特性、系统组成），本项目不含第 1 章仿真入口，不适用 |

## 第 2 章（单载波时域均衡）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| 2-47 | 被动时反（单阵元）：`y = h*(-n) ⊛ r` | `+scfde/+equalizers/ptr_dfe.m`、`subband_ptr.m` | `channel.impulse`、`channel.received` | test_audit_round3_fixes（等效信道） | fig2_17 | A | 无 | 第2-4轮 |
| 2-48 | 子阵被动时反：`y_p = Σ_k h_k*(-n) ⊛ r_k` | `subband_ptr.m`、`subband_equivalent_channel.m` | `channel.branches`、`channel.branchImpulses` | test_audit_round3_fixes（逐阵元自相关和误差 0） | fig2_17 | A | 无 | 第2-4轮 |
| 2-18 曲线 | McDFE/PTR-DFE/Sub-PTR-McDFE/BiMcDFE BER | `reproduce_chapter2_sc_tde_paper.m` | 数字化原图参考 `paper_figure_218_reference` | 无独立测试 | fig2_18 | C | Frobenius 相对误差 0.76；低 SNR 中间方法排序有差异 | 第3轮 |
| RLS-DFE | 多通道 RLS 更新 | `mc_rls_dfe.m`、`adaptive_update.m` | λ=0.9995、训练 1500 | test_modular_pipeline | fig2_18 | B | 训练长度 512→1500 方收敛 | 第3轮 |

## 第 3 章（单载波频域均衡与同步）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| 3-8 形式 | UW 相关峰位置差多普勒估计：`a = Δd/(N_b·T_s)` | `cross_peak_tracker.m`（包）、`cross_correlation_tracker.m` | 块内 pre/post 峰间距 | test_audit_round3_fixes（交替多普勒端到端） | fig3_6/3_7/3_8/3_9/3_10 | A | 整数采样量化 1.45e-4（抛物线插值缓解） | 第3-5轮 |
| 3-9..3-15 | 二维 UW 相关搜索（Φ1/Φ2/Φ3、窗长随 Doppler 缩放） | `estimate_fig35_doppler_errors_velocity.m`、`two_d_tracker.m` | λ=4、固定先验范围 | test_audit_round3_fixes（块跟踪） | fig3_5..3_10 | A | 无（真值仅用于生成信号） | 第2-5轮 |
| 图3.6 | 单帧 5 块时变跟踪 | `tracking_frame.m`（包）、`simulate_tracking_frame.m` | 每块独立 [UW;UW;data;UW] + 连续载波相位 | testCrossTrackerInBlockAlgebra、testCarrierPhaseBoundaryAdvance | fig3_6 | A | 块5 尾部抛物线偏差 1.5e-4 | 第4-5轮 |
| MMSE-FDE | `W = H*/(\|H\|²+σ²)` | `ch3_mmse_frequency_equalize.m`、`normalized_mmse_equalizer` | σ²=10^(-SNR/10) | 无独立测试 | fig3_x | A | 无 | — |
| HTFDE | 混合时频判决反馈 | `htfde.m`、`ch3_htfde_equalize.m` | 可靠度缩放为工程设置 | 无 | fig3_x | C | 可靠度变量来源/融合公式未按原文逐式 | 待办 P1 |
| Doppler 补偿链路 | 同帧估计+逆伸缩+相位补偿 | `simulate_coded_sync_ber.m`、`estimate_frame_doppler.m`、`estimate_frame_cross.m` | 帧 [UW;UW;data;UW;...] | 无独立测试 | fig3_10 | A | 无 | 第3-4轮 |

## 第 4 章（单载波迭代均衡）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| 4-10..4-18 | MMSE-FD-DFE：`F_k = 1+Σf_m e^{-j2πkm/N}`、`(V-I)f=-v`、`W_k = F_k·H*/(\|H\|²+σ²)`、时域判决反馈 | `fd_dfe_design.m`（包）、`fdfe_symbols.m` | 循环 Toeplitz V、q=ifft(γ) | testFdDfeFeedforwardDependsOnFeedbackLength（独立显式参考 1e-10、g=f 自洽 1e-17） | fig4_2/4_5 | A | 硬判决误差传播（genie 反馈单调改善） | 第3-5轮 |
| 4-56..4-58 | FDE-FDFE 迭代系数（ρ、λ） | `simulate_coded_equalizers` 内 IBDFE 循环 | ρ∈[0.45,0.97] | 无独立测试 | fig4_7/4_8 | B | 迭代改善不稳定 | 待复核 |
| BCJR MAP/Log-MAP | 前向后向算法 | `ch4_bcjr_log_domain.m`、`ch4_bcjr_probability.m` | — | 已验证两者数值差 6.66e-16 | fig4_x | A | 无 | 第1轮 |
| 图4-24/4-25 | 频域块自适应均衡（严格 overlap-save）：重叠缓存、G 时域约束、前 Nf 污染丢弃、频域 NLMS | `fblms_equalizer.m` + 模块 `fblms.m`（注册表 `fblms` ID） | N/Nf/μ/ε 参数化（cfg.fblms*） | test_fblms_and_curve_benchmark（无噪声收敛、边界无污染、旧循环块必败、块数修正、逐样本训练、QPSK 判决） | 统一入口 qpsk 场景（fblms ID） | B（结构一致，步长量级未定） | 已按图4-24 前/中/后 N+2Nf 结构 + 整块能量标量分母重写；无噪声充足训练下收敛（mse→0）；但统一入口 QPSK 场景短训练段（64 符号）下标量分母收敛不足（原文 L_train 需较长）；图4-31 FDDA-TEQ 家族参考已数字化，曲线对比待 fdda_teq 集成 | 本轮 |
| IBDFE 权重 | `B_k = (λ(σ²+\|H\|²)-σ²)/(σ²+\|H\|²-ρ\|H\|²)` | `simulate_coded_equalizers` | mean(B)≈0 | 已验证 | fig4_7 | A | 无 | 第1轮 |

## 第 5 章（互补码键控扩频）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| CCK 码本 | 8/16/32 码片 256 唯一字 | `ch5_cck_codebook.m` | 单位能量误差 ≤1.11e-16 | test_audit_round3_fixes（码字恢复/bit 表） | fig5_x | A | 无 | 第1-3轮 |
| CCK Turbo 外码 | 完整卷积/LDPC 外码 + 交织 + SISO 译码 | `ch5_turbo_cck_frame.m` | 目前用重复码替代 | 无 | fig5_x | C | 外码被重复码替代，非原文完整 Turbo | 待办 P1 |
| 5.5 节信道 | 11 径信道 | `ch5_long_uwa_channel.m` | 合成信道 | 无 | fig5_xx | C | 非原文精确信道，未保存逐径参数 | 待办 P1 |

## 第 6 章（循环移位扩频）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| CSK 码本 | M 元循环移位 + bit table | `ch6_csk_codebook.m`、`ch6_bit_table.m` | M=4 | test_audit_round3_fixes（bit 级 BER） | fig6_x | A | 无 | 第3轮 |
| PIC/SIC/ESE | 软干扰消除迭代 | `csk_ese.m`、`csk_soft_sic.m`、`ch6_ese_residual.m` | 阻尼系数为工程设置 | 无 | fig6_x | C | 阻尼系数非原文规定 | 待办 P1 |
| CSK-IDMA | 多用户迭代检测 | `ch6_csk_idma_detect.m` | — | 无 | fig6_x | B | 待复核 | — |

## 统一入口与指标

| 内容 | 代码 | 测试 | 状态 |
|---|---|---|---|
| CCK/CSK bit 级 BER（bit table 映射） | `run_unified_equalizer.m`（run_cck/csk_scenario） | test_audit_round3_fixes | A |
| 严格 MMSE 正则（无经验系数） | `known_dfe_core.m`、`receiver_bank_tde.m` | test_modular_pipeline | A |
| 解析残余方差（热噪声+残余 ISI） | `equalized_noise_variance` | 无独立测试 | A |
| 实验注册表 11 项 | `list_simulations.m`、`run_all_simulations.m` | 无独立测试 | A |

## 仿真曲线定量基准框架

| 工具 | 说明 | 测试 |
|---|---|---|
| `curve_benchmark.m` | log-BER RMSE、分区 RMSE、最大 SNR 偏差、排序一致率、A/B/C/D 分级 | testCurveBenchmarkMetrics |

分级标准：A：log-BER RMSE ≤ 0.15；B：≤ 0.30；C：仅趋势与排序一致；D：未实现。
已建参考数据：curve_reference/ch4_fig431_fdda_teq.mat（图4-31 FDDA-TEQ 未编码 BER，16 点，SNR -5~10 dB）。
注：dda_teq 为第4章专用模块（卷积码 (7,5) 码率 1/2 + 交织 + BCJR），与统一入口 QPSK 场景的未编码帧结构不兼容（info 长度不匹配）；图4-31 曲线对比待专用编码帧集成后计算。

## 已知缺口（对应 README 审计说明）

1. **HTFDE 可靠度缩放**（第3章）：工程设置，未按原文逐式（待办 P1）
2. **BLMS overlap-save**（第4章）：已新增严格 overlap-save 的 `fblms_equalizer`（图4-25 语义，含重叠缓存/G 约束/污染丢弃/负向回归），现有 Turbo 融合版保留；原文步长量级与图 4-25 曲线数字化待办
3. **CCK Turbo 外码**（第5章）：重复码替代完整外码；若无原文公开矩阵，应标 B/C（待办 P1）
4. **PIC/ESE 阻尼系数**（第6章）：工程设置，需敏感性分析（待办 P1）
5. **5.5 章 11 径信道**（第5章）：合成信道，需保存逐径参数与敏感性分析（待办 P1）
6. **BER 置信区间与结果元数据**：当前仅点值（待办 P1）
