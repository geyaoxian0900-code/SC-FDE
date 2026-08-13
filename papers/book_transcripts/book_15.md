◇ injected env (0) from .env // tip: ◈ secrets for agents [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ custom filepath { path: '/custom/path/.env' }
以下是根据提供的《单载波水声通信技术》扫描图（四页拼图）的完整转写内容，按页码分组输出：

### 第 3 章 单载波时域均衡 - 59 -

#### 3.3 单载波时频域联合均衡

##### 3.3.1 时频域联合均衡系统模型

上面讨论的频域均衡器属于线性均衡器，判决反馈均衡器在频率选择性衰落水声信道中能够获得更佳性能。在常规的 DFE 中，为避免干扰后续符号，对数据符号进行逐符号判决、滤波并立即反馈的操作。因为块 FFT 信号处理中存在无法消除的延迟，所以这种即时滤波判决反馈无法在频域内完成 DFE，时频域联合均衡算法避免了上述常规 DFE 的反应延迟问题，即前向滤波分支在频域实现，而反向滤波分支在时域实现。常规的时频域联合均衡器结构如图 3-11 所示，其反馈系数需要通过时域或频域计算获得[3]。

![图 3-10 有无相位补偿的效果](attachment://image.png)

**图 3-10 有无相位补偿的效果**

与 2.3.2 节所述的被动时反均衡方法类似，本节给出了一种 SC-FDE 系统的时域 - 频域联合判决反馈均衡器（hybrid time-frequency domain decision feedback equalizer, HTF-DFE），以获得一定的空间分集增益，减少信号的相位波动，消除由信道估计误差造成的残余 ISI。同时，以固定的接收机参数实现多数水声信道下

![图 3-11 常规时频域联合均衡器结构](attachment://image-1.png)

**图 3-11 常规时频域联合均衡器结构**

### 第 3 章 单载波时域均衡 - 60 -

的稳定传输[21]。HTF-DFE 接收机结构如图 3-12 所示，包括常规多通道频域均衡器和内嵌 DPLL 的自适应时域 DFE。多通道接收阵元子阵的数量为 \( P \)，每个子阵含 \( K \) 个阵元，子阵中 \( K \) 个阵元的接收信号通过 FFT 转换为频域形式，再进行频域联合均衡。之后通过 IFFT 变为单路时域输出信号，共计 \( P \) 路时域信号，其中 \( 1 \leqslant P \leqslant M \)，此结构和 2.4 节中的子阵被动时反类似，不同之处在于频域均衡部分，其中每个支路的均衡器系数 \( C_k \) 为

\[
C_k = (\tilde{H}_k^{\mathrm{H}} \Phi_{kk} \tilde{H}_k + \sigma^2 I)^{-1} \tilde{H}_k^{\mathrm{H}} \Phi_{kk}^{1/2}
\]
\[
= (\lambda_i^2 \tilde{H}_k^{\mathrm{H}} \tilde{H}_k + \sigma^2 I)^{-1} (\lambda_i \tilde{H}_k^{\mathrm{H}})
\tag{3-61}
\]

每个子阵含 \( K \) 个阵元，则 \( K \) 路信号频域联合均衡后，经 IFFT 后的时域信号可表示为

\[
x_m = F^{\mathrm{H}} X_k
\]
\[
= F^{\mathrm{H}} \left( \sum_{k=1}^{K} C_k R_k \right), \quad 1 \leqslant m \leqslant P
\tag{3-62}
\]

![图 3-12 HTF-DFE 接收机结构](attachment://image-2.png)

**图 3-12 HTF-DFE 接收机结构**

如图 3-12 所示，经过子阵频域联合均衡输出后获得 \( P \) 路时域信号，再通过 \( P \) 路内嵌二阶 DPLL 的时域自适应判决反馈均衡器，HTF-DFE 中多通道部分利用频域均衡降低了计算量，HTF-DFE 中单通道内嵌 DPLL 的判决反馈均衡器可进一步消除残余码间干扰、相位波动的影响，同时由于锁相环的因素，可以避免常规 FDE 中的相位补偿部分。

类似于单载波时域均衡章节中所述的双向判决反馈均衡器[
