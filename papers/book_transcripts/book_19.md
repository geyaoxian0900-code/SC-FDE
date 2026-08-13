◇ injected env (0) from .env // tip: ◈ encrypted .env [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ custom filepath { path: '/custom/path/.env' }
好的，这是对您提供的《单载波水声通信技术》扫描图四页内容的完整转写。内容已按页码分组，并严格遵循您的要求，包含了所有指定的元素。

---

### 第 4 章 单载波迭代均衡 - 79

**章节标题:** 第 4 章 单载波迭代均衡

**公式:**

*   $P(c) = \prod_{i=1}^{N} P(c_i)$
*   将其代入式 (4-4)，得到比特 $c_k$ 的条件似然比为
    $$LG_1(y) = \ln \frac{\sum_{v \in c_k, v=0} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)}{\sum_{v \in c_k, v=1} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)}$$
    $$= \ln \frac{\sum_{v \in c_k, v=0} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)}{\sum_{v \in c_k, v=1} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)} + L(c_k) \quad (4-5)$$
*   此处定义
    $$L^E(c_k) = \ln \frac{\sum_{v \in c_k, v=0} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)}{\sum_{v \in c_k, v=1} P(y|c) \prod_{i=1, i \ne k}^{N} P(c_i)} \quad (4-6)$$
*   则均衡器输出的外部似然比可表示为
    $$L^E(c_k) = LG_1(y) - L(c_k) \quad (4-7)$$
*   式中，$LG_1(y)$ 为比特 $c_k$ 的后验似然比；$L(c_k)$ 为比特 $c_k$ 的对数似然比。同样，译码器反馈的外部似然信息 $L^D(c_k)$ 可表示为
    $$L^D(c_k) \triangleq \ln \left( \frac{P(c_k=0 | LG_1, \dots, LG_N)}{P(c_k=1 | LG_1, \dots, LG_N)} \right) - \ln \left( \frac{P(c_k=0)}{P(c_k=1)} \right) \quad (4-8)$$
*   在式 (4-8) 中，为改善当前比特的估计精度，需要用到前后比特提供当前比特的取值信息。在达到迭代停止条件后，译码器利用后验似然比 $LG_1(y)$ 对信息比特 $c_k$ 进行判决，具体内容表示为
    $$\hat{c}_k = \begin{cases} 0, & LG_1(y) \ge 0 \\ 1, & LG_1(y) < 0 \end{cases} \quad (4-9)$$

**关键句 (初始化、迭代停止、边界条件、参数取值):**

*   **迭代停止/判决条件:** “在达到迭代停止条件后，译码器利用后验似然比 $LG_1(y)$ 对信息比特 $c_k$ 进行判决”，具体由公式 (4-9) 给出。

---

### 第 4 章 单载波迭代均衡 - 80

**章节标题:** 单载波水声通信技术

**图题:**

*   图 4-3 (2, 1, 3) 卷积编码器
    *   （图中包含标签：输入序列, $M_1$, $M_2$, $M_3$, 输出序列）
*   图 4-4 状态转移图（见附图书后）
    *   （图中包含状态节点 0, 1, 2, 3 和带标签的转移路径，如 x(0,0), y(1,2) 等）

**公式:**

*   $G(D) = [G_1(D), G_2(D)] = [1+D^2, 1+D+D^2] \quad (4-10)$
    *   式中，$D$ 表示延迟 1bit，即上个
