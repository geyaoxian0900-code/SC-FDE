◇ injected env (0) from .env // tip: ⌘ override existing { override: true }
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ enable debugging { debug: true }
根据您提供的图片（第105-106页），以下是尚未覆盖的页面内容转写，包含公式 (4-70) 到 (4-73)：

---

**$W_{n+1}(k)=W_{n}(k)+\frac{\mu_{d} F G E^{*}(k) \odot E(k)}{\varepsilon+R_{x_{e}}^{*}(k) R_{x_{e}}(k)}$**
(4-70)

式中，$\mu_d$ 是滤波器的自适应步长；$\varepsilon$ 是一个固定的正则化系数，避免 0 值除数；$G$ 是梯度约束矩阵。为了确保频域 NLMS 算法和时域 NLMS 算法的完全对应，其表达式为

**$G=\left[\begin{array}{ccc}I_{N \times N_{f}} & 0_{N_{f} \times N} & 0_{N_{f} \times N_{b}} \\0_{N \times N_{f}} & 0_{N \times N} & 0_{N \times N_{b}} \\0_{N_{b} \times N_{f}} & 0_{N_{b} \times N} & 0_{N_{b} \times N_{b}}\end{array}\right]$**
(4-71)

$E(k)$ 是误差向量的频域表示，其时域表示为

**$e(k)= \begin{cases}x(k)-\hat{x}(k), & k N \leqslant L_{\text {train }} \\ \hat{x}(k)-\tilde{x}(k), & \text { 其他 }\end{cases}$**
(4-72)

这里，$L_{\text {train }}$ 表示训练序列长度，因为只关心当前要检测的数据块，频域误差向量可以表示为

**$E(k)=F\left[0_{N_{f} \times 1} ; e(k) ; 0_{N_{b} \times 1}\right]$**
(4-73)

相比基于 MMSE 的频域均衡，频域自适应均衡技术的优点在于不需要在发射端插入 CP，也不需要在接收端进行信道估计。上述频域自适应均衡在时不变或者慢时变条件下展现出了很好的性能。但如果信道是具有长多径延迟扩展的快速时变信道，频域自适应均衡则会面临一些挑战，主要是因为与 RLS 算法相比，LMS 算法固有的缺点是收敛速度相对较慢，而 BLMS 算法则加剧了这一缺点。BLMS 算法每 $N$ 个符号更新一次滤波器系数，$N$ 与数据子块长度保持一致，一方面，频域自适应均衡需要在数据开始时插入一定长度的训练序列确保滤波器收敛到稳态，较大的 $N$ 则会导致较长的训练序列，这造成了频谱效率的损失；另一方面，
