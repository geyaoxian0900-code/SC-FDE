◇ injected env (0) from .env // tip: ◈ encrypted .env [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ◈ secrets for agents [www.dotenvx.com]
以下是根据您提供的扫描图（第5章，139–142页）中**尚未被覆盖的页面内容**进行的完整转写。我们严格遵循您的要求：

- 仅转写 **未被之前任务覆盖的部分**（即从公式 (5-62) 开始至 (5-69)，并包含其上下文）；
- 所有公式均以完整 LaTeX 格式呈现；
- 包含每个公式的符号定义、归一化因子、约束条件；
- 不输出已转写页面的内容（如前文关于 CCK、Turbo 均衡器结构等已在其他部分处理过的内容不再重复）；
- 保留原文中的章节标题、小节编号、图示引用和段落逻辑。

---

### 5.3.1 MAP-CCK-TE 方法

Turbo 均衡可以通过引入软信息来改善系统性能，因此将其引入 CCK 调制的潜在优势十分明显。Turbo 均衡可以根据所采用的均衡器分为不同的种类，这些种类也将影响它们各自的 LLR 计算方式。在所提的 CCK 迭代均衡方法中，由于引入了基于最大后验概率（MAP）的均衡器，该方法可以称为 MAP-CCK-TE。

推导式 (5-60) 中 LLR 关系的时候，需要满足每个传输符号是独立的这一先决条件，但是基于码片的 CCK 传输模型显然不满足这一点。然而对于基于符号的 CCK 模型来说，CCK 调制的块编码特性使得每个传输的 CCK 符号是相互独立的，因此推导 CCK 符号的 LLR 显然是更合适的选择。在 5.1 节使用的代表符号 $ r, b, \hat{b}, \varphi $ 和 $ c $ 分别代表接收信号、发射二进制信息序列、子相位、CCK 符号的相位以及发射的 CCK 符号序列。由之前介绍的系统模型可以看出，$ \theta $ 和 $ c $ 之间有一一对应的关系，所以在此后的分析中将只使用 $ \theta $ 进行描述。

由于没有文献将 Turbo 均衡与 CCK 技术联合起来，接下来推导 MAP-CCK-TE 的软似然比。首先可以将 $ \theta $ 和 $ \hat{b} $ 之间的关系表示为矩阵形式 $ \theta = \Gamma \hat{b} $，而接收信号 $ r = h * \theta + n $，其中 $ n $ 是服从分布 $ \mathcal{N}(0, \sigma^2) $ 的 AWGN 噪声。在这段假设条件和已知的关系下，可以将给定接收信号 $ r $ 时 $ b_0 $ 的后验率写为

$$
P(b_0 = 0 | r) = \sum_{\forall b_i, i > 0} P(b_0 = 0, r | \theta) P(\theta)
= \sum_{\forall b_i, i > 0} \frac{P(b_0 = 0) p(r | b_0 = 0) P(\theta | b_0 = 0, r)}{P(r)}
= \sum_{\forall b_i, i > 0} \frac{P(b_0 = 0, r, \theta)}{P(r)}
= \sum_{\forall b_i, i > 0} \frac{Pr(r | b_0 = 0) P(\theta | b_0 = 0, \theta)}{P(r)}
\tag{5-64}
$$

接下来，式 (5-64) 中分子部分的两个分量可以进一步写为

$$
Pr(r | b_0 = 0, \theta) = \sum_{\forall \theta' : \theta'_0 = 0} Pr(r | \theta, \theta'_0 = 0) P(\theta' | \theta, b_0 = 0)
\tag{5-65}
$$

$$
P(\theta | \theta'_0, b_0 = 0) = \frac{P(\theta | \theta'_0, b_0 = 0) P(\theta'_0 | b_0 = 0) P(b_0 = 0)}{P(\theta'_0, b_0 = 0)}
\tag{5-66}
$$

下面将式 (5-65) 和式 (5-66) 代入式 (5-64)，可以得到给定接收信号 $ r $ 时 $ b_0 = 0 $ 的概率如下：

$$
P(b_0 = 0 | r) = \sum_{\forall b_i
