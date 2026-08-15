# 公式追踪矩阵（FORMULA TRACEABILITY）

本文件是**公式级**追踪矩阵：每一条原书编号公式一行。
规则：**原书有编号公式但本矩阵中没有记录 = 未复现。**

事实源：`book/` 扫描件（48 张四页拼图，只读，覆盖正文约 1~188 页）→ 转写见
`papers/book_transcripts/` 与 `papers/BOOK_CONVENTIONS.md`。图片存在但尚未逐式转录的区间标
`TRANSCRIPTION-PENDING`；项目中不再使用“扫描缺失”描述。OCR 存疑处标
`OCR-UNCERTAIN`，须回原图核对。

`run_equalizer_app.m` 注册的全部 37 种方法所应遵循的完整公式、输入输出、边界和禁止项，
统一见 [`STRICT_FORMULA_SPEC.md`](STRICT_FORMULA_SPEC.md)。本矩阵负责记录当前实现状态，
该规范负责定义整改目标；两者不得相互替代。

## 状态定义（全项目唯一）

| 状态 | 含义 | 是否算原文复现 |
|---|---|---|
| BOOK-EXACT | 原公式、变量定义、归一化、初值、边界、迭代规则、公开参数全部一致 | ✅ |
| ALG-EQUIV | 实现形式不同，但有代数证明 + golden vector 证明严格等价 | ✅ |
| ENGINEERING | damping、近似概率、替代编码、经验缩放等（已显式拆分 `*_engineering`） | ❌ |
| PARAM-UNRECOVERABLE | 公式完全一致，但原书未公布某实验参数 | ✅公式 / ❌原图 |
| FAIL | 与原公式不一致 | ❌ |
| —（未实现） | 公式已登记但无实现（等同未复现，计入分母） | ❌ |

## 公共约定（全项目冻结，见 `BOOK_CONVENTIONS.md`）

约定 | 定义 | 状态 | OK |
|---|---|---|
DFT/FFT | `X_k=Σx_n e^{-j2πkn/N}` 前向无 1/N；逆变换含 1/N | BOOK（与书 3-37~3-38 区域一致） | OK |
能量 | `m_x=E\ | x_n\ | ²`，`M_x=E\ | X_k\ | ²=N·m_x`（Parseval，书式 3-65） | BOOK | OK |
噪声 | `σ_w²=E\ | w_n\ | ²`；`E\ | W_k\ | ²=Nσ_w²`；`σ_w²=P·10^(-SNR/10)` | BOOK | OK |
MMSE/IBDFE 正则化 | `λ=Nσ_w²/M_x=σ_w²/m_x` | BOOK | OK |
LLR 符号 | `L(b)=ln[P(b=0)/P(b=1)]`（0 为正，书式 4-2）；`ĉ=0 当 L≥0`（4-9）；`Lᵉ=L后验-L先验`（4-7） | BOOK | OK |

## `run_equalizer_app` 公式对应性说明（2026-08-14 扫描件复核）

`run_equalizer_app.m` 是注册表、场景和 BER 绘图入口，本身不包含均衡公式。`37/37 PASS`
只表示模块能按运行契约完成，不表示 37 种方法都已严格复现原书。严格公式结论必须同时满足：

1. 生产路径确实调用对应公式实现，而不是同名简化内核；
2. 原式中的阵元/分支、调制、帧结构、初始化、边界和迭代规则均一致；
3. 工程阻尼、候选裁剪、经验回退等未混入 BOOK 主路径；
4. 存在独立于生产实现的原式 golden test，而不是把同一实现重新手算一遍。

当前生产路径静态复核分组如下。这里“核心递推可对应”仍不等于原文整条 BER 曲线复现；
App 的可选信道、SNR、BPSK/QPSK 差异及未公开信道参数需另行核准。

| 章节 | 核心递推可对应 | 部分对应/工程近似 | 明显不能认证为原文实现 |
|---|---|---|---|
| 第2章 | dfe、lms-dfe、nlms-dfe、rls-dfe、dpll-dfe、mc-lms-dfe、mc-nlms-dfe、mc-rls-dfe、ptr-dfe、subband-ptr-dfe（批次5 逐式严格化**已验证的具体公式**：静态维纳 DFE (2-6)~(2-11)、盒式 LMS (2-14)/NLMS (2-16)/RLS (2-23)~(2-25)、DPLL (2-34)~(2-37)（(2-36) 符号修正）、多阵元 (2-43)~(2-46)、PTR (2-47) 求和、子带 (2-48)/(2-49) P 子阵结构；待转录的 (2-17)~(2-22)/(2-38)~(2-42) 为 Fast RLS/DPLL 推导区，不在任一注册方法的必要生产链内，故不影响 10 法 BOOK-EXACT（口径见“已知缺口”第 7 条）；不得概括为“(2-6)~(2-49) 全部 BOOK-EXACT”） | — | — |
| 第3章 | mmse-fde、zf-fde（批次6：MMSE 公共因子 golden、严格 ZF） | — | sd-ibdfe、hd-ibdfe（(3-86) A_k BLOCKED-SOURCE-REVIEW）、ice-sd-ibdfe、ice-hd-ibdfe（(3-92) 方差定义 BLOCKED-SOURCE-REVIEW）、htfde（(3-61) λ 转写 SOURCE-INCONSISTENT；批次1 逐阵元重写，公式 12/12 已验证，但最弱环节未复核不得标 BOOK-EXACT） |
| 第4章 | td-turbo、fblms、fdda-teq（公式结构已验证） | tf-turbo、bitf-turbo、tdda-teq、fdda-dfe-teq（ALG-EQUIV）、blms-tf-turbo（ENGINEERING：spec 4.6 要求严格块 FBLMS 内核，现用逐频点 BLMS 扩展） | fd-dfe、fd-turbo（(4-57)/(4-58) BLOCKED-SOURCE-REVIEW） |
| 第5章 | cck-rake、cck-mfb、cck-dfe | cck-tr-diversity（(5-57) 合并结构 BOOK-EXACT，支路软输出 ALG-EQUIV，帧头 ENGINEERING → 整体 ALG-EQUIV）、cck-fde（(5-80) ALG-EQUIV；0.65/0.35 软值混合与性能回滚已于批次8 删除） | cck-bidfe、cck-bidfe2 |
| 第6章 | — | csk-matched-filter、csk-ese、csk-soft-sic（ESE 矩 BOOK-EXACT/LLR 与域 ALG-EQUIV；SIC 派生 ALG-EQUIV，无阻尼） | — |

数量口径：核心递推可对应 18，部分对应/工程近似 10，明显不能认证 9。该分组是当前代码快照的
审计结论，不得改写成“18 种完整原文复现”。已确认的主要原因包括：

- QPSK/CCK 场景把同一 `received` 复制为两行 `branches`，不构成独立阵元观测；
- 第4章统一入口使用 BPSK，而原书相应 FDDA 实验使用 QPSK 和多阵元数据；
- HTFDE 已于批次1 重写为式 (3-61)/(3-62) 的逐阵元 `C_{m,k} R_{m,k}` 合并 + 多通道 DPLL-DFE 后级（公式 12/12 已验证；但 (3-61) λ 转写 SOURCE-INCONSISTENT → 认证 BLOCKED-SOURCE-REVIEW，最弱环节原则）；
- FDDA 式 (4-77) 的 `W_m^H`、反馈加号、多阵元求和及内层迭代已按 book/26.png 人工复核并通过独立 oracle（批次2，test_fdda_eq_4_74_82 15/15）；
- BiDFE 式 (5-57) 已由批次3 接入生产路径：`ch5_tr_diversity_combine`（等权 1/2）+ `ch5_tr_diversity_restore`（rev[]=conj(fliplr) 恢复到同一时间序）驱动 `cck-tr-diversity`；支路码片级软输出按 (5-46)/(5-47) 生产模型推导（ALG-EQUIV，帧头前 memory 码片无时反窗取前向支路 = ENGINEERING），待 (5-48)~(5-56) 逐式转录复核；
- 第6章 App 默认单用户；Soft-SIC 固定 0.45/0.55 阻尼已由批次4 移除（spec 6.2 禁止），改为按接收功率排序的后验软均值串行 SIC（ID 级 ALG-EQUIV）；ESE BOOK 路径阻尼 α=1，α<1 仅在 `csk_ese_damped`；

---

## 第 1 章 绪论（书页 1~14，理论章）

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (1-1) 声速经验式 `c=1449.2+4.6t-0.055t²+0.00029t³+(1.34-0.01t)(S-35)+0.016H` | 2-3 | t,S,H → c；实数/scalar | — | — | scfde.book_formulas.ch1_sound_speed | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-2) `A(l,f)=l^k[α(f)]^l` 传播损失 | 2-3 | l,f,k → A | — | — | scfde.book_formulas.ch1_propagation_loss | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-3) `TL=k·10lg(1000/l)+l·10·lgα(f)` | 2-3 | l,f → TL(dB) | dB | — | scfde.book_formulas.ch1_propagation_loss | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-4) `10lgα(f)=0.11f²/(1+f²)+44f²/(4100+f²)+2.75e-4f²+0.003` | 2-3 | f(kHz) → α | dB/km | — | scfde.book_formulas.ch1_thorp_absorption | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-5) `Δf_max=(v_max/c)·f` | 5-6 | v,c,f → Δf | — | — | scfde.book_formulas.ch1_doppler_spread | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-6) 四类环境噪声谱（N_s/N_v/N_h/N_t） | 5-6 | f,s,w → N(dB re μPa) | dB | — | scfde.book_formulas.ch1_noise_psd | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-7) `N(f)=N_s+N_v+N_h+N_t` | 5-6 | 分量 → 总噪声 | — | — | scfde.book_formulas.ch1_noise_psd | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-8) `10lgN(f)=N_0-q·lgf` | 5-6 | f → N | dB；N0=50, q=18 | — | scfde.book_formulas.ch1_noise_psd | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-9) `y(t)=∫h(t,τ)x(t-τ)dτ+n(t)` | 9-10 | h,x → y；时域 | — | — | scfde.book_formulas.ch1_channel_model | — | test_book_formulas_ch1 | ALG-EQUIV | OK |
| (1-10) `h(t,τ)=Σa_p(t)δ(τ-τ_p(t))` 多径模型 | 9-10 | a_p,τ_p → h | — | — | scfde.book_formulas.ch1_channel_model | — | test_book_formulas_ch1 | ALG-EQUIV | OK |
| (1-11) `I=速率×距离` | 13-14 | — | kbit/s·km | — | scfde.book_formulas.ch1_capacity_index | — | test_book_formulas_ch1 | BOOK-EXACT | OK |
| (1-12) `E=R_b/W` 带宽效率 | 13-14 | — | — | — | scfde.book_formulas.ch1_bandwidth_efficiency | — | test_book_formulas_ch1 | BOOK-EXACT | OK |

第1章结论：理论章，模型公式已登记；除信道建模（1-9/1-10）外多数不进入算法路径。

## 第 2 章 单载波时域均衡（书页 14~43）

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (2-1) `s(t)=a(t)cos(2πf_c t+φ_k)=s_I cos-s_Q sin` | 14 | 已调信号 | — | — | scfde.book_formulas.ch2_modulated_signal | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-2) `s(t)=Re{u(t)e^{j2πf_c t}}` | 17-18 | 复包络 | — | — | scfde.book_formulas.ch2_modulated_signal | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-3) `u(t)=Σa(n)g(t-nT)` | 17-18 | 成形 | — | — | scfde.book_formulas.ch2_pulse_shaped | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-4) `r'(t)=Σ_n d_n h(t-nT-τ)e^{jθ}+w(t)` | 17-18 | 连续接收模型（无 Doppler 项） | — | — | scfde.book_formulas.ch2_received_continuous | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-5) `r_k=e^{jθ}Σ_l d_l h_{k-l}+w_k = e^{jθ}d_k h_0+e^{jθ}Σ_{l≠k} d_l h_{k-l}+w_k` | 17-18 | 离散接收（当前符号+ISI+AWGN） | — | — | scfde.book_formulas.ch2_received_model | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-6) `d̂_k=Σf_i^*r_{k-i}-Σb_j^*d̂_{k-j}` | 17-18 | DFE 结构；反馈为负 | — | `known_dfe_core.m`/`conventional_dfe.m`（批次5：静态维纳 DFE，数据段不再自适应跟踪） | — | — | test_ch2_tde_eq_2_6_49/test_modular_pipeline | BOOK-EXACT | OK |
| (2-7) `u_k=[d(k-N)…r(k+L-1)]^T` 输入向量 | 17-18 | DFE 输入 | — | `adaptive_dfe_core.m` | — | — | — | ALG-EQUIV | OK |
| (2-8) `w_k=[h(1)…f(-L+1)]^T` 权向量 | 17-18 | 权重结构 | — | `adaptive_dfe_core.m` | — | — | — | ALG-EQUIV | OK |
| (2-9) `e(k)=d(k)-w_n^H u_k` | 19-20 | 误差 | — | `adaptive_update.m` | — | — | — | ALG-EQUIV | OK |
| (2-10) `J(w)=E\ | e_k\ | ²` | 19-20 | MSE 目标 | scfde.book_formulas.ch2_mse | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-11) `w^o=R_u^{-1}R_{du}` 维纳解 | 19-20 | 统计最优 | — | `known_dfe_core.m`（训练 LS = 经验维纳解，批次5） | scfde.book_formulas.ch2_wiener | — | test_ch2_tde_eq_2_6_49/test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-12) `w(n+1)=w(n)-μ∇_w J` | 19-20 | 梯度下降 | — | `adaptive_update.m` | — | — | — | ALG-EQUIV | OK |
| (2-13) `∇_w J=-2E[e^*(n)u(n)]` | 19-20 | 梯度 | — | — | scfde.book_formulas.ch2_lms_gradient | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-14) `w(n+1)=w(n)+2μe^*(n)u(n)` LMS | 19-20 | 系数更新 | 2μ 显式（cfg.lmsStep = 2μ_book） | `lms_dfe.m`/`adaptive_update.m` | — | — | test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-15) `0<μ<1/λ_max` | 19-20 | 收敛界 | — | — | scfde.book_formulas.ch2_lms_convergence_bound | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-16) `w(n+1)=w(n)+μe^*(n)u(n)/(δ+u^Hu(n))` NLMS（spec 2.3 框定） | 21-24 | 系数更新 | δ=1e-5 仅防零除 | `nlms_dfe.m`/`adaptive_update.m`（单一复合向量一次更新） | — | — | test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-17)~(2-22) | 21-24 | 扫描已存在；Fast RLS 等推导区待逐式转录 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (2-23)~(2-25) `k=Pu/(λ+u^HPu)`、`w+=ke^*`、`P=λ^{-1}[P-ku^HP]` RLS（spec 2.4 框定） | 21-24 | 系数更新 | 0.8<λ<1；P(0)=δ^{-1}I（δ^{-1}=cfg.rlsInitialInverseCorrelation=100，数值初始化已记录） | `rls_dfe.m`/`adaptive_update.m` | — | — | test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-26) `r(k)=[r(k)…r(k+N-1)]^T` | 25-26 | 前馈输入 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-27) `p_k=a^H r(k)e^{-jθ_k}` | 25-26 | 相位补偿 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-28) `d⃗(k)` 反馈输入 | 25-26 | 判决序列 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-29) `q_k=b^H d⃗(k)` | 25-26 | 反馈输出 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-30) `d⃗_k=p_k-q_k=w^H u(k)` | 25-26 | 复合结构 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-31) `e_k=d_k-d⃗_k` | 25-26 | 误差 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-32) `∂MSE/∂a=-2E{r e_k^* e^{-jθ_k}}` | 25-26 | 前馈梯度 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-33) `∂MSE/∂b=-2E{d⃗ e_k^*}` | 25-26 | 反馈梯度 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-34) `∂MSE/∂θ=-2Im{E{p_k(d_k+q_k)^*}}` | 25-26 | 相位梯度 | — | `dpll_dfe.m` | — | — | — | BOOK-EXACT | OK |
| (2-35) `θ̂_{k+1}=θ̂_k+K_1 φ_k+K_2 Σ_{i=1}^k φ_i`（φ 为相位误差，非均衡误差 e；K_2=0.1K_1 见 (2-37)） | 25-26 | DPLL 递推 | — | `dpll_dfe.m`（phaseError 路径） | — | — | test_eq_2_36/testLoopConvergesToRotation/test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-36) `φ_l=Im{p_l(d_l+q_l)^*}` | 25-26 | 相位检测 | q=b^H d⃗ 为正 | `dpll_dfe.m`（批次5 修正 q 项符号：Im{p conj(d)}+Im{p conj(q)}） | — | — | test_eq_2_36/test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-37) `K_I2=0.1·K_P2` | 25-26 | 环参数 | — | cfg.KI2rel | — | — | — | BOOK-EXACT | OK |
| (2-38)~(2-42) | 29-32 | 扫描已存在；DPLL 推导余部待逐式转录 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (2-43)~(2-46) `z(k)=Σ_p a_p^H(k) r_p(k) e^{-jθ̂_{p,k}}-b^H(k)d̃(k)` 多阵元 DPLL-DFE（spec 2.6~2.8 框定） | 29-32 | 多阵元 | 每阵元独立相位环 | `multichannel_dfe_core.m`（批次5：新增每阵元 DPLL + 复合 LMS/NLMS/RLS 更新） | — | — | test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-47) `r̂(t)=Σh_i'(-t)⊗r_i(t)=Q(t)⊗s(t)+ς(t)` | ~29-30 | PTR 等效信道 | 线性卷积 | `ptr_dfe.m`（线性主路径；批次5 多阵元 Σ_p 求和） | — | — | test_eq_2_47/test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-48) `y_p(n)=Σh̃_p^*(-k)⊗r_k(n)` | ~29-30 | 子阵 PTR | 线性卷积 | `subband_ptr.m`（线性主路径；批次5 P 子阵分组） | — | — | test_eq_2_47/test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-49) `d̂=Σa_n^H y_p-b^H d` | ~29-30 | Sub-PTR-DFE | — | `subband_ptr_dfe.m`（批次5：P 支路已知维纳 DFE `multibranch_known_dfe_core.m`） | — | — | test_ch2_tde_eq_2_6_49 | BOOK-EXACT | OK |
| (2-50) `y_r^D(n)=y_r(N-n+1)` | 33-34 | 时反 | — | `cck_bidfe2.m`/BiDFE 反向支路 | — | — | — | BOOK-EXACT | OK |
| (2-51) `d̂_F=Σa_p^(F)y_p-b^(F)d̃^(F)` | 33-34 | 前向支路 | — | BiDFE 模块 | — | — | — | ALG-EQUIV | OK |
| (2-52) `d̂_B^D=Σa_p^(B)y_p^D-b^(B)d̃^(B)` | 33-34 | 反向支路 | — | BiDFE 模块 | — | — | — | ALG-EQUIV | OK |
| (2-53) `d̄=dec[(d̂_F+d̂_B^D)/2]` | 33-34 | 合并判决 | 1/2 | BiDFE 模块 | — | — | — | BOOK-EXACT | OK |

## 第 3 章 单载波频域均衡与同步（书页 45~74）★ 模板章

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (3-1) `s=[s_0…s_{N-1}]^T` | 47-48 | 数据块 | — | 帧构造 | — | — | — | BOOK-EXACT | OK |
| (3-2) `h=[h_0…h_{L-1}]^T` | 47-48 | 信道 | — | channel.impulse | — | — | — | BOOK-EXACT | OK |
| (3-3) `r_k=Σh_i s_{k-i}+w_k` | 47-48 | 线性卷积 | — | apply_multipath | — | — | — | BOOK-EXACT | OK |
| (3-4)/(3-5) 线性卷积矩阵/向量 | 47-48 | 矩阵形式 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (3-6)/(3-7) CP 插入/复制 | 47-48 | 帧结构 | CP=M | 帧构造 | — | — | — | BOOK-EXACT | OK |
| (3-8)~(3-26) | 49-50 | 扫描已存在；UW/同步区待逐式转录与生产核对 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (3-27) `η_CP-SC=N/(N+M)` | 51-52 | 频谱效率 | — | — | scfde.book_formulas.ch3_spectral_efficiency | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-28) `η_UW-SC=(N-P)/(N+M)` | 51-52 | 频谱效率 | — | — | scfde.book_formulas.ch3_spectral_efficiency | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-30) 补零块 | 51-52 | 帧结构 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (3-31) `r=H_circ s+w` 循环卷积 | 51-52 | 循环矩阵 | 循环卷积 | — | — | — | test_eq_3_31 | BOOK-EXACT | OK |
| (3-32) 循环卷积逐行 | 51-52 | 展开式 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (3-37) `r=DHs+w`, `D=diag[e^{jθ_k}]` | 55-58 | 多普勒相位 | — | — | scfde.book_formulas.ch3_doppler_matrix | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-38) `R=Fr=ΦHS+W`, `Φ=FDF^H` | 55-58 | 频域模型 | 前向 DFT 无 1/N | — | scfde.book_formulas.ch3_freq_model | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-39~3-41) `Φ≈λI`, `λ=(1/N)Σe^{jθ_p}` | 55-58 | 相位近似 | 1/N | — | scfde.book_formulas.ch3_phase_approx | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-42~3-44) `C=(Ĥ^HΦ^HΦĤ+σ²I)^{-1}Ĥ^HΦ^H` | 55-58 | MMSE 矩阵解 | — | — | scfde.book_formulas.ch3_mmse_matrix | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-45) `ŝ=F^H CHFs+w̃=AĤs+w̃` | 55-58 | 时域输出 | IDFT 含 1/N | — | scfde.book_formulas.ch3_time_output | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-46) `ŝ_k=β_k s_k+w'_k` 相位补偿 | 55-58 | 残余相位 | — | — | scfde.book_formulas.ch3_time_output | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-47)~(3-60) | 59-62 | 扫描已存在；区间待逐式转录与生产核对 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (3-61) `C_{m,k}=(\tilde H^H\Phi^H\Phi\tilde H+\sigma^2I)^{-1}\tilde H^H\Phi^H`，`\Phi=\lambda I` 时为 `(\|λ\|²Ĥ^HĤ+σ²I)^{-1}λ*Ĥ^H`（逐阵元） | 59-60 | 频域 MMSE | — | `ch3_htfde_equalize.m`（批次1 重写） | — | — | test_htfde_eq_3_61_62 | SOURCE-INCONSISTENT（转写第二行 λ 似无共轭；Resolution：跟随第一行矩阵式与 (3-44)，实现 \|λ\|² 分母、λ* 分子）；生产 BLOCKED-SOURCE-REVIEW（最弱环节：矩阵式实现 12/12 PASS 本机复验，但 λ 转写未复核） | OK |
| (3-62) `x_m=F^H Σ_{k=1}^{K} C_{m,k}R_{m,k}` 子阵频域合并输出 | 59-60 | 频域合并 | 1/N（IFFT） | `ch3_htfde_equalize.m`（批次1 重写） | — | — | test_htfde_eq_3_61_62 | BLOCKED-SOURCE-REVIEW（逐阵元实现 12/12 PASS 本机复验；整体认证随 (3-61) λ 转写为最弱环节） | OK |
| (3-64) `X̂^l=(C^l)^H R-(B^l)^H X̂^{l-1}` | 63-64 | IBDFE 迭代 | — | `ch3_ibdfe_equalize.m`（批次6：首迭代反馈为零退化为 MMSE-FDE） | — | C IBDFE | test_eq_3_87/test_ch3_fde_ibdfe_eq_3_39_92 | BOOK-EXACT | OK |
| (3-65) `M_Xk=E\ | X_k\ | ², M_X̂k=E\ | X̂_k\ | `BOOK_CONVENTIONS` | — | — | — | BOOK-EXACT | OK |
| (3-66) `r_{Xk,X̂k*}=E[X_k X̂_k^*]` | 63-64 | 相关 | — | — | scfde.book_formulas.ch3_ibdfe_corr | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-67) `J^IB=(1/N)ΣE\ | x̂_k-x_k\ | ²` | 63-64 | MSE | scfde.book_formulas.ch3_ibdfe_mse | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-68)~(3-80) | 65-66 | 扫描已存在；IBDFE 权重推导区待完成逐式转录及归一化核对 | — | `ch3_ibdfe_equalize.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (3-81) `B_k'=C_k'H_k^*-1` | 67-68 | 反馈系数 | — | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-82) `β'=(1/N)ΣC_k'H_k^*` 初值 | 67-68 | 增益 | 1/N | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-83) `β'` 后续迭代=1 | 67-68 | 迭代规则 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (3-84) `C_k'=A_k'/Γ` | 67-68 | 前馈归一化 | — | `ch3_ibdfe_equalize.m` | — | C IBDFE | test_eq_3_87/test_ch3_fde_ibdfe_eq_3_39_92 | BOOK-EXACT | OK |
| (3-85) `B_k'=C_k'H_k^*-1` | 67-68 | 反馈 | — | `ch3_ibdfe_equalize.m` | — | C IBDFE | test_eq_3_87/test_ch3_fde_ibdfe_eq_3_39_92 | BOOK-EXACT | OK |
| (3-86) `A_k'=(H_k')^*ΓΣ^{-1}/(\ | H_k'\ | ²ΓΣ^{-1}+Nσ_w²)` | 67-68 | — | — | C IBDFE | test_eq_3_87 | OCR-UNCERTAIN | N/A |
| (3-87) `Γ=(1/N)ΣA_k'H_k^*` | 67-68 | 归一化因子 | **1/N** | — | — | C IBDFE（2026-08-11 已补 /N） | — | BOOK-EXACT | OK |
| (3-88) `H_LS'=R/X_D^0=H+W/X_D^0=H+e'` | 67-68 | LS 信道估计 | — | `ch3_ibdfe_equalize.m`（批次6：数据驱动 LS，自第 2 轮起；返修：`Y·conj(X̄)/\|X̄\|²` 数值安全复数除法，book/17.png 人工确认 R/X_D^0 形式）/`ch3_estimate_channel_ls.m` | — | — | test_eq_3_88/test_ch3_fde_ibdfe_eq_3_39_92 | BOOK-EXACT | OK |
| (3-89) `h_est,k^j=Σ_{n=0}^{N-1}H_LS,n^j e^{+j2πkn/N}=h_k+e_k^j`（正文"将 H_LS 进行 IDFT 变换"；原式无 1/N，而 MATLAB ifft 固有 1/N，标度差待 (3-88)~(3-91) 全链 golden 定案） | 67-68 | 时域变换（IDFT 方向） | 1/N 待定 | `ch3_ibdfe_equalize.m` 内 ifft | — | — | — | SOURCE-NORMALIZATION-REVIEW | N/A |
| (3-90) `h_est'` 前 L 抽头加窗 | 67-68 | 稀疏化 | — | `ch3_estimate_channel_ls.m`（L 截断） | — | — | test_eq_3_90 | BOOK-EXACT | OK |
| (3-91) `H_est'=DFT(h_est')` | 67-68 | 回频域 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (3-92) `H'=(Hσ_DFT²+H_est'σ_old²)/(σ_old²+σ_DFT²)` MMSE 方差加权（spec 3.6 框定） | 67-68 | 信道合并 | — | `ch3_ibdfe_equalize.m`（批次6：盒式实现，固定 ρ 混合已移除；**权重排列 sigmaDft2·H_old+sigmaOld2·H_DFT 已由 book/17.png 人工确认，不得交换**；方差取残差能量 σ_DFT²=mean\|H_LS−H_DFT\|²、σ_old²=mean\|H_old−H_LS\|²） | — | — | test_ch3_fde_ibdfe_eq_3_39_92 | BOOK-EXACT（盒式，权重排列扫描确认）；两方差完整估计公式未恢复 → **ENGINEERING-BLOCKED** | OK |

### 第3章算法状态（模板章验收）

算法 | 状态 | 说明 | OK |
|---|---|---|
MMSE-FDE（`mmse_fde.m`） | BOOK-EXACT | 与书式 `H*/(Nσ_w²+M_x\ | H\ | ²)` 差公共正实因子 N（m_x=1 单位能量），批次6 golden 证明判决等价（test_ch3_fde_ibdfe_eq_3_39_92） | OK |
IBDFE（`sd_ibdfe.m`/`hd_ibdfe.m`/`ch3_ibdfe_equalize.m`） | BLOCKED-SOURCE-REVIEW（最弱环节） | 3-64/3-65/3-82/3-84/3-85/3-87 全闭环已 oracle 锁定；unit-gain 断言 `\ | mean(CH)-1\ | <1e-10`；首迭代退化为 MMSE-FDE、软路径后验均值（不硬切）、硬路径上一整块判决；但 (3-86) A_k 完整形式仍待 book/17.png 复核，故整体不得标 BOOK-EXACT | OK |
HTFDE（`htfde.m`） | BLOCKED-SOURCE-REVIEW（最弱环节） | 批次1：逐阵元 (3-61)/(3-62) 前端 + 多通道 DPLL-DFE 后级；本机复验：公式测试 12/12、多阵元及 BER 契约 8/8、运行契约 21/21、全量 143/143 均 PASS；seed=42、12 dB 时 0/112、BER=0（训练区不计入）；但 (3-61) λ 转写 SOURCE-INCONSISTENT 未复核，故整体不得标 BOOK-EXACT；BOOK 模式要求显式 P/K，缺失抛 `SCFDE:BookParameterUnavailable`；原书实验参数（N/M/P/K、DPLL 增益、μ）PARAM-UNRECOVERABLE，不得宣称原文实验复现 | OK |
ICE（`ice_sd_ibdfe.m`/`ice_hd_ibdfe.m`） | BLOCKED-SOURCE-REVIEW（最弱环节） | 批次6：数据驱动 LS→DFT 截断→盒式 MMSE 方差加权（(3-88)~(3-91) 与 (3-92) 权重排列均已确认），首轮保持训练估计 H，固定 ρ 混合已移除；训练观测合成与 randn 已删除（RNG 透明）；但 (3-92) 两个方差定义仍待 book/17.png 复核，故整体不得标 BOOK-EXACT | OK |
ZF-FDE（`zf_fde.m`） | BOOK-EXACT | spec 3.2 框定 `C_k=1/(λH_k)`；批次6 严格化：无 ε 下限、奇异频点 trace.singularBins 报告（λ=1 零多普勒场景） | OK |

## 第 4 章 单载波迭代均衡（书页 75~112）

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (4-1) `y_n=Σh_l x_{n-l}+w_n` | 75-76 | 信道模型 | — | 帧/信道构造 | — | — | — | BOOK-EXACT | OK |
| (4-2) `L(c_k)=ln[P(0)/P(1)]` | 75-76 | LLR 定义 | — | ch4_bcjr_log_domain | — | — | — | BOOK-EXACT | OK |
| (4-3) `L(c_k | y)=ln[P(0 | y)/P(1 | y)]` | 75-76 | — | — | — | BOOK-EXACT | OK |
| (4-4) `P(c_k=c | y)=ΣP(y | c)P(c)/P(y)` | 75-76 | ch4_probability_posteriors | — | — | — | BOOK-EXACT | OK |
| (4-5) `P(c)=ΠP(c_k)`；后验 LLR 展开 | 79-80 | 比特独立 | — | ch4_bcjr_probability | — | — | — | BOOK-EXACT | OK |
| (4-6) `L^e(c_i)` 外信息 | 79-80 | 外信息 | — | ch4_log_combine | — | — | — | BOOK-EXACT | OK |
| (4-7) `L^e=L后验-L先验` | 79-80 | 减法 | — | ch4_log_combine | — | — | — | BOOK-EXACT | OK |
| (4-8) `L^e(c_i)≜…` | 79-80 | 定义 | — | — | — | — | — | OCR-UNCERTAIN | N/A |
| (4-9) `ĉ_i=0 当 L≥0` | 79-80 | 硬判决 | — | ch4_hard_bpsk | — | — | — | BOOK-EXACT | OK |
| (4-10)~(4-15) | 81-82 | 扫描已存在；交织/解交织公式待逐式转录与生产核对 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (4-16) `L(c_k)=ln[Σ_{c=0}P(s,s')/Σ_{c=1}…]` | 83-84 | BCJR 后验 | — | ch4_bcjr_siso_decode | — | — | — | BOOK-EXACT | OK |
| (4-17) `P(s_k,s_{k+1},y)` 联合概率分解 | 83-84 | BCJR | — | ch4_branch_metrics | — | — | — | BOOK-EXACT | OK |
| (4-18) `α_k=Σα_{k-1}γ_k` 前向 | 83-84 | BCJR | 归一化可选 | ch4_bcjr_probability | — | — | — | BOOK-EXACT | OK |
| (4-19) `β_k=Σβ_{k+1}γ_k` 后向 | 83-84 | BCJR | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (4-20) `γ_k=P(c^1)P(c^2 | y)` 分支度量 | 83-84 | BCJR | ch4_branch_metrics | — | — | — | OCR-UNCERTAIN | N/A |
| (4-21) `P(0)=1/(1+e^{-L})` | 83-84 | 概率-LLR | — | ch4_logadd | — | — | — | BOOK-EXACT | OK |
| (4-22) `P(1)=e^{-L}/(1+e^{-L})=1/(1+e^{L})` | 83-84 | 概率-LLR | — | ch4_logadd | — | — | — | SOURCE-INCONSISTENT | N/A |
| (4-23) `{P_k}_{i,j}=γ_k…` | 83-84 | 矩阵形式 | — | — | — | — | — | OCR-UNCERTAIN | N/A |
| (4-24)~(4-31) `x̂=x̄+VH^H(HVH^H+σ²I)^{-1}(y-Hx̄)` 时域 LMMSE（spec 4.1 框定，V=diag(1-\|x̄\|²)） | 85-86 | 逐迭代 LMMSE | — | `ch4_iterate_time_turbo.m`（批次7 盒式重写） | — | — | test_ch4_turbo_eq_4_24_73 | BOOK-EXACT | OK |
| (4-32)~(4-41) | 85-86 | 扫描已存在；LMMSE 推导余部待逐式转录 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (4-42) `p(x̂_k | x_k=s_i)=1/(πσ̂²)e^{- | x̂-μ̂s_i | ²/σ̂²}` | 87-88 | 高斯外信息模型 | — | `ch4_iterate_frequency_turbo.m`（批次7：μ̂/σ̂² 按 (4-60)/(4-61) 训练段估计） | — | — | test_ch4_turbo_eq_4_24_73 | BOOK-EXACT | OK |
| (4-43) `L^E(c_{k,j})` 均衡器外信息 | 87-88 | 外信息 | — | ch4_iterate_*_turbo | — | — | test_ch4_turbo_eq_4_24_73 | BOOK-EXACT | OK |
| (4-44) `P(c=0)=1/(1+e^{L^D})` | 87-88 | 译码先验 | — | ch4_log_combine | — | — | — | BOOK-EXACT | OK |
| (4-45) `P(c=1)=e^{L^D}/(1+e^{L^D})` | 87-88 | 译码先验 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (4-46) `L^D` 译码器外信息 | 87-88 | 外信息 | — | ch4_bcjr_siso_decode | — | — | — | BOOK-EXACT | OK |
| (4-47) `x̄_k=E(x_k)=Σs_i P(x_k=s_i)` 软符号 | 87-88 | 软符号 | — | `ch4_decoder_feedback_frame.m`（批次7：反馈均值改由译码器**外信息** tanh(L_D^e/2) 计算，训练位置锁定） | — | — | test_ch4_turbo_eq_4_24_73 | BOOK-EXACT | OK |
| (4-48) `P(x_k=s_i)=ΠP(c_{k,j}=s_{i,j})` | 87-88 | 比特独立 | — | ch4_probability_posteriors | — | — | — | BOOK-EXACT | OK |
| (4-49) `x̄_n=Σ(f_l^H)^*y_{n+l}^H-(g_l)^T x̄_n` | 87-88 | 时域软反馈 | — | ch4_iterate_time_turbo | — | — | — | OCR-UNCERTAIN | N/A |
| (4-50)~(4-63) | 89-90 | 扫描已存在；FD-DFE/FD-Turbo 权重区：零均值约束 (4-52) 已显式施加（批次7）；(4-57)/(4-58) 分子分母仍 **BLOCKED-SOURCE-REVIEW**（book/21.png），故 `fd-dfe` 标 ALG-EQUIV、`fd-turbo` 标 **BLOCKED-SOURCE-REVIEW**（批次11 认证枚举统一，旧 BOOK-EXACT-STRUCTURE 非标准值已废弃） | — | `ch4_fd_ibdfe_weights.m`/`ch4_frequency_dfe_baseline.m`/`ch4_iterate_frequency_turbo.m` | — | — | test_ch4_turbo_eq_4_24_73 | TRANSCRIPTION-PENDING | N/A |
| (4-64) `y'_u,y_u,y'_d,r_u` 块定义 | 103-106 | BLMS 块 | N、N_v | — | — | C FBLMS | test_fblms_and_curve_benchmark | BOOK-EXACT | OK |
| (4-65) `R_u(k)=F r_u(k)` | 103-106 | 频域变换 | 无 1/N | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-66) `X̂(k)=ΣW_n⊙R_n` | 103-106 | 频域滤波 | ⊙ | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-67) `x̂(k)=F^H X̂(k)` | 103-106 | 回时域 | 1/N | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-68) `T=[0 I 0]` 块提取 | 103-106 | 投影 | — | fblms.m | — | — | — | OCR-UNCERTAIN | N/A |
| (4-69) `x̃(k)=T x̂(k)` | 103-106 | 有效块 | — | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-70)~(4-73) | 105-106 | 扫描已存在；BLMS 标量能量分母、时域约束与误差块公式可直接核对 | — | `fblms_equalizer.m` | — | — | `test_fblms_and_curve_benchmark` | BOOK-EXACT | OK |
| (4-74) `y_in,y_re,y_out,r_m` | 107-110 | FDDA 块（非对称 `[Nf; N; Nb]`，`L=Nf+N+Nb`，滑动步长 `N_s<N`） | N、N_f、N_b | ch4_fdda_teq_core.m（批次2 重写） | — | — | test_fdda_eq_4_74_82 | BOOK-EXACT | OK |
| (4-75) `x̃(k)=[x̃_pre;0_N;x̃_post]` 反馈窗口 | 107-110 | 反馈构造 | 中间块置零 | ch4_fdda_teq_core.m（批次2 内联，`[Nf;N;Nb]`） | — | — | test_fdda_eq_4_74_82/test_fblms_and_curve_benchmark | BOOK-EXACT | OK |
| (4-76) `R_m=Fr_m; X̃=F x̃` | 107-110 | 频域 | 无 1/N | ch4_fdda_teq_core.m | — | — | test_fdda_eq_4_74_82 | BOOK-EXACT | OK |
| (4-77)~(4-80) `X̂=Σ_m W_m^H⊙R_m+B⊙X̃`、公共误差 E、逐阵元更新 | 108-109 | 输出/误差/更新 | 共轭、反馈加号、多阵元求和（批次2 独立 golden 1e-12） | `ch4_fdda_teq_core.m`（批次2 重写） | — | — | test_fdda_eq_4_74_82 | BOOK-EXACT | OK |
| (4-81) 内层轮继承 W/B（`W_m^i(1)=W_m^{i-1}(K)`；i 为内层编号） | 110 | 迭代规则 | — | `ch4_fdda_teq_core.m`（weightHistory 记录更新前权值） | — | — | test_fdda_eq_4_74_82 | BOOK-EXACT | OK |
| (4-82) 块内更新 W/B（γ^i 按内层 i=1 起、逐阵元标量分母 δ+R_m^H R_m、FGF⁻¹） | 110 | 自适应 | — | `ch4_fdda_teq_core.m` | — | — | test_fdda_eq_4_74_82 | BOOK-EXACT | OK |

第4章编码参数：**(171,133)₈**（书页 91-94、表4-4）为 4.3 节 BOOK；FDDA 实验原文用 **(7,5)₈**（书页 111-112）。`ch4_convolutional_trellis/encode` 已参数化（八进制解释，poly2trellis 惯例），默认 (7,5)₈ 不变，`cfg.convCodeG=[171 133]` 可选（test_eq_4_convcode）。

## 第 5 章 单载波互补码键控扩频（书页 122~164）

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (5-1)~(5-7) | 123-124 | 扫描已存在；CCK 码本生成区待逐式转录与生产核对 | — | `ch5_cck_codebook.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-8) Golay 递推 `[A_k;B_k]=[A_{k-1} B_{k-1};B_{k-1} -A_{k-1}]` | 125-128 | 互补对 | — | ch5_golay_complementary_pair | — | — | — | BOOK-EXACT | OK |
| (5-9) A_1/B_1/A_2/B_2 序列 | 125-128 | 码本 | — | ch5_cck_codebook | — | — | — | OCR-UNCERTAIN | N/A |
| (5-10) G^T 生成矩阵 | 125-128 | 生成矩阵 | — | ch5_cck_codebook | — | — | — | OCR-UNCERTAIN | N/A |
| (5-11) `r(i)=Σa(k)h(i-k)+w(i)` | 125-128 | 接收模型 | 线性卷积 | ch5_static_cck_frame | — | — | — | BOOK-EXACT | OK |
| (5-12) 码片相关展开 | 125-128 | — | — | — | — | — | — | OCR-UNCERTAIN | N/A |
| (5-13)~(5-23) | 127-128 | 扫描已存在；无 ISI 最优接收与 MF 界分析区待逐式转录 | — | `ch5_matched_filter_detect.m`/`ch5_rake_detect.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-24) `argmin_i‖r-a_i‖²` ML 判决 | 129-132 | 检测 | — | ch5_nearest_book | — | — | — | BOOK-EXACT | OK |
| (5-25) 判决区域 Z_i | 129-132 | 检测 | — | — | — | — | — | THEORY-ONLY | N/A |
| (5-26)~(5-28) 错误概率 P_e | 129-132 | 理论 | 1/KM | — | — | — | — | THEORY-ONLY | N/A |
| (5-29) 条件错误概率 | 129-132 | 理论 | — | — | — | — | — | OCR-UNCERTAIN | N/A |
| (5-30)~(5-40) | 129-132 | 扫描已存在；误码界、Rake 与 DFE 区待逐式转录，候选裁剪实现按工程近似处理；批次8 已建 Rake MRC 逐径共轭增益合并的决策等价 oracle | — | `ch5_rake_detect.m`/`ch5_dfe_detect.m` | — | — | test_ch5_cck_eq_5_11_80 | TRANSCRIPTION-PENDING | N/A |
| (5-41) `x_i=Σh_l b_{i-l}` | 133-136 | 接收 | 线性卷积 | ch5_expected_block | — | — | — | BOOK-EXACT | OK |
| (5-42) `x'_k=x_n` CMF+CIR | 133-136 | 处理链 | — | ch5_matched_filter_detect | — | — | — | BOOK-EXACT | OK |
| (5-43) `μ_k=Σh_l^* n_{k+l}` 噪声项 | 133-136 | 噪声 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-44)/(5-45) `y_k` 含前后 ISI | 133-136 | 检测输出 | — | ch5_candidate_scores | — | — | — | BOOK-EXACT | OK |
| (5-46) `â_k=y_k-Σx'ã-Σx'â` 双向消除 | 133-136 | DFE 判决 | — | ch5_dfe_detect/ch5_backward_dfe_detect | — | — | — | BOOK-EXACT | OK |
| (5-47) `ã_k=y_k-Σx'â` 后置 ISI | 133-136 | 临时判决 | — | ch5_dfe_detect | — | — | — | BOOK-EXACT | OK |
| (5-48)~(5-56) | 134-136 | 扫描已存在；BiDFE-1/BiDFE-2 与时反分集区待逐式转录，App 分支复制不构成独立接收分集 | — | `ch5_backward_dfe_detect.m`/`ch5_tr_diversity_detect.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-57) `y(k)=(ỹ(k)+ỹ_e(k))/2=a(k)+(μ̃(k)+μ_e(k))/2`（两个 BiDFE 输出恢复到同一时间顺序后等权合并，2026-08-13 回 book/32.png 复核） | 137-140 | 分集合并 | 1/2 | `ch5_tr_diversity_combine.m`（等权 1/2）+ `ch5_tr_diversity_restore.m`（rev[]=conj(fliplr) 恢复同一时间序，批次3） | — | — | test_cck_tr_diversity_eq_5_57 | BOOK-EXACT | OK |
| (5-58) `â(k)=dec[y(k)]` | 137-140 | 判决 | — | `cck_tr_diversity.m`（合并软片上全码本信道模型判决；恒等信道即最近码本，批次3） | — | — | test_cck_tr_diversity_eq_5_57 | BOOK-EXACT | OK |
| (5-59) 扩展判决递推 | 137-140 | 迭代 | — | ch5_extend_cck_word | — | — | — | BOOK-EXACT | OK |
| (5-60) `L^o(b_1)=L_e^o+L_a^o` | 137-140 | LLR | — | ch5_soft_book_detect_with_prior | — | — | — | BOOK-EXACT | OK |
| (5-61) `L^o(c_n)=L_e^o+L_a^o` | 137-140 | LLR | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (5-62)~(5-69) | 139-140 | 扫描已存在；MAP-CCK-TE 后验/外信息推导待完成逐式生产核对 | — | `ch5_soft_book_detect_with_prior.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-70) RSSE 分支度量 λ(x̃_k\ | S[k]) | 141-144 | 网格搜索 | ch5_candidate_scores | — | — | — | OCR-UNCERTAIN | N/A |
| (5-71) 符号后验 P(x_k\ | z_k) | 141-144 | 概率 | ch5_soft_book_detect_with_prior | — | — | — | BOOK-EXACT | OK |
| (5-72) 外信息高斯 pdf | 141-144 | EXIT 分析 | — | — | — | — | — | THEORY-ONLY | N/A |
| (5-73)/(5-74) EXIT 互信息 | 141-144 | EXIT | — | — | — | — | — | THEORY-ONLY | N/A |
| (5-75) `z_q=c_{s_q}e_q` | 145-148 | CCK-SM | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-76) `y=hx+w` MIMO | 145-148 | 模型 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-78) `Y_k=H_k X_k+W_k` | 145-148 | 频域 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-80) `X̂_k^{(i)}=(C^{(i)})^H Y_k-(B^{(i)})^H X̃^{(i)}` | 145-148 | MIMO-IBDFE | — | ch5_fde_cck_detect（批次8：删除 0.65/0.35 软值混合与残差能量回滚，反馈改为 (5-81)/(5-82) 后验均值） | — | — | test_ch5_cck_eq_5_11_80 | ALG-EQUIV | OK |
| (5-81) `x̄_m^i=x_m^i+n̄_m^i` | 145-148 | 软估计 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-82) 软概率 P(x̄_m^i=β_j) | 145-148 | 概率 | — | ch5_soft_book_detect | — | — | — | OCR-UNCERTAIN | N/A |
| (5-83)~(5-96) | 147-148 | 扫描已存在；CCK-SM 接收区尚未逐式转录和实现 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-97) `h(t,τ)=Σβ_l δ(τ-τ_l)` 3km 信道 | 149-152 | 信道 | — | ch5_long_uwa_channel（合成，非原 taps） | — | — | — | BOOK-EXACT | PARAM-UNRECOVERABLE |

第5章已知工程偏差：
- CCK Turbo 外码：原书未公开生成多项式/交织器 → 重复码工程替代，标 ENGINEERING；
  公式部分（5-60/5-61 后验=外+先验）BOOK-EXACT，原图 PARAM-UNRECOVERABLE。
- 软检测：主实现已为指数/log-sum-exp 形式（`ch5_soft_book_detect` 权重 exp(-d/σ²)、`ch5_soft_book_detect_with_prior` metric=-d/σ²+先验 + log-sum-exp LLR）→ BOOK-EXACT；无 `1/(1+d/σ²)` 残留。

## 第 6 章 单载波循环移位扩频（书页 166~196）

| Formula | Page | Domain | Normalization | MATLAB Production | MATLAB Oracle | C | Test | FormulaStatus | ParameterStatus |
|---|---|---|---|---|---|---|---|---|---|
| (6-1) `I(t)=Σs(n)Σc(l)g(t-lT_c)` | 167-168 | DSSS 基带 | — | ch6_csk_codebook 基础 | — | — | — | OCR-UNCERTAIN | N/A |
| (6-2) `R=1/(L T_c)` | 167-168 | 速率 | — | — | scfde.book_formulas.ch6_spreading_rate | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-3) `R=log₂M/(L T_c)` | 167-168 | M 元速率 | — | — | scfde.book_formulas.ch6_spreading_rate | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-4) 循环移位矩阵 T | 167-168 | 矩阵 | — | ch6_shifted_codebook | — | — | — | OCR-UNCERTAIN | N/A |
| (6-5) `c^T T^m c=M (m≡0); 1 (其他)` | 167-168 | 正交性 | — | ch6_csk_codebook | — | — | — | BOOK-EXACT | OK |
| (6-6) `s=T^a α` | 169-172 | 调制 | — | ch6_shifted_codebook | — | — | — | BOOK-EXACT | OK |
| (6-7) `ϑ_a=1/G Re{F^{-1}[(Fa)^*⊙(Fa)]}` 扩频序列自相关 | 169-172 | 自相关 | 1/G | — | scfde.book_formulas.ch6_sequence_autocorrelation | — | test_book_formulas_ch6/testEq67Autocorrelation | BOOK-EXACT | OK |
| (6-8) `δ_Δ(g)` 冲击窗 | 169-172 | 判决 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-9) `θ=1/G Re{F^{-1}[(Fŝ)^*⊙(Fa)]}` CSK 解调相关（共轭在接收侧） | 169-172 | 相关 | 1/G | — | scfde.book_formulas.ch6_demod_correlation | — | test_book_formulas_ch6/testEq69DemodCorrelation | BOOK-EXACT | OK |
| (6-10) `θ=T^{-Δ}ϑ_a`（书内符号矛盾：字面 T^{-Δ} 与 (6-11)/(6-12) 峰向 +Δ 移动不一致） | 169-172 | 移位关系 | — | — | scfde.book_formulas.ch6_shift_relation | — | test_book_formulas_ch6/testEq610_612ShiftEstimate | SOURCE-INCONSISTENT | N/A |
| (6-11) `θ(g)=δ_Δ(g-Δ)` | 169-172 | 峰位置 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-12) `Δ̂=argmax_g θ` | 169-172 | 峰判决 | — | — | scfde.book_formulas.ch6_shift_detect | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-13) `c_i(t)=ΣC_{i,k}φ(t-kT_c)` | 169-172 | 扩频波形 | — | — | scfde.book_formulas.ch6_spread_waveform | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-14) `s_i(t)=Σf(k)d_{i,k}c_i(t-kT_f)` | 169-172 | 发射 | T_f=L_c T_c | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-15) `f^l(L_c c_i)` 循环移位 | 169-172 | 移位操作 | — | ch6_shifted_codebook | — | — | — | BOOK-EXACT | OK |
| (6-16)~(6-19) | 171-172 | 扫描已存在；常规 CSK 接收区待逐式转录与生产核对 | — | `csk_matched_filter.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (6-20) `h_{n,a}=[… ]^T` | 177-180 | 用户-信道 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-21) `r_n(j)=Σh_{n,a}(l)x_m(j-l)+w_n(j)` | 177-180 | 接收模型 | — | ch6_csk_idma_detect | — | — | — | BOOK-EXACT | OK |
| (6-22) `E(r_n(j))=ΣΣh E(x)` | 177-180 | 均值 | — | ch6_posterior_signal_estimate | — | — | — | BOOK-EXACT | OK |
| (6-23) `Var(r_n(j))=ΣΣ\ | h\ | ²Var+σ_w²` | 177-180 | ch6_posterior_signal_estimate | — | — | — | BOOK-EXACT | OK |
| (6-24)/(6-25) 干扰分解 ζ：`E[ζ]=E[r_n(j+l)]-h_{n,m}(l)E[x_m(j)]`、`Var[ζ]=Var[r_n(j+l)]-\|h_{n,m}(l)\|²Var[x_m(j)]`（spec 6.3 框定） | 177-180 | 干扰项 | — | ch6_ese_residual | — | — | test_csk_ese_sic_eq_6_21_65 | BOOK-EXACT | OK |
| (6-26)~(6-37) | 178-180 | 扫描已存在；ESE/IDMA 均值、方差与 LLR 更新区待完成逐式生产核对。Soft-SIC 派生路径（spec 6.2）已由批次4 重写：按接收功率排序的软串行 SIC、后验软均值抵消、后验二阶矩方差、无固定阻尼（ID 级 ALG-EQUIV） | — | `ch6_csk_idma_detect.m`/`ch6_ese_residual.m`/`ch6_soft_sic_detect.m` | — | — | test_csk_ese_sic_eq_6_21_65 | TRANSCRIPTION-PENDING | N/A |
| (6-38) `Q_m(t)=Σh_{m,n}⊗b̂_n(-t)` PTR 等效信道 | 181-184 | PTR | 线性卷积 | ch6_ptr_context | — | — | — | BOOK-EXACT | OK |
| (6-39) `w̃_i(t)=Σw_n⊗ĥ_n(-t)` | 181-184 | 噪声 | — | ch6_ptr_context | — | — | — | BOOK-EXACT | OK |
| (6-40) `y^{(s)}(j)=ΣΣQ_m(l)x_m(j-l)+w̃` | 181-184 | 接收 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-41) `E(y^{(s)})` | 181-184 | 均值 | — | — | scfde.book_formulas.ch6_ptr_ese_moments | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-42) `Var(y^{(s)})` | 181-184 | 方差 | — | — | scfde.book_formulas.ch6_ptr_ese_moments | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-43)~(6-63) | 181-188 | 扫描已存在；PTR-CSK-IDMA 估计、后验与外层迭代区待完成逐式生产核对 | — | `ch6_csk_idma_detect.m`/`ch6_posterior_signal_estimate.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (6-53) `L^e_{n,m,l}(x_m(j))=2Re{h^*_{n,m}(l)[r_n(j+l)-Eζ_{n,m,l}(j)]}/Var[ζ_{n,m,l}(j)]`（spec 6.3 框定） | 181-188 | ESE 外 LLR | — | `ch6_csk_idma_detect.m`（字典域码字级似然 + 重复码先验；首迭代一致先验下与逐码片 LLR 严格相等，批次4 oracle 锁定） | — | — | test_csk_ese_sic_eq_6_21_65 | ALG-EQUIV | OK |
| (6-64) `x̂_i(j)=P(1)-P(-1)` 软符号 | 185-188 | 软符号 | — | ch6_posterior_signal_estimate | — | — | — | BOOK-EXACT | OK |
| (6-65) `Var(x_i)=1-(E(x_i))²` | 185-188 | 方差 | — | 同上 | — | — | — | BOOK-EXACT | OK |

第6章已知工程偏差：
- ESE damping：主路径 `csk_ese.m` 已改为 α=1（书式无阻尼定义）；α 可配版本拆分为 `csk_ese_damped.m`（cfg.eseDamping，默认 0.58，ENGINEERING）。
- PIC/SIC/ESE 目前共用同一检测核心（flag 区分），需按书式拆独立实现并建立 identity/single-user/two-user oracle（待整改）。

---

## 37 均衡器运行契约审计（2026-08-10，保留）

- 37/37 注册均衡器 ID → 模块映射；模块组：QPSK 17、Turbo 10、CCK 7、CSK 3；
  `run_all_equalizers.m` 独立运行 37 个 ID，37/37 PASS（单次运行，1 帧/ID）。
- 上述 PASS 仅为运行契约证据，不是公式对应性结论；方法级公式分组见本文开头
  “`run_equalizer_app` 公式对应性说明”。
- 第 4 章帧契约：[256 已知训练; 1024 交织编码数据]；BCJR 仅处理 1024 编码数据，返回恰 512 信息位；训练符号不进 BCJR。
- 交织器由场景统一生成（cfg.permutation）；所有第 4 章包装器不调用 rng/randperm。
- 计量：errorBits/totalBits 逐方法整数向量，Clopper-Pearson 95% 区间逐方法报告。
- 可复现性：同 seed 精确复现；结果元数据记录 gitCommit。
- 算法等级不再使用旧 A/B/C 体系（见本文件头部状态定义）。

## 全书复审修复（2026-08-11，保留）

- C 版 IBDFE Γ=(1/N)ΣA_kH_k（补 /N）。
- unified csk-ese BER 用真正 ESE 输出；ch6_repeated_symbol_indices 无重复 randperm。
- C BITF-Turbo 反向复数除法原地覆盖 bug；C BLMS-TF-Turbo residual/estimate 修正；
  C FBLMS/FDDA overlap-save front_tail 索引补 n_f 偏移；C CCK-FDE residual 保留策略。
- DPLL 相位误差改为书中 Im{p(ŝ+q)*}（MATLAB 与 C 统一）。
- PTR/Sub-PTR 线性化时修正匹配滤波窗口对齐 bug：h*(-n) 主抽头经 fliplr 落在位置 L（h 长度），窗口须从 L 开始（此前用 max(|h|) 位置导致 identity 信道全错）；MATLAB 与 oracle 均已回归（test_eq_2_47）。
- C csk_receive_ese 从 MF wrapper 升级为软后验检测。

## 已知缺口（按本方案状态体系重述）

1. **HTFDE**（第3章）：批次1 已将生产路径重写为式 (3-61)/(3-62) 的逐阵元频域合并 + 多通道 DPLL-DFE 后级；旧单一 `H` 分段实现保留于 `ch3_htfde_equalize_engineering.m`。公式与集成均已完成本机验证（公式 12/12、多阵元及 BER 契约 8/8、运行契约 21/21、全量 143/143；seed=42、12 dB 时 0/112）。剩余约束仅为原书实验参数（N/M/P/K、DPLL 增益、μ）PARAM-UNRECOVERABLE。
2. **第3章 (3-86)**：OCR-UNCERTAIN（Σ^{-1} 项），须回原图 book/17.png 复核后锁定。
3. **第3章 (3-92)**：批次6 已按 spec 3.6 盒式实现 MMSE 方差加权（固定 ρ 混合已移除）；**权重排列与 (3-88) 的 R/X_D^0 形式已由 book/17.png 人工确认**；两方差的完整估计公式仍未恢复（当前残差能量定义为 ENGINEERING 估计），须回原图复核后方可解除 **ENGINEERING-BLOCKED**。
4. **CCK Turbo 外码**（第5章）：原书未公开 → PARAM-UNRECOVERABLE，重复码标 ENGINEERING。
5. **ESE damping**（第6章）：主路径需 α=1；α=0.58 拆 `csk_ese_damped.m`。
6. **第4章 (4-56)~(4-58)**：FD-DFE 生产已施加 (4-52) 零均值约束（批次7）；(4-57)/(4-58) 分子分母仍待 book/21.png 人工复核（BLOCKED-SOURCE-REVIEW），复核前 `fd-dfe` 不得标 BOOK-EXACT；FDDA (4-77)~(4-82) 部分已由批次2 完成独立原式验证。
7. **待逐式转录/核对区间**：2-17~2-22、2-38~2-42、3-8~3-26、3-68~3-80、
   4-10~4-15、4-24~4-41、4-50~4-63、5-1~5-7、5-13~5-23、5-30~5-40、
   5-48~5-56、5-62~5-69、5-83~5-96、6-16~6-19、6-26~6-37、6-43~6-63。
   上述区间的图片均已存在于 `book/`，缺的是完整人工转录、变量映射和生产路径验证，不是扫描页。
   **第2章口径说明（批次11 最弱环节复核）**：第2章注册 10 法的必要公式链为
   (2-6)~(2-11) 结构 + 各自盒式递推 —— NLMS (2-16)、RLS (2-23)~(2-25)、
   DPLL (2-34)~(2-37)、多阵元 (2-43)~(2-46)、PTR (2-47)、子带 (2-48)/(2-49) ——
   全部已逐式转录并经独立 oracle 锁定（批次5），故 10 法整体 BOOK-EXACT 成立。
   待转录的 (2-17)~(2-22)（Fast RLS 推导区）与 (2-38)~(2-42)（DPLL 推导余部）是
   推导/分析区间，不包含任何注册方法生产路径所读取的公式；若未来某 ID 改用这些推导
   公式，其认证须重新评估。此处不再使用旧的“2-16~2-25、2-38~2-46”区间表述（与
   逐式表格中 (2-16)/(2-23)~(2-25)/(2-43)~(2-46) 的 BOOK-EXACT 行矛盾）。

## 完成统计（本批基线）

```text
已登记编号公式（第1~6章）：约 200 行（含待转录/待核对区间行）
旧版分章 BOOK-EXACT/ALG-EQUIV 数量：暂不沿用；其中混入了 oracle、未接入生产路径和
                   尚未完成扫描件逐式核对的条目，须在本轮复核结束后重新统计
FAIL：             另见 App 分组中的不能认证方法（HTFDE 已于批次1 重写并通过公式与集成验证，不再计入 FAIL）
ENGINEERING：      ICE 3-92（ρ 加权 LS，待补 MMSE 加权原式）、FDDA γ_f/γ_b=0.97（原文仅 γ<1）、FDDA 跨训练边界逐样本 desired/反馈策略（工程决策，待来源确认）、FDDA 译码驱动包装器连续 hop（重叠拼接规则未确认）、
                   ESE damping（独立 ENGINEERING 算法 csk_ese_damped.m）、CCK Turbo 外码（重复码替代）、
                   CCK-FDE 软值混合/回退、候选裁剪等（Soft-SIC 固定阻尼已于批次4 移除，改后验软均值 SIC）
PARAM-UNRECOVERABLE：第3章 N/M/P 具体值、第5章 3km 信道 taps、CCK Turbo 外码参数、γ_f/γ_b
THEORY-ONLY：      仅纯分析公式：第5章 5-25~5-28 理论错误概率、5-72~5-74 EXIT 互信息（无算法路径，保留登记）。
                   可执行公式（信道模型/检测/均衡/编码/扩频/软估计/迭代更新）一律实现 oracle 或保留未实现于分母；
                   第1章 1-1~1-12、第2章 2-1~2-15、第3章 3-27/3-28/3-37~3-46/3-66/3-67、
                   第6章 6-2~6-7/6-10~6-13/6-38/6-41/6-42 已实现 oracle（BOOK-EXACT（oracle））；
                   第5章 CCK-SM (5-75)~(5-82) 为收发算法公式，标未实现（计入分母），不得 THEORY-ONLY
缺扫描页区间：    0（`book/` 的 48 张四页拼图覆盖正文约 1~188 页）
待逐式转录/核对： 见“已知缺口”第 7 项；不得与扫描缺失混同
未实现（公式已登记）：其余行
```

注：本批新增 `+scfde/+book_formulas/` 公式 oracle 包，将"已扫描到但未实现"的
可执行公式（第1/2/3/6章）实现为数值函数并接入公式测试；纯分析公式
（第5章理论错误概率 5-25~5-28、EXIT 5-72~5-74）标 THEORY-ONLY，从算法验收
分母中剔除（见 BOOK_CONVENTIONS.md scope 规则）。CCK-SM (5-75)~(5-82) 为
收发算法公式，标未实现并计入分母，不得 THEORY-ONLY。每章完成后按上方表格
更新状态。

---

## FDDA 批次2 整改记录（2026-08，commit 见 git log）

- **`fdda-teq`（注册 ID）**：公式结构 (4-74)~(4-82) 已按 book/26.png 人工复核锁定并重写
  `ch4_fdda_teq_core.m`：非对称窗口 `[Nf;N;Nb]`（`L=Nf+N+Nb`）、滑动步长 `N_s<N`
  重叠窗、`W_m^H` 共轭、反馈加号、多阵元求和、单一公共误差、逐阵元标量分母
  `δ+R_m^H R_m`、γ^i 按**内层**编号自 i=1 起、内层权值继承 (4-81)、FGF⁻¹ 约束、
  trace 全量元数据（effectiveParameters/formulaMode/bookExperimentEquivalent）。
  验证（本机复验）：test_fdda_eq_4_74_82 **15/15**、test_fblms_and_curve_benchmark
  **23/23**、运行契约 **21/21**、全量 papers/tests **158/158**、Incomplete 0。
  状态：**公式结构 BOOK-EXACT**；实验复现仍 **PARAM-UNRECOVERABLE**（γ_f/γ_b 数值、
  实验信道、QPSK 调制环境、重叠窗口输出拼接规则均未恢复/未确认），
  `bookExperimentEquivalent=false`。
- **`fdda-dfe-teq`（注册 ID）**：迁移到共享 FDDA 内核（`ch4_fdda_teq_core`），仅反馈来源
  不同（`fddaDfeFeedbackMode`："hard" 默认 / "turbo-soft" 显式工程扩展）；已删除
  `ch4_iterate_fd_blms_turbo` 调用与全部 BLMS 参数读取；`trace.kernel="fdda"`。
  等级 **ALG-EQUIV**（项目组合名，非原书独立方法，不存在独立 BOOK-EXACT 路径）。
- **冻结/工程决策**：重叠窗口（hop<N）最终输出拼接规则 **SOURCE-UNCERTAIN** —— 内核
  重叠模式 `dataOut=[]` 且不驱动译码器；译码驱动包装器固定连续 hop（`trace.hopMode`
  记录，`cfg.fddaHopLength` 暂存不用）；跨训练边界窗口采用逐样本 desired/反馈策略，
  标为显式工程决策，待来源确认。
- **待办（非阻塞）**：`fddaDfeFeedbackMode` 非法值显式拒绝（当前静默回退 "hard"）；
  两个旧语义测试（testFddaEquationDenominatorThreeBlocks / 已更名
  testFddaLegacyBridgeMapsIterationsToInnerRounds）已迁移到新公式基线。

---

## CCK-TR-Diversity 批次3 整改记录（2026-08，commit 见 git log）

- **`cck-tr-diversity`（注册 ID）**：已从“多分支匹配滤波 + 码本判决”（规范 5.5 明令禁止冒充式
  (5-57)）重写为 (5-57)~(5-59) 结构：
  1. `ch5_dfe_detect.m` / `ch5_backward_dfe_detect.m` 新增第三输出 SOFT —— 码片级 DFE 软输出
     （(5-47) 临时判决软输出：观测减去已判支路的状态溢出，本块判决不回灌本块输出；
     时反支路返回原始反序域、行 j 对应反序流块 j）；
  2. `ch5_tr_diversity_restore.m`：按 rev[]=conj(fliplr) 把时反支路恢复到同一时间顺序
     （反序窗口观测原始码片 k=frameLength−8j+1..+8，即原块 N−j+1 的响应尾段；帧头前
     memory 码片无时反窗，置 NaN）；
  3. `ch5_tr_diversity_combine.m`：等权合并 y(k)=(ỹ(k)+ỹ_e(k))/2；NaN 帧头取前向支路单独
     输出（ENGINEERING，trace.headRegionStatus 记录）；
  4. `cck_tr_diversity.m`：(5-58) 在合并软片上按信道模型全码本判决（恒等信道退化为最近码本
     dec[]；(5-59) 临时判决递推 = 两支路 DFE 的逐块状态反馈）。
- 状态：(5-57) 合并结构 **BOOK-EXACT**（扫描件 2026-08-13 复核锁定）；支路码片级软输出
  **ALG-EQUIV**（按 (5-46)/(5-47) 生产模型推导，支路级精确方程待 (5-48)~(5-56) 逐式转录后
  复核）；帧头规则 **ENGINEERING**。禁止的匹配滤波路径不再接入注册 ID
  （`ch5_tr_diversity_detect.m` 保留为参考文件，未删除）。
- 测试：新增 `test_cck_tr_diversity_eq_5_57.m`（等权平均/交换/线性/退化/帧头/软输出负例/
  恢复置位/恢复无尾帧/探测器软输出恒等/前向支路仅消过去溢出 oracle/包装器恒等精确/
  对齐合并接线 oracle/码字→bitTable 汉明位错/RNG 保持/多径良构）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。

---

## 第2章 10 TDE 批次5 整改记录（2026-08，commit 见 git log）

- **`dfe`（(2-6)~(2-11)）**：`known_dfe_core.m` 重写为**静态维纳 DFE** —— 训练段 LS
  求解（经验 `w=R_u^{-1}r_du`，正则化仅在秩亏时由 `\` 触发）、数据段**固定滤波器**
  判决反馈，删除数据段 NLMS 跟踪（(2-6)~(2-11) 无自适应项）；trace 记录
  solveMode/adaptation="none"/decisionDelay/taps。`ptr-dfe`/`subband-ptr-dfe` 后级
  同步受益。
- **`lms-dfe`/`nlms-dfe`/`rls-dfe`**：盒式更新原已一致（(2-14) `lmsStep=2μ`、(2-16)
  δ=1e-5 仅防零除、(2-23)~(2-25) 含 P(0)=δ^{-1}I=100·I），批次5 补 trace
  updateEquation/stepParameters/formulaStatus 与逐符号权重增量 oracle。
- **`dpll-dfe`**：(2-36) `φ=Im{p(d+q)*}` 的 **q 项符号修正**（旧代码
  `Im{p conj(d)}+Im{p conj(feedbackTerm)}` 在 feedbackTerm=−q 下等于
  `Im{p conj(d)}−Im{p conj(q)}`，与盒式不符；改为 `−Im{p conj(feedbackTerm)}`）；
  K2=0.1K1（cfg 默认 0.002/0.020）已记录。
- **`mc-lms-dfe`/`mc-nlms-dfe`/`mc-rls-dfe`**：`multichannel_dfe_core.m` 新增
  **每阵元独立二阶 DPLL**（φ_p=Im{p_p(d+q)*}，输入按 `e^{-jθ̂_p}` 旋转，前馈相干
  求和，公共反馈），更新仍为单一复合向量（LMS/NLMS/RLS）；trace 增加
  phases/frequencies/branchFeedforwardOutputs/inputHistory/parameters。
- **`ptr-dfe`**：(2-47) 多阵元求和 —— `Σ_p h_p*(-t)⊗r_p(t)`、等效信道
  `Σ_p h_p*(-t)⊗h_p(t)`；单支路回退保留。
- **`subband-ptr-dfe`**：(2-48)/(2-49) P 子阵结构 —— 阵元按 round-robin 分
  P=min(numSubbands,M) 组、逐组 y_p、等效信道 g_p=Σ_k h_k*(-n)⊗h_k（无交叉项）、
  后级为 `multibranch_known_dfe_core.m`（P·Nf+Nb 训练 LS 静态维纳 DFE）。
- 测试：新增 `test_ch2_tde_eq_2_6_49.m`（10 项：维纳解 R_u/r_du oracle + 数据段静态
  负例、LMS/NLMS/RLS 手算更新、(2-36) 逐符号符号修正 RED、多阵元每阵元相位递推、
  复合 NLMS 更新、(2-47) 多阵元求和 RED、(2-48)/(2-49) 子阵结构 + |Σh|² 负例、
  10 包装器 RNG/trace 契约）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。

---

## 第3章剩余 6 法 批次6 整改记录（2026-08，commit 见 git log）

- **`mmse-fde`**：(3-71) 逐频点 `H*/(|H|²+σ²)` 与书式 `H*/(Nσ_w²+M_X|H|²)` 的公共正实
  因子 N 由 golden 测试锁定（m_x=1 单位能量），状态 BOOK-EXACT。
- **`zf-fde`**：spec 3.2 严格化 —— `C_k=1/(λH_k)`（λ=1 零多普勒场景），**删除 max(H,eps)
  下限**；|H_k|=0 时严格 ZF 不存在，奇异频点经 `trace.singularBins` **报告**（不再静默
  返回 1/eps）。正则化 `H*/(|H|²+ε)` 为工程扩展，未使用。
- **`sd-ibdfe`/`hd-ibdfe`**：`ch3_ibdfe_equalize.m` 结构按 spec 3.4/3.5 锁定 ——
  C=A/Γ、B=CH−1、unit-gain 断言、首迭代反馈为零退化为 MMSE-FDE；软路径后验均值
  （tanh 闭式 = 4 点 softmax，不硬切）、硬路径取上一整块判决；trace 增加
  feedbackMeans/channelHistory/formulaStatus。A_k 的 H* 形式与 ρ 估计仍
  BLOCKED-SOURCE-REVIEW（(3-86)/(3-87) 待 book/17.png）。
- **`ice-sd-ibdfe`/`ice-hd-ibdfe`**：(3-88)~(3-91) 数据驱动 LS→DFT 截断 + (3-92) 盒式
  MMSE 方差加权（**固定 ρ 线性混合已删除**，spec 3.6 禁止）；更新自第 2 轮起（首轮保持
  训练估计 H，spec 3.7）；两方差取残差能量定义，与下标序同列 **BLOCKED-SOURCE-REVIEW**
  （book/17.png）。训练观测合成与 randn 已删除 → RNG 透明。
- 测试：新增 `test_ch3_fde_ibdfe_eq_3_39_92.m`（8 项：MMSE 公共因子 golden、首迭代退化、
  严格 ZF+奇异报告 RED、IBDFE 结构/unit-gain、硬反馈上一整块、软后验均值 4 点等价+不硬切、
  ICE (3-88)~(3-92) 盒式 oracle、6 包装器 RNG/trace 契约）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。

---

## 第4章剩余 8 法 批次7 整改记录（2026-08，commit 见 git log）

- **`td-turbo`**：(4-24)~(4-31) 盒式逐迭代 LMMSE `x̂=x̄+VH^H(HVH^H+σ²I)^{-1}(y−Hx̄)`，
  V=diag(1−|x̄|²)（旧固定滤波残差形式已替换；预解 timeEqualizer 不再使用）。
- **Turbo 反馈均值**：`ch4_decoder_feedback_frame.m` 的软符号改为译码器**外信息**
  `tanh(L_D^e/2)`（spec 4.3；旧版用后验 LLR，等于把均衡器先验回灌下一轮）；BOOK 路径
  阻尼固定 α=1（cfg.turboDamping 保留为工程参数，所有 turbo 内核不再读取）。
- **`fd-turbo`**：(4-60)/(4-61) 训练段估计 μ̂/σ̂² + (4-42)/(4-43) 高斯外 LLR
  `2Re{μ̂*x̃}/σ̂²`（数据段）；只交换外信息。`ch4_fd_ibdfe_weights` 显式施加 (4-52)
  零均值约束 Σb=0；(4-57)/(4-58) 分子分母仍 BLOCKED-SOURCE-REVIEW（book/21.png）。
- **`tf-turbo`**：(4-43)~(4-49) 结构 —— 单通道 HTF 前馈（(3-61) 判决等价形）+ 时域软
  反馈 g^H x̄（g 取等效信道尾抽头，ALG-EQUIV 抽头设计）；**删除固定 0.5 时/频混合**
  （spec 4.4 禁止）。
- **`bitf-turbo`**：(2-50)~(2-53)/(4.5) —— 正/反两支路**独立状态**（反向支路用反转
  信道），反向输出恢复原时间序后**等权 1/2 合并**；删除旧三重 0.5 混合。
- **`tdda-teq`**：spec 4.8 盒式 —— 未归一化 LMS（μ_f/μ_b）、反馈支路 w_b^H x̄_{n−1}、
  d_a=训练 d/数据 E[x|L_D^e]、**零初值（删除真信道 MMSE 初始化，spec 4.8 禁止）**；
  ID 级 ALG-EQUIV（项目组合名）。
- **`blms-tf-turbo`**：逐频点 BLMS 信道自适应为 ENGINEERING 扩展（spec 4.6 要求严格块
  FBLMS 内核），trace 明示；`fd-dfe` 标 ALG-EQUIV（(4-57)/(4-58) 阻塞）；`fblms` 补
  trace.formulaStatus（内核批次2 已验）。`ch4_iterate_fd_blms_turbo.m` 不再接入注册
  路径（保留为参考文件）。
- 测试：新增 `test_ch4_turbo_eq_4_24_73.m`（8 项：盒式 LMMSE oracle、外信息反馈均值
  RED、μ̂/σ̂² 外 LLR oracle、零均值约束、TDDA 盒式 LMS 复本 oracle、TF 无 0.5 混合
  RED、BiTF (2-53) 等权合并 oracle、8 包装器 RNG/trace/512 契约）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。

---

## 批次 3~7 统一返修记录（2026-08，本机基线 84/94 定向、199/209 全量，10 失败全数关闭）

- **批次3**：`ch5_backward_dfe_detect.m`/`ch5_dfe_detect.m` 的 memory 改为**最后非零
  抽头**（`[1]`/`[1,0]`/`[1,0,0]` 均为零记忆，旧 numel 式 memory 把零填充变成幻影 2 抽头
  跨块状态）；`ch5_expected_block.m` 段起点改为 `numel(state)`；`cck_tr_diversity.m`
  判决零状态同步；blockCount/tailOffset 保持帧约定（numel(channel) 尾样本）不变。
  测试：扰动线性 AbsTol 0→1e-14；新增补零无状态、非零尾必有状态、补零/未补零等价
  三个负向回归。
- **批次4**：`test_csk_ese_sic_eq_6_21_65.m` 的 history 尺寸断言改为逐维
  `size(history,1/2/3)`（MATLAB 省略尾部 singleton）。
- **批次5**：`known_dfe_core.m` 新增 `trace.finalCoefficients`/
  `trace.lastProcessedSymbol`（并补 formulaMode/bookExperimentEquivalent/
  effectiveParameters）；Wiener oracle 改比 finalCoefficients 与最后处理列；DPLL 与
  多阵元 DPLL 测试改为后更新语义 `freq(k)-freq(k-1)==K2·φ(k)`、
  `phase(k)-phase(k-1)==freq(k)+K1·φ(k)`。
- **批次6**：`ch3_ibdfe_equalize.m` 的 (3-88) LS 改为 `Y·conj(X̄)/max(|X̄|²,eps)`
  （book/17.png 确认 R/X_D^0）；(3-92) 分子权重排列与扫描一致不交换，方差定义标
  **ENGINEERING-BLOCKED**；测试 oracle 改用第 2 轮 feedbackMeans(2,:) 与复数 QPSK
  星座 4 点后验均值；MMSE 公共因子 AbsTol 0→1e-13。
- **批次7**：Check Code 清理 —— `ch4_decoder_feedback_frame.m` 删除未用后验变量；
  `ch4_iterate_time_turbo.m`/`ch4_iterate_time_frequency_turbo.m` 未用接口参数加
  `%#ok<INUSD>`（保留公共接口契约）；`test_ch4_turbo_eq_4_24_73.m`（及 ch3 测试）
  加 `%#ok<*DEFNU>`。
- 未提交；须用户本机全量验证（FAIL=0、INCOMPLETE=0）后按批提交，不推送。

---

## 第5章其余 6 法 批次8 整改记录（2026-08，commit 见 git log）

- **`cck-rake`**：spec 5.1 的逐径共轭增益合并已建立决策等价 oracle —— 生产的码片域 MRC
  求和 + 单次码本判决与盒式 `argmax_q Re Σ_l h_l* Σ_n r(n+τ_l)a_q*(n)` 决策等价
  （test_ch5_cck_eq_5_11_80）；恒等无噪声全恢复锁定。trace 补 formulaStatus/
  formulaMode/bookExperimentEquivalent/effectiveParameters。
- **`cck-dfe`**：(5-40)~(5-47) 前向 DFE（当前码字不进当前反馈，码片级临时判决 oracle
  见批次3）；trace 补四项字段，status BOOK-EXACT。
- **`cck-mfb`**：保持 (5-40)~(5-43) CMF 全线性卷积 + 主抽头对齐 + (5-24) 最近码本判决
  结构（MFB 基准接收），CMF oracle 锁定；trace 补四项字段，status BOOK-EXACT。
- **`cck-fde`**：`ch5_fde_cck_detect.m` **删除 0.65/0.35 固定软值混合与残差能量回滚**
  （spec 5.6 明令禁止），反馈改为 (5-81)/(5-82) 指数似然后验均值（不阻尼）；(5-80)
  系数形式仍 ALG-EQUIV；(5-81)/(5-82) 后验反馈由内联复本 oracle 锁定（RED 击穿旧混合）。
- **`cck-bidfe`/`cck-bidfe2`**：初始化与前后向执行次序仍 **BLOCKED-SOURCE-REVIEW**
  （book/31.png、book/32.png），当前执行次序显式标 ENGINEERING（trace）；前/反向 DFE
  子模块在恒等信道下单独认证。
- 测试：新增 `test_ch5_cck_eq_5_11_80.m`（8 项：Rake MRC 等价 oracle、Rake 恒等、DFE
  结构/契约、FDE 后验均值 RED、MFB CMF oracle、BiDFE 阻塞状态+子模块、6 包装器
  RNG/契约、bitTable 汉明语义）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。

---

## 批次 9~12 记录（2026-08）

### 批次11 `tdda-teq` 根因审计（返修完成，待本机复验后提交）

- **根因（理论推导，非调参）**：spec 4.8 盒式为**未归一化 LMS**；`cfg.tdNlmsStep=0.35`
  是 NLMS 时代遗留值，超出联合回归量均值收敛参考 → 发散 → 18 dB 实测 BER≈0.51。修复：
  新增 `cfg.tddaMu`（默认 0.05，ch4_setup 锁定），内核优先使用 tddaMu 并在 trace 记录
  逐轮均值收敛参考与 `trainingErrorPower/dataErrorPower` 拆分。
- **均值收敛参考（P1 返修）**：不再声称 `2/(Nf·E|r|²)`（前馈分量近似被误当整体界）。现按
  **联合回归量** `u_n=[r_n; −x̄_{n−1}]` 计算 `R̂=mean(u u^H)`、`2/λ_max(R̂)`（独立同分布
  近似）；`2/(Nf·mean|r|²)` 仅作 `feedforwardOnlyMeanBound` 保留。18 dB 实测≈0.096，
  故 μ=0.05 约为参考的 0.5 倍（不再声称固定 0.4×）。
- **逐轮重测与语义降级（P1 二轮返修）**：反馈回归量随轮次变化（第 1 轮无先验、第 ≥2
  轮译码外信息），只在第 1 轮测一次不能覆盖后续轮次。现每轮开始时按当前 softSymbols
  重测：`trace.meanConvergenceBound(iteration)` / `trace.withinMeanConvergenceBound
  (iteration)` 为逐轮数组，总体诊断 `meanBoundSatisfiedAllIterations = μ <
  min(参考)`（`trace.minimumMeanConvergenceBound`）。**该量仅为独立性假设下的均值
  收敛参考（理论诊断），不是稳定性保证**：实测 10 dB 夹具参考≈0.8586 时 μ=0.5 仍在
  参考之下却严重发散，实际发散改由误差/权值轨迹（errorPower/trainingErrorPower/
  finalChannel）判定，trace 与文档已按此口径命名与表述。
- **特征值标量化（P0 返修）**：`max(real(eig(R̂)), eps)` 为逐元素比较、返回特征值向量
  导致标量槽赋值失败（11 Incomplete），已改为先 `max(real(eig(R̂)))` 取 λ_max 再算参考，
  并加 Hermitian 清理 `(R̂+R̂')/2`；测试内联 oracle 同步。
- **越界步长动态选取（P0 返修）**：旧测试固定 `μ=0.5`，但该夹具参考≈0.8586，0.5 低于
  参考 → “应当越界”的断言不成立。现按 `μ_over = 1.1 × 实测参考` 动态选取，再验证越界
  标记与发散轨迹。
- **训练误差判定去阈值化（P1 返修）**：无来源的绝对阈值 `<1e-4`（实测末轮训练误差
  ≈7.2e-4）替换为组合判定：相对首轮下降 ≥10×、轮间不恶化（diff ≤ 1e-12）、权值有限且
  非零、无噪声判决精确；迭代数作为显式工程参数记录（effectiveParameters.iterations）。
- **零填充拼接维度（P0 返修）**：帧首零填充窗原为横向拼接（两列向量行数不同 →
  `MATLAB:catenate:dimensionMismatch`），已改纵向拼接，TDDA 内核与两处内联副本同步。
- **边界规则（P1 返修）**：因果输入窗 `r_n` 帧首**零填充**（删除 mod() 循环回绕，
  帧尾编码数据不得泄漏进帧首训练回归量）；新增负测试
  `testFrameTailDoesNotLeakIntoHeadTraining`（线性卷积帧、仅翻转最后编码符号，前 Nf
  样本第 1 轮估计须逐位相同——旧循环窗会被击穿）。
- **第一轮无先验（P1 返修）**：删除 `ch4_initial_soft_feedback`（真信道 MMSE 初始化
  曾把真信道辅助注入数据软目标）；现第 1 轮数据软符号为 0（无 d_a 目标），**仅在训练段
  自适应**，数据段只均衡；第 ≥2 轮用译码器外信息均值全帧自适应。包装器
  `tdda_teq.m` 不再从真信道构造任何输入（Y/Hinitial/Hreference 均传空，NMSE 度量退
  位为 NaN，不进自适应）。
- **认证枚举统一与最弱环节重审（P2 返修）**：废弃非标准值
  `IMPLEMENTED-VERIFIED-FORMULA-CORE` 与 `BOOK-EXACT-STRUCTURE`；认证按**生产链最弱
  必要环节**重新制定（某核心递推/合并公式精确不等于整个注册 ID 可标 BOOK-EXACT）：
  * htfde → **BLOCKED-SOURCE-REVIEW**（(3-61) λ 转写 SOURCE-INCONSISTENT）；
  * sd/hd-ibdfe → **BLOCKED-SOURCE-REVIEW**（(3-86) A_k 未确认）；
  * ice-sd/ice-hd → **BLOCKED-SOURCE-REVIEW**（(3-92) 方差定义未确认）；
  * fd-turbo → **BLOCKED-SOURCE-REVIEW**（(4-57)/(4-58) 未确认）；
  * tf-turbo/bitf-turbo → **ALG-EQUIV**（反馈抽头设计未逐项见于扫描件）；
  * cck-tr-diversity → **ALG-EQUIV**（(5-57) 合并 BOOK-EXACT，但支路软输出
    ALG-EQUIV、帧头 ENGINEERING）；
  * `fdda_dfe_teq.m` 显式覆盖共享内核状态为 ALG-EQUIV/project-combination/false。
  `test_37_registry_audit` 新增枚举合法性 + 逐 ID 期望认证断言（合法枚举五值，
  期望表按最弱环节制定并镜像注册表顺序）。
- 决定性测试 `test_tdda_teq_spec4_8.m`（7 项）：单位信道/双径无噪声精确恢复与对齐、
  训练后权值非零且训练误差收敛（相对下降+轮间不恶化，无绝对阈值）、联合回归量均值
  收敛参考逐轮复现 + 动态越界步长被标记且权值/误差轨迹发散、帧尾不泄漏负测试、加长
  训练不恶化（合成帧）、同 seed 精确复现 + 异 seed 变化；batch-7
  `testTddaBoxedLmsEq4_8` 内联副本同步新语义（tddaMu、零填充窗、无先验）。
- 状态：`tdda-teq` 保持 **ALG-EQUIV / project-combination / bookExperimentEquivalent
  =false**；μ 为 ENGINEERING 参数（进入 effectiveParameters 与 trace），不得冒充原文
  参数；曲线评级（0:2:18 dB、多帧、≥3 seed、Clopper-Pearson）待本机执行后录入。
- 其余方法曲线评级使用 `curve_benchmark.m`（不外推、NaN 保留、逐方法覆盖率分母、
  最差方法保守总等级），待本机执行。

### 批次9 `csk-matched-filter`

- **状态：已由用户本机复验通过（批次9 测试 8/8、ESE 回归 8/8、全量 233/233，提交
  87c5b4e）**；本机首测 5/8（根序列主峰
  1/G≠1、相关方向、恒等测试发射字典不匹配），已按实测修正：
  1. **根序列严格 ±1**（删除 `root/‖root‖`，(6-5)/(6-7) 的 1/G 相关主峰 = 1；字典
     域行能量归一由 `ch6_apply_circular_channel` 的 scale 精确吸收，三 CSK 方法决策
     不变，输出码片回到书式 ±1 字母表）；
  2. **(6-9) 相关方向**保留接收侧共轭（与书式一致），测试经
     `mod(−(peak−1), G)` 映射回发送移位（(6-10) 与 (6-11)/(6-12) 的方向矛盾仍
     SOURCE-INCONSISTENT，已记录）；
  3. **恒等测试**发射端改用与接收端相同的用户 1 字典 `dicts{1}(idx,:)`，输出按基码本
     `book(idx,:)` 比较（包装器输出基码本判决契约明确）。
- 生产为信道匹配字典相关（(6-6)~(6-12)/(6-16)~(6-19) 结构，ALG-EQUIV；恒等信道下
  与 (6-9) 循环相关峰决策等价）；(6-16)~(6-19) 仍 TRANSCRIPTION-PENDING；实验复现
  PARAM-UNRECOVERABLE。

### 批次10 37 法统一入口与注册表审计

- **状态：已由用户本机复验通过（批次10 测试 5/5、四场景 17/10/7/3 全跑通、全量
  233/233，提交 169e038）**；本机首测 3/4 + 1 Incomplete
  （`unique()` 不接受函数句柄 cell；四字段元数据缺 12 个方法），已按实测修正：
  1. 句柄唯一性改经 `func2str` 名字比较；模块文件存在性改用
     `which(func2str(handle))` 解析（`functions(handle).file` 对包函数句柄返回空）；
  2. **规则6 四字段补齐全部 37 法**：`mmse-fde`/`zf-fde`、`td-turbo`/`fd-dfe`/
     `fd-turbo`/`tf-turbo`/`bitf-turbo`/`blms-tf-turbo`/`fblms`/`tdda-teq`、
     `csk-soft-sic`/`csk-ese` 及 `multibranch_known_dfe_core` 补
     formulaMode/bookExperimentEquivalent/effectiveParameters；
  3. 新增 `testAllScenarioTracesRecordRule6Fields`：四场景银行全部 trace 逐方法
     验证四字段存在与类型（本机复验全 PASS）；
  4. string array 输入用例改为两个同场景 ID 的数组（消除单元素方括号 NBRAK2 提示
     并真正覆盖多元素路径）。
- 统一入口：单 string / cell / string array 三种输入解析一致；`results.equalizerId`
  与逐方法 `results.formulaStatus`（缺失显式 `NOT-RECORDED`）；`ber == errorBits./
  totalBits` 精确；零误码 Clopper-Pearson 上界 `1-(α/2)^{1/n}` 精确断言。
- 模块化：按批 10.3 要求未做大规模搬迁；已知重复实现（各 CCK 包装器内的
  `cck_indices_to_symbols` 本地副本、章节套件脚本中的本地检测副本）记录为待收敛项，
  仅在职责冲突时拆分。
- **注意**：`tdda-teq` 本机单帧 BER≈0.512（近随机），smoke PASS 不构成算法正确性
  证据，曲线评级阶段须单独审计（批 11）。

### 批次11 曲线复现评级

- 评级器 `curve_benchmark.m` 已满足批 11 全部规则（无外推、NaN 保留、逐方法覆盖率
  分母、最差方法保守总等级、无参考→覆盖率 0→等级 D）；评级执行与数字化参考数据须在
  用户本机运行（源码提交后重跑并记录 gitCommit，产物单独提交）。
- 数字化数据文件必须记录 source page/figure、digitizer、date、modulation、
  channel、frame length、iteration count、known mismatch（见 README 约定）。

### 批次12 文档

- 新建 `SOURCE_REVIEW_REQUEST.md`：5 项人工复核请求（book/21.png (4-57)/(4-58)；
  book/31.png+32.png BiDFE 初始化/次序；第3章 (3-86) A_k；book/17.png (3-92) 方差
  定义（权重排列已确认不再列为未知）；未公开参数清单）。
- 本文件各批次记录、行状态与 App 分组已同步；最终每方法四维状态
  （公式实现/实验参数/信道恢复/曲线复现）见各章表格与批次记录，禁止概括为
  “37 种全部严格复现”。

---

## CSK Soft-SIC / ESE 批次4 整改记录（2026-08，commit 见 git log）

- **`csk-soft-sic`（注册 ID，spec 6.2：派生实现，最多 ALG-EQUIV）**：`ch6_soft_sic_detect.m`
  重写 —— 按接收功率排序（`userOrder`，能量降序）的软串行 SIC：同一轮内按序处理，残差
  `r_res = r − Σ_{p≠q} H E[x_p]` 全部取自各用户**后验软均值**（spec 6.2 允许的抵消来源）；
  码片方差按 (6-25) 用**后验二阶矩** `p·|dict|² − |p·dict|²`（旧 `mean(|dict|²,1)` 均值近似
  已替换，与 `ch6_ese_residual` 一致）；**固定 0.45/0.55 阻尼已删除**（spec 6.2 明令禁止），
  `soft = updated`。包装器 trace：`damping=1`、`userOrder`、`formulaStatus="ALG-EQUIV"`。
- **`csk-ese`（注册 ID，spec 6.3）**：BOOK 路径已为 α=1（`ch6_csk_idma_detect(..., damping=1)`），
  trace 增加 `damping=1/formulaStatus/eseDomain`；α<1 仍只在 `csk_ese_damped`（ENGINEERING）。
  (6-22)/(6-24)/(6-25)/(6-64)/(6-65) 矩运算 BOOK-EXACT；(6-53) 盒式 LLR 以字典域码字级似然
  + 重复码先验实现（首迭代一致先验下与逐码片 LLR 严格相等）→ ALG-EQUIV。
- **RNG 透明性**：`ch6_select_csk_root.m` 由全局 `rng(2024,...)` 改为局部
  `RandStream("mt19937ar","Seed",2024)`（序列不变、码本不变，但不再重置调用方全局 RNG）。
- 测试：新增 `test_csk_ese_sic_eq_6_21_65.m`（ESE 残差/方差手算 oracle、(6-53) 手算 LLR、
  (6-64)/(6-65) 反馈统计、单用户退化、双用户串行 SIC 全量 oracle（RED 击穿旧固定阻尼）、
  包装器 trace/无阻尼/RNG 保持、damped 工程变体）。
- 本沙箱 MATLAB 无法启动：上述测试须在用户本机执行（见批次报告命令），验证前不得标
  “已通过”，未提交。
