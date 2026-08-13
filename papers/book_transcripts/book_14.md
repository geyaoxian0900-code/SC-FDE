
---

### 第 3 章 单载波频域均衡 - 55

之间的相对运动、系统中的 A/D 和 D/A 采样误差以及水流的变化等因素引起；$\varphi_{k,0}$ 是由定时误差引起的初始相位旋转（phase rotating）；$w(k,n)$ 是加性高斯白噪声，方差为 $\sigma^2$。

对应的第 $k$ 个接收数据块可表示为
$$ r(k) = [r(k,0), r(k,1), \dots, r(k,N-1)]^T \quad (3-36) $$
为简洁，省略掉数据块标记，接收信号数据块表示为$^{[4,16]}$
$$ r = DHs + w $$
式中，$w$ 为噪声向量；$H$ 为式 (3-14) 所示的循环 Toeplitz 矩阵；$D$ 为多普勒频移引起的相位旋转对角矩阵，可表示为
$$ D = \text{diag}\{e^{j\theta_0}, e^{j\theta_1}, \dots, e^{j\theta_{N-1}}\} \quad (3-38) $$
对式 (3-37) 两边进行 DFT，并根据傅里叶变换的性质 $F^H F = F^H F = I$，可得接收信号的频域形式：
$$ R = Fr $$
$$ = FD F^H F H F^H Fs + W $$
$$ = \Phi \hat{H} S + W \quad (3-39) $$
式中，$\hat{H}$ 为式 (3-18) 所示的对角矩阵；相位矩阵
$$ \Phi = FDF^H \quad (3-40) $$
为一循环矩阵，通常情况下，$\Phi$ 的非对角线元素值与对角元素相比相对较小，可被忽略，且其对角元素相等，则
$$ \Phi = \lambda I \quad (3-41) $$
其中
$$ \lambda \triangleq \Phi(n,n) = \frac{1}{N} \sum_{k=0}^{N-1} e^{j\theta_k}, \quad n=1,2,\dots,N \quad (3-42) $$
对接收频域信号 $R$ 进行均衡，可得
$$ Y = CR $$
$$ = C \Phi \hat{H} S + W \quad (3-43) $$
根据 MMSE 准则，则均衡器系数 $C$ 可表示为
$$ C = (\hat{H}^H \Phi^H \Phi \hat{H} + \sigma^2 I)^{-1} \hat{H}^H \Phi^H $$
$$ = (|\lambda|^2 \hat{H}^H \hat{H} + \sigma^2 I)^{-1} (\lambda \hat{H})^H \quad (3-44) $$
进一步简化和近似可得$^{[16]}$
$$ \hat{s} = F^* C \Phi \hat{H} Fs + \tilde{w} $$
$$ = F^* CHFs + \tilde{w} $$
$$ = A \Phi s + \tilde{w} \quad (3-45) $$

---

### 单载波水声通信技术 - 56

因此 $A$ 是一个 $N \times N$ 的循环矩阵。实际中，矩阵 $A$ 的非对角线元素值可被忽略，则由式 (3-45) 可知
$$ \hat{s}_k = \beta_k s_k + \tilde{w}_k = |\beta_k| e^{j \arg \beta_k} s_k + \tilde{w}_k \quad (3-46) $$
由式 (3-46) 可知，均衡后的信号受到一个复系数 $\beta_k$ 的影响，接收端需要对该信号进行相位补偿。

#### 3.2.1 残余多普勒频移估计

根据式 (3-37) 和式 (3-38)，接收信号受到残余多普勒频移 $f_k$ 引起的相位偏移 $D = \text{diag}\{e^{j\theta_0}, e^{j\theta_1}, \dots, e^{j\theta_{N-1}}\}$ 的影响，其中

