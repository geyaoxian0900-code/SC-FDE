根据式 (6-21), 接收信号 \(r_{n}(j)\) 的均值与方差可表示为

$\begin{aligned}& E\left(r_{n}(j)\right)=\sum_{l=0}^{L} \sum_{m=1}^{M} h_{m, n}(l) E\left(x_{m}(j-l)\right) \\& \operatorname{Var}\left(r_{n}(j)\right)=\sum_{l=0}^{L} \sum_{m=1}^{M}\left|h_{m, n}(l)\right|^{2} \operatorname{Var}\left(x_{m}(j-l)\right)+\sigma_{w}^{2}\end{aligned}$

式中, \(E(\cdot)\) 和 \(\operatorname{Var}(\cdot)\) 分别表示均值与方差函数。

进一步, 式 (6-21) 可重写为

$r_{n}(j+l)=h_{n, n}(0) x_{n}(j-l)+\zeta_{n, n}^{(i)}(j)$

式中, \(\zeta_{n, n}^{(i)}(j)\) 为第 \(n\) 个接收机在第 \(j\) 路径上对第 \(m\) 个用户的干扰。 \(\zeta_{n, n}^{(i)}(j)\) 可表示为

$\zeta_{n, n}^{(i)}(j)=r_{n}(j+l)-h_{n, n}(0) x_{n}(j)$

在 IDMA 方法中, 根据中心极限定理, 将 \(\zeta_{n, n}^{(i)}(j)\) 近似为高斯变量。因此式 (6-24) 中 \(r_{n}(j+l)\) 的条件概率密度函数可表示为

$\begin{aligned}P\left(r_{n}(j) \mid x_{n}(j)= \pm 1\right) & =\frac{1}{\sqrt{2 \pi \operatorname{Var}\left(\zeta_{n, n}^{(i)}(j)\right)}} \\& \cdot \exp \left(-\frac{\left(r_{n}(j+l)-\left(\pm h_{n, n}(0)+E\left(\zeta_{n, n}^{(i)}(j)\right)\right)\right)^{2}}{2 \operatorname{Var}\left(\zeta_{n, n}^{(i)}(j)\right)}\right)\end{aligned}$

因此, 对于第 \(n\) 个接收信号, 图 6-10 中 ESE 输出的 \(x_{n}(j)\) 的外部对数似然比 (LLR)可定义为

$e_{\mathrm{ESE}}^{\text {out }}\left(x_{n}(j)\right)=\ln \frac{P\left(r_{n} \mid x_{n}(j)=+1\right)}{P\left(r_{n} \mid x_{n}(j)=-1\right)}$

式中, \(\ln\) 表示自然对数。

式 (6-27) 与干扰统计信息 \(\zeta_{n, n}^{(i)}(j)\) 有关。根据式 (6-26) 计算 \(E\left(\zeta_{n, n}^{(i)}(j)\right)\) 和 \(\operatorname{Var}\left(\zeta_{n, n}^{(i)}(j)\right)\) 为

$\begin{aligned}& E\left(\zeta_{n, n}^{(i)}(j)\right)=E\left(r_{n}(j+l)-h_{n, n}(0) E\left(x_{n}(j)\right)\right) \\& \operatorname{Var}\left(\zeta_{n, n}^{(i)}(j)\right)=\operatorname{Var}\left(r_{n}(j+l)-\left|h_{n, n}(0)\right|^{2} \operatorname{Var}\left(x_{n}(j)\right)\right)\end{aligned}$

式 (6-22) 与式 (6-23) 分别给出式 (6-28) 与式 (6-29) 中 \(E(j+l)\) 的统计信息。通过外部的对数似然比 \(e_{\mathrm{ESE}}\left(x_{n}(j)\right)\), 即前一次迭代中信道解码器的输出
