◇ injected env (0) from .env // tip: ◈ secrets for agents [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ multiple files { path: ['.env.local', '.env'] }
以下是根据您提供的《单载波水声通信技术》扫描图（第65页和第66页）的完整转录内容，严格覆盖公式 (3-66) 至 (3-80)，包含所有符号定义、归一化因子、约束条件及推导正文：

---

**第 65 页**

式中，$ d_k $ 为发射的 MPSK 信号；$ \hat{d}_k $ 为均衡器输出信号；$ N $ 为发射符号数。

不同均衡器输出信号星座图如图 3-15 所示。其中，图 3-15（a）为单通道频域均衡（FDE）输出信号的星座图，误码率为 $ 7.0 \times 10^{-2} $，输出信噪比为 2.4dB；图 3-15（b）为 6 通道频域均衡输出信号的星座图，误码率为 $ 1.6 \times 10^{-2} $，输出信噪比为 3.9dB；图 3-15（c）和（d）分别为时频域联合均衡器输出信号 $ P=1 $ 和 $ P=2 $ 的星座图，误码率均为 $ 2.7 \times 10^{-4} $，输出信噪比分别为 8.2dB 和 8.6dB；图 3-15（e）

此时，均衡器输出信号的均方误差为

$$
J^{(0)} = \frac{1}{N} \sum_{n=0}^{N-1} E[|\hat{x}_n - x_n|^2]
= \frac{1}{N} \sum_{k=0}^{N-1} E[|C_k^* R_k - \tilde{B}_k^* \hat{X}_k^{(-1)} - X_k|^2]
\tag{3-67}
$$

对于反向滤波器，还有约束条件为

$$
\sum_{k=0}^{N-1} B_k^* = 0
\tag{3-68}
$$

最小化式 (3-68)，得到最优的滤波器系数为

$$
B_k^* = \frac{r_{x_k, \hat{x}_k^{(-1)}}}{M_{\hat{x}_k}} [H_k C_k^* - \gamma], \quad 0 \leq k \leq N-1
\tag{3-69}
$$

$$
C_k^* = \frac{H_k^*}{N \sigma_w^2 + M_{X_k} \left(1 - \frac{|r_{x_k, \hat{x}_k^{(-1)}}|^2}{M_{\hat{x}_k} M_{X_k}}\right) |H_k|^2}, \quad 0 \leq k \leq N-1
\tag{3-70}
$$

式中，$ \sigma_w $ 为噪声方差。

对于第一次迭代，没有反馈的信息，所以 IBDFE 就等同于 MMSE 均衡：

$$
C_k^* = \frac{H_k^*}{N \sigma_w^2 + M_{X_k} |H_k|^2}
\tag{3-71}
$$

上述均衡器采用的是存在性能损失的硬判决方式，且需要估计判决信号与发射信号的相关性。同时滤波器的设计过程中需要利用信道信息。而由于水声信道的时变性，利用初始训练序列估计的信道可能出现失配。在传统的 IBDFE 中，迭代时一直保持原来的信道，因此当出现信道失配时，系统性能将变得越来越差。

### 3.4.1 块迭代软判决反馈均衡

本节提出基于迭代信道估计的块迭代软判决反馈均衡器（iterative channel estimation soft decision iterative block feedback equalizer, ICE-SD-IBDFE）。其结构框图如图 3-17 所示。对于该均衡器的输出结果，采用软判决的方式，并将符号的

---

**第 66 页**

似然比进行反馈，进而提高均衡器性能 [25]。同时提出联合训练序列和面向判决的迭代信道估计方法，将反馈的信号估计结果作为迭代过程中对信道进行重新估计的依据。为了防止错误扩展的发生导致系统性能下降，对估计的信道进行加权。

对于第 $ l $ 次迭代，均衡器的输出为

$$
\hat{X}^l = (C^l)^H R - (B^l)^H \hat{X}^{l
