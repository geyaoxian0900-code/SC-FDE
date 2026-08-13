
### 第 3 章 单载波频域均衡 - 51 -

比较式 (3-27) 和式 (3-28)，通常情况下，\(\eta_{CP} > \eta_{UW}\)，即 CP-SC 的带宽效率略高于 UW-SC。然而实际系统中，UW-SC 的独特字是已知信号，可以用作信道估计，此外则无须额外的导频信号。而在 CP-SC 系统中，为进行信道估计，CP-SC 系统需要插入额外的导频信号，设导频信号的长度为 \(P\)，则此时 CP-SC 系统的带宽效率降为

\[
\eta_{CP} = \frac{N-P}{N+M} \tag{3-29}
\]

此时，合理设计系统参数，则 UW-SC 系统的带宽效率可优于 CP-SC 系统。举例来说，设数据块长度 \(N=1024\)，循环前缀长度 \(M=256\)，CP-SC 系统中的导频符号长度 \(P=96\)，则 CP-SC 系统的带宽效率为 72.5%，UW-SC 系统的带宽效率为 75%。

![图 3-4 基于独特字的 SC-FDE 帧结构](attachment://image.png)

将独特字看作 CP，在接收端可以利用单抽头频域均衡器实现检测与解码，除此之外，UW-SC 具有如下优点。

（1）从信号同步的角度看，独特字自相关性好，可以作为块同步信号，这对移动水声通信来说较为有利，可以对每个数据块进行再同步，减轻多普勒效应的影响。

（2）从信道估计的角度看，既可以利用 UW-SC 中的 UW 信号进行信道估计，也可以考虑联合已估计的数据符号和 UW 信号，进一步提高估计的精度。考虑到水声信道时变性，为降低其对通信系统性能的影响，可对各数据块进行独立的信道估计和均衡。

（3）从多普勒估计的角度看，可以利用 UW-SC 中的 UW 信号估计多普勒频移，实现逐块进行多普勒估计和补偿，以应对时变多普勒效应。

补零单载波（zero padding-single carrier, ZP-SC）的帧格式如图 3-5 所示，与 CP-SC 系统中复制信号前插的处理方式不同，它在每个数据块后插入 \(M\) 个零，当 \(M > L\) 时，可消除 IBI 的干扰[5]。

![图 3-5 基于补零单载波系统帧格式](attachment://image2.png)

### 第 3 章 单载波频域均衡 - 52 -

通过补零后，其数据块可表示为

\[
s_{N+M} = [s_0 \quad s_1 \quad \cdots \quad s_{N-1} \quad 0 \quad \cdots \quad 0]^T \tag{3-30}
\]

由于在数据块 \(s\) 前后均包含 \(M\) 个零元素，则接收信号 \(r\) 可表示为

\[
\begin{bmatrix}
r_0 \\
r_1 \\
\vdots \\
r_{N-1}
\end{bmatrix}
=
\begin{bmatrix}
h_0 & h_L & \cdots & h_1 \\
h_1 & h_0 & \cdots & h_2 \\
\vdots & \vdots & \ddots & \vdots \\
h_{L-1} & h_{L-2} & \cdots & h_0 \\
h_L & h_{L-1} & \cdots & h_1 \\
\vdots & \vdots & \ddots & \vdots \\
0 & 0 & \cdots & 0
\end{bmatrix}
\begin{bmatrix}
s_0 \\
s_1 \\
\vdots \\
s_{N-1}
\end{bmatrix}
+
\begin{bmatrix}
w_0 \\
w_1 \\
\vdots \\
w_{N-1}
\end{bmatrix} \tag{3-31}
\]

由此可构造如下的矩阵关系：

\[
\begin{bmatrix}
r_N \\
r_{N+1}
