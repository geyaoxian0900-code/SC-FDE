
---

### **第 3 章 单载波频域均衡 - 47**

**图题:**
图 3-3 SC-FDE 系统数据帧格式

**公式及文本:**

SC-FDE 系统采用分帧传输, 其数据帧格式如图 3-3 所示。由同步段、保护间隔、$K$ 个数据块组成, 每个数据块由待传输的 $N$ 个数据符号和长度为 $M$ 的循环前缀组成。

先将数据分成 $K$ 个数据块, 数据块长度为 $N$, 即
$$ s = [s_0, s_1, \cdots, s_{N-1}]^T \tag{3-1} $$

设水声信道为
$$ h = [h_0, h_1, \cdots, h_{L-1}]^T \tag{3-2} $$

假设仅发射一个数据块, 接收信号可表示为
$$ r_k = \sum_{l=0}^{L-1} h_l s_{k-l} + w_k, \quad 0 \le k \le N+L-1 \tag{3-3} $$

对应于发射信号向量, 接收信号向量可表示为
$$ \begin{bmatrix} r_0 \\ r_1 \\ \vdots \\ r_{N-1} \\ r_N \\ \vdots \\ r_{N+L-1} \end{bmatrix} = \begin{bmatrix} h_0 & & & & & \\ h_1 & h_0 & & & & \\ \vdots & \ddots & \ddots & & & \\ h_{L-1} & \cdots & h_1 & h_0 & & \\ 0 & \ddots & & \ddots & \ddots & \\ \vdots & \ddots & \ddots & & \ddots & h_0 \\ & & h_{L-1} & \cdots & h_1 & h_0 \end{bmatrix} \begin{bmatrix} s_0 \\ s_1 \\ \vdots \\ s_{N-1} \end{bmatrix} + w \tag{3-4} $$

式中
$$ r = [r_0, r_1, \cdots, r_{N-1}, r_N, \cdots, r_{N+L-1}]^T \tag{3-5} $$

信道矩阵为$(N+L-1) \times N$。若将每个数据块后面的 $M$ ($M>L$) 个符号复制到块首作为循环前缀, 其作用和 OFDM 中的 CP 一致, 获得循环卷积的作用, 可消

---

### **- 48 - 单载波水声通信技术**

**公式及文本:**

除数据块间干扰的影响。插入循环前缀后每个数据块可表示为
$$ s_{N:M} = [s_{-M} \cdots s_{-1} \ s_0 \ s_1 \ \cdots \ s_{N-1}]^T \tag{3-6} $$

而
$$ [s_{-M} \cdots s_{-1}]^T = [s_{N-M} \cdots s_{N-1}]^T \tag{3-7} $$

则单个数据块接收信号变为
$$ \tilde{r} = [r_{-M} \cdots r_{-1} \ r_0 \ r_1 \ \cdots \ r_{N-1} \ r_N \ \cdots \ r_{N+L-1}]^T \tag{3-8} $$

接收端去除掉循环前缀部分, 并且只取 $N$ 点数据, 根据线性卷积的关系可得
$$ \begin{aligned} r_0 &= h_0 s_0 + h_1 s_{-1} + \cdots + h_{L-1} s_{-L+1} \\ r_1 &= h_0 s_1 + h_1 s_0 + \cdots + h_{L-1} s_{-L+2} \\ &\vdots \\ r_{L-1} &= h_0 s_{L-1} + h_1 s_{L-2} + \cdots + h_{L-1} s_0 \\ r_L &= h_0 s_L + h
