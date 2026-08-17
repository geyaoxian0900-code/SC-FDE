# 37 种均衡方法严格公式规范

_适用于 `run_equalizer_app.m` 注册的全部 37 个接收方法；事实源为 `book/` 扫描件，版本日期 2026-08-14。_

---

## 📋 使用范围与认证规则

本文件规定每个注册 ID **应当实现的数学内容**，不是对当前代码正确性的追认。
公式正文以 `book/*.png` 为最高事实源，`papers/book_transcripts/` 仅用于定位。
若转录文本与原图冲突，必须按原图修正后才能修改生产代码。

严格复现必须同时满足以下条件：

1. 执行本节列出的输入输出式、滤波器设计式和递推式
2. 保持原式的共轭、转置、正负号、归一化和索引方向
3. 保持训练、判决导向、内外迭代、首尾补零等时序语义
4. 多阵元算法必须使用独立接收分支，禁止复制同一 `received` 充当不同阵元
5. 原书未给出的参数必须记为 `PARAM-UNRECOVERABLE`，不得猜测后标为原文参数
6. 阻尼、回退、裁剪、固定混合权重和真信道初始化只能进入显式 `ENGINEERING` 路径
7. 只有原书直接定义的方法才能标 `BOOK-EXACT`；多个原式组合出的注册 ID 最多标 `ALG-EQUIV`

> **重要：** 本文件中的“必须”表示 BOOK 主路径的验收要求。工程扩展可以保留，但不得改变 BOOK 主路径输出。

## 📐 全局数学约定

### 离散傅里叶变换

本项目 MATLAB 路径固定采用前向无缩放、逆变换含 `1/N` 的约定：

$$
X_k=\sum_{n=0}^{N-1}x_n e^{-j2\pi kn/N},\qquad
x_n=\frac{1}{N}\sum_{k=0}^{N-1}X_k e^{j2\pi kn/N}.
$$

因此

$$
\sum_{k=0}^{N-1}|X_k|^2=N\sum_{n=0}^{N-1}|x_n|^2,
\qquad M_x=E|X_k|^2=N m_x.
$$

式中，`F` 表示前向 DFT，`F^{-1}` 或 `F^H/N` 表示逆 DFT。若推导采用酉矩阵
`F_u`，必须显式使用 `F_u=F/\sqrt N`，禁止混用两套标度。

### 信道、阵元与噪声

第 `p` 个独立接收阵元必须满足

$$
r_p(n)=\sum_{\ell=0}^{L_p-1}h_p(\ell)x(n-\ell)+w_p(n),
\qquad E[w_p(n)w_q^*(m)]=\sigma_w^2\delta_{pq}\delta_{nm}.
$$

单分支模型是 `P=1` 的特例。多分支接收不得令 `r_1=r_2=\cdots=r_P`，除非该相等关系
本身就是被测试的退化情形。

### 判决、误差和 LLR

统一定义

$$
e(n)=d(n)-\hat d(n),\qquad
L(b)=\ln\frac{P(b=0)}{P(b=1)},\qquad
L^e=L^{\rm post}-L^a.
$$

故硬比特判决为

$$
\hat b=\begin{cases}0,&L(b)\ge0,\\1,&L(b)<0.\end{cases}
$$

复数向量默认是列向量；`(\cdot)^T` 是转置，`(\cdot)^*` 是逐元素共轭，
`(\cdot)^H` 是共轭转置，`\odot` 是逐元素乘法，`\otimes` 是线性卷积。

### 公共 DFE 状态

长度为 `N_f` 的前馈输入和长度为 `N_b` 的反馈输入定义为

$$
\mathbf r_n=[r(n),\ldots,r(n-N_f+1)]^T,
\qquad
\tilde{\mathbf d}_n=[\tilde d(n-1),\ldots,\tilde d(n-N_b)]^T.
$$

统一 DFE 输出为书式 (2-6) 的符号约定：

$$
z(n)=\mathbf f^H(n)\mathbf r_n-\mathbf b^H(n)\tilde{\mathbf d}_n,
\qquad \tilde d(n)=\mathcal Q\{z(n)\}.
$$

训练区令 `d(n)` 为已知训练符号；训练结束后才允许用 `\tilde d(n)` 计算误差。

## 📘 第 2 章：时域与多通道均衡（10 种）

### 2.1 `dfe`：常规判决反馈均衡

**原文依据：** 式 (2-6)～(2-11)。

$$
\hat d_k=\sum_{i=0}^{N_f-1}f_i^*r_{k-i}
-\sum_{j=1}^{N_b}b_j^*\tilde d_{k-j}
=\mathbf w_k^H\mathbf u_k,
$$

$$
e_k=d_k-\hat d_k,\qquad
J(\mathbf w)=E|e_k|^2,
$$

$$
\mathbf w^\circ=\mathbf R_u^{-1}\mathbf r_{du},\quad
\mathbf R_u=E[\mathbf u_k\mathbf u_k^H],\quad
\mathbf r_{du}=E[\mathbf u_k d_k^*].
$$

严格实现必须明确滤波器抽头长度和判决时延。若用正则化数值解，只能在矩阵奇异时启用，
并把正则化量作为数值参数记录，不得改变公式目标函数。

### 2.2 `lms-dfe`：LMS 判决反馈均衡

**原文依据：** 式 (2-9)、(2-12)～(2-15)。

$$
\hat d(n)=\mathbf w^H(n)\mathbf u(n),\qquad
e(n)=d(n)-\hat d(n),
$$

$$
\nabla_{\mathbf w}J=-2E[e^*(n)\mathbf u(n)],
$$

$$
\boxed{\mathbf w(n+1)=\mathbf w(n)+2\mu e^*(n)\mathbf u(n)},
\qquad 0<\mu<\lambda_{\max}^{-1}.
$$

若代码把 `2\mu` 重命名为 `\mu_{\rm code}`，必须通过
`\mu_{\rm code}=2\mu_{\rm book}` 的参数映射证明等价。

### 2.3 `nlms-dfe`：归一化 LMS 判决反馈均衡

**原文依据：** 第 2.2.2 节 NLMS 定义及式 (2-14) 的归一化形式。

$$
\boxed{
\mathbf w(n+1)=\mathbf w(n)+
\frac{\mu\,e^*(n)\mathbf u(n)}{\delta+\mathbf u^H(n)\mathbf u(n)}},
\qquad \delta>0.
$$

`\delta` 只能防止零除；不得额外加入与 SNR、信道能量或经验 BER 有关的下限。
前馈和反馈抽头若分开存储，必须等价于对同一复合向量 `\mathbf u(n)` 的一次更新。

### 2.4 `rls-dfe`：递归最小二乘判决反馈均衡

**原文依据：** 式 (2-18)～(2-25)。

$$
J_n=\sum_{i=0}^{n}\lambda^{n-i}|d(i)-\mathbf w^H(n)\mathbf u(i)|^2,
\qquad 0.8<\lambda<1,
$$

$$
\mathbf k(n)=
\frac{\mathbf P(n-1)\mathbf u(n)}
{\lambda+\mathbf u^H(n)\mathbf P(n-1)\mathbf u(n)},
$$

$$
e(n)=d(n)-\mathbf w^H(n-1)\mathbf u(n),
$$

$$
\boxed{\mathbf w(n)=\mathbf w(n-1)+\mathbf k(n)e^*(n)},
$$

$$
\boxed{\mathbf P(n)=\lambda^{-1}
[\mathbf P(n-1)-\mathbf k(n)\mathbf u^H(n)\mathbf P(n-1)]}.
$$

初始化必须显式记录，例如 `\mathbf w(0)=0`、`\mathbf P(0)=\delta^{-1}I`；
该初始化是数值实现参数，不得声称为原书唯一给定值。

### 2.5 `dpll-dfe`：内嵌数字锁相环 DFE

**原文依据：** 式 (2-26)～(2-43)。

$$
p_k=\mathbf a^H\mathbf r(k)e^{-j\hat\theta_k},\qquad
q_k=\mathbf b^H\tilde{\mathbf d}(k),
$$

$$
\hat d_k=p_k-q_k,\qquad e_k=d_k-\hat d_k,
$$

$$
\varphi_k=\operatorname{Im}\{p_k(d_k+q_k)^*\},
$$

$$
\boxed{\hat\theta_{k+1}=\hat\theta_k+K_1\varphi_k
+K_2\sum_{i=1}^{k}\varphi_i},\qquad K_2=0.1K_1.
$$

等价的二阶递推可写为书式 (2-38)，但必须由上式代数推出。相位检测器必须使用
`\varphi_k`，不得误用均衡误差 `e_k` 直接替代。

### 2.6 `mc-lms-dfe`：多通道 LMS-DFE

**原文依据：** 式 (2-43)～(2-46) 与 LMS 式 (2-14)。

对 `P` 个独立阵元，

$$
z(k)=\sum_{p=1}^{P}\mathbf a_p^H(k)\mathbf r_p(k)
e^{-j\hat\theta_{p,k}}-\mathbf b^H(k)\tilde{\mathbf d}(k),
$$

$$
e(k)=d(k)-z(k),
$$

$$
\mathbf a_p(k+1)=\mathbf a_p(k)+2\mu_a e^*(k)
\mathbf r_p(k)e^{-j\hat\theta_{p,k}},
$$

$$
\mathbf b(k+1)=\mathbf b(k)-2\mu_b e^*(k)\tilde{\mathbf d}(k).
$$

反馈更新的负号来自输出中的 `-\mathbf b^H\tilde{\mathbf d}`。每个阵元的相位环独立，
输出只在前馈滤波后相干求和。

### 2.7 `mc-nlms-dfe`：多通道 NLMS-DFE

**原文依据：** 多通道式 (2-44)～(2-46) 与 NLMS 归一化递推。

令复合输入

$$
\mathbf u(k)=
[\mathbf r_1^T(k)e^{-j\hat\theta_{1,k}},\ldots,
\mathbf r_P^T(k)e^{-j\hat\theta_{P,k}},-\tilde{\mathbf d}^T(k)]^T,
$$

则

$$
z(k)=\mathbf w^H(k)\mathbf u(k),\qquad
\boxed{\mathbf w(k+1)=\mathbf w(k)+
\frac{\mu e^*(k)\mathbf u(k)}{\delta+\|\mathbf u(k)\|_2^2}}.
$$

禁止对复制出来的相同分支分别归一化后宣称获得空间分集。

### 2.8 `mc-rls-dfe`：多通道 RLS-DFE

**原文依据：** 多通道式 (2-44)～(2-46) 与 RLS 式 (2-23)～(2-25)。

使用上一节定义的复合输入 `\mathbf u(k)`：

$$
\mathbf k(k)=\frac{\mathbf P(k-1)\mathbf u(k)}
{\lambda+\mathbf u^H(k)\mathbf P(k-1)\mathbf u(k)},
$$

$$
\mathbf w(k)=\mathbf w(k-1)+\mathbf k(k)e^*(k),
$$

$$
\mathbf P(k)=\lambda^{-1}
[\mathbf P(k-1)-\mathbf k(k)\mathbf u^H(k)\mathbf P(k-1)].
$$

`\mathbf P` 的维度必须等于所有阵元前馈抽头与公共反馈抽头的总长度。

### 2.9 `ptr-dfe`：被动时反 DFE

**原文依据：** 式 (2-47)。

$$
\hat r(t)=\sum_{p=1}^{P}\hat h_p^*(-t)\otimes r_p(t)
=D(t)\otimes s(t)+\zeta(t),
$$

$$
D(t)=\sum_{p=1}^{P}\hat h_p^*(-t)\otimes h_p(t),\qquad
\zeta(t)=\sum_{p=1}^{P}\hat h_p^*(-t)\otimes w_p(t).
$$

之后必须以等效信道 `D(t)` 驱动第 2.1～2.4 节的 DFE。线性卷积不得替换为未补零的循环卷积；
匹配滤波主抽头的延迟必须由 `L_h-1` 对齐。

### 2.10 `subband-ptr-dfe`：子阵被动时反多通道 DFE

**原文依据：** 式 (2-48)、(2-49)。

将 `M=PK` 个阵元划分为 `P` 个子阵，每个子阵 `K` 个阵元：

$$
y_p(n)=\sum_{k=1}^{K}\tilde h_{p,k}^*(-n)\otimes r_{p,k}(n),
\qquad p=1,\ldots,P,
$$

$$
\hat d(n)=\sum_{p=1}^{P}\mathbf a_p^H\mathbf y_p(n)
-\mathbf b^H\tilde{\mathbf d}(n).
$$

后级等效信道必须是逐阵元自相关之和

$$
g_p(n)=\sum_{k=1}^{K}\tilde h_{p,k}^*(-n)\otimes h_{p,k}(n),
$$

不得使用 `|\sum_k h_{p,k}|^2`，因为后者引入原式不存在的阵元交叉项。

## 📗 第 3 章：频域与迭代块均衡（7 种）

### 3.1 `mmse-fde`：最小均方误差频域均衡

**原文依据：** 式 (3-39)～(3-44)、(3-71)。

$$
\mathbf R=\boldsymbol\Phi\hat{\mathbf H}\mathbf S+\mathbf W,
\qquad \boldsymbol\Phi\approx\lambda I,
$$

$$
\boxed{\mathbf C=(\hat{\mathbf H}^H\boldsymbol\Phi^H
\boldsymbol\Phi\hat{\mathbf H}+\sigma_w^2I)^{-1}
\hat{\mathbf H}^H\boldsymbol\Phi^H}.
$$

忽略残余相位且信道为对角阵时，逐频点形式为

$$
C_k^*=\frac{H_k^*}{N\sigma_w^2+M_{X_k}|H_k|^2}.
$$

单位能量符号的判决等价形式是 `H_k^*/(|H_k|^2+\sigma_w^2/m_x)`；
若省略的只是所有频点共同的正实比例因子，必须用 golden test 证明判决等价。

### 3.2 `zf-fde`：迫零频域均衡

**原文依据：** 式 (3-43)～(3-44) 的零噪声极限。

$$
\boxed{C_k=\frac{1}{\lambda H_k}},\qquad
\hat x=F^{-1}\{C_kR_k\}.
$$

当 `H_k=0` 时严格 ZF 不存在。BOOK 主路径必须报告奇异频点；若使用
`H_k^*/(|H_k|^2+\epsilon)`，该路径是正则化 ZF 工程扩展而非严格 ZF。

### 3.3 `htfde`：时频域联合判决反馈均衡

**原文依据：** 式 (3-61)、(3-62) 以及第 2 章 DPLL-DFE。

每个子阵 `m` 内含 `K` 个独立阵元。第 `k` 个阵元的频域 MMSE 系数为

$$
\boxed{
C_{m,k}=(\tilde H_{m,k}^H\Phi_{m,k}^H\Phi_{m,k}\tilde H_{m,k}
+\sigma_w^2I)^{-1}\tilde H_{m,k}^H\Phi_{m,k}^H}.
$$

若 `\Phi_{m,k}=\lambda_{m,k}I`，则

$$
C_{m,k}=(|\lambda_{m,k}|^2\tilde H_{m,k}^H\tilde H_{m,k}
+\sigma_w^2I)^{-1}\lambda_{m,k}^*\tilde H_{m,k}^H.
$$

子阵输出必须为

$$
\boxed{x_m=F^{-1}\left\{\sum_{k=1}^{K}C_{m,k}R_{m,k}\right\}},
\qquad m=1,\ldots,P.
$$

随后把 `P` 路 `x_m` 输入多通道 DPLL-DFE。用单一 `H`、时域分段或复制分支替代
`\sum_k C_{m,k}R_{m,k}` 均不满足原式。

### 3.4 `sd-ibdfe`：软判决块迭代 DFE

**原文依据：** 式 (3-64)～(3-71)、(3-84)～(3-87)。

第 `i` 次迭代：

$$
\hat{\mathbf X}^{(i)}=(\mathbf C^{(i)})^H\mathbf R
-(\mathbf B^{(i)})^H\bar{\mathbf X}^{(i-1)},
$$

$$
\bar x_n^{(i-1)}=E[x_n\mid L_a]
=\sum_{s\in\mathcal S}sP(x_n=s\mid L_a),
$$

$$
C_k^{(i)}=A_k^{(i)}/\Gamma^{(i)},\qquad
B_k^{(i)}=C_k^{(i)}H_k-1,
$$

$$
\Gamma^{(i)}=\frac1N\sum_{k=0}^{N-1}A_k^{(i)}H_k,
\qquad \frac1N\sum_k C_k^{(i)}H_k=1.
$$

第一次迭代必须令反馈为零，退化为 MMSE-FDE；之后反馈软符号期望，不得先硬切片。

### 3.5 `hd-ibdfe`：硬判决块迭代 DFE

**原文依据：** 式 (3-64)～(3-71)。

$$
\hat{\mathbf X}^{(i)}=(\mathbf C^{(i)})^H\mathbf R
-(\mathbf B^{(i)})^H\tilde{\mathbf X}^{(i-1)},
$$

$$
\tilde x_n^{(i-1)}=\mathcal Q\{F^{-1}\hat{\mathbf X}^{(i-1)}\}_n.
$$

滤波器归一化与上一节相同。硬判决必须来自上一迭代的完整块；禁止读取当前尚未写入的输出区。

### 3.6 `ice-sd-ibdfe`：迭代信道估计软判决 IBDFE

**原文依据：** 式 (3-88)～(3-92) 加 `sd-ibdfe`。

由当前软符号估计得到 LS 频响 `H_{LS,k}^{(i)}`，再进行 DFT 降噪：

$$
h_{\rm est,n}^{(i)}=F^{-1}\{H_{LS,k}^{(i)}\},
$$

$$
h_{\rm DFT,n}^{(i)}=
\begin{cases}h_{\rm est,n}^{(i)},&0\le n<\hat L,\\0,&\hat L\le n<N,\end{cases}
\qquad H_{\rm DFT}^{(i)}=Fh_{\rm DFT}^{(i)}.
$$

书式 (3-92) 要求按估计误差方差进行 MMSE 加权：

$$
\boxed{
H^{(i)}=
\frac{H^{(i-1)}\sigma_{\rm DFT}^2
+H_{\rm DFT}^{(i)}\sigma_{\rm old}^2}
{\sigma_{\rm old}^2+\sigma_{\rm DFT}^2}}.
$$

然后用 `H^{(i)}` 重算 IBDFE 系数。固定 `\rho` 线性混合不是式 (3-92)。扫描转录中
两个方差的下标次序仍须以 `book/17.png` 原图为最终准绳。

### 3.7 `ice-hd-ibdfe`：迭代信道估计硬判决 IBDFE

**原文依据：** 式 (3-88)～(3-92) 加 `hd-ibdfe`。

信道更新与上一节完全相同，但重估信道使用

$$
\tilde x_n^{(i)}=\mathcal Q\{\hat x_n^{(i)}\}
$$

而不是软期望。首轮只使用训练/UW 信道估计；数据判决只能从上一轮进入下一轮信道估计。

## 📙 第 4 章：Turbo 与直接自适应均衡（10 种）

### 4.1 `td-turbo`：时域 Turbo 均衡

**原文依据：** 式 (4-5)～(4-9)、(4-16)～(4-23)、(4-24)～(4-49)。

由译码器先验得到符号均值和方差

$$
\bar x_k=\sum_{s\in\mathcal S}sP(x_k=s),\qquad
v_k=\sum_{s\in\mathcal S}|s|^2P(x_k=s)-|\bar x_k|^2.
$$

令 `V=diag(v_k)`，时域 LMMSE 后验估计为

$$
\boxed{
\hat{\mathbf x}=\bar{\mathbf x}
+\mathbf V\mathbf H^H(\mathbf H\mathbf V\mathbf H^H
+\sigma_w^2I)^{-1}(\mathbf y-\mathbf H\bar{\mathbf x})}.
$$

均衡器外信息必须按书式 (4-42)～(4-45) 由高斯条件密度计算：

$$
p(\tilde x_k\mid x_k=s_i)=\frac1{\pi\hat\sigma^2}
\exp\left(-\frac{|\tilde x_k-\hat\mu s_i|^2}{\hat\sigma^2}\right),
$$

$$
L^E(c_{k,j})=ln
\frac{\sum_{s_i\in\mathcal S_j^0}p(\tilde x_k|s_i)
\prod_{j'\ne j}P(c_{k,j'})}
{\sum_{s_i\in\mathcal S_j^1}p(\tilde x_k|s_i)
\prod_{j'\ne j}P(c_{k,j'})}.
$$

### 4.2 `fd-dfe`：频域判决反馈均衡

**原文依据：** 式 (4-50)～(4-59)。

$$
\bar{\mathbf x}^{(i)}=F^{-1}
[\mathbf W^{(i)}\mathbf y-\mathbf B^{(i)}\bar{\mathbf X}^{(i-1)}],
$$

$$
y_k=h_kX_k+n_k,qquad
w_k^{(i)}=\frac{h_k^*(1+b_k^{(i)})}{\sigma_n^2+|h_k|^2}.
$$

反馈滤波器必须满足零均值约束

$$
\sum_{k=0}^{K-1}b_k^{(i)}=0,
$$

并由书式 (4-57)、(4-58) 的相关系数 `\rho^{(i)}` 与归一化量求得，而不是沿用通用
IBDFE 或固定经验反馈系数。第一次迭代 `\bar{\mathbf X}^{(0)}=0`。

> **扫描约束：** (4-57)、(4-58) 的分子分母必须从 `book/21.png` 人工双人复核后写入生产 oracle；在完成前本 ID 不得标 `BOOK-EXACT`。

### 4.3 `fd-turbo`：频域 Turbo 均衡

**原文依据：** 式 (4-42)～(4-63)。

使用上一节的 `W^{(i)}`、`B^{(i)}`，但反馈符号改为译码器软期望：

$$
\bar x_k^{(i)}=\sum_{s\in\mathcal S}sP(x_k=s\mid L_D^{e,(i-1)}),
$$

$$
\hat{\mathbf x}^{(i)}=F^{-1}
[\mathbf W^{(i)}\mathbf y-\mathbf B^{(i)}F\bar{\mathbf x}^{(i-1)}].
$$

利用式 (4-60)、(4-61) 估计等效增益和残余方差：

$$
\hat\mu=\frac1N\sum_{k=0}^{N-1}\hat x_kx_k^*,\qquad
\hat\sigma^2=\frac1N\sum_{k=0}^{N-1}|\hat x_k-\hat\mu x_k|^2,
$$

再按式 (4-42)、(4-43) 生成外 LLR。均衡器与 BCJR 之间只交换外信息，禁止把后验 LLR
不减先验就反馈。

### 4.4 `tf-turbo`：时频域 Turbo 均衡

**原文依据：** 式 (4-43)～(4-49) 与第 3 章 HTF-DFE。

每个子阵先执行严格 HTF 前馈：

$$
x_m=F^{-1}\left\{\sum_{k=1}^{K}C_{m,k}R_{m,k}\right\},
$$

再执行时域软反馈：

$$
\hat x_n=\sum_{m=1}^{P}\mathbf f_m^H\mathbf x_m(n)
-\mathbf g^H\bar{\mathbf x}_{n-1},
$$

$$
\bar x_n=E[x_n\mid L_D^e].
$$

输出按式 (4-42)、(4-43) 产生外 LLR。任何固定 `0.5` 混合、复制阵元或用单路 FDE
替代子阵求和的路径均为工程近似。

### 4.5 `bitf-turbo`：双向时频域 Turbo 均衡

**原文依据：** 式 (2-50)～(2-53)、(4-42)～(4-49)。

正向和反向序列分别执行上一节的 TF-Turbo：

$$
\hat d_F(n)=\mathcal T_F\{r(1{:}N)\},
$$

$$
\hat d_B^R(n)=\operatorname{rev}
\left(\mathcal T_B\{\operatorname{rev}(r(1{:}N))\}\right),
$$

$$
\boxed{\bar d(n)=\frac{\hat d_F(n)+\hat d_B^R(n)}2}.
$$

两支路必须使用独立滤波器状态；反向支路输出必须恢复原时间顺序后才能合并。
若在 LLR 域合并，应使用独立观测的 LLR 相加，并证明与符号域等权合并的假设一致。

### 4.6 `blms-tf-turbo`：BLMS 时频域 Turbo 均衡

**原文依据：** 式 (4-64)～(4-73) 与式 (4-42)～(4-49)。

前馈采用第 4.7 节的严格 FBLMS 更新，反馈符号采用

$$
\bar x_n^{(i)}=E[x_n\mid L_D^{e,(i-1)}].
$$

有效块误差为

$$
e_k=\begin{cases}
d_k-\hat x_k,&k<L_{\rm train},\\
\bar x_k^{(i)}-\hat x_k,&k\ge L_{\rm train}.
\end{cases}
$$

每轮更新后按式 (4-42)、(4-43) 输出外 LLR。若实现使用另一套迭代内核、固定 residual
混合或循环块无污染丢弃，则不能与本公式链等同。

### 4.7 `fblms`：频域块 LMS 均衡

**原文依据：** 式 (4-64)～(4-73)。

构造三段输入块

$$
\mathbf r_u(k)=[\mathbf y_u'^T(k),\mathbf y_u^T(k),
\mathbf y_d'^T(k)]^T\in\mathbb C^{N_f+N+N_b},
$$

$$
\mathbf R_u(k)=F\mathbf r_u(k),\qquad
\hat{\mathbf X}(k)=\sum_u\mathbf W_u(k)\odot\mathbf R_u(k),
$$

$$
\hat{\mathbf x}(k)=F^{-1}\hat{\mathbf X}(k),\qquad
\tilde{\mathbf x}(k)=\mathbf T\hat{\mathbf x}(k),
$$

$$
\mathbf T=[0_{N\times N_f}\ I_N\ 0_{N\times N_b}].
$$

误差频谱与时域约束为

$$
\mathbf E(k)=F[0_{N_f};\mathbf e(k);0_{N_b}],
$$

$$
\mathbf G=\operatorname{blkdiag}(I_{N_f},0_N,0_{N_b}),
$$

$$
\boxed{
\mathbf W_u(k+1)=\mathbf W_u(k)+
\frac{\mu_f F\mathbf G F^{-1}
[\mathbf R_u^*(k)\odot\mathbf E(k)]}
{\epsilon+\mathbf R_u^H(k)\mathbf R_u(k)}}.
$$

分母是整块标量能量；前后污染样本必须丢弃；末块补零样本不得参与误差或权值更新。

### 4.8 `tdda-teq`：时域直接自适应 Turbo 均衡

**原文依据：** 第 4.5 节直接自适应思想与 Turbo 外信息式 (4-42)～(4-49)。

时域直接自适应 DFE 必须写成

$$
z(n)=\mathbf w_f^H(n)\mathbf r_n-
\mathbf w_b^H(n)\bar{\mathbf x}_{n-1},\qquad
e(n)=d_a(n)-z(n),
$$

$$
\mathbf w_f(n+1)=\mathbf w_f(n)+\mu_f\mathbf r_n e^*(n),
$$

$$
\mathbf w_b(n+1)=\mathbf w_b(n)-\mu_b\bar{\mathbf x}_{n-1}e^*(n).
$$

训练时 `d_a=d`；数据时 `d_a=E[x|L_D^e]`。不得用真信道计算初始权值。

> **认证边界：** `tdda-teq` 是项目注册名；原书未把上述组合列成独立编号公式，因此满足公式链后最多标 `ALG-EQUIV`。

### 4.9 `fdda-teq`：频域直接自适应 Turbo 均衡

**原文依据：** 式 (4-74)～(4-82)。

第 `k` 个滑动窗口对第 `m` 个阵元构造

$$
\mathbf r_m(k)=[\mathbf y_{m,\rm pre}^T,
\mathbf y_{m,\rm cur}^T,\mathbf y_{m,\rm post}^T]^T,
$$

反馈窗口必须满足式 (4-75)：

$$
\tilde{\mathbf x}(k)=
[\tilde{\mathbf x}_{\rm pre}^T,\mathbf0_N^T,
\tilde{\mathbf x}_{\rm post}^T]^T.
$$

第一次外迭代无先验，数据段反馈窗口全零。频域量为

$$
\mathbf R_m(k)=F\mathbf r_m(k),\qquad
\tilde{\mathbf X}(k)=F\tilde{\mathbf x}(k).
$$

书式 (4-77) 的输出为

$$
\boxed{
\hat{\mathbf X}(k)=
\sum_{m=1}^{M}\mathbf W_m^H(k)\odot\mathbf R_m(k)
+\mathbf B(k)\odot\tilde{\mathbf X}(k)}.
$$

$$
\hat{\mathbf x}_{\rm valid}(k)=
\mathbf T F^{-1}\hat{\mathbf X}(k),
\qquad \mathbf T=[0\ I_N\ 0].
$$

式 (4-80)、(4-82) 的自适应更新为

$$
\boxed{
\mathbf W_m^{(i)}(k+1)=\mathbf W_m^{(i)}(k)+
\frac{\gamma_f^i\mu_f F\mathbf G F^{-1}
[\mathbf R_m^*(k)\odot\mathbf E(k)]}
{\epsilon+\mathbf R_m^H(k)\mathbf R_m(k)}} ,
$$

$$
\boxed{
\mathbf B^{(i)}(k+1)=\mathbf B^{(i)}(k)+
\frac{\gamma_b^i\mu_b F\mathbf G F^{-1}
[\tilde{\mathbf X}^*(k)\odot\mathbf E(k)]}
{\epsilon+\tilde{\mathbf X}^H(k)\tilde{\mathbf X}(k)}} .
$$

外迭代继承权值：

$$
\mathbf W_m^{(i)}(0)=\mathbf W_m^{(i-1)}(K),\qquad
\mathbf B^{(i)}(0)=\mathbf B^{(i-1)}(K).
$$

`\gamma_f^i`、`\gamma_b^i` 在同一外迭代内对所有块相同。`\gamma_f`、`\gamma_b`
的具体数值原书未公开。输出式的共轭和反馈加号必须按原图实现，不得按常见 DFE 习惯擅自改成减号。

### 4.10 `fdda-dfe-teq`：FDDA 判决反馈 Turbo 派生均衡

**原文依据：** 式 (4-50)～(4-63) 与式 (4-74)～(4-82) 的组合。

前馈和反馈权值必须完全使用第 4.9 节 FDDA 更新；区别只在反馈信息来源：

$$
\tilde x_n^{(i)}=
\begin{cases}
0,&i=0,\\
\mathcal Q\{\hat x_n^{(i-1)}\},&\text{硬判决模式},\\
E[x_n\mid L_D^{e,(i-1)}],&\text{Turbo 软反馈模式}.
\end{cases}
$$

不得另建与式 (4-80)/(4-82) 无关的 BLMS 经验内核。该 ID 是项目组合名，不是原书独立命名方法，
即使组合公式全部正确也只能标 `ALG-EQUIV`。

## 📕 第 5 章：CCK 接收方法（7 种）

### 5.1 `cck-rake`：CCK Rake 接收机

**原文依据：** 式 (5-11)、(5-24)、(5-33)～(5-40)。

CCK 码字 `\mathbf a_q\in\mathcal C` 通过多径信道：

$$
r(i)=\sum_{\ell=0}^{L-1}h(\ell)a_q(i-\ell)+w(i).
$$

第 `\ell` 条可分辨路径的相关输出为

$$
z_\ell(q)=h_\ell^*\sum_n r(n+\tau_\ell)a_q^*(n),
$$

最大比合并为

$$
Z(q)=\sum_{\ell\in\mathcal P}z_\ell(q),\qquad
\boxed{\hat q=\arg\max_q\operatorname{Re}Z(q)}.
$$

各 Rake 指必须对应可分辨路径时延，合并权为该路径复增益的共轭；候选路径裁剪只能按原书
公开门限，否则属于工程模式。

### 5.2 `cck-dfe`：CCK 判决反馈接收机

**原文依据：** 式 (5-40)～(5-47)。

信道匹配滤波输出为

$$
y_k=a_k+\sum_{i=1}^{L-1}x_{k-i}'a_{k+i}
+\sum_{i=1}^{L-1}x_{k+i}'a_{k-i}+\mu_k,
$$

其中第一和第二个求和分别对应前置、后置 ISI。常规前向 DFE 的临时判决为

$$
\boxed{\tilde a_k=y_k-
\sum_{i=1}^{L-1}\hat x_{k+i}'\hat a_{k-i}},
$$

$$
\hat a_k=\mathcal Q_{\mathcal C}\{\tilde a_k\}
=\arg\min_{a_q\in\mathcal C}|\tilde a_k-a_q|^2.
$$

码本判决必须在完整 CCK 码字空间进行，BER 必须查 `bitTable` 的汉明距离，不能把码字错误
直接按全部比特错误统计。

### 5.3 `cck-bidfe`：CCK 双向 DFE 第一型

**原文依据：** 式 (5-46)～(5-54)。

先执行前向临时 DFE 获得过去符号估计，再对整块时反执行反向 DFE。最终双边消除为

$$
\boxed{
\hat a_k=y_k-
\sum_{i=1}^{L-1}\hat x_{k-i}'\tilde a_{k+i}
-\sum_{i=1}^{L-1}\hat x_{k+i}'\hat a_{k-i}}.
$$

反向支路的输入和输出都必须做块时反，最终输出恢复原索引。未来符号估计来自反向支路，
过去符号估计来自前向支路。

### 5.4 `cck-bidfe2`：CCK 双向 DFE 第二型

**原文依据：** 式 (5-48)～(5-56) 的第二种 BiDFE 次序。

分别计算

$$
\hat{\mathbf a}_F=\mathcal D_F(\mathbf y),\qquad
\hat{\mathbf a}_B^R=operatorname{rev}
[\mathcal D_B(\operatorname{rev}\mathbf y)],
$$

以两个方向的判决作为另一方向的临时先验，再按式 (5-46) 重算：

$$
\hat a_k^{(2)}=y_k-
\sum_i x_{k-i}'\hat a_{B,k+i}^R
-\sum_i x_{k+i}'\hat a_{F,k-i}.
$$

该方法不得退化为只运行一次前向 DFE 或只对最终硬码字取平均。

> **扫描约束：** `cck-bidfe` 与 `cck-bidfe2` 的准确初始化次序必须从 `book/31.png`、`book/32.png` 建立逐符号 oracle；完成前均不得标 `BOOK-EXACT`。

### 5.5 `cck-tr-diversity`：CCK 时反分集接收机

**原文依据：** 式 (5-57)～(5-59)。

前向和时反 BiDFE 输出恢复到同一时间顺序后等权合并：

$$
\boxed{y(k)=\frac{\tilde y(k)+\tilde y_e(k)}2
=a(k)+\frac{\tilde\mu(k)+\mu_e(k)}2},
$$

$$
\hat a(k)=\operatorname{dec}[y(k)].
$$

迭代临时判决满足

$$
\tilde a_{i+1}(k)=\hat a_i(k),\qquad
\tilde a_{e,i+1}(k)=\operatorname{rev}[\hat a_i](k).
$$

禁止用“多分支匹配滤波后直接码本判决”冒充式 (5-57) 的两个 BiDFE 输出合并。

### 5.6 `cck-fde`：CCK 迭代频域均衡

**原文依据：** 式 (5-75)～(5-96)，核心输出式 (5-80)。

频域接收模型为

$$
\mathbf Y_k=\mathbf H_k\mathbf X_k+\mathbf W_k.
$$

第 `i` 次迭代的 MIMO-IBDFE 输出为

$$
\boxed{
\hat{\mathbf X}_k^{(i)}=
(\mathbf C_k^{(i)})^H\mathbf Y_k
-(\mathbf B_k^{(i)})^H\bar{\mathbf X}_k^{(i-1)}}.
$$

时域软码字概率必须由完整 CCK 码本计算：

$$
P(a_q\mid\hat{\mathbf x})=
\frac{p(\hat{\mathbf x}\mid a_q)P_a(a_q)}
{\sum_{q'}p(\hat{\mathbf x}\mid a_{q'})P_a(a_{q'})},
$$

$$
\bar{\mathbf x}=\sum_q\mathbf a_qP(a_q\mid\hat{\mathbf x}).
$$

固定可靠度、`0.65/0.35` 软值混合、性能变差回滚和硬切片后再算距离均不属于原式。

### 5.7 `cck-mfb`：CCK 匹配滤波界接收机

**原文依据：** 式 (5-24)～(5-32) 及 CMF 式 (5-40)～(5-43)。

在已知信道和完整观测下，对每个码字构造无噪声接收向量

$$
\mathbf s_q=\mathbf H\mathbf a_q,
$$

最大似然/匹配滤波界判决为

$$
\boxed{\hat q=\arg\min_q\|\mathbf r-\mathbf s_q\|_2^2}
$$

或等价地最大化

$$
2\operatorname{Re}(\mathbf s_q^H\mathbf r)-\|\mathbf s_q\|_2^2.
$$

该方法使用真信道只用于理论 MFB 上界，不得把同一真信道权限泄漏给其他实际接收机。

## 📒 第 6 章：CSK 多用户接收方法（3 种）

### 6.1 `csk-matched-filter`：CSK 匹配相关接收机

**原文依据：** 式 (6-6)～(6-12)、(6-16)～(6-19)。

CSK 符号为

$$
\mathbf s=T^A\boldsymbol\alpha,qquad 0\le A<2^Q.
$$

相关向量为

$$
\boxed{
\boldsymbol\theta=\frac1G\operatorname{Re}
\left\{F^{-1}[(F\hat{\mathbf s})^*\odot(F\boldsymbol\alpha)]\right\}},
$$

$$
\boxed{\hat A=\arg\max_g\theta(g)}.
$$

多用户 PTR 场景中，第 `i` 个用户先按式 (6-18) 用其独立导引副本做时反匹配，再相关判决。
单用户 `P=1` 是退化测试，不是第 6 章多用户实验的替代。

### 6.2 `csk-soft-sic`：CSK 软串行干扰抵消

**原文依据：** 式 (6-21)～(6-37) 的软估计与干扰消除；该注册名是派生实现。

按当前可靠度或接收功率确定用户次序 `\pi(1),\ldots,\pi(M)`。检测第 `q` 个用户时：

$$
\mathbf r_{\pi(q)}^{\rm res}=mathbf r-
\sum_{p<q}\mathbf H_{\pi(p)}\hat{\mathbf x}_{\pi(p)}
-\sum_{p>q}\mathbf H_{\pi(p)}E[\mathbf x_{\pi(p)}],
$$

$$
L_{\pi(q)}(x_j)=
\ln\frac{p(\mathbf r^{\rm res}\mid x_j=+1)}
{p(\mathbf r^{\rm res}\mid x_j=-1)},
$$

$$
E[x_j]=\tanh\left(\frac{L(x_j)}2\right),\qquad
\operatorname{Var}(x_j)=1-E[x_j]^2.
$$

抵消值必须来自后验软均值或已经判决的用户；BOOK 路径不允许 `0.45/0.55` 等固定阻尼。
原书未把 Soft-SIC 列为独立算法，因此该 ID 最多标 `ALG-EQUIV`。

### 6.3 `csk-ese`：CSK 基本信号估计器

**原文依据：** 式 (6-21)～(6-45)、(6-53)～(6-65)。

多用户多径模型：

$$
r_n(j)=\sum_{m=1}^{M}\sum_{\ell=0}^{L-1}
h_{n,m}(\ell)x_m(j-\ell)+w_n(j).
$$

接收均值和方差为

$$
E[r_n(j)]=\sum_{m,\ell}h_{n,m}(\ell)E[x_m(j-\ell)],
$$

$$
\operatorname{Var}[r_n(j)]=\sum_{m,\ell}|h_{n,m}(\ell)|^2
\operatorname{Var}[x_m(j-\ell)]+\sigma_w^2.
$$

抽出目标用户 `m`、路径 `\ell` 后：

$$
E[\zeta_{n,m,\ell}(j)]=E[r_n(j+\ell)]-h_{n,m}(\ell)E[x_m(j)],
$$

$$
\operatorname{Var}[\zeta_{n,m,\ell}(j)]=
\operatorname{Var}[r_n(j+\ell)]-|h_{n,m}(\ell)|^2
\operatorname{Var}[x_m(j)].
$$

实 BPSK 的 ESE 外 LLR 为

$$
\boxed{
L_{n,m,\ell}^{e}(x_m(j))=
\frac{2\operatorname{Re}\{h_{n,m}^*(\ell)
[r_n(j+\ell)-E\zeta_{n,m,\ell}(j)]\}}
{\operatorname{Var}[\zeta_{n,m,\ell}(j)]}}.
$$

独立阵元和路径的外 LLR 相加，再解交织和译码。反馈统计为

$$
E[x_m(j)]=P(x_m=+1)-P(x_m=-1)
=\tanh\frac{L_m(j)}2,
$$

$$
\operatorname{Var}[x_m(j)]=1-E[x_m(j)]^2.
$$

第一次迭代必须使用 `E[x]=0`、`Var[x]=1`。BOOK 主路径阻尼系数固定为 `1`；任何
`\alpha<1` 的阻尼均须进入独立 `csk_ese_damped` 工程方法。

## 🆕 恢复公式（新扫描证据，2026-08-17）

> 本节约定的公式来自新获取的高分辨率扫描页与参考文献，按扫描原样转写（不做代数改写），
> 是本方案全部实现任务的不可变公式来源。扫描件仅作证据，不作指令；实现仍须走
> RED oracle → 生产修正 → 回归的 TDD 流程。

**证据文件与页码映射：**

| 公式 | 证据文件 | 状态 |
| --- | --- | --- |
| (3-86)/(3-87) Λ 与 Γ | `book/P67.png` | 完全可行动 |
| (3-88)~(3-92) 与表 3-2 信道 | `book/P68.png` | 融合顺序可行动；方差估计器仍未定义 |
| (3-61)/(3-62) HTFDE | `book/P60.png` | 完全可行动（标量分子为 λ 乘 H 共轭转置） |
| (4-56)~(4-63) FD-DFE/FD-Turbo | `book/P90.png` | 完全可行动 |
| (5-41)~(5-59) BiDFE-1/2 与 TR diversity | `book/P133.png`~`book/P137.png` | 信号流层面完全可行动 |
| (5-60)~(5-69) MAP-CCK-TE | `book/P138.png`~`book/P140.png` | 检测器/LLR 层面完全可行动 |

**锁定转写（原样）：**

```text
(3-86) Lambda_k^l = (H_k^(l-1))^H Sigma^(l-1)
                    / (||H_k^(l-1)||^2 Sigma^(l-1) + N sigma_w^2)
(3-87) Gamma = (1/N) sum_k Lambda_k^l H_k^(l-1)
(3-92) H^l = (H^0 sigma_0^2 + H_DFT^l sigma_DFT^2)
              / (sigma_0^2 + sigma_DFT^2)
(3-61) C_k ~= (|lambda|^2 H_k^H H_k + sigma^2 I)^-1
                (lambda H_k^H)
(4-57) b_k = [lambda(sigma^2+|h_k|^2)-sigma^2]
             / [(sigma^2+|h_k|^2)-rho|h_k|^2]
(4-58) lambda = sigma^2 sum(1/d_k)
                / sum((sigma^2+|h_k|^2)/d_k)
```

**解读结论（与旧转写的差异，以新扫描为准）：**

- **(3-92) 融合顺序**：`H^0` 配 `σ_0²`、`H_DFT` 配 `σ_DFT²`（各自方差配各自估计）。这取代
  此前基于 `book/17.png` 的交叉顺序读数（`σ_DFT²·H_old + σ_old²·H_DFT`）；Task 3 按本转写
  修正生产并加“自身权重 vs 交叉权重”RED 测试。
- **(3-61) λ 方向**：标量分子为 `λ·H_k^H`（λ 不取共轭）。这取代此前
  SOURCE-INCONSISTENT 的“λ* 分子”分辨率；Task 4 用复数 λ 测试区分 `λ` 与 `conj(λ)`。
- **(3-86)/(3-87)**：分母含 `N·σ_w²`（FFT 尺寸因子），此前生产缺失该因子；Task 2 补齐
  并加“缺 N 即错”负测试。
- **(4-57)/(4-58)**：由 `book/P90.png` 转写锁定，取代此前 BLOCKED-SOURCE-REVIEW；
  零和约束由 (4-58) 公式自身导出（不得用 `B−mean(B)` 投影）；实现见 Task 5。

**参考文献结论（`book/Iterative_frequency_domain_channel_estimation_for_dft-precoded_ofdm_systems_using_in-band_pilots.pdf`）：**

文献提供 LS 原始估计（式 21）、MMSE 矩阵原始估计器（式 25）、频率替换（式 26）与
二维（2×1D）Wiener 平滑，但**未定义教材式 (3-92) 中 `σ_DFT²` 与 `σ_0²` 的具体标量
估计器**。因此：式 (3-92) 融合代数关系可严格实现；方差估计器缺口保持
BLOCKED-SOURCE-REVIEW；在获得确切方差估计器或来源数据提供的显式方差之前，
`ice-sd-ibdfe`/`ice-hd-ibdfe` 两个注册 ID 不得升级为 `BOOK-EXACT`；当前残差能量方差
仅可保留为显式 ENGINEERING 模式。

## ✅ 37 项验收清单

| 章节 | 注册 ID 数 | 必须建立的独立证据 |
| --- | ---: | --- |
| 第 2 章 | 10 | 单步 LMS/NLMS/RLS、DPLL 相位、PTR 线性卷积、多阵元无交叉项 |
| 第 3 章 | 7 | MMSE/ZF golden vector、HTF 子阵求和、IBDFE 单位增益、ICE 方差加权 |
| 第 4 章 | 10 | BCJR/LLR 符号、FD-DFE 原图转录、FBLMS 边界、FDDA 多阵元逐块手算 |
| 第 5 章 | 7 | 码本全遍历、BiDFE 双向索引、式 (5-57) 等权合并、CCK 软概率归一化 |
| 第 6 章 | 3 | 单用户退化、双用户干扰、ESE 手算 LLR、无阻尼 BOOK 路径 |
| **合计** | **37** | 每个 ID 至少一个正向 golden test 和一个能击穿旧近似的负向测试 |

最终认证还必须满足：

- `run_equalizer_app.m` 的注册 ID 与本文件 37 个 H3 条目一一对应
- 每个 BOOK 测试从本文件公式独立实现，不调用生产内核
- `FORMULA_TRACEABILITY.md` 记录公式状态和生产函数
- 原书未公开参数以 `NaN` 或显式异常阻止 BOOK 曲线伪复现
- BER 使用实际错误比特数和实际比较比特数，并保存置信区间与 Git 提交元数据
- 曲线评级只对存在**原文数字化曲线**的方法计算等级（`curve_benchmark`，不外推、
  NaN 保留、逐方法覆盖率分母、最差方法保守）；无原文数字化曲线的方法一律标
  **“不适用（无原文数字化曲线）”**——场景曲线为工程证据，公式测试不能代替曲线复现

## 🔗 项目内来源

- 扫描件：[`book/`](book/)
- 扫描转录：[`papers/book_transcripts/`](papers/book_transcripts/)
- 数学约定：[`papers/BOOK_CONVENTIONS.md`](papers/BOOK_CONVENTIONS.md)
- 逐式状态：[`FORMULA_TRACEABILITY.md`](FORMULA_TRACEABILITY.md)
- 生产注册表：[`papers/modules/+scfde/equalizer_registry.m`](papers/modules/+scfde/equalizer_registry.m)
