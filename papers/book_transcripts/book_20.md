◇ injected env (0) from .env // tip: ◈ secrets for agents [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ◈ encrypted .env [www.dotenvx.com]
好的，这是对您提供的《单载波水声通信技术》扫描图的完整转写。内容已按页码分组，并包含了您要求的所有元素。

---

### 第 83 页

**页眉/页脚信息:**
*   章节标题: 第4章 单载波迭代均衡
*   页码: · 83 ·

**正文与公式:**

$L(c_1)$, 输出是后验似然比信息 $L(c_1)$。每个时刻的输入比特信息都会使当前时刻的系统状态产生定向的改变, 所以每一个时刻 $k$ 的输入比特概率可以用所有 $k$ 时刻输入比特引起的状态转移事件的集合的概率表示, 即
$$
\begin{aligned}
L(c_k \mid y) &= \ln \frac{\sum_{s'} P(s_k = s', x_{0,k-1} = s \mid y)}{\sum_{s'} P(s_k = s', x_{0,k-1} = s \mid y)} \\
&= \ln \frac{\sum_{s'} P(y_k \mid s', x_{0,k-1} = s, y) P(s_k = s', x_{0,k-1} = s)}{\sum_{s'} P(y_k \mid s', x_{0,k-1} = s, y) P(s_k = s', x_{0,k-1} = s)}
\end{aligned}
\tag{4-16}
$$

单编码器的编码过程可以认为是一个 Markov 过程, 即时刻 $k$ 之后的状态只为时刻 $k$ 的状态和发生的事件有关, 而与时刻 $k$ 之前的状态和发生过的事件无关。利用条件概率公式 $p(a,b) = p(a)p(b|a)$ 对式 (4-16) 进行分解:
$$
\begin{aligned}
P(s_k, x_{0,k-1}, y) &= P(y_k, y_{k+1:N}, y_{1:k-1}) P(s_k, x_{0,k-1} \mid y_k, y_{k+1:N}, y_{1:k-1}) \\
&= \alpha_k(s_k) \gamma_k(s_{k-1}, s_k) \beta_k(s_k)
\end{aligned}
\tag{4-17}
$$
式中, $\alpha_k$、$\beta_k$ 可以用 $\gamma_k$ 分别进行正向、反向递推:
$$
\alpha_k(s_k) = \sum_{s_{k-1}} \alpha_{k-1}(s_{k-1}) \gamma_k(s_{k-1}, s_k)
\tag{4-18}
$$
$$
\beta_k(s_k) = \sum_{s_{k+1}} \beta_{k+1}(s_{k+1}) \gamma_{k+1}(s_k, s_{k+1})
\tag{4-19}
$$

其中对于初始边界值的设定, 一般情况下编码器系统的初始状态为 0, 即对应的开始时刻系统状态为 0 的概率值为 1, 对应的 $\alpha_0 = [1 \ 0 \ 0 \ 0]^T$。而对于 $\beta$ 则分两种情况: 一种情况是在编码过程中在末尾加入一定数量的 0 使得系统的最终状态变为 00, 对应的 $\beta_N = [1 \ 0 \ 0 \ 0]^T$; 另一种情况是编码时并未加入 0, 对应的系统最终状态未知, 此时可设置为最终时刻的系统各状态的概率相等, 对应于 $\beta_N = [1 \ 1 \ 1 \ 1]^T$。

在 BCJR 算法的全部过程中, 关键的是 $\gamma_k(s_{k-1}, s_k)$ 的计算:
$$
\begin{aligned}
\gamma_k(s_{k-1}, s_k) &= P(c_{k,1}, c_{k,2} \mid s_k) = P(c_{k,1} \mid s_k) P(c_{k,2} \mid s_k, c_{k,1}) \\
&= \begin{cases} P(b_j = b) P(c_{k,1} = c_1 \mid y) P(c_{k,2} = c_2 \mid y), & (k,k+1) \in B \\ 0, & (k,k+1) \notin B \end{cases}
\end{aligned}
\tag{4-20}
$$
式中, $b
