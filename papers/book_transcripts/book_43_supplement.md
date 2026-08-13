◇ injected env (0) from .env // tip: ⌁ auth for agents [www.vestauth.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ◈ encrypted .env [www.dotenvx.com]
好的，这是对您提供的《单载波水声通信技术》扫描图（第183-184页）中尚未覆盖内容的完整转写。

---

### 第183页

为了提高性能，本节采用了软解调方法。假设 $d_i = [d_i(1) \ d_i(2) \cdots d_i(Q)]^T$ 表示由 $\tilde{x}_i$ 的 CSK 信号映射的编码信息。令 $d_i^A$ 表示转换为十进制的序列 $A (0 \le A \le 2^{Q\omega} - 1)$，对应的 CSK 信号是 $s_i^A$。根据式 (6-51) 和式 (6-52)，$\theta(g)$ 的 PDF 为
$$ P(\theta(g)|s_i=s_i^A)= \begin{cases} \frac{1}{\sqrt{2\pi\sigma_g^2}}\exp\left(-\frac{(\theta(g)-1)^2}{2\sigma_g^2}\right), & g=A \\ \frac{1}{\sqrt{2\pi(\sigma_v^2+\sigma_g^2)}}\exp\left(-\frac{(\theta(g))^2}{2(\sigma_v^2+\sigma_g^2)}\right), & \text{其他} \end{cases} \tag{6-53} $$
假设的 $\theta_i$ 分量是独立的，则有
$$ P(\theta_i|d_i=d_i^A)=\prod_{g=1}^G P(\theta_i(g)|d_i=d_i^A)=\prod_{g=1}^G P(\theta_i(g)|s_i=s_i^A) \tag{6-54} $$
由式 (6-53) 得
$$ \begin{aligned} P(\theta_i|d_i=d_i^A) &= \frac{1}{\sqrt{2\pi\sigma_g^2}}\left(\frac{1}{\sqrt{2\pi(\sigma_v^2+\sigma_g^2)}}\right)^{G\omega} \exp\left(-\sum_{g:A(g)=A}\frac{(\theta_i(g))^2}{2(\sigma_v^2+\sigma_g^2)}-\frac{(\theta_i(A)-1)^2}{2\sigma_g^2}\right) \\ &= A\exp\left(\frac{(\theta_i(A))^2}{2(\sigma_v^2+\sigma_g^2)}-\frac{(\theta_i(A))^2}{2\sigma_g^2}-\frac{1}{\sigma_g^2}\right) \end{aligned} \tag{6-55} $$
式中
$$ A=\frac{1}{\sqrt{2\pi\sigma_g^2}}\left(\frac{1}{\sqrt{2\pi(\sigma_v^2+\sigma_g^2)}}\right)^{G\omega}\exp\left(-\sum_{g=1,g \ne A}^{G\omega}\frac{(\theta_i(g))^2}{2(\sigma_v^2+\sigma_g^2)}-\frac{1}{\sigma_g^2}\right) \tag{6-56} $$
$A$ 对于指定的 $\theta_i$ 为常数。

编码位 $d_i(q)$ 的外部对数似然比为
$$ e_{\text{CSK}}(d_i(q)) = L_{\text{post}}(d_i(q)) - L_{\text{prior}}(d_i(q)) \tag{6-57} $$
式中，$L_{\text{post}}(d_i(q))$ 是先验信息：
$$ L_{\text{post}}(d_i(q)) = \ln \frac{P(d_i(q)=0)}{P(d_i(q)=1)} \tag{6-58} $$
在第一次内层迭代中，先验信息为零。

---

### 第184页

后验 LLR 为
$$ L_{\text{post}}(d_i(q)) = \ln \left\{ \frac{P(d_i(q)=0|\theta_i)}{P(d_i(q)=1|\theta_i)} \right\} = \ln \left\{ \frac{\sum_{\forall d_i, d_i(q)=0} P(\theta_i|d_i)P(d_i)}{\sum_{\forall d_i, d_i(q)=1} P(\theta_i|d_i)P(d_i)} \right\} \tag{6-59} $$
则式 (6-
