◇ injected env (0) from .env // tip: ⌘ override existing { override: true }
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ multiple files { path: ['.env.local', '.env'] }
根据您提供的扫描图（第 127–128 页），以下是尚未被覆盖页面的完整转写内容，严格包含从 (5-1) 到 (5-23) 之间每一个编号公式或码本定义的完整 LaTeX、符号定义、归一化因子、约束条件：

---

**第 5 章 单载波互补码键控扩频**

· 127 ·

GCCK 调制模式如表 5-2 所示。在表 5-2 中，“—”表示无此种数据通信速率，GCCK-QPSK 表示 $\varphi_0, \varphi_1$ 是 QPSK 调制，而 GCCK-8PSK 表示 $\varphi_0, \varphi_1$ 是 8PSK 调制。比较表 5-2 同方式获得的相同数据通信速率，发现 GCCK-QPSK-6R、GCCK-QPSK-4R 以及 GCCK-QPSK-3R 的性能优于 GCCK-8PSK-6R、GCCK-8PSK-4R 以及 GCCK-8PSK-3R。

**表 5-2 GCCK 调制**

| GCCK-QPSK | GCCK-8PSK | R |
|-----------|-----------|---|
| —         | 12R       | DHPSK |
| 8R        | 11R       | DQPSK |
| 7R        | 10R       | DPSK |
| 6R        | 9R        | —   |
| —         | 6R        | DHPSK |
| 4R        | 5R        | DQPSK |
| 3R        | 4R        | DPSK |
| 2R        | 3R        | —   |

对于不同数据通信速率的 GCCK，接收机需要对其检测算法进行修改，但是不必改变码片速率，这使得硬件的实现更简单。同时为了简洁，仅考虑三种典型的调制模式，分别为 GCCK-QPSK-4R、GCCK-QPSK-8R 和 GCCK-8PSK-12R。其中 GCCK-QPSK-4R 为上面提及的 HR-CCK 模式，而 GCCK-QPSK-8R 对应的是 FR-CCK 模式。对于 GCCK-8PSK-12R 调制，每个 GCCK 符号表示 $12\text{bit}(A_0 \sim A_{11})$，其中 $(b_0, b_1, b_2)$ 对 $\varphi_0$ 进行 DBPSK 编码，所有奇数 GCCK 码字附加 $180^\circ$ 的相位旋转；$\varphi_1, \psi_1, \psi_2$ 分别由 $(b_3, A_0, A_1), (b_4, A_2, A_3), (b_5, A_{10}, b_{11})$ 根据 Gray 编码进行 8PSK 映射。

### 5.1.4 CCK 码片扩展

对于以上提到的 CCK 调制，8 个码片由 $12/8/4$ 位信息比特映射而来，因此其具有较高的数据通信速率，相应地，其扩频增益也相对较低。对于水声信道来讲，信道时延扩展十分严重，采用 8 个码片的 CCK 模式可能依旧不能抵抗多径效应。因此，根据文献[8]中 CCK 码字生成方法的原理，对 CCK 调制进行扩展，以提高其扩频增益。

对于一个长度为 4 的序列 $A, B$，其中，$A = [1\ 1]$，$B = [1\ -1]$，按照下面方式对其进行扩展：

$$
r(i) = \sum_{k=0}^{7} a(k) h(i-k) + w(i)
\tag{5-1}
$$

式中，$r(i)$ 是第 $i$ 个接收采样点；$a(k)$ 是第 $k$ 个发射信号码片；$h(k)$ 是离散时间 CIR；$w(i)$ 是加性高斯白噪声，其均值为 0，方差为 $\sigma^2$。

检测的第一步是估计 CIR。CIR 可以通过前导符号、训练步长来估计。GCCK 接收机的功能在于根据接收到的信号和估计的 CIR 来估计所发送的数据比特，在没有 ISI 时
