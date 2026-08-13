◇ injected env (0) from .env // tip: ⌁ auth for agents [www.vestauth.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ multiple files { path: ['.env.local', '.env'] }
以下是根据提供的《单载波水声通信技术》扫描图（四页拼图）的完整转写，按页码分组输出：

### 第 4 章 单载波迭代均衡 - 87 -

#### 利用 \(\hat{\mu}\) 和 \(\hat{\sigma}^2\) 可以求得条件概率 \(p(\tilde{x}_k | x_k = s_i)\) 为

\[ p(\tilde{x}_k | x_k = s_i) = \frac{1}{\pi \hat{\sigma}^2} \exp \left( -\frac{|\tilde{x}_k - \hat{\mu}s_i|^2}{\hat{\sigma}^2} \right) \tag{4-42} \]

#### 同时结合符号的先验概率，均衡器输出的似然比 \(L^E(c_{k,j})\) 可按照下面公式进行计算：

\[ L^E(c_{k,j}) = \ln \left( \frac{\sum_{s_i \in S_j^+} p(\tilde{x}_k | x_k = s_i) \prod_{j' \neq j} P(c_{k,j'})}{\sum_{s_i \in S_j^-} p(\tilde{x}_k | x_k = s_i) \prod_{j' \neq j} P(c_{k,j'})} \right) \tag{4-43} \]

式中，\(c_{k,j}\) 表示第 \(k\) 个传输符号的第 \(j\) 比特；\(P(c_{k,j'})\) 表示第 \(k\) 个传输符号的第 \(j'\) 比特取 0 或 1 的先验概率，可按下列公式进行计算：

\[ P(c_{k,j'} = 0) = \frac{1}{1 + e^{-L^D(c_{k,j'})}} \tag{4-44} \]

\[ P(c_{k,j'} = 1) = \frac{e^{-L^D(c_{k,j'})}}{1 + e^{-L^D(c_{k,j'})}} \tag{4-45} \]

式中，\(e^{L^D(c_{k,j'})}\) 是上一次迭代时译码器输出的软信息，在第一次迭代的时候，译码器还没有开始工作，无先验信息，其值为 1。

计算得到的外似然比 \(L^E(c_{k,j})\) 经解交织后作为输入进入译码器，其中译码器采用 MAP 算法进行译码并输出两者之间的差值：

\[ L^D(c_{k,j}) \triangleq \ln \left( \frac{P(c_{k,j} = 0 | L(c_1), \cdots, L(c_K))}{P(c_{k,j} = 1 | L(c_1), \cdots, L(c_K))} \right) - \ln \left( \frac{P(c_{k,j} = 0)}{P(c_{k,j} = 1)} \right) \tag{4-46} \]

对译码器输出的软信息 \(L^D(c_k)\) 进行交织，并进行符号映射，得到符号 \(x_k\) 的符号软估计值：

\[ \bar{x}_k = E(x_k) = \sum_{s_i \in S} s_i P(x_k = s_i) \tag{4-47} \]

式中

\[ P(x_k = s_i) = \prod_{j=1}^J P(c_{k,j} = s_{i,j}) \tag{4-48} \]

表示 \(x_k\) 取值为 \(s_i\) 的概率；\(\prod\) 为乘法运算。定义 \(s_{i,j} \in (0, 1)\)，\(P(c_{k,j} = 1) = \frac{e^{-L^D(c_{k,j})}}{1 + e^{-L^D(c_{k,j})}}\)、\(P(c_{k,j} = 0) = \frac{1}{1 + e^{-L^D(c_{k,j})}}\) 分别表示第 \(k\) 个符号第 \(j\) 比特取 1 或 0 的概率。这样，当得到译码符号软估计后，在接下来的均衡器输出为

\[ \bar{x}_k = \sum_{l=1}^K (f_l^H)^* y_l e^{j\theta_l} - (g_k)^* \bar{x}_k \tag{4-49}
