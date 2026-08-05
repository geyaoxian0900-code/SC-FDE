# 第三章同步与多普勒仿真

运行：

```powershell
matlab -batch "addpath('papers/chapter3_simulation'); addpath('papers/common'); run_chapter3_simulation"
```

覆盖的论文数值图：图 3.2、3.3、3.5、3.6、3.7、3.8、3.9、3.10。

论文给出的参数已经采用：四径时延 `[0, 3.4, 6.7, 10] ms`、幅度
`[1, 0.6, 0.6, 0.3]`、采样率 48 kHz、载频 10 kHz、QPSK、码元宽度
0.25 ms、五个数据块、UW 长度 16 ms。

论文没有给出二维搜索窗口、搜索步数、随机试验次数以及 LDPC 校验矩阵。
本实现使用论文式 (3-9) 对应的搜索分辨率建立 Monte Carlo 捕获模型，并使用
`../common` 中可重复构造的短码长、码率 1/2 稀疏 LDPC 码。该码不是作者未公开的
原始 LDPC 矩阵，因此目标是复现算法趋势而不是逐点描摹原曲线。
