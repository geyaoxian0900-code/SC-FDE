
---

### 第 4 章 单载波迭代均衡 - 107 -

为了跟踪信道动态，$N$ 应该选择一个较小的值，但滤波器的长度必须大于信道延迟扩展。对于传统的 FDBNLMS 算法来说，可能会出现滤波器长度不足的情况导致稳态 MSE 增加。因此，$N$ 的选择会造成收敛速度和频潜效率之间的冲突。为了解决上述的问题，本章提出了一种新的频域自适应均衡方法在快速时变水声信道上实现频域均衡。

#### 4.5.2 频域直接自适应 Turbo 均衡

在传统的 FDBNLMS 算法中，滤波器更新的频率与数据子块的长度保持一致。为此，可以采用一种滑动窗口机制来分离这两个参数。进一步，在线性频域均衡器的基础上，选择采用频域的判决反馈均衡结构，并将其与软译码器结合，实现频域直接自适应 Turbo 均衡器 (frequency domain direct adaptive turbo equalizer, FDDA-TEQ) [19]。图 4-25 给出了 FDBNLMS 的频域自适应判决反馈均衡器的结构框图。


*(图 4-25 FDBNLMS 的频域自适应判决反馈均衡器)*

---

### 第 4 章 单载波迭代均衡 - 108 -

在第 $k$ 个数据子块的处理过程中，前向滤波器的输入数据为
$$
\begin{aligned}
y_{re}^T(k) &= [y_{re}((k-1)N_c - N_f + 1) \ y_{re}((k-1)N_c - N_f + 2) \ \cdots \ y_{re}((k-1)N_c)]^T \\
y_{im}^T(k) &= [y_{im}((k-1)N_c - N_f + 1) \ y_{im}((k-1)N_c - N_f + 2) \ \cdots \ y_{im}((k-1)N_c)]^T \\
y_{re}^T(k) &= [y_{re}((k-1)N_c + N + 1) \ y_{re}((k-1)N_c + N + 2) \ \cdots \ y_{re}((k-1)N_c + N_f)]^T \\
r_m(k) &= [y_{re}^T(k) \ y_{im}^T(k) \ y_{re}^T(k) \ y_{im}^T(k)]^T
\end{aligned}
\tag{4-74}
$$
同理，反向滤波器的输入数据为
$$
\begin{aligned}
\tilde{x}^T(k) &= [\tilde{x}((k-1)N_c - N_r + 1) \ \tilde{x}((k-1)N_c - N_r + 2) \ \cdots \ \tilde{x}((k-1)N_c)]^T \\
\tilde{x}^T(k) &= [\tilde{x}((k-1)N_c + N + 1) \ \tilde{x}((k-1)N_c + N + 2) \ \cdots \ \tilde{x}((k-1)N_c + N_r)]^T \\
\tilde{x}(k) &= [\tilde{x}^T(k) \ \tilde{x}^T(k)]^T
\end{aligned}
\tag{4-75}
$$
第 $k$ 次处理和第 $k+1$ 次处理有一部分数据是重叠的，$N_c(N_c < N)$ 是滑动窗口步长。图 4-26 给出了所提出的 AFDE 接收机的滑动窗口策略。


| 第k次处理 | $y_{re}^T(k)$ | $y_{im}^T(k)$ | $y_{re}^T(k)$ |
| :--- | :---: | :---: | :---: |
| 第k+1次处理 | $y_{re}^T(k+1)$ | $y_{im}^T(k+1)$ | $y_{re}^T(k+1)$ |
| | $-N_f$ | $N$ | $N_f$ |
| | | $N_c$ | |

图 4-26 滑动窗口策略

基于该滑动窗口
