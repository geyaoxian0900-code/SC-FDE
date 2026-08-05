# 第 5.5 节仿真：CCK 性能与增强方法

入口是 simulate_chapter5_5_cck_results.m，核心实现是
../modules/+scfde/run_chapter5_5_cck_suite.m。实验分为 GCCK、扩展 CCK、CCK Turbo/IBDFE
和 CCK-SM 四个可独立选择的组。

原文截图给出了图 5-14 至图 5-31 的模型、结构和比较关系，但未提供原始湖试或海试
多径记录。因此当前实现是按公式建立的工程复现：默认 3 km 信道为 11 路稀疏离散抽头，
可替换为实测 CIR；不应将默认数值称作原始测量数据。

## GCCK 与 3 km 多径

八码片 CCK 核为

\[
\boldsymbol c(\phi_1,\phi_2,\phi_3,\phi_4)=
\begin{bmatrix}
e^{j(\phi_1+\phi_2+\phi_3+\phi_4)}&
e^{j(\phi_1+\phi_3+\phi_4)}&
e^{j(\phi_1+\phi_2+\phi_4)}&
-e^{j(\phi_1+\phi_4)}\\
e^{j(\phi_1+\phi_2+\phi_3)}&
e^{j(\phi_1+\phi_3)}&
-e^{j(\phi_1+\phi_2)}&
e^{j\phi_1}
\end{bmatrix}.
\]

GCCK-QPSK-4R、GCCK-QPSK-8R 和 GCCK-8PSK-12R 分别使用 4、8、12 个输入比特。
AWGN 图同时画出 Monte Carlo BER 与有限个最近邻码字对计算的联合界近似：

\[
P_b\lesssim\frac{1}{q}\sum_{j\in\mathcal N(i)}
d_H(\boldsymbol b_i,\boldsymbol b_j)
Q\left(\sqrt{\frac{\|\boldsymbol c_i-\boldsymbol c_j\|^2}{2N_0}}\right).
\]

3 km 多径模型和接收信号为

\[
h[n]=\sum_{\ell=0}^{L_h-1}\beta_\ell\delta[n-\tau_\ell],\qquad
r[n]=\sum_{\ell}h[\ell]x[n-\ell]+w[n].
\]

给定前序码片状态 \(\boldsymbol s_{k-1}\) 和候选码字 a，块度量是

\[
\mu_k(\boldsymbol s_{k-1},a)=
\frac{1}{N_0}\sum_i
\left|r[kN_c+i]-\mathcal H(\boldsymbol s_{k-1},\boldsymbol c_a)[i]\right|^2.
\]

DFE 使用 \(\hat a_k=\arg\min_a\mu_k(\hat{\boldsymbol s}_{k-1},a)\)。BiDFE-1 融合前、反向
评分；BiDFE-2 以首次融合结果固定两向反馈状态后重新评分。Rake、Rake-DFE、两接收支路
TR-Diversity 和已知过去码片的 MFB 同时保留为可选基线。

## 时变信道

原文的时变路径扰动和多普勒过程采用等价的一阶 Gauss-Markov 更新：

\[
h_\ell[k]=a h_\ell[k-1]+\sqrt{1-a^2}\,u_\ell[k],
\qquad u_\ell[k]\sim\mathcal{CN}(0,\sigma_\ell^2).
\]

a 是路径时间相关系数。a=1 对应静态信道；较小 a 对应更快的残余多普勒或散射变化。
接收端保持对初始信道的估计，以显示信道失配对 CCK 检测的影响。

## 扩展 CCK、DSSS 与 Turbo

CCK-16 和 CCK-32 由基础码字重复后乘以与码字标签相关的正交符号块构成。互相关先按

\[
\widetilde{\boldsymbol c}_i=
\frac{\boldsymbol c_i c_{i,N_c}^{*}}{\|\boldsymbol c_i c_{i,N_c}^{*}\|_2}
\]

归一化，因此不把仅相差整体相位的合法 CCK 码字记为完全相关。

图中的相关性柱状图不再使用容易被少数最近邻主导的最大值，而使用去自项、去等效整体相位后的
两两相关系数 \(ρ\) 的平均值 \(\mathbb E[ρ]\)。95% 分位数和最大值仍作为结果字段保留，供需要
高分位或最坏情况判据的后续算法调用。

DSSS-4 和 DSSS-8 使用 QPSK 与长度为 4 或 8 的 PN 扩频序列。它们和 CCK-Rake、
CCK-TE-1、CCK-TE-2、CCK-TE-3 在相同多径和噪声条件下比较。

CCK-IBDFE 的频域反馈为

\[
\widehat X^{(i)}_k=C_kY_k-B_k\overline X^{(i-1)}_k,\qquad
C_k=\frac{H_k^*}{|H_k|^2+N_0},\quad B_k=C_kH_k-1.
\]

每轮按码字后验形成软反馈

\[
\overline{\boldsymbol c}_k=
\sum_a
\frac{\exp[-\|\widehat{\boldsymbol x}_k-\boldsymbol c_a\|^2/N_0]}
{\sum_{a'}\exp[-\|\widehat{\boldsymbol x}_k-\boldsymbol c_{a'}\|^2/N_0]}
\boldsymbol c_a.
\]

5.5.3 的 CCK-TE-2/3 额外采用交织重复率 \(1/2\) 外码，而不是把无外码的 IBDFE
反复计算误称为 Turbo 增益。设信息比特为 \(\boldsymbol u\)，两个位置集合为
\(\mathcal I_1,\mathcal I_2\)，则

\[
b[\mathcal I_1]=\boldsymbol u,\qquad
b[\mathcal I_2]=\boldsymbol u[\pi],\qquad
L_A^{(i+1)}(q)=\eta L_E^{(i)}(p(q)).
\]

其中 \(p(q)\) 是第 \(q\) 个编码比特的交织副本位置，\(\eta\) 为阻尼系数。码字后验的度量加入
先验 LLR：

\[
\Lambda_a=-\frac{\|\widehat{\boldsymbol x}-\boldsymbol c_a\|^2}{N_0}
+\frac{1}{2}\sum_r(1-2b_r(a))L_{A,r},
\qquad L_E=L_{\mathrm{post}}-L_A.
\]

因此图 5-31 给出的是多个独立帧平均的信息 BER 与残差收敛，而不是利用发送端真值挑选每轮结果。

## CCK-SM MIMO-IBDFE

当第 k 个码字激活天线为 \(a_k\) 时，发送向量为

\[
\boldsymbol x_k=\boldsymbol e_{a_k}\boldsymbol c_{m_k},\qquad
\boldsymbol Y_k=\boldsymbol H_k\boldsymbol X_k+\boldsymbol W_k.
\]

第 i 次 MIMO-IBDFE 为

\[
\widehat{\boldsymbol X}^{(i)}_k=
\boldsymbol C_k\boldsymbol Y_k-
\boldsymbol B_k\overline{\boldsymbol X}^{(i-1)}_k,
\]

\[
\boldsymbol C_k=(\boldsymbol H_k^H\boldsymbol H_k+N_0\boldsymbol I)^{-1}
\boldsymbol H_k^H,\qquad
\boldsymbol B_k=\boldsymbol C_k\boldsymbol H_k-\boldsymbol I.
\]

随后对所有天线索引-CCK 码字联合候选形成后验软度量

\[
\gamma_{a,m}=-\frac{\|\widehat{\boldsymbol X}-\boldsymbol e_a\boldsymbol c_m\|_F^2}{N_0},
\qquad
P(a,m)=\frac{e^{\gamma_{a,m}}}{\sum_{a',m'}e^{\gamma_{a',m'}}},
\]

并以 \(\overline{\boldsymbol X}=\sum_{a,m}P(a,m)\boldsymbol e_a\boldsymbol c_m\) 作为下一轮反馈，
硬判决取最大后验候选。总 BER 同时计入 CCK 信息位和空间索引位；图中分别显示两类错误随
迭代的变化。默认的主图采用 \(4\times2\) 过载 MIMO，收敛诊断使用 \(-3\) dB，避免高信噪比下
所有曲线过早降为零而无法观察迭代作用。诊断帧另用 `smDiagnosticSeed` 固定随机流，因此不受
GCCK、扩展 CCK 或 Turbo 分支的运行顺序影响；主 BER 曲线仍由各帧 Monte Carlo 统计得到。

## 运行与图

~~~matlab
result = simulate_chapter5_5_cck_results(struct( ...
    "groups", ["gcck", "extended", "turbo", "sm"], ...
    "gcckModes", "all", ...
    "receiverMethods", "all", ...
    "turboMethods", ["CCK-Rake", "CCK-TE-3"], ...
    "smTxAntennas", 4, ...
    "smRxAntennas", 4, ...
    "makePlot", true));
~~~

默认输出 chapter5_5_gcck_awgn.png、chapter5_5_gcck_receivers.png、
chapter5_5_extended_cck.png、chapter5_5_cck_turbo.png 和 chapter5_5_cck_sm.png。
