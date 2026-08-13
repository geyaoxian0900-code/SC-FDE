◇ injected env (0) from .env // tip: ⌘ override existing { override: true }
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ custom filepath { path: '/custom/path/.env' }
根据您提供的图片，以下是尚未覆盖的页面内容转写：

### 第 5 章 单载波互补码扩频

#### 135 页

由式 (5-41) 可得

\[ x_{i}^{*}=x_{n} \tag{5-42} \]

该关系由 CMF 和 CIR 的关系确定，如图 5-4（b）所示，复合信道冲激响应按幅度最大的路径对称。需要注意的是，CMF 输出噪声 \( \mu_k \) 是有色高斯噪声，后续的检测算法将忽略该噪声的相关性，该噪声为

\[ \mu_{k}=\sum_{l=0}^{L} h_{l}^{*} n_{k+l} \tag{5-43} \]

根据式 (5-42) 的对称性，可以将式 (5-40) 变为

\[
\begin{aligned}
y_{k} &= x_{k} a_{k}+\sum_{i=1}^{L} x_{k-i} a_{k+i}+\sum_{i=1}^{L-1} x_{k+i} a_{k-i}+\mu_{k} \\
&= x_{k} a_{k}+\sum_{i=1}^{L} x_{k-i} a_{k+i}+\sum_{i=1}^{L-1} x_{k+i}^{*} a_{k-i}+\mu_{k} \\
&= x_{k} a_{k}+\sum_{i=1}^{L} x_{k-i}^{*} a_{k+i}+\sum_{i=1}^{L-1} x_{k+i}^{*} a_{k-i}+\mu_{k}
\end{aligned} \tag{5-44}
\]

对信道相关函数进行归一化，有 \( x_0 = 1 \)，则

\[ y_{k}=a_{k}+\sum_{i=1}^{L} x_{k-i}^{*} a_{k+i}+\sum_{i=1}^{L-1} x_{k+i}^{*} a_{k-i}+\mu_{k} \tag{5-45} \]

#### 136 页

式 (5-45) 右边第二项是未来的 GCCK 符号对当前 GCCK 符号的多径干扰，即前置 ISI；第三项是过去的 GCCK 符号对当前 GCCK 符号的多径干扰，即后置 ISI；第四项是噪声。

##### 3. 双向判决反馈均衡器

由式 (5-45) 可知，为了正确判断发送的 GCCK 符号，首先需要对前置和后置 ISI 进行估计以消除它们对当前 GCCK 检测的影响，可以获得

\[ \hat{a}_{k}=y_{k}-\sum_{i=1}^{L} x_{k-i}^{*} \tilde{a}_{k+i}-\sum_{i=1}^{L-1} x_{k+i}^{*} \hat{a}_{k-i} \tag{5-46} \]

式中，\( \tilde{a}_{k+i} \) 和 \( \hat{a}_{k-i} \) 是过去 GCCK 符号和未来 GCCK 符号的估计。由式 (5-46) 可知，为了消除前置和后置 ISI，必须先获得当前 GCCK 符号的前面和后面的 GCCK 符号的估计。采用常规的 DFE 可消除后置 ISI，而为了消除前置 ISI，需引入临时判决（tentative decision）的概念，并同时采用 DFE 消除前置 ISI，其中 DFE 的输出为

\[ \tilde{a}_{k}=y_{k}-\sum_{i=1}^{L-1} x_{k+i}^{*} \hat{a}_{k-i} \tag{5-47} \]

式中，\( \tilde{a}_k \) 是过去 GCCK 符号的临时判决，假设 \( \hat{a} \) 估计正确，则 \( \tilde{a}_k \) 中仅包含如图 5-4（b）所示的后置 ISI 的干扰。为了消除由未来 GCCK 符号造成的前置 ISI，采用分组时间反转（block time reversal, BTR）。所谓 BTR，就是通过倒组一组接收采样信号的序列次序，获得时反信号。对均衡器来说，时反信号所经过的 CIR 变为实际 CIR 的时间反。这种情况下，原始序列的后置 ISI 变成时反序列的前
