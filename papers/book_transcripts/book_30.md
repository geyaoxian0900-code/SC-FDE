
---

### 第 5 章 单载波互补码键控扩频 - 129 -

**图题:**
- 图 5-1 无 ISI 情况下的最佳接收机

**公式:**

(5-24)
$\arg \min _{i}\left\|\boldsymbol{r}-\boldsymbol{a}_{i}\right\|^{2}$

(5-25)
$Z_{i}=\left(i: \| r-a_{i} \|<\left\|r-a_{j}\right\|, \forall j=1,2, \cdots, K M, j \neq i\right), \quad i=1,2, \cdots, K M$

(5-26)
$P_{e}=\sum_{i=1}^{K M} P\left(r \notin Z_{i} \mid a_{i} \text { 发送 }\right) p\left(a_{i} \text { 发送 }\right)$

(5-27)
$p\left(a_{i} \text { 发送 }\right)=\frac{1}{K M}$

(5-28)
$P_{e}=\frac{1}{K M} \sum_{i=1}^{K M} P\left(r \notin Z_{i} \mid a_{i} \text { 发送 }\right)$

(5-29)
$P\left(r \notin Z_{i} \mid a_{i} \text { 发送 }\right)=P\left(\bigcup_{j \neq i}\left(r \notin Z_{i} \mid a_{i} \text { 发送 }\right)\right) \leqslant \sum_{j \neq i} P\left(r \notin Z_{j} \mid a_{i} \text { 发送 }\right)$

(5-30)
$\begin{aligned} P\left(r \notin Z_{j} \mid a_{i} \text { 发送 }\right) & =\int_{r:\left\|r-a_{j}\right\|<\left\|r-a_{i}\right\|} \frac{1}{\pi N_{0}} \exp \left(-\frac{\left\|r-a_{i}\right\|^{2}}{N_{0}}\right) \mathrm{d} r \\ & =Q\left(\sqrt{\frac{d_{i j}^{2}}{2 N_{0}}}\right) \end{aligned}$

**关键句:**
- GCKC 调制是一种 $M$ 元正交调制...本节分析在 AWGN 下最优接收机的错误概率。
- 因此, $a_i$ 可由判决空间 $Z_i$ 确定。
- 式中, $M$ 是基本码字的数量; $K$ 是相位 $a_k$ 的可能取值。
- 在 $M$ 元检测中, 错误概率为...
- 假设 GCKC 码字等概率发送, 即...
- 由于 GCKC 调制的复杂性, 符号错误概率的闭式解 (5-28) 无法确定, 因此将应用一致上界 (union bound) 对 GCKC 性能进行分析。
- 对 $P(r \notin Z_j | a_i \text{发送})$ 采用一致上界, 可得...
- 式中, $P(r \notin Z_j | a_i \text{发送})$ 表示当发送 $a_i$ 时, 判定成 $a_j$ 的概率。在 AWGN 信道下, 为...
- 式中, $d_{ij}$ 是两个 GCKC 码字 $a_i$ 和 $a_j$ 之间的欧几里得 (Euclidean) 距离。

---

### - 130 - 单载波水声通信技术

**公式:**

(5-31)
$\begin{aligned} d_{i j} & =\left\|a_{i}-a_{j}\right\| \\ & =\sqrt{\sum_{n=1}^{N}\left(a_{i, n}-a_{j, n}\right)^{2}} \end{aligned}$

(5-32)
$P_{e} \leqslant \frac{1}{K M} \sum_{i=1}^{K M} \sum_{j \neq i
