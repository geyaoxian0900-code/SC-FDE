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
| 第2章 | lms-dfe、nlms-dfe、rls-dfe、dpll-dfe、ptr-dfe | dfe、mc-lms-dfe、mc-nlms-dfe、mc-rls-dfe、subband-ptr-dfe | — |
| 第3章 | mmse-fde、zf-fde、sd-ibdfe、hd-ibdfe | ice-sd-ibdfe、ice-hd-ibdfe | —（htfde 已于批次1 重写为逐阵元 (3-61)/(3-62)，IMPLEMENTED-VERIFIED-FORMULA-CORE / INTEGRATION-VERIFIED） |
| 第4章 | fd-turbo、fblms | td-turbo、tf-turbo、bitf-turbo、fdda-teq | fd-dfe、blms-tf-turbo、tdda-teq、fdda-dfe-teq |
| 第5章 | cck-rake、cck-mfb | cck-dfe、cck-tr-diversity、cck-fde | cck-bidfe、cck-bidfe2 |
| 第6章 | csk-matched-filter | csk-ese | csk-soft-sic |

数量口径：核心递推可对应 14，部分对应/工程近似 15，明显不能认证 8。该分组是当前代码快照的
审计结论，不得改写成“14 种完整原文复现”。已确认的主要原因包括：

- QPSK/CCK 场景把同一 `received` 复制为两行 `branches`，不构成独立阵元观测；
- 第4章统一入口使用 BPSK，而原书相应 FDDA 实验使用 QPSK 和多阵元数据；
- HTFDE 已于批次1 重写为式 (3-61)/(3-62) 的逐阵元 `C_{m,k} R_{m,k}` 合并 + 多通道 DPLL-DFE 后级（IMPLEMENTED-VERIFIED-FORMULA-CORE / INTEGRATION-VERIFIED）；
- FDDA 式 (4-77) 的 `W_m^H`、反馈项符号、多阵元求和及内层迭代仍需独立原式验证；
- BiDFE 式 (5-57) 的两个滤波器输出等权合并未接入生产路径；
- 第6章 App 默认单用户，Soft-SIC 另含书中未定义的 0.55 阻尼。

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
| (2-6) `d̂_k=Σf_i^*r_{k-i}-Σb_j^*d̂_{k-j}` | 17-18 | DFE 结构；反馈为负 | — | `known_dfe_core.m`/`conventional_dfe.m` | — | — | test_modular_pipeline | ALG-EQUIV | OK |
| (2-7) `u_k=[d(k-N)…r(k+L-1)]^T` 输入向量 | 17-18 | DFE 输入 | — | `adaptive_dfe_core.m` | — | — | — | ALG-EQUIV | OK |
| (2-8) `w_k=[h(1)…f(-L+1)]^T` 权向量 | 17-18 | 权重结构 | — | `adaptive_dfe_core.m` | — | — | — | ALG-EQUIV | OK |
| (2-9) `e(k)=d(k)-w_n^H u_k` | 19-20 | 误差 | — | `adaptive_update.m` | — | — | — | ALG-EQUIV | OK |
| (2-10) `J(w)=E\ | e_k\ | ²` | 19-20 | MSE 目标 | scfde.book_formulas.ch2_mse | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-11) `w^o=R_u^{-1}R_{du}` 维纳解 | 19-20 | 统计最优 | — | — | scfde.book_formulas.ch2_wiener | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-12) `w(n+1)=w(n)-μ∇_w J` | 19-20 | 梯度下降 | — | `adaptive_update.m` | — | — | — | ALG-EQUIV | OK |
| (2-13) `∇_w J=-2E[e^*(n)u(n)]` | 19-20 | 梯度 | — | — | scfde.book_formulas.ch2_lms_gradient | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-14) `w(n+1)=w(n)+2μe^*(n)u(n)` LMS | 19-20 | 系数更新 | 2μ 显式 | `lms_dfe.m`/`adaptive_update.m` | — | — | — | ALG-EQUIV | OK |
| (2-15) `0<μ<1/λ_max` | 19-20 | 收敛界 | — | — | scfde.book_formulas.ch2_lms_convergence_bound | — | test_book_formulas_ch2 | BOOK-EXACT | OK |
| (2-16)~(2-25) | 21-24 | 扫描已存在；RLS/NLMS/Fast RLS 推导区待逐式转录与生产核对 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (2-26) `r(k)=[r(k)…r(k+N-1)]^T` | 25-26 | 前馈输入 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-27) `p_k=a^H r(k)e^{-jθ_k}` | 25-26 | 相位补偿 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-28) `d⃗(k)` 反馈输入 | 25-26 | 判决序列 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-29) `q_k=b^H d⃗(k)` | 25-26 | 反馈输出 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-30) `d⃗_k=p_k-q_k=w^H u(k)` | 25-26 | 复合结构 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-31) `e_k=d_k-d⃗_k` | 25-26 | 误差 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-32) `∂MSE/∂a=-2E{r e_k^* e^{-jθ_k}}` | 25-26 | 前馈梯度 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-33) `∂MSE/∂b=-2E{d⃗ e_k^*}` | 25-26 | 反馈梯度 | — | `dpll_dfe.m` | — | — | — | ALG-EQUIV | OK |
| (2-34) `∂MSE/∂θ=-2Im{E{p_k(d_k+q_k)^*}}` | 25-26 | 相位梯度 | — | `dpll_dfe.m` | — | — | — | BOOK-EXACT | OK |
| (2-35) `θ̂_{k+1}=θ̂_k+K_1 φ_k+K_2 Σ_{i=1}^k φ_i`（φ 为相位误差，非均衡误差 e；K_2=0.1K_1 见 (2-37)） | 25-26 | DPLL 递推 | — | `dpll_dfe.m`（phaseError 路径） | — | — | test_eq_2_36/testLoopConvergesToRotation | BOOK-EXACT | OK |
| (2-36) `φ_l=Im{p_l(d_l+q_l)^*}` | 25-26 | 相位检测 | — | `dpll_dfe.m` | — | — | test_eq_2_36 | BOOK-EXACT | OK |
| (2-37) `K_I2=0.1·K_P2` | 25-26 | 环参数 | — | cfg.KI2rel | — | — | — | BOOK-EXACT | OK |
| (2-38)~(2-46) | 29-32 | 扫描已存在；PTR-DFE 推导区待逐式转录与生产核对 | — | — | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (2-47) `r̂(t)=Σh_i'(-t)⊗r_i(t)=Q(t)⊗s(t)+ς(t)` | ~29-30 | PTR 等效信道 | 线性卷积 | `ptr_dfe.m`（线性主路径） | — | — | test_eq_2_47 | BOOK-EXACT | OK |
| (2-48) `y_p(n)=Σh̃_p^*(-k)⊗r_k(n)` | ~29-30 | 子阵 PTR | 线性卷积 | `subband_ptr.m`（线性主路径） | — | — | test_eq_2_47 | BOOK-EXACT | OK |
| (2-49) `d̂=Σa_n^H y_p-b^H d` | ~29-30 | Sub-PTR-DFE | — | `subband_ptr_dfe.m` | — | — | — | ALG-EQUIV | OK |
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
| (3-61) `C_{m,k}=(\tilde H^H\Phi^H\Phi\tilde H+\sigma^2I)^{-1}\tilde H^H\Phi^H`，`\Phi=\lambda I` 时为 `(\|λ\|²Ĥ^HĤ+σ²I)^{-1}λ*Ĥ^H`（逐阵元） | 59-60 | 频域 MMSE | — | `ch3_htfde_equalize.m`（批次1 重写） | — | — | test_htfde_eq_3_61_62 | SOURCE-INCONSISTENT（转写第二行 λ 似无共轭；Resolution：跟随第一行矩阵式与 (3-44)，实现 \|λ\|² 分母、λ* 分子）；生产 IMPLEMENTED-VERIFIED-FORMULA-CORE / INTEGRATION-VERIFIED（12/12 PASS，本机复验） | OK |
| (3-62) `x_m=F^H Σ_{k=1}^{K} C_{m,k}R_{m,k}` 子阵频域合并输出 | 59-60 | 频域合并 | 1/N（IFFT） | `ch3_htfde_equalize.m`（批次1 重写） | — | — | test_htfde_eq_3_61_62 | IMPLEMENTED-VERIFIED-FORMULA-CORE / INTEGRATION-VERIFIED（12/12 PASS，本机复验） | OK |
| (3-64) `X̂^l=(C^l)^H R-(B^l)^H X̂^{l-1}` | 63-64 | IBDFE 迭代 | — | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-65) `M_Xk=E\ | X_k\ | ², M_X̂k=E\ | X̂_k\ | `BOOK_CONVENTIONS` | — | — | — | BOOK-EXACT | OK |
| (3-66) `r_{Xk,X̂k*}=E[X_k X̂_k^*]` | 63-64 | 相关 | — | — | scfde.book_formulas.ch3_ibdfe_corr | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-67) `J^IB=(1/N)ΣE\ | x̂_k-x_k\ | ²` | 63-64 | MSE | scfde.book_formulas.ch3_ibdfe_mse | — | test_book_formulas_ch3 | BOOK-EXACT | OK |
| (3-68)~(3-80) | 65-66 | 扫描已存在；IBDFE 权重推导区待完成逐式转录及归一化核对 | — | `ch3_ibdfe_equalize.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (3-81) `B_k'=C_k'H_k^*-1` | 67-68 | 反馈系数 | — | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-82) `β'=(1/N)ΣC_k'H_k^*` 初值 | 67-68 | 增益 | 1/N | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-83) `β'` 后续迭代=1 | 67-68 | 迭代规则 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (3-84) `C_k'=A_k'/Γ` | 67-68 | 前馈归一化 | — | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-85) `B_k'=C_k'H_k^*-1` | 67-68 | 反馈 | — | — | — | C IBDFE | test_eq_3_87 | BOOK-EXACT | OK |
| (3-86) `A_k'=(H_k')^*ΓΣ^{-1}/(\ | H_k'\ | ²ΓΣ^{-1}+Nσ_w²)` | 67-68 | — | — | C IBDFE | test_eq_3_87 | OCR-UNCERTAIN | N/A |
| (3-87) `Γ=(1/N)ΣA_k'H_k^*` | 67-68 | 归一化因子 | **1/N** | — | — | C IBDFE（2026-08-11 已补 /N） | — | BOOK-EXACT | OK |
| (3-88) `H_LS'=R/X_D^0=H+W/X_D^0=H+e'` | 67-68 | LS 信道估计 | — | `ch3_estimate_channel_ls.m` | — | — | test_eq_3_88 | BOOK-EXACT | OK |
| (3-89) `h_est,k^j=Σ_{n=0}^{N-1}H_LS,n^j e^{+j2πkn/N}=h_k+e_k^j`（正文"将 H_LS 进行 IDFT 变换"；原式无 1/N，而 MATLAB ifft 固有 1/N，标度差待 (3-88)~(3-91) 全链 golden 定案） | 67-68 | 时域变换（IDFT 方向） | 1/N 待定 | `ch3_ibdfe_equalize.m` 内 ifft | — | — | — | SOURCE-NORMALIZATION-REVIEW | N/A |
| (3-90) `h_est'` 前 L 抽头加窗 | 67-68 | 稀疏化 | — | `ch3_estimate_channel_ls.m`（L 截断） | — | — | test_eq_3_90 | BOOK-EXACT | OK |
| (3-91) `H_est'=DFT(h_est')` | 67-68 | 回频域 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (3-92) `H'=(H*σ_H²+H_est'σ_est…)/(…)` MMSE 加权 | 67-68 | 信道合并 | — | ICE 用 ρ 加权 LS（工程） | — | — | — | ENGINEERING | OK |

### 第3章算法状态（模板章验收）

算法 | 状态 | 说明 | OK |
|---|---|---|
MMSE-FDE（`mmse_fde.m`） | ALG-EQUIV | `H*/(\ | H\ | ²+σ²)` vs 书式 `H*/(Nσ_w²+M_x\ | H\ | ²)` 差正实因子 M_x，判决等价；λ 双形式断言见 test_eq_3_71 | OK |
IBDFE（`sd_ibdfe.m`/`hd_ibdfe.m`/`ch3_ibdfe_equalize.m`） | BOOK-EXACT | 3-64/3-65/3-82/3-84/3-85/3-87 全闭环；unit-gain 断言 `\ | mean(CH)-1\ | <1e-10` | OK |
HTFDE（`htfde.m`） | IMPLEMENTED-VERIFIED-FORMULA-CORE / INTEGRATION-VERIFIED | 批次1：逐阵元 (3-61)/(3-62) 前端 + 多通道 DPLL-DFE 后级；本机复验：公式测试 12/12、多阵元及 BER 契约 8/8、运行契约 21/21、全量 143/143 均 PASS；seed=42、12 dB 时 0/112、BER=0（训练区不计入）；BOOK 模式要求显式 P/K，缺失抛 `SCFDE:BookParameterUnavailable`；原书实验参数（N/M/P/K、DPLL 增益、μ）PARAM-UNRECOVERABLE，不得宣称原文实验复现 | OK |
ICE（`ice_sd_ibdfe.m`/`ice_hd_ibdfe.m`） | ENGINEERING（partial） | ENGINEERING | OK |
ZF-FDE | ALG-EQUIV | 书式未扫描到独立编号（3-42~3-44 区域） | OK |

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
| (4-24)~(4-41) | 85-86 | 扫描已存在；时域 LMMSE Turbo 区待逐式转录，`td-turbo` 暂按部分对应处理 | — | `ch4_iterate_time_turbo.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (4-42) `p(x̂_k | x_k=s_i)=1/(πσ̂²)e^{- | x̂-μ̂s_i | ²/σ̂²}` | ch4_normalized_mmse | — | — | — | BOOK-EXACT | OK |
| (4-43) `L^E(c_{k,j})` 均衡器外信息 | 87-88 | 外信息 | — | ch4_iterate_*_turbo | — | — | — | BOOK-EXACT | OK |
| (4-44) `P(c=0)=1/(1+e^{L^D})` | 87-88 | 译码先验 | — | ch4_log_combine | — | — | — | BOOK-EXACT | OK |
| (4-45) `P(c=1)=e^{L^D}/(1+e^{L^D})` | 87-88 | 译码先验 | — | 同上 | — | — | — | BOOK-EXACT | OK |
| (4-46) `L^D` 译码器外信息 | 87-88 | 外信息 | — | ch4_bcjr_siso_decode | — | — | — | BOOK-EXACT | OK |
| (4-47) `x̄_k=E(x_k)=Σs_i P(x_k=s_i)` 软符号 | 87-88 | 软符号 | — | ch4_initial_soft_feedback | — | — | — | BOOK-EXACT | OK |
| (4-48) `P(x_k=s_i)=ΠP(c_{k,j}=s_{i,j})` | 87-88 | 比特独立 | — | ch4_probability_posteriors | — | — | — | BOOK-EXACT | OK |
| (4-49) `x̄_n=Σ(f_l^H)^*y_{n+l}^H-(g_l)^T x̄_n` | 87-88 | 时域软反馈 | — | ch4_iterate_time_turbo | — | — | — | OCR-UNCERTAIN | N/A |
| (4-50)~(4-63) | 89-90 | 扫描已存在；FD-DFE/FD-Turbo 权重区待逐式转录，`fd_dfe_design` 未接入 `fd-dfe` 生产路径 | — | `ch4_fd_ibdfe_weights.m`/`ch4_frequency_dfe_baseline.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (4-64) `y'_u,y_u,y'_d,r_u` 块定义 | 103-106 | BLMS 块 | N、N_v | — | — | C FBLMS | test_fblms_and_curve_benchmark | BOOK-EXACT | OK |
| (4-65) `R_u(k)=F r_u(k)` | 103-106 | 频域变换 | 无 1/N | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-66) `X̂(k)=ΣW_n⊙R_n` | 103-106 | 频域滤波 | ⊙ | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-67) `x̂(k)=F^H X̂(k)` | 103-106 | 回时域 | 1/N | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-68) `T=[0 I 0]` 块提取 | 103-106 | 投影 | — | fblms.m | — | — | — | OCR-UNCERTAIN | N/A |
| (4-69) `x̃(k)=T x̂(k)` | 103-106 | 有效块 | — | fblms.m | — | — | — | BOOK-EXACT | OK |
| (4-70)~(4-73) | 105-106 | 扫描已存在；BLMS 标量能量分母、时域约束与误差块公式可直接核对 | — | `fblms_equalizer.m` | — | — | `test_fblms_and_curve_benchmark` | BOOK-EXACT | OK |
| (4-74) `y_in,y_re,y_out,r_m` | 107-110 | FDDA 块 | N_c、N_f | ch4_fdda_teq_core | — | — | — | BOOK-EXACT | OK |
| (4-75) `x̃(k)=[x̄;x̂;x̃]` 反馈窗口 | 107-110 | 反馈构造 | 中间块置零 | ch4_fdda_feedback_block | — | — | — | BOOK-EXACT | OK |
| (4-76) `R_m=Fr_m; X̃=F x̃` | 107-110 | 频域 | 无 1/N | ch4_fdda_teq_core | — | — | — | BOOK-EXACT | OK |
| (4-77)~(4-80) | 108-109 | 扫描已存在；原式含 `W_m^H`、多阵元求和及反馈项，当前单路实现的共轭/符号约定尚无独立等价证明 | — | `ch4_fdda_teq_core.m` | — | — | 现有测试复用生产符号约定 | SOURCE-NORMALIZATION-REVIEW | N/A |
| (4-81) 外迭代继承 W/B | 110 | 迭代规则 | — | `ch4_fdda_teq_core.m` | — | — | — | BOOK-EXACT | OK |
| (4-82) 块内更新 W/B | 110 | 自适应 | 标量分母与 γ 指数已实现；反馈符号/共轭/内层迭代仍待独立核对 | `ch4_fdda_teq_core.m` | — | — | 生产同构测试，不足以单独认证原式 | SOURCE-NORMALIZATION-REVIEW | N/A |

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
| (5-30)~(5-40) | 129-132 | 扫描已存在；误码界、Rake 与 DFE 区待逐式转录，候选裁剪实现按工程近似处理 | — | `ch5_rake_detect.m`/`ch5_dfe_detect.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-41) `x_i=Σh_l b_{i-l}` | 133-136 | 接收 | 线性卷积 | ch5_expected_block | — | — | — | BOOK-EXACT | OK |
| (5-42) `x'_k=x_n` CMF+CIR | 133-136 | 处理链 | — | ch5_matched_filter_detect | — | — | — | BOOK-EXACT | OK |
| (5-43) `μ_k=Σh_l^* n_{k+l}` 噪声项 | 133-136 | 噪声 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-44)/(5-45) `y_k` 含前后 ISI | 133-136 | 检测输出 | — | ch5_candidate_scores | — | — | — | BOOK-EXACT | OK |
| (5-46) `â_k=y_k-Σx'ã-Σx'â` 双向消除 | 133-136 | DFE 判决 | — | ch5_dfe_detect/ch5_backward_dfe_detect | — | — | — | BOOK-EXACT | OK |
| (5-47) `ã_k=y_k-Σx'â` 后置 ISI | 133-136 | 临时判决 | — | ch5_dfe_detect | — | — | — | BOOK-EXACT | OK |
| (5-48)~(5-56) | 134-136 | 扫描已存在；BiDFE-1/BiDFE-2 与时反分集区待逐式转录，App 分支复制不构成独立接收分集 | — | `ch5_backward_dfe_detect.m`/`ch5_tr_diversity_detect.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (5-57) `y(k)=(ỹ(k)+ỹ_e(k))/2=a(k)(â(k)+μ_e(k))/2`（两个 BiDFE 输出等权合并，2026-08-13 回 book/32.png 复核） | 137-140 | 分集合并 | 1/2 | —（待建 BiDFE-1/BiDFE-2 合并函数；原挂 ch5_tr_diversity_detect 为多分支匹配滤波+码本判决，非本式，已移除） | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (5-58) `â(k)=dec[y(k)]` | 137-140 | 判决 | — | — | — | — | — | BOOK-EXACT | OK |
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
| (5-80) `X̂_k^{(i)}=(C^{(i)})^H Y_k-(B^{(i)})^H X̃^{(i)}` | 145-148 | MIMO-IBDFE | — | ch5_fde_cck_detect | — | — | — | ALG-EQUIV | OK |
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
| (6-24)/(6-25) 干扰分解 ζ | 177-180 | 干扰项 | — | ch6_ese_residual | — | — | — | OCR-UNCERTAIN | N/A |
| (6-26)~(6-37) | 178-180 | 扫描已存在；ESE/IDMA 均值、方差与 LLR 更新区待完成逐式生产核对 | — | `ch6_csk_idma_detect.m`/`ch6_ese_residual.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
| (6-38) `Q_m(t)=Σh_{m,n}⊗b̂_n(-t)` PTR 等效信道 | 181-184 | PTR | 线性卷积 | ch6_ptr_context | — | — | — | BOOK-EXACT | OK |
| (6-39) `w̃_i(t)=Σw_n⊗ĥ_n(-t)` | 181-184 | 噪声 | — | ch6_ptr_context | — | — | — | BOOK-EXACT | OK |
| (6-40) `y^{(s)}(j)=ΣΣQ_m(l)x_m(j-l)+w̃` | 181-184 | 接收 | — | — | — | — | — | EXECUTABLE-UNIMPLEMENTED | OK |
| (6-41) `E(y^{(s)})` | 181-184 | 均值 | — | — | scfde.book_formulas.ch6_ptr_ese_moments | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-42) `Var(y^{(s)})` | 181-184 | 方差 | — | — | scfde.book_formulas.ch6_ptr_ese_moments | — | test_book_formulas_ch6 | BOOK-EXACT | OK |
| (6-43)~(6-63) | 181-188 | 扫描已存在；PTR-CSK-IDMA 估计、后验与外层迭代区待完成逐式生产核对 | — | `ch6_csk_idma_detect.m`/`ch6_posterior_signal_estimate.m` | — | — | — | TRANSCRIPTION-PENDING | N/A |
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
3. **第3章 (3-92)**：书中 MMSE 加权合并未实现，ICE 现用 ρ 加权 LS（ENGINEERING）。
4. **CCK Turbo 外码**（第5章）：原书未公开 → PARAM-UNRECOVERABLE，重复码标 ENGINEERING。
5. **ESE damping**（第6章）：主路径需 α=1；α=0.58 拆 `csk_ese_damped.m`。
6. **第4章 (4-56)~(4-58)/(4-77)~(4-82)**：扫描已存在；需对 FD-DFE 的实际生产调用，以及 FDDA 的共轭、反馈符号、多阵元求和、内层迭代建立独立原式测试。
7. **待逐式转录/核对区间**：2-16~2-25、2-38~2-46、3-8~3-26、3-68~3-80、
   4-10~4-15、4-24~4-41、4-50~4-63、5-1~5-7、5-13~5-23、5-30~5-40、
   5-48~5-56、5-62~5-69、5-83~5-96、6-16~6-19、6-26~6-37、6-43~6-63。
   上述区间的图片均已存在于 `book/`，缺的是完整人工转录、变量映射和生产路径验证，不是扫描页。

## 完成统计（本批基线）

```text
已登记编号公式（第1~6章）：约 200 行（含待转录/待核对区间行）
旧版分章 BOOK-EXACT/ALG-EQUIV 数量：暂不沿用；其中混入了 oracle、未接入生产路径和
                   尚未完成扫描件逐式核对的条目，须在本轮复核结束后重新统计
FAIL：             另见 App 分组中的不能认证方法（HTFDE 已于批次1 重写并通过公式与集成验证，不再计入 FAIL）
ENGINEERING：      ICE 3-92（ρ 加权 LS，待补 MMSE 加权原式）、FDDA γ_f/γ_b=0.97（原文仅 γ<1）、
                   ESE damping（独立 ENGINEERING 算法 csk_ese_damped.m）、CCK Turbo 外码（重复码替代）、
                   CCK-FDE 软值混合/回退、Soft-SIC 阻尼及候选裁剪等
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
