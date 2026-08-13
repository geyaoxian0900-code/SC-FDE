
---

### **第 181 页**

**页眉/章节标题:**
第6章 单载波频域移位扩频 · 181 ·

**正文与公式:**

式中，$\otimes$ 表示卷积操作且
$$Q_m(t) = \sum_{k=0}^{K-1} h_m(t) \otimes \hat{h}_m(-t) \quad (6-38)$$
$$\tilde{w}_i(t) = \sum_{m=1}^{M} w_m(t) \otimes \hat{h}_m(-t) \quad (6-39)$$

在式（6-37）中第一项为期望信号，$Q_i(t)$ 为经过 PTR 处理后第 $i$ 个用户的等效信道；第二项是干扰信号，$Q_m(t)$ 是来自第 $m$ 个用户相对于第 $i$ 个用户的等效推理信道；$\tilde{w}_i(t)$ 是方差为 $\sigma_w^2 = \sum_{m=1}^{M} ||\hat{h}_m(t)||^2 \sigma_n^2$ 的噪声。

等效信道 $Q_i(t)$ 是压缩的，可以看作 Sinc 函数。因此，对于之前使用 PTR 处理后的输出，可以再使用 ESE 直接处理。另外 $Q_i(t)$ 的增益比其他 $Q_m(t)(m \ne i)$ 大得多，这也提高了每个用户的 SINR。

一般来说，等效信道 $Q_i(t)$ 的长度为 $\tilde{L} = L + \hat{L} - 1$，其中 $\hat{L}$ 为估计信道 $\hat{h}_m(t)$ 的长度。然而，由于 PTR 处理的压缩特性，$Q_i(t)$ 的主要路径集中在 $\tilde{l} = \hat{L}-1$ 附近。因此，PTR 处理的输出可以重写为
$$y^{(e)}(j) = \sum_{m=1}^{M} \sum_{l=0}^{\tilde{L}-1} Q_m(l)x_m(j-l) + \tilde{w}_i(j) \quad (6-40)$$

经过 PTR 处理将 SIMO 系统变成一个等效的 SISO 系统。

**1. 基本信号估计器**

该接收机的基本信号估计与传统的 IDMA 系统相似。不同之处在于每个用户的输入信号是不同的。$y^{(e)}(j)$ 只代表单个用户。第 $i$ 个用户的统计信息可表示为
$$E(y^{(e)}(j)) = \sum_{m=1, m \ne i}^{M} Q_m(l)E(x_m(j-l)) \quad (6-41)$$
$$\text{Var}(y^{(e)}(j)) = \sum_{m=1, m \ne i}^{M} \sum_{l=0}^{\tilde{L}-1} |Q_m(l)|^2 \text{Var}(x_m(j-l)) + \sum_{l=0}^{\tilde{L}-1} |\hat{h}_m(l)|^2 \sigma_n^2 \quad (6-42)$$
$$E(\zeta_m^{(e)}(j)) = E(y^{(e)}(j+l)) - Q_m(l)E(x_m(j)) \quad (6-43)$$
$$\text{Var}(\zeta_m^{(e)}(j)) = \text{Var}(y^{(e)}(j+l)) - |Q_m(l)|^2 \text{Var}(x_m(j)) \quad (6-44)$$

$x_i(j)$ 的 LLR 为
$$e_{\text{ESE}}(x_i(j)) = 2Q_i(l) \frac{y^{(e)}(j+l) - E(\zeta_i^{(e)}(j))}{\text{Var}(\zeta_i^{(e)}(j))} \quad (6-45)$$

为了计算式（6-45），需要知道统计信息 $E(x_i(j))$ 和 $\text{Var}(x_i(j))$。第一次迭代时，$E(x_i(j))=0$, $\text{Var}(x_i(j))=1$。它们可以通过下一次迭代的解码器输出得到。

---

### **第 
