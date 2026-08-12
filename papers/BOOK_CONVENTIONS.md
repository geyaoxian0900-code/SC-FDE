# BOOK CONVENTIONS — 全项目数学约定（冻结）

本文件锁定全项目统一数学定义。任何算法代码、测试、audit 都不得偏离。
偏离即为 FAIL；只有本书未公开的参数可以标 PARAM-UNRECOVERABLE。
本约定作为第一批工作冻结，后续章节（2/4/5/6）以此为准，不再允许
各 chapter suite 自行解释 (M_x)、(1/N)、时域/频域归一化。

状态体系（全项目唯一，双枚举）：

```text
FormulaStatus（公式状态，每行一个）:
  BOOK-EXACT                原公式、变量定义、归一化、初值、边界、迭代规则、公开参数全部一致
  ALG-EQUIV                 实现形式不同，但有代数证明 + golden vector 证明严格等价
  SOURCE-INCONSISTENT       扫描件清楚，但书内不同公式互相矛盾（如 (4-22)、(6-10)）；
                            须注明 Resolution（跟随哪一式）
  SCAN-MISSING              原书页码不在 book/ 扫描件内，公式未转写
  OCR-UNCERTAIN             转写存疑，须回原图核对
  EXECUTABLE-UNIMPLEMENTED  公式已转写且可执行，但无实现（计入分母）
  ENGINEERING               damping、近似概率、替代编码、经验缩放等（显式拆分）
  THEORY-ONLY               纯分析公式（错误概率积分/EXIT/容量上界），剔除于算法分母

ParameterStatus（参数状态，每行一个）:
  OK                        原书参数可用
  PARAM-UNRECOVERABLE       原书未公布某实验参数（公式 ✅ / 原图 ❌）
  N/A                       该行无参数概念（如理论/缺扫行）
```

规则：

1. 原书有编号公式但 `FORMULA_TRACEABILITY.md` 中没有记录 = **未复现**。
2. ENGINEERING 处理全部显式拆成 `*_engineering` / `*_approx` / `*_damped`，
   不得混在主路径里；主路径只允许书中公式。
3. 参数缺失写 `NaN`，运行时抛 `SCFDE:BookParameterUnavailable`，不许猜。
4. `PARAM-UNRECOVERABLE` 不是公式状态；公式正确性与参数缺失正交。

---

## 1. FFT / DFT

全项目统一（与 MATLAB `fft`/`ifft` 一致，前向无 1/N）：

```text
X_k = sum_{n=0}^{N-1} x_n e^{-j2pi kn/N}         (forward, NO 1/N)
x_n = (1/N) sum_{k=0}^{N-1} X_k e^{+j2pi kn/N}    (inverse, 1/N)
```

推论（非归一化 DFT）：

```text
sum_k |X_k|^2 = N * sum_n |x_n|^2          (Parseval)
```

来源：第3章块模型 `r = H s + w`，`R = F r`（书式 3-37~3-38 区域）。
注意：书页 55-58 转写提到 `F^H F = I`（对应酉归一化 DFT 的写法），
本项目按上方非归一化约定冻结，两者关系在 FORMULA_TRACEABILITY 中记录。

## 2. 能量

严格区分时域与频域：

```text
m_x = E|x_n|^2          (time domain, 每符号)
M_x = E|X_k|^2          (frequency domain, 每子载波)
```

按非归一化 FFT 约定：

```text
M_x = N * m_x           (Parseval)
```

来源：书式 (3-65) `M_Xk = E[|X_k|^2]`, `M_Xhat,k = E[|Xhat_k|^2]`。
单位能量符号（工程 QPSK/BPSK）即 `m_x = 1`，此时 `M_x = N`。

## 3. 噪声

```text
sigma_w^2 = E|w_n|^2          (time domain per-symbol noise variance)
```

频域（非归一化 DFT）：

```text
E|W_k|^2 = N * sigma_w^2
```

SNR 定义（与现有 `ch3_add_awgn` / `add_awgn` 保持一致）：

```text
sigma_w^2 = P_signal * 10^(-snrDb/10)
```

单位符号功率下 `P_signal = m_x = 1`，故 `sigma_w^2 = 10^(-snrDb/10)`。

## 4. MMSE / IBDFE 正则化

统一推导：

```text
lambda = N * sigma_w^2 / M_x = sigma_w^2 / m_x
```

- `m_x = 1`（单位能量符号）时 `lambda = sigma_w^2 = noiseVariance`。
- MMSE 频域系数（书式，第3章）：

```text
C_k = H_k* / (N sigma_w^2 + M_x |H_k|^2)
```

工程实现 `ch3_mmse_frequency_equalize` 使用 `H*/(|H|^2 + sigma^2)`；
两者差正实因子 `M_x`（判决等价），状态标 **ALG-EQUIV**，并必须通过
`test_eq_3_71` 的 lambda 双形式断言。

IBDFE（书式 3-84~3-87）：

```text
A_k                                    (前馈未归一化系数)
Gamma = (1/N) sum_k A_k H_k            (3-87)
C_k   = A_k / Gamma                    (3-84)
B_k   = C_k H_k - 1                    (3-85)
单位增益不变式: (1/N) sum_k C_k H_k = 1
```

## 5. 时域索引约定

统一语义（第2/5/6章卷积类算法）：

```text
convolution output 长度 = len(x) + len(h) - 1   (full)
delay 0 定义在滤波器第 1 个非零抽头
前块 tail  = 上一块最后 (L-1) 个样本（后游标 ISI 来源）
后块 head  = 下一块前 (L-1) 个样本（前游标 ISI 来源）
reverse branch: y_r^D(n) = y_r(N-n+1)           (书式 2-50)
block 起止 index: 半开区间 [start, start+N)
```

## 6. 概率 / LLR 符号

全项目唯一约定（与书式 4-2 一致）：

```text
L(b) = ln P(b=0) / P(b=1)
```

即 **0 为正**。推论：

```text
P(b=0) = 1/(1+e^{-L}),  P(b=1) = e^{-L}/(1+e^{-L})        (书式 4-21/4-22)
硬判决: b_hat = 0 当 L >= 0                                (书式 4-9)
外信息: L^e = L_posterior - L_a                            (书式 4-7)
```

任何实现若使用相反符号（1 为正），必须显式标注 ENGINEERING 并给出换算，
不允许混合。

## 验收

- `papers/tests/test_book_conventions.m`（convention sanity）全部 PASS；
- 4 个 audit（qpsk/turbo/cck/csk）开头调用 `scfde.book_check_conventions()`
  且不报错；
- 任何新公式测试必须引用本文件约定，不得自造定义。

## Scope 规则（THEORY-ONLY 剔除条件）

1. **可执行公式**（可进入收发算法路径的公式）必须实现 executable oracle：
   `+scfde/+book_formulas/` 数值函数 + 对应公式测试，否则状态为"未实现"并计入分母。
2. **纯分析公式**（理论错误概率积分、EXIT 互信息、容量/分析性上界、纯推导中间
   恒等式，不参与算法路径）标 `THEORY-ONLY`，保留登记，**从算法验收分母中剔除**；
   不允许"未实现却计入完成度"。
3. **不得标 THEORY-ONLY 的公式类别**（必须实现 oracle 或保留"未实现"于分母）：
   channel/input-output model（含 (1-9)/(1-10) 信道模型）、detector、equalizer、
   encoder/modulator、spread/despread、soft estimator、iterative update。
   例如第5章 CCK-SM 的 (5-75)~(5-82)（z_q=c_{s_q}e_q、y=hx+w、频域检测、
   软估计）是收发算法公式，不属于 THEORY-ONLY。
4. 已扫描到的公式禁止以"未实现"停留在完成度分母之外：要么实现 oracle，
   要么明确标 THEORY-ONLY，两者必居其一。
5. 原书未公开的参数（NaN 配置）属 PARAM-UNRECOVERABLE；书中**根本不存在**的
   处理（如 ESE damping）是独立 ENGINEERING 算法，不属于 PARAM-UNRECOVERABLE。
