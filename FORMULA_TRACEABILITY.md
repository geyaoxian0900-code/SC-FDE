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
| 5-60~5-69 | MAP-CCK-TE LLR：后验 = 外信息 + 先验，log-sum-exp 计算 | `ch5_soft_book_detect_with_prior.m`（后验 LLR）+ `ch5_fde_cck_turbo_detect.m`（外信息交换） | 先验 LLR、噪声方差 | 无独立测试 | fig5_x | B | 后验 LLR 结构与原文一致 | 本轮 |
| CCK Turbo 外码 | 原文明确为 Turbo 码（未给生成多项式/校验矩阵/码率/交织器） | `ch5_turbo_cck_frame.m` | 目前重复码率 1/2 + 交织 | 无 | fig5_x | C | 原文未公开外码参数；保留重复码不猜测（按审计规则） | 本轮 |
| 5.5 节信道 | 11 径信道 | `ch5_long_uwa_channel.m` | 合成信道 | 无 | fig5_xx | C | 非原文精确信道，未保存逐径参数 | 待办 P1 |

## 第 6 章（循环移位扩频）

| 公式编号 | 原文定义 | 代码函数 | 参数映射 | 测试 | 仿真图 | 等级 | 已知偏差 | 审计状态 |
|---|---|---|---|---|---|---|---|---|
| CSK 码本 | M 元循环移位 + bit table | `ch6_csk_codebook.m`、`ch6_bit_table.m` | M=4 | test_audit_round3_fixes（bit 级 BER） | fig6_x | A | 无 | 第3轮 |
| PIC/SIC/ESE | 软干扰消除迭代 | `ch6_csk_idma_detect.m`（L38 后验相信阻尼融合）、`csk_ese.m`、`csk_soft_sic.m` | 阻尼可配置（eseDamping，默认 0.58） | 敏感性已完成：0→发散，0.3→0.014，0.58→0.009-0.014，0.8-1.0→0.0078（最优） | fig6_x | C | 原文未规定阻尼；已参数化+敏感性分析，标为工程参数 | 本轮 |
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
注： fdda-teq 为原文图4-25 真自适应 Turbo 均衡器（ fdda_teq_true.m + 共享核心 ch4_fdda_teq_core.m）：
- 式(4-75) 反馈块窗口：Xtilde0(k)=[前部判决; 0_N; 后部判决]，中间当前块 N 个位置严格为零（反馈只消除相邻块间干扰）；训练段用已知训练符号构窗口，数据段 outer=1 无先验反馈全零，outer>1 用上一轮判决/软符号构窗口（ch4_fdda_feedback_block，三项独立测试）；
- 式(4-82) 完整执行：外迭代内 **每个数据块都更新 W 和 B**（训练模式用已知训练符号、决策引导模式用判决/软符号误差），带指数遗忘因子 gamma_f^i/gamma_b^i（i=外迭代编号，同一外迭代内所有块缩放相同；默认 gamma_f=gamma_b=0.97，为参数假设已记录）；式(4-81) 外迭代继承 W/B；
- 参数与原文一致：mu_f=0.2、mu_b=0.01、Nc=32、Nf=32、Nb=10、I_inner=1、I_outer=3（无 80-epochs 训练放大）；
- 分母默认为原文式(4-82) 标量 delta+R^H R（denomMode='equation'，生产包装器与核心默认一致，包装器级回归测试确认）；'block'/'bin'为工程变体；单块数值等价测试证实 W/B 与手动式(4-82) 完全一致；
- 反馈/误差参考默认为原文决策引导模式（ fddaSoftFeedback='decision'），软符号同时进反馈谱 Xtilde 与误差 E(k)；bcjr/equalized 为工程扩展分别记录；BCJR 软译码用于最终输出（原文“最后内迭代输出送调解调器软译码”）；
- 诊断轨迹对同一真值：iterationMse/决策 BER 均以发送数据符号为参考，外迭代不发散；轨迹为 outerIterations x numBlocks 矩阵（stepScale/W/B 逐块记录）；
- 遗忘因子 gamma=0.97 为工程参数（原文仅给 gamma<1）；
- 图4-31 工程趋势基准（ch4_fdda_teq_uncoded_qpsk.m 调用与生产共享的核心，同样 equation 分母）：uncoded QPSK、I_outer=3、256+1024、Eb/N0，100 帧/SNR=204800 bit，零误码 0 个，Clopper-Pearson 95% 上界审删；logRmse=2.30、maxSnrDev=4.74dB、等级 C；绝对偏移与高 SNR 平台为原文标量分母下小步长的数学后果加合成 3 仲信道（原文 3km 参数未披露），趋势/排序一致。

## 37 均衡器运行契约审计（2026-08-10）

- 37/37 注册衡器 ID → 模块映射；模块组：QPSK 17、Turbo 10、CCK 7、CSK 3；
un_all_equalizers.m 独立运行 37 个 ID，37/37 PASS（单次运行，1 帧/ID）。
- 第 4 章帧契约：[256 已知训练; 1024 交织编码数据]（ch4_turbo_frame_contract）；BCJR 仅处理 1024 编码数据，返回恰 512 信息位（ch4_decoder_feedback_frame）；训练符号不进 BCJR。
- 交织器由场景统一生成（cfg.permutation）；所有第 4 章包装器不调用 rng/randperm，10/10 直接调用 RNG 状态保持测试通过。
- 计量精确化：errorBits/	otalBits 为逐方法整数向量，er = errorBits ./ totalBits，Clopper-Pearson 95% 区间逐方法报告；不用 round(ber .* totalBits) 重建。
- CCK 边界：symbols < 4 触发 SCFDE:FrameTooShort（非索引异常）。
- 可复现性：同 seed 精确复现 errorBits/totalBits/BER；异 seed 至少一个误码数变化；结果元数据记录源代码 gitCommit。
- Bellhop 新版：本地 gfortran 16.1 编译 Scripps MPL 新版源码（A-New-BellHope/bellhop, ae1a477 2023-03-30 = 远程最新）→ bellhop.exe/运行时 DLL 在 Bellhop/ 目录（无 PATH 依赖）；ind_bellhop_executable 支持旧版 windows-bin/ 与新版 Bellhop/ 布局。
- 海面粗糙度：新旧版均通过 **altimetry 文件**（TopOpt 第 5 位 '~' + .ati）实现，非 'G' 行；ellhopSurface='gaussian' 生成 Pierson-Moskowitz 谱海面（RMS 波高/PM 风速），浅源实测粗糙海面改变到达增益分布（flat 2 径 vs rough 3 径）。
- Bellhop 环境参数化：ellhopSediment（silt/mud/clay/fine-sand/coarse-sand/rock/custom 预设，Jensen 表）、ellhopSsp（linear/cvw/file）+自定义 SSP 文件、ellhopSurfaceSpeed/BottomSpeed；海面平坦为默认（该 Bellhop 构建不支持 surface 选项行，'G' 已明确拒绝并提示用表面混合层 SSP 近似海况）。
- Bellhop 信道接入：
un_unified_equalizer 支持 channelMode="bellhop"（qpsk/turbo 场景），通过 scfde_bellhop_impulse 将 Bellhop 浅海到达时延/增益采样为符号率冲击响应（缓存于 results/bellhop_impulse_cache.mat）；默认仍为合成信道（可复现无外部依赖）。
- 跨场景契约：scenario=auto 查询注册表，多场景组合触发 SCFDE:MixedScenarios（不再按优先级猜测）；显式指定场景时验证所有内置 ID 属于该场景；"all" 按当前场景解析为 17/10/7/3 全部方法。
- blms 为双场景模块：注册主场景 turbo（解码信息判决），同时允许 qpsk 场景保留框符号输出（同一时间仅在一个场景运行）。
- 算法等级 A/B/C 不因运行时修复而改变；运行完成不等于公式实现等级。

## 全书复审修复（2026-08-11）

已确认并修复：
- C 版 IBDFE Γ = (1/N)Σ A_k H_k（补 /N）；原来前馈系数小 N 倍。
- unified csk-ese BER 改用真正 ESE 输出（infoIndices→码符号映射），不再用 MF；ch6_repeated_symbol_indices 信息符号码字改为无重复 randperm（原 randi 可重复导致映射不唯一）；统一 csk 场景改为发送重复码帧（pair 由场景传入）。
- C BITF-Turbo 反向复数除法原地覆盖 bug（保存 a/b 后计算 re/im）。
- C BLMS-TF-Turbo：residual 用已算 estimate（不再清零），重新均衡用更新后的 g_turbo_h。
- C FBLMS/FDDA overlap-save front_tail 索引补 n_f 偏移（取 current 块尾部）。
- C CCK-FDE residual 变差时直接保留上一轮 detected（不再覆盖为当前更差结果）。
- DPLL 相位误差改为书中 Im{p(ŝ+q)*}（MATLAB 与 C 统一）。
- C csk_receive_ese 从 MF wrapper 升级为软后验检测（距离加权后验均值；单用户退化，多用户 IDMA 迭代在 MATLAB ch6_csk_idma_detect）。

工程近似标注（非书中逐式 A 级）：circular PTR 模块（书中时域线性卷积意义）、ICE 训练构造（[u,u,u,u]、简化软概率（有理函数加权）、ESE damping=0.58（工程默认）、第4章卷积码 (7,5)_8 vs 书中 (171,133)_8。

## 已知缺口（对应 README）

1. **HTFDE 可靠度缩放**（第3章）：工程设置，未按原文逐式（待办 P1）
2. **BLMS overlap-save**（第4章）：已新增严格 overlap-save 的 `fblms_equalizer`（图4-25 语义，含重叠缓存/G 约束/污染丢弃/负向回归），现有 Turbo 融合版保留；原文步长量级与图 4-25 曲线数字化待办
3. **CCK Turbo 外码**（第5章）：重复码替代完整外码；若无原文公开矩阵，应标 B/C（待办 P1）
4. **PIC/ESE 阻尼系数**（第6章）：工程设置，需敏感性分析（待办 P1）
5. **5.5 章 11 径信道**（第5章）：合成信道，需保存逐径参数与敏感性分析（待办 P1）
6. **BER 置信区间与结果元数据**：当前仅点值（待办 P1）
