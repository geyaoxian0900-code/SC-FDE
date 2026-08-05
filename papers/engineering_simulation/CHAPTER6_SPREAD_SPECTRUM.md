# 第六章仿真：循环移位扩频与多用户通信

入口为 simulate_chapter6_csk_multiuser.m，核心模块为
../modules/+scfde/run_chapter6_spread_spectrum_suite.m。它将原文第 6 章分为三个可以独立
选择的实验组：

- principles：6.1 的 DS-BPSK、M 元正交扩频、CSK、相关捕获与跳频序列。
- conventional：6.2 的多用户 M 元 CSK、匹配滤波、软 PIC 和用户负载。
- idma：6.3 的 CSK-IDMA 内/外迭代、软码字 MSE、用户数和 DSSS-IDMA 基线对比。

原文截图给出了湖试地点、设备和部分统计表，但没有提供原始 CIR、接收波形、用户定时和数据包。
因此默认信道是与原文多径结构一致的**参数化参考多径**，不是湖试数据复现。传入测量 CIR 后，
程序将使用其中的 h、ir 或 impulseResponse 字段替换默认信道。

## 6.1 扩频与 CSK

长度为 \(L\) 的归一化 PN 根序列记为 \(\boldsymbol c_0\)。第 \(m\) 个循环移位码字为

\[
c_m[n]=c_0[(n-m)\bmod L],\qquad
\|\boldsymbol c_m\|_2^2=1,\qquad m=0,\ldots,M-1.
\]

第 6 章中的 CSK 信息由移位索引承载，\(q=\log_2 M\) 个比特映射为一个码字。接收端的
捕获统计量为

\[
\Gamma[\tau]=\left|\sum_{n=0}^{L-1}r[n]c_0^*[(n-\tau)\bmod L]\right|,
\qquad
\widehat{\tau}=\arg\max_{\tau}\Gamma[\tau].
\]

仿真在同一 \(E_b/N_0\) 标尺下比较 DS-BPSK、M 元正交扩频和 CSK；因此 M 元码字的噪声方差为
\(N_0=1/(q\,10^{E_b/N_0/10})\)。

### 可选扩频序列组

`principles` 组还包含六类可选扩频序列的独立仿真。为使 m 序列、Gold 序列和小集合
Kasami 序列使用完整周期，默认公共周期为 \(L=63=2^6-1\)；Walsh 码组保持自然长度
64。所有发射码字均按 \(\|\boldsymbol c\|_2^2=1\) 归一化，因此单用户 AWGN 性能不会因
幅度标定不同而失真。

| 标识 | 构造 | 默认码组 |
|---|---|---|
| `m-sequence` | 本原多项式 \(x^6+x+1\) | 同一 m 序列的循环移位 |
| `gold` | \(x^6+x+1\) 与 \(x^6+x^5+x^2+x+1\) 的优选对异或 | 不同相对相位的 Gold 码 |
| `kasami` | 小集合 Kasami 码 | m 序列与 9 倍抽取序列的异或 |
| `walsh` | 64 阶 Sylvester-Hadamard 矩阵 | 前 8 个正交 Walsh 码 |
| `zadoff-chu` | \(L=63\)、根参数 \(q=5\) | 同一 ZC 根序列的循环移位 |
| `chaotic` | Logistic 映射 | 混沌实值序列的循环移位 |

m 序列的二元递推为

\[
a[n+6]=a[n+1]\oplus a[n].
\]

若 \(a[n]\) 和 \(b[n]\) 是上表给出的两条 m 序列，Gold 码写为

\[
g_\tau[n]=a[n]\oplus b[(n+\tau)\bmod L].
\]

小集合 Kasami 码使用 \(v[n]=a[(2^{6/2}+1)n\bmod L]=a[9n\bmod L]\)，并取

\[
k_\tau[n]=a[n]\oplus v[(n+\tau)\bmod L].
\]

Walsh 码由 \(\boldsymbol W_{2N}=\begin{bmatrix}\boldsymbol W_N&\boldsymbol W_N\\
\boldsymbol W_N&-\boldsymbol W_N\end{bmatrix}\) 递归构造。奇数长度 Zadoff-Chu 序列为

\[
z_q[n]=\exp\left(-j\pi q\frac{n(n+1)}{L}\right),\qquad \gcd(q,L)=1.
\]

混沌序列由 Logistic 映射 \(x[n+1]=4x[n](1-x[n])\) 产生，并以
\(c[n]=x[n]-\operatorname{mean}(x)\) 去直流后归一化。

专用图同时给出周期自相关、码组零时延互相关、单用户 DS-BPSK 和同步多用户 DS-CDMA
匹配滤波 BER。多用户观测和判决为

\[
\boldsymbol r=\sum_{u=1}^{U}(1-2b_u)\boldsymbol c_u+\boldsymbol w,
\qquad
\widehat b_u=\mathbb I\!\left\{\Re\left(\boldsymbol r\boldsymbol c_u^H\right)<0\right\}.
\]

码组间干扰由 \(\rho_{ij}=|\boldsymbol c_i\boldsymbol c_j^H|\) 量化；因此多用户 BER 的差异
直接对应码组互相关，而不把单用户 AWGN 中本应等价的归一化序列人为画出性能优劣。

## 6.2 常规多用户 CSK

第 \(u\) 个用户的已知等效字典为
\(\mathcal D_u=\{\boldsymbol d_{u,0},\ldots,\boldsymbol d_{u,M-1}\}\)，其中字典包含
用户循环移位、扰码和参考多径。一个码字符号周期内的接收向量为

\[
\boldsymbol y=\sum_{u=1}^{U}\boldsymbol d_{u,m_u}+\boldsymbol w.
\]

匹配滤波/最小欧氏距离初判为

\[
\widehat m_u^{(0)}
=\arg\min_m\left\|\boldsymbol y-\boldsymbol d_{u,m}\right\|_2^2.
\]

软并行干扰抵消（PIC）在第 \(i\) 轮使用其余用户的软码字均值
\(\overline{\boldsymbol d}_v^{(i-1)}\) 构造残差：

\[
\boldsymbol r_u^{(i)}
=\boldsymbol y-\sum_{v\ne u}\overline{\boldsymbol d}_v^{(i-1)},\qquad
\Lambda_{u,m}^{(i)}
=-\frac{\|\boldsymbol r_u^{(i)}-\boldsymbol d_{u,m}\|_2^2}{N_0}.
\]

\[
p_{u,m}^{(i)}
=\frac{\exp(\Lambda_{u,m}^{(i)})}
{\sum_a\exp(\Lambda_{u,a}^{(i)})},\qquad
\overline{\boldsymbol d}_u^{(i)}
=\sum_m p_{u,m}^{(i)}\boldsymbol d_{u,m}.
\]

## 6.3 CSK-IDMA

CSK-IDMA 为每个用户配置独立码片交织器 \(\pi_u\)。为使“外迭代”具有独立的信息来源，
当前工程实现使用交织重复率 \(1/2\) 的外码，而不将单纯的 PIC 重复计算称为外迭代：

\[
\boldsymbol a_u[1:K]=\boldsymbol b_u,\qquad
\boldsymbol a_u[K+1:2K]=\boldsymbol b_u[\pi_u].
\]

内迭代以 ESE/PIC 的码字后验作为软反馈；外迭代将每个副本的对数度量传给其交织副本：

\[
L_{A,u,t}^{(o+1)}(m)=
\Lambda_{u,p_u(t)}^{(o)}(m),\qquad
\widehat b_{u,k}
=\arg\max_m\left[
\Lambda_{u,k}(m)+\Lambda_{u,p_u(k)}(m)\right].
\]

图 6-12 分别显示内、外迭代次数的 BER，图 6-13 显示软码字估计
\(\operatorname{MSE}=\mathbb E\{|\overline d-d|^2\}\)，图 6-14 和图 6-15 显示用户数及
DSSS-IDMA/CSK-IDMA 对比。

## 运行

运行全部第六章仿真：

~~~matlab
result = simulate_chapter6_csk_multiuser(struct("makePlot", true));
disp(result.figurePaths)
~~~

单独运行某一节：

~~~matlab
result = simulate_chapter6_csk_multiuser(struct( ...
    "groups", ["conventional", "idma"], ...
    "idmaUsers", 8, ...
    "idmaUserCounts", [8, 12, 16], ...
    "makePlot", true));
~~~

只比较指定序列族：

~~~matlab
result = simulate_chapter6_csk_multiuser(struct( ...
    "groups", "principles", ...
    "sequenceFamilies", ["m-sequence", "gold", "kasami", ...
        "walsh", "zadoff-chu", "chaotic"], ...
    "sequenceUsers", 4, ...
    "makePlot", true));
study = result.principles.sequenceStudy;
disp(study.multiUserBer)
~~~

使用测量 CIR：

~~~matlab
result = simulate_chapter6_csk_multiuser(struct( ...
    "measuredChannelFile", "measured_cir.mat", ...
    "makePlot", true));
~~~

默认生成：

- chapter6_spreading_principles.png
- chapter6_spreading_sequence_families.png
- chapter6_conventional_multiuser.png
- chapter6_csk_idma_iterations.png
- chapter6_csk_idma_loading.png

这些文件保存在 papers/engineering_simulation/results/。
