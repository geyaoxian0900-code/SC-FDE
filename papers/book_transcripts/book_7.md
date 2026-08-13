
---

### 第 2 章 单载波时域均衡 - 25 -

前向滤波器输入信号为
$r(k) = [r(k) \ r(k+1) \ \cdots \ r(k+N-1)]^T$ (2-26)
设前向滤波器的阶数为 $N$，对前向滤波器的输出进行相位补偿，可得
$p_k = a^H r(k)e^{-j\hat{\theta}_k}$ (2-27)
式中，为简便起见，$a$ 表示 $k$ 时刻 $N \times 1$ 前向滤波器系数列向量；$\hat{\theta}_k$ 是相位偏移估计。

反向滤波器的输入为
$\tilde{d}(k) = [\tilde{d}_{k-1} \ \tilde{d}_{k-2} \ \cdots \ \tilde{d}_{k-M}]^T$ (2-28)
令 $b$ 表示 $k$ 时刻 $M \times 1$ 反向滤波器系数向量，则反向滤波器的输出为
$q_k = b^H \tilde{d}(k)$ (2-29)
利用 $q_k$ 消除前向滤波器输出信号中的码间干扰，计算判决器输入端的符号：
$\begin{aligned} \hat{d}_k &= p_k - q_k \\ &= a^H r(k)e^{-j\hat{\theta}_k} - b^H \tilde{d}(k) \\ &= [a^H \ b^H] \begin{bmatrix} r(k)e^{-j\hat{\theta}_k} \\ -\tilde{d}(k) \end{bmatrix} \\ &= w^H u(k) \end{aligned}$ (2-30)
式中，$w^H$ 是复合均衡器向量；$u(k)$ 是复合输入信号。
计算 $\hat{d}_k$ 和真实值 $d_k$ 之间的估计误差可表示为
$e_k = d_k - \hat{d}_k$ (2-31)
式中，训练模式时 $d_k$ 取已知的训练序列，工作模式时，$d_k$ 由 $\hat{d}_k$ 代替。
接收机各种参数的最优化应通过最小化均方误差 $\text{MSE} = E\{|e_k|^2\}$ 来获得。最小化 MSE 可以通过对各参数求梯度得到，如下：
$\frac{\partial \text{MSE}}{\partial a} = -2E\{r(k)e_k^* e^{-j\hat{\theta}_k}\}$ (2-32)
$\frac{\partial \text{MSE}}{\partial b} = -2E\{\tilde{d}(k)e_k^*\}$ (2-33)
$\frac{\partial \text{MSE}}{\partial \hat{\theta}} = -2\text{Im}\{E[p_k(d_k + q_k)^*]\}$ (2-34)
要迭代均衡器抽头系数，采用梯度算法和自适应算法。
同样地，采用 DPLL 的相位补偿的迭代公式为
$\hat{\theta}_{k+1} = \hat{\theta}_k + K_1 \varphi_k + K_2 \sum_{i=1}^{k} \varphi_i$ (2-35)
式中
$\varphi_k = \text{Im}\{p_k(d_k^* + q_k^*)\}$ (2-36)

---

### - 26 - 单载波水声通信技术

为等效鉴相器的输出，$K_1$ 与 $K_2$ 是 DPLL 的比例系数用于调节增益，通常情况下有
$K_2 = 0.1 \times K_1$ (2-37)
那么，相位补偿的迭代公式可表示为
$\hat{\theta}_k = 2\hat{\theta}_{k-1} - \hat{\theta}_{k-2} + K_2 \times 1.1 \times \varphi_k - K_1 \times \varphi_{k-1}$ (2-38)
内嵌 DPLL 判决反馈均衡的算法总结如下：
$\hat{d}(k) = a^H(k)r(k)e^{-j\hat{\theta}_k} - b^H(k)\
