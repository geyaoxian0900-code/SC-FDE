根据您提供的扫描图（第 5 章，147-150 页），以下是尚未覆盖的页面内容转写。这些内容涵盖了从公式 (5-83) 到 (5-96) 的所有编号公式及其相关描述。

### 第 147 页

将式 (5-80) 中的输出转换到时域得到 $\tilde{x}_{d}$。因为在发射端，发射信号经过了一个循环移位器 $\Pi_{s}$，所以可以假设发射信号之间是相互独立的。这样 $\tilde{x}_{d}^{\prime}$ 可以看作一个期望信号和扰乱信号的和，即

$\tilde{x}_{d}^{\prime}=x_{d}^{\prime}+\tilde{w}_{d}^{\prime}$

(5-81)

式中，扰乱信号 $\tilde{w}_{d}^{\prime}$ 可以看作一个均值为零、方差为 $\sigma_{\tilde{w}_{d}^{\prime}}^{2}$ 的高斯随机变量。因此，对于第 $m$ 个发射阵元的第 $i$ 个符号 $x_{m, i}$，可以得到其第 $l$ 次估计的后验概率为

$P(\tilde{x}_{m, i}=\beta_{j})=\frac{1}{\pi \sigma_{\tilde{w}_{d}^{\prime}}^{2}} \exp \left(-\frac{\left\|\tilde{x}_{d, i}^{\prime}-\beta_{j}\right\|^{2}}{\sigma_{\tilde{w}_{d}^{\prime}}^{2}}\right), \quad \beta_{j} \in B$

(5-82)

扰乱信号的方差 $\sigma_{\tilde{w}_{d}^{\prime}}^{2}$ 可以通过下面公式估计 [20]：

$\sigma_{\tilde{w}_{d}^{\prime}}^{2}=\frac{1}{K} \sum_{k=1}^{K}\left\|\tilde{x}_{d, k}^{\prime}-x_{d, k}^{\prime}\right\|^{2}$

(5-83)

式中，$x_{d, k}^{\prime}$ 为 $\tilde{x}_{d}^{\prime}$ 的硬判决结果。

均衡器的软判决结果可以表示为 $x_{d}^{\prime}$ 的期望，即

$x_{d, e}^{\prime}=\sum_{\beta_{j} \in B} \beta_{j} P(\tilde{x}_{d}^{\prime}=\beta_{j})$

(5-84)

期望信号 $X_{d}^{e x p}$ 的方差为

$\begin{aligned} \Psi_{d+1} & =E\left[\left(X_{d}^{e x p}-\bar{X}_{d}^{e x p}\right)^{H}\right] \\ & =\sum_{k=1}^{K} \sum_{\beta_{j} \in B}\left\|\beta_{j}\right\|^{2} P(\tilde{x}_{d, k}^{\prime}=\beta_{j})-\left\|x_{d, k}^{\prime}\right\|^{2} \end{aligned}$

(5-85)

滤波器的系数可以通过对下面方程优化求解得到 [21]：

$\left\{\begin{array}{l} \min _{c, c^{\prime}} E\left[\left\|x_{d}-x_{d, e}\right\|^{2}\right] \\ \text { s.t. } \sum_{n=-N}^{N} g_{n}^{(q)}=0 \end{array}\right.$

(5-86)

因此滤波器的系数为

$C_{d}^{e q l}=T_{d}^{-1} / \eta^{e q l}$

(5-87)

$B_{d}^{e q l}=H_{d}^{H} C_{d}^{e q l} * e_{q}$

(5-88)

式中

$\eta^{e q l}=\frac{1}{K} \sum_{k=1}^{K} H_{d}^{H} \Sigma_{d}^{-1} T_{d}^{-1}$

(5-89)

$T_{d}^{-1}=\left(H_{d} \Sigma_{d}^{-1} H_{
