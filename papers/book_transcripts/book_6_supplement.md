◇ injected env (0) from .env // tip: ◈ secrets for agents [www.dotenvx.com]
◇ injected env (3) from C:\Users\geyaoxian\.config\opencode\skills\image-vision\.env // tip: ⌘ suppress logs { quiet: true }
好的，这是根据您提供的扫描图（第23页和第24页）进行的转录。

---

### 第23页

式中
$$
\boldsymbol{w}^{\circ} = \boldsymbol{R}_{x}^{-1}(n)\boldsymbol{r}(n) \tag{2-18}
$$
$$
\boldsymbol{R}(n) = \sum_{i=0}^{n}\lambda^{n-i}\boldsymbol{u}^{H}(i)\boldsymbol{u}(i) \tag{2-19}
$$
$$
\boldsymbol{r}(n) = \sum_{i=0}^{n}\lambda^{n-i}\boldsymbol{d}^{*}(i)\boldsymbol{u}(i) \tag{2-20}
$$
根据式 (2-19) 和式 (2-20) 可得, RLS 算法以递推方式获取抽头系数最优解, 有
$$
\boldsymbol{R}(n) = \lambda\boldsymbol{R}(n) + \boldsymbol{u}(n)\boldsymbol{u}^{H}(n) \tag{2-21}
$$
$$
\boldsymbol{r}(n) = \lambda\boldsymbol{r}(n) + \boldsymbol{d}^{*}(n)\boldsymbol{u}(n) \tag{2-22}
$$
由于式 (2-21) 三项都是方阵, 则根据矩阵求逆引理可得
$$
\boldsymbol{P}(n) = \frac{1}{\lambda}[\boldsymbol{P}(n-1) - k(n)\boldsymbol{u}^{H}(n)\boldsymbol{P}(n-1)] \tag{2-23}
$$
式中, $P(n) = R^{-1}(n)$; $k(n)$ 称为 Kalman 增益向量, 为
$$
k(n) = \frac{\boldsymbol{P}(n-1)\boldsymbol{u}^{*}(n)}{\lambda + \boldsymbol{u}^{T}(n)\boldsymbol{P}(n-1)\boldsymbol{u}(n)} \tag{2-24}
$$
根据上述递推公式可得
$$
\boldsymbol{w}(n) = \boldsymbol{w}(n-1) + k(n)e^{*}(n) \tag{2-25}
$$
观察上述 RLS 算法, 均衡器的每个抽头系数均受 $k(n)$ 中的一个分量控制。与此相比, LMS 各抽头系数随时间更新仅受到一个统一步长 $\mu$ 的控制。RLS 算法的收敛速度快, 用于跟踪快变信道较为合适。均衡器的性能随着 RLS 算法中的遗忘因子 $\lambda$ 发生变化, 一般情况下, 遗忘因子的取值为 $0.8 < \lambda < 1$ 的常数。$\lambda$ 值只对 RLS 均衡器的跟踪能力产生影响, 不会对收敛速度产生影响。RLS 算法每次迭代的运算量为 $2.5N^2+4.5N$, 具有庞大的计算量。

通过图 2-6 所示例子, 对 LMS、NLMS 和 RLS 算法的收敛速度进行比较。假设信道冲激响应为 $h=[1,0.5,-1,5,2]$, 信号长度为 600, 信噪比为 20dB, 均衡器长度为 $N=6$, LMS 算法中的步长 $\mu=0.008$, NLMS 算法的步长 $\mu=0.15$, $\delta=0.001$, RLS 算法的遗忘因子 $\lambda=0.995$。运用上述三种算法分别进行 300 次训练, 每种算法均获得 300 个不同的误差曲线, 集平均后获得的平均误差曲线如图 2-6 所示。均衡器的收敛速度不仅和自适应算法有关, 还和均衡器的阶数有关。水声通信多径时延扩展大, 均衡器的阶数较高, 通常可达上百阶, 则训练序列的长度需足够长, 影响通信系统的带宽效率。

#### 2.2.3 内嵌数字锁相环的 DFE

水声信道使接收信号产生严重的相位偏移, 给单载波相位相干接收机带来

---

### 第24页

很大的困难。接收端的载波相位偏移可以分为三部分: 由定时误差引起的常数相位偏移、D
