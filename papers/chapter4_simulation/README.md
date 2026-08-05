# 第四章判决反馈均衡仿真

运行：

```powershell
matlab -batch "addpath('papers/chapter4_simulation'); addpath('papers/common'); run_chapter4_simulation"
```

覆盖论文数值仿真图 4.2、4.4、4.5、4.7、4.8。实现包括 MMSE、基于已知
UW 的 Wiener 误差预测、频域前馈/时域反馈 FD-DFE，以及 LDPC 辅助 IB-DFE。

采用论文给出的 512 点 FFT、64 点 UW、QPSK、四径时延
`[0, 3.4, 6.7, 10] ms` 和幅度 `[1, 0.6, 0.6, 0.3]`。论文未公开
多径相位和 LDPC 校验矩阵，本实现使用固定多径相位以及 `../common` 中的短码长、
码率 1/2 稀疏 LDPC 码，因此属于可验证的趋势复现。

图 4.9 至图 4.13 是论文作者在哈尔滨工程大学水池录制数据得到的波形、信道响应
和同步图。当前没有原始水听器录音，不能从仿真重新生成这些实测图。
