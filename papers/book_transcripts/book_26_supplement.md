◇ injected env (0) from .env // tip: ⌘ enable debugging { debug: true }
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ multiple files { path: ['.env.local', '.env'] }
根据您提供的图片（第4章 单载波迭代均衡，页码107-110），以下是该部分内容的完整转录。

---

### **第 4 章 单载波迭代均衡**

为了跟踪信道动态，$N$ 应该选择一个较小的值，但滤波器的长度必须大于信道延迟扩展。对于传统的 FDBNLMS 算法来说，可能会出现滤波器长度不足的情况导致稳态 MSE 增加。因此，$N$ 的选择会造成收敛速度和频谱效率之间的冲突。为了解决上述的问题，本章提出了一种新的频域自适应均衡方法在快速时变水声信道上实现频域均衡。

#### **4.5.2 频域直接自适应 Turbo 均衡**

在传统的 FDBNLMS 算法中，滤波器更新的频率与数据子块的长度保持一致。为此，可以采用一种滑动窗口机制来分离这两个参数。进一步，在线性频域均衡器的基础上，选择采用频域的判决反馈均衡结构，并将其与软译码器结合，实现频域直接自适应 Turbo 均衡器 (frequency domain direct adaptive turbo equalizer, FDDA-TEQ) [39]。图 4-25 给出了 FDBNLMS 的频域自适应判决反馈均衡器的结构框图。

**(图 4-25 略：FDBNLMS 的频域自适应判决反馈均衡器)**

在第 $k$ 个数据子块的处理过程中，前向滤波器的输入数据为
$$
\begin{aligned}
y_{re}^T(k) &= [y_{re}((k-1)N_c - N_f + 1) \quad y_{re}((k-1)N_c - N_f + 2) \quad \cdots \quad y_{re}((k-1)N_c)]^T \\
y_{im}^T(k) &= [y_{im}((k-1)N_c + 1) \quad y_{im}((k-1)N_c + 2) \quad \cdots \quad y_{im}((k-1)N_c + N_f)]^T \\
y_{re}^D(k) &= [y_{re}((k-1)N_c + N + 1) \quad y_{re}((k-1)N_c + N + 2) \quad \cdots \quad y_{re}((k-1)N_c + N + N_f)]^T \\
y_{im}^D(k) &= [y_{im}(k) \quad y_{im}(k+1) \quad \cdots \quad y_{im}(k+N_f-1)]^T
\end{aligned}
\tag{4-74}$$
同理，反向滤波器的输入数据为
$$
\begin{aligned}
\tilde{x}^T(k) &= [\tilde{x}((k-1)N_c - N_b + 1) \quad \tilde{x}((k-1)N_c - N_b + 2) \quad \cdots \quad \tilde{x}((k-1)N_c)]^T \\
\tilde{x}^D(k) &= [\tilde{x}((k-1)N_c + N + 1 - N_b) \quad \tilde{x}((k-1)N_c + N + 2 - N_b) \quad \cdots \quad \tilde{x}((k-1)N_c + N)]^T \\
\tilde{X}(k) &= [\tilde{x}^T(k) \quad \tilde{x}^D(k)]^T
\end{aligned}
\tag{4-75}$$
第 $k$ 次处理和第 $k+1$ 次处理有一部分数据是重叠的，$N_s (N_s < N)$ 是滑动窗口步长。图 4-26 给出了所提出的 AFDE 接收机的滑动窗口策略。

**(表 4-26 略：滑动窗口策略)**

基于该滑动窗口策略，滤波器系数每 $N_s$ 个符号更新一次。$N_s$ 可以根据信道的时变程度进行选择。当信道是快速时变时，$N_s$ 需要尽量小以跟踪信道变化；当信道是不变或者慢时变时，$N_s$ 可以选择一个较大的值从而降低复杂度。

$\tilde{x}(k)$ 不同数据块重叠的目的是在不考虑当前检测的第 $k$ 个数据块内部相邻符号间的干扰。需要注意的是，第一次 Turbo 均衡时因为没有先验信息可用，反向滤波器的输入为 0。

经过
