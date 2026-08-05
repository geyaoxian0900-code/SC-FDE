# 第 5 章 CCK 仿真：5.1、5.2、5.3

入口为 simulate_chapter5_cck.m，核心实现在 ../modules/+scfde/run_chapter5_cck_suite_impl.m。
码本、ISI 接收机和 Turbo 检测器均可独立选择，中文图输出到 results/。

## 5.1 CCK 码本

八码片 CCK 码字为

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
\end{bmatrix},\qquad \boldsymbol x=\boldsymbol c/\sqrt{8}.
\]

对标准 FR-CCK，代码使用

\[
q(b_0,b_1)=\frac{\pi}{2}(b_0+2b_1),\quad
d(b_0,b_1)=\frac{\pi}{4}+q(b_0,b_1),
\]

\[
[\phi_1,\phi_2,\phi_3,\phi_4]
=[d(b_1,b_2),q(b_3,b_4),q(b_5,b_6),q(b_7,b_8)].
\]

在差分帧中，\(\phi_{1,k}\) 应累加前一 CCK 符号相位；本仿真假定已有载波相位参考，
所以直接以相位增量构造一个可检测码字。HR-CCK 保留 \(\phi_1,\phi_2\)，并令
\(\phi_3=\phi_4=0\)。GCCK-* 和 Extended-CCK 是可替换扩展码本，不应表述为
IEEE 802.11b 标准模式。

FR-CCK 的 256 个码字有仅相差整体相位的四元组，故直接计算
\(|\boldsymbol c_i^H\boldsymbol c_j|\) 会得到 1，且这不是重复码字。图中采用

\[
\widetilde{\boldsymbol c}_i=
\frac{\boldsymbol c_i c_{i,8}^{*}}{\|\boldsymbol c_i c_{i,8}^{*}\|_2}
\]

消除整体相位，再在余下的 64 个形状码字上显示互相关。

## 5.2 码片级 ISI 接收

令每个 CCK 码字有 \(N_c=8\) 个码片、索引为 \(a_k\)，则

\[
x[n]=c_{a_k}[n-kN_c],\qquad
r[n]=\sum_{\ell=0}^{L_h-1}h_\ell x[n-\ell]+w[n],
\]

其中 \(w[n]\sim\mathcal{CN}(0,\sigma_w^2)\)，默认信道为

\[
\boldsymbol h=
\frac{[1,\ 0.62e^{j0.5},\ 0.30e^{-j1.0}]}
{\|[1,\ 0.62e^{j0.5},\ 0.30e^{-j1.0}]\|_2}.
\]

以 \(L_h-1\) 个前序码片构成状态 \(\boldsymbol s_{k-1}\)，候选码字的块度量为

\[
\mu_k(\boldsymbol s_{k-1},a)
=\frac{1}{\sigma_w^2}\sum_{i=0}^{N_c-1}
\left|r[kN_c+i]-\mathcal H(\boldsymbol s_{k-1},\boldsymbol c_a)[i]\right|^2.
\]

| 方法 | 代码中的实现 |
|---|---|
| MLD | 16 个 FR-CCK 尾部码片状态上的 Viterbi：\(M_k(s')=\min_{s,a:g(a)=s'}[M_{k-1}(s)+\mu_k(s,a)]\)。 |
| Rake | \(z[n]=\sum_\ell h_\ell^*r[n+\ell]\)，再做码本最近邻判决。 |
| DFE | \(\hat a_k=\arg\min_a\mu_k(\hat s_{k-1},a)\)。 |
| BiDFE-1 | 前、反向 DFE 归一化评分相加：\(\Lambda_k=\bar\Lambda_k^F+\bar\Lambda_k^B\)。 |
| BiDFE-2 | 用 BiDFE-1 判决固定前、反向反馈状态后，重新评分并融合。 |
| TR-Rake | \(h_{\mathrm{TR}}[n]=h^*[L_h-1-n]\)，等效聚焦信道 \(g=h*h_{\mathrm{TR}}\)，补偿峰值时延后判决。 |

MLD 的状态是物理尾部码片，而不是把 256 个 CCK 码字两两暴力枚举，因而是该有限
记忆模型上的精确 Viterbi 形式。

## 5.3 MAP-CCK-Turbo 与 RSSE-CCK-Turbo

对候选码字 \(a\) 的比特标签 \(\boldsymbol b_a\) 和先验 LLR \(L_A(k,i)\)，SISO
均衡器使用

\[
\Gamma_k(s,a)=-\mu_k(s,a)+
\frac{1}{2}\sum_{i=1}^{8}[1-2b_{a,i}]L_A(k,i).
\]

前、反向递推为

\[
\alpha_k(s')=\log\sum_{s,a:g(a)=s'}\exp\{\alpha_{k-1}(s)+\Gamma_k(s,a)\},
\]

\[
\beta_{k-1}(s)=\log\sum_a\exp\{\Gamma_k(s,a)+\beta_k(g(a))\}.
\]

位后验与外信息为

\[
L_P(k,i)=
\log\frac{\sum_{a:b_{a,i}=0}\exp\{\Lambda_k(a)\}}
{\sum_{a:b_{a,i}=1}\exp\{\Lambda_k(a)\}},\qquad
L_E(k,i)=L_P(k,i)-L_A(k,i).
\]

默认外码是交织的重复 \(1/2\) 码。对重复副本位置 \(\pi(p)\)，下一轮先验为

\[
L_A^{(t+1)}(p)=\rho L_E^{(t)}(\pi(p)),\qquad \rho=0.75.
\]

这保证每轮获得来自另一副本的外信息。设置 turboOuterCode="none" 可关闭外码，
单独观察 CCK SISO 检测。MAP-CCK-TE 默认使用 16 个物理状态和 256 个候选码字；
RSSE-CCK-TE 默认使用 4 个代表状态和每块 32 个候选码字。mapStateList、
reducedStateList 和 rsseTrellisStates 分别控制候选列表与缩减状态数，复杂度主项为
\(\mathcal O(KSQ)\)。

## 运行与选择

~~~matlab
result = simulate_chapter5_cck(struct( ...
    "modulationMethods", ["FR-CCK", "HR-CCK"], ...
    "isiMethods", ["MLD", "DFE", "BiDFE-2"], ...
    "turboMethods", "all", ...
    "mapStateList", 256, ...
    "reducedStateList", 32, ...
    "rsseTrellisStates", 4, ...
    "makePlot", true));
~~~

allAwgnBer、allIsiBer、allTurboBer 保存全部算法；awgnBer、isiBer、turboBer
保存本次选择。
