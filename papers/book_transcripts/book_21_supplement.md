根据您提供的扫描图，以下是第89页和第90页中尚未覆盖的页面内容（即第4章频域判决反馈权重推导区）的完整转写。我们将包含 (4-50) 到 (4-63) 之间的每一个编号公式及其相关描述。

### 第89页

#### 图4-8 FDE-FDDF结构框图

![图4-8 FDE-FDDF结构框图](attachment://image.png)

第 $i$ 次迭代的均衡器输出可以表示为
$$
\overline{\boldsymbol{x}}^{(i)}=\boldsymbol{F}^{\mathrm{H}}\left(\boldsymbol{W}^{(i)} \boldsymbol{y}-\boldsymbol{B}^{(i)} \overline{\boldsymbol{x}}^{(i)}\right)
\tag{4-50}
$$
式中，$\boldsymbol{F}$、$\boldsymbol{F}^{\mathrm{H}}$分别代表傅里叶变换矩阵和傅里叶逆变换矩阵；$\boldsymbol{y}$是接收序列 $\boldsymbol{y}_{n}$ 的频域形式，可以表示为
$$
\boldsymbol{y}=\boldsymbol{F} \boldsymbol{r}=\boldsymbol{D} \boldsymbol{F} \boldsymbol{x}+\boldsymbol{F} \boldsymbol{n}
\tag{4-51}
$$
这里将信道矩阵 $\boldsymbol{h}_{m n}$ 分解为 $\boldsymbol{F}^{\mathrm{H}} \boldsymbol{D} \boldsymbol{F}$。其中 $\boldsymbol{D}$ 的对角元素即为信道的频域响应 $h_{k}$，可以表示为
$$
h_{k}=\sum_{l=0}^{L-1} h(l) \mathrm{e}^{-j 2 \pi l k / K}, \quad k=0,1, \cdots, K-1
\tag{4-52}
$$
而 $\boldsymbol{W}^{(i)}=\operatorname{diag}\left[w_{0}^{(i)}, w_{1}^{(i)}, \cdots, w_{K-1}^{(i)}\right]$ 和 $\boldsymbol{B}^{(i)}=\operatorname{diag}\left[b_{0}^{(i)}, b_{1}^{(i)}, \cdots, b_{K-1}^{(i)}\right]$ 分别为前向和反向滤波器的系数，它们是根据 MMSE 准则计算得到的，即保证 $E\left(\left|\overline{\boldsymbol{x}}^{(i)}-\boldsymbol{x}\right|^{2}\right)$ 的值最小，数据块的均方误差可表示为
$$
\begin{aligned}
& \frac{1}{K} \sum_{k=0}^{K-1} E\left[\left|\overline{x}_{k}^{(i)}-x_{k}\right|^{2}\right]=\frac{\sigma_{s}^{2}}{K} \sum_{k=0}^{K-1}\left|w_{k}^{(i)}\right|^{2}+\frac{1}{K} \sum_{k=0}^{K-1}\left|w_{k}^{(i)}\right|^{2}\left|h_{k}\right|^{2} \\
& -\frac{2}{K} \operatorname{Re}\left[w_{k}^{(i)} h_{k}^{*}\left(1+b_{k}^{(i)} \rho^{(i)}\right)\right]+\frac{\sigma_{n}^{2}}{K} \sum_{k=0}^{K-1}\left|b_{k}^{(i)}\right|^{2} \\
& +\frac{2}{K} \operatorname{Re}\left[b_{k}^{(i)} \sum_{l=0}^{K-1} \rho_{l}^{(i)}\right]+1
\end{aligned}
\tag{4-53}
$$
式中，$\rho_{l}^{(i)}=E\left(x_{k} \hat{x}_{k-l}^{(i)}\right), \quad k=0,1, \cdots, K-1$，由下面公式计算：
$$
\begin{aligned}
\rho_{0}^{(i)} & =E\left(x_{k} \overline{x}_{k}\right)=E
