根据提供的扫描图，以下是第 5 章 131-134 页区中尚未覆盖的页面内容转写，包含 (5-30) 到 (5-40) 之间每一个编号公式的完整 LaTeX、符号定义、归一化因子、约束条件。

### 第 131 页

#### 2. 误码率和匹配滤波器界性能分析

GCCK 调制是一种 $M$ 元正交调制，本节分析在 AWGN 下最优接收机的错误概率，如前面所述，在 AWGN 下，最优接收机为最大似然检测：

$\text{argmin} \| \mathbf{r} - \mathbf{a}_i \|^2$

因此，$\mathbf{a}_i$ 可由判决空间 $\mathcal{Z}_i$ 确定，定义为

$Z_i = \{ \mathbf{r} : \| \mathbf{r} - \mathbf{a}_i \| < \| \mathbf{r} - \mathbf{a}_j \|, \forall j \neq i, j=1,2,\cdots,KM \}, \quad i=1,2,\cdots,KM$

式中，$M$ 是基本码字的数量；$K$ 是相应 $\mathbf{a}_i$ 的可能取值。

在 $M$ 元检测中，错误概率为

$P_e = \sum_{i=1}^{KM} P(\mathbf{r} \notin Z_i | \mathbf{a}_i \text{发送}) p(\mathbf{a}_i \text{发送})$

假设 GCCK 码字等概率发送，即

$p(\mathbf{a}_i \text{发送}) = \frac{1}{KM}$

将式（5-27）代入式（5-26）得

$P_e = \frac{1}{KM} \sum_{i=1}^{KM} P(\mathbf{r} \notin Z_i | \mathbf{a}_i \text{发送})$

由于 GCCK 调制的复杂性，符号错误概率的闭式解式（5-28）无法确定，因此将应用一致上界（union bound）对 GCCK 性能进行分析。对 $P(\mathbf{r} \notin Z_i | \mathbf{a}_i \text{发送})$ 采用一致上界，可得

$P(\mathbf{r} \notin Z_i | \mathbf{a}_i \text{发送}) = P\left( \bigcup_{j \neq i} (\mathbf{r} \in Z_j | \mathbf{a}_i \text{发送}) \right) \leqslant \sum_{j \neq i} P(\mathbf{r} \in Z_j | \mathbf{a}_i \text{发送})$

式中，$P(\mathbf{r} \in Z_j | \mathbf{a}_i \text{发送})$ 表示当发送 $\mathbf{a}_i$ 时，判定成 $\mathbf{a}_j$ 的概率，在 AWGN 信道下，为

$P(\mathbf{r} \in Z_j | \mathbf{a}_i \text{发送}) = \int_{d_{ij}/2}^{\infty} \frac{1}{\sqrt{2\pi N_0}} \exp\left(-\frac{v^2}{N_0}\right) dv$

$= Q\left(\frac{d_{ij}}{\sqrt{2N_0}}\right)$

式中，$d_{ij}$ 是两个 GCCK 码字 $\mathbf{a}_i$ 和 $\mathbf{a}_j$ 之间的欧几里得（Euclidean）距离，定义为

$d_{ij} = \| \mathbf{a}_i - \mathbf{a}_j \|$

$= \sqrt{\sum_{n=1}^{KN} (a_{in} - a_{jn})^2}$

将式（5-29）、式（5-30）代入式（5-28）可得 GCCK 的一致上界为

$P_e \leqslant \frac{1}{KM} \sum_{i=1}^{KM} \sum_{j \neq i}^{KM} Q\left(\frac{d_{ij}}{\sqrt{2N_0}}\right)$

式中，对应于 GCCK-QPSK-4R、GCCK-QPSK-
