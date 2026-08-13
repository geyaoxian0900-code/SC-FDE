◇ injected env (0) from .env // tip: ⌘ suppress logs { quiet: true }
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ multiple files { path: ['.env.local', '.env'] }
好的，这是对您提供的《单载波水声通信技术》扫描图四个页面的完整转写。内容已按页码分组，并包含了您要求的所有元素：页码、章节标题、公式、表格、图题以及关键句。

---

### 第 125 页

**页眉/页脚:**
- 页眉: 第 5 章 单载波互补键控扩频
- 页码: · 125 ·

**正文内容:**

GCCK 调制模式如表 5-2 所示。在表 5-2 中，“—”表示无此种数据通信速率，GCCK-QPSK 表示 $\varphi_1$、$\varphi_3$ 是 QPSK 调制，而 GCCK-8PSK 表示 $\varphi_1$、$\varphi_3$ 是 8PSK 调制。比较表 5-2 同方式获得的相同数据通信速率，发现 GCCK-QPSK-6R、GCCK-QPSK-4R 以及 GCCK-QPSK-3R 的性能优于 GCCK-8PSK-6R、GCCK-8PSK-4R 以及 GCCK-8PSK-3R。

**表格:**

**表 5-2 GCCK 调制**
| | GCCK-QPSK | | GCCK-8PSK | $\theta$ |
| :--- | :---: | :---: | :---: | :---: |
| — | | | 12R | DHPSK |
| 8R | | | 11R | DQPSK |
| 7R | | | 10R | DPSK |
| 6R | | | 9R | — |
| — | | | 6R | DHPSK |
| 4R | | | 5R | DQPSK |
| 3R | | | 4R | DPSK |
| 2R | | | 3R | — |

对于不同数据通信速率的 GCCK，接收机需要对其检测算法进行修改，但是不必改变码片速率，这使得硬件的实现更简单。同时为了简洁，仅考虑三种典型的调制模式，分别为 GCCK-QPSK-4R、GCCK-QPSK-8R 和 GCCK-8PSK-12R。其中 GCCK-QPSK-4R 为上面提及的 HR-CCK 模式，而 GCCK-QPSK-8R 对应的是 FR-CCK 模式。对于 GCCK-8PSK-12R 调制，每个 GCCK 符号表示 $12\text{bit}(A_0 \cdots A_{11})$，其中 $(A_0, A_4, A_8)$ 对 $\varphi_1$ 进行 DBPSK 编码，所有奇数 GCCK 码字后加 $180^\circ$ 的相位旋转；$\varphi_2$、$\varphi_3$、$\varphi_4$ 分别由 $(A_1, A_5, A_9)$、$(A_2, A_6, A_{10})$、$(A_3, A_7, A_{11})$ 根据 Gray 编码进行 8PSK 映射。

#### 5.1.4 CCK 码片扩展

对于以上提到的 CCK 调制，8 个码片由 $12/8/4$ 位信息比特映射而来，因此其具有较高的数据通信速率，相应地，其扩频增益也相对较低。对于水声信道来讲，信道时延扩展十分严重，采用 8 个码片的 CCK 模式可能依旧不能抵抗多径效应。因此，根据文献[8]中 CCK 码字生成方法的原理，对 CCK 调制进行扩展，以提高其扩频增益。

对于一个长度为 4 的序列 $A, B_i$，其中，$A_i = [1 \ 1]$，$B_i = [1 \ -1]$，按照下面方式对其进行扩展：

---

### 第 126 页

**页眉/页脚:**
- 页眉: 单载波水声通信技术
- 页码: · 126 ·

**正文内容:**

$$
\begin{bmatrix} A_s \\ B_s \end{bmatrix} = \begin{bmatrix} A_{s-1} & B_{s-1} \\ B_{s-1} & -A_{s-1} \end{bmatrix}
