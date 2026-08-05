# 工程仿真迁移区

本目录收纳原 `Projects/02_SC_FDE_UWA_MODEM/matlab` 中的 MATLAB 仿真和演示。
原目录暂时保留，避免破坏 MCU 工程及已有调用；新的统一入口位于
`../run_all_simulations.m`。

## 实验索引

| ID | 入口 | 内容 |
|---|---|---|
| `engineering.sc_tde` | `simulate_chapter2_single_carrier_tde` | DFE、NLMS、PLL、PTR、多通道 SC-TDE |
| `engineering.sc_tde_paper` | `reproduce_chapter2_sc_tde_paper` | Bellhop 八阵元、PTR 等效信道、五方法 BER 复现 |
| `engineering.sc_fde` | `simulate_chapter3_scfde` | CP/ZP/UW-SC、PN 同步、HTFDE、IBDFE |
| `engineering.iterative` | `simulate_chapter4_iterative_equalization` | Turbo 与时频迭代均衡 |
| `engineering.cck` | `simulate_chapter5_cck` | CCK、ISI、Turbo 检测、CCK-SM |
| `engineering.cck_5_5` | `simulate_chapter5_5_cck_results` | GCCK、扩展 CCK、CCK-Turbo/IBDFE、CCK-SM |
| `engineering.csk` | `simulate_chapter6_csk_multiuser` | CSK、多用户检测、IDMA |
| `engineering.text` | `run_text_scfde_demo` | 文本端到端收发链路 |

SC-TDE 已接入 `../modules/+scfde` 的可替换流水线。其他实验保持原算法实现，
但通过统一入口管理参数、输出目录和执行状态，后续可以逐个接入同一模块契约。

## 第 6 章扩频与 CSK-IDMA

`simulate_chapter6_csk_multiuser` 已重构为可选实验组：`principles`、
`conventional` 和 `idma`。它覆盖 DS-BPSK、M 元扩频、循环移位键控（CSK）、
跳频、多用户匹配滤波与软 PIC，以及 CSK-IDMA 的内/外迭代、软估计 MSE、
用户负载和 DSSS-IDMA 对比。`principles` 还可用 `sequenceFamilies` 选择
`m-sequence`、`gold`、`kasami`、`walsh`、`zadoff-chu` 和 `chaotic`，并输出
周期自相关、码组互相关及四用户 DS-CDMA BER 对比。

```matlab
result = simulate_chapter6_csk_multiuser(struct( ...
    "groups", ["principles", "conventional", "idma"], ...
    "makePlot", true));
disp(result.figurePaths)
```

核心实现位于 `../modules/+scfde/run_chapter6_spread_spectrum_suite.m`；公式、
模块接口和可替换实测信道的输入约定见 `CHAPTER6_SPREAD_SPECTRUM.md`。默认四径
信道明确标记为参数化参考模型，不能视为原文湖试 CIR 的数值复现。传入
`measuredChannelFile`（字段为 `h`、`ir` 或 `impulseResponse`）即可替换信道。

## 第 3 章 SC-FDE 公式复现

`simulate_chapter3_scfde` 默认采用原文的 `N=1024`、保护长度 `M=256` 和 QPSK。
接收端使用周期 PN 块估计残余频偏，再由独立 PN 块按正则化 LS 估计信道；
信道估计不再由真实频响直接加随机误差构造。基本 SC-FDE 使用式 (3-26) 的
MMSE 频域系数，同时输出 CP-SC、ZP-SC 和 UW-SC 的保护间隔结构比较。

HTFDE 将长度 `N` 的接收块划分为 `P` 个时段，逐段估计相位、执行可靠度控制的
时域后游标抵消，再按式 (3-61)、(3-62) 汇合各分支 FFT 结果。IBDFE 按式
(3-64) 执行 `C_k Y_k-B_k Xbar_k`，并按式 (3-69) 至 (3-87) 用可靠度更新
前馈和反馈系数；程序逐轮检查平均增益 `mean(C_k H_k)=1`。

```matlab
result = simulate_chapter3_scfde(struct("makePlot", true));
disp([result.basicBer; result.htfdeBer; result.ibdfeBer])
disp([result.cpBer; result.zpBer; result.uwBer])
```

默认信道和 `lakeImpulseResponse` 仍是合成回退数据。原文湖试记录未提供时，
不能将该部分表述为图 3-13 至图 3-21 的精确实测复现；传入实测冲激响应后可替换。

## 第二、三章算法选择

第二章工程 SC-TDE 入口支持以下稳定 ID：`dfe`、`nlms-dfe`、`pll-dfe`、
`mcdfe`、`ptr-dfe`、`subband-ptr-dfe`。论文参数复现入口另外提供 `PTR`、
`PTR-DFE`、`McDFE`、`Sub-PTR-McDFE` 和 `Sub-PTR-BiMcDFE`。

```matlab
tde = simulate_chapter2_single_carrier_tde(struct( ...
    "methods", ["dfe", "pll-dfe"]));
paperTde = reproduce_chapter2_sc_tde_paper(struct( ...
    "methods", ["PTR", "Sub-PTR-BiMcDFE"]));
```

第三章均衡算法包括 `ZF-SC-FDE`、`MMSE-SC-FDE`、`HTFDE`、`SD-IBDFE`、
`HD-IBDFE`、`ICE-SD-IBDFE` 和 `ICE-HD-IBDFE`。保护结构通过独立参数选择：
`CP-SC`、`ZP-SC`、`UW-SC`。`methods="all"` 和 `guardMethods="all"` 为默认值。

```matlab
fde = simulate_chapter3_scfde(struct( ...
    "methods", ["MMSE-SC-FDE", "HTFDE", "ICE-SD-IBDFE"], ...
    "guardMethods", "UW-SC", ...
    "makePlot", true));
disp(fde.methodNames)
disp(fde.methodBer)
```

筛选参数控制控制台输出、结果矩阵、图例和星座图。完整候选表保存在
`availableMethods`，实际选择保存在 `methodNames`；旧字段 `basicBer`、
`htfdeBer` 和 `ibdfeBer` 继续保留以兼容已有调用。

第二章 SC-TDE 的均衡算法对比图采用 BER-SNR 曲线，而非单一 SNR 的柱状图。默认扫描
`berSnrDb=0:2:14`，每个点执行一次链路；曲线数据保存为 `berSnrDb` 和 `berBySnr`。
需要更稳定的蒙特卡洛统计时，可设置 `berSweepFrames=3` 或更高。
默认 `rlsForgettingFactor=0.985`，使 RLS 能跟踪本链路的 `1.5 Hz` 残余多普勒相位变化；
将其调回接近 1 的值会降低噪声敏感性，但会显著减慢时变信道跟踪。

## SC-TDE 链路可视化

当前 SC-TDE 是用于比较均衡算法的 BPSK 链路：训练符号和数据符号经过双水听器
多径信道，再分别送入传统 DFE、自适应 NLMS-DFE、PLL 辅助 DFE、多通道 DFE、
被动时反 DFE 和子带被动时反 DFE。它目前不包含文本分包、UW、LDPC 和 RRC，
这些工程收发环节属于后面的文本 SC-FDE 链路。

设置 `makePlot=true` 后，`figurePaths` 返回八张中文图：

1. `00_sc_tde_beginner_overview.png`：用日常语言解释训练、前馈、反馈和误码评价。
2. `01_sc_tde_source_channel.png`：显示 BPSK 符号、多径抽头、接收波形和均衡前散点。
3. `02_sc_tde_equalizer_learning.png`：显示六种学习曲线、判决前输出及均衡前后散点。
4. `03_sc_tde_result_comparison.png`：显示 BER、硬判决、逐位错误位置和方法排序。
5. `04_sc_tde_dfe_internal_terms.png`：逐符号显示接收值、前馈项、反馈抵消项、最终估计和判决。
6. `05_sc_tde_nlms_coefficient_update.png`：显示 NLMS 误差、权值范数、36 个抽头的更新热图和最终权值。
7. `06_sc_tde_all_method_outputs.png`：并列显示六种方法的判决前散点及对应 BER。
8. `07_sc_tde_modular_architecture.png`：显示信源、信道、接收、评价和绘图模块的输入输出与替换接口。

```matlab
result = simulate_chapter2_single_carrier_tde(struct("makePlot", true));
disp(result.figurePaths)
```

PNG 和矢量 PDF 保存在 `results/sc_tde_stages/`。默认的接收模块还通过
`equalizerEstimates` 返回六种均衡器的判决前连续输出；发送、信道、接收、
评价和绘图模块仍可分别通过 `options.modules` 替换。`equalizerTraces` 进一步保存
`feedforwardOutput`、`feedbackCancellation`、`error`、`weightNorm`、
`coefficientHistory` 和 `phase`，用于复核 DFE 内部每一步数值。

## 论文图 2-16 至图 2-18 复现

`reproduce_chapter2_sc_tde_paper` 按论文第 2.4.2 节参数建立独立实验：水深
`100 m`、源深 `50 m`、距离 `5 km`、载频 `6 kHz`，8 阵元接收深度为
`40:1.5:50.5 m`。QPSK 比特率为 `8 kbit/s`，因此码元率为 `4 ksymbol/s`；
训练序列长度为 512，IPNLMS 用于信道估计，DFE 前馈和反馈长度均为 50，
递推 RLS 的遗忘因子为 0.999。双向方法采用“前训练序列｜数据｜后训练序列”帧，
反向支路按式 (2-50) 直接倒序，最后按式 (2-53) 对前、后向估计做等权平均。

```matlab
result = reproduce_chapter2_sc_tde_paper();
disp(result.ber)
```

结果保存在 `results/sc_tde_paper_reproduction/`：

1. `fig2_16_bellhop_eight_channel.png`：按原文图 2-16 数字化的八通道多径冲激响应。
2. `fig2_17_passive_tr_equivalent_channel.png`：两个子阵和完整阵列的 PTR 等效信道。
3. `fig2_18_paper_digitized_reference.png`：按原文图 2-18 数字化的 BER 参考曲线；该图不是链路仿真结果。
4. `fig2_18_channel_driven_simulation.png`：以图 2-16 数字化 CIR 为输入的独立可执行仿真结果。

真实仿真的 BER 仅由 `results.errorCounts ./ results.bitCounts` 得到，并保存在
`results.ber` 中；`results.berSource` 记录其来源。论文读图数据单独保存在
`results.paperReferenceBer`，不得与实际误码统计混用。

默认 `channelOptions.source="paper-figure"` 直接使用图 2-16 读出的八个通道的
路径时延和归一化幅度，因此图 2-16 的主径位置、多径簇和阵元间差异由原图驱动。
原图没有给出每条路径的复相位，程序以确定性相位补全该缺失量；故图 2-17 和图 2-18
的实际仿真不能视为原作者原始 Bellhop 复到达数据的严格数值复现。`results.paperReferenceBer`
保存图 2-18 的读图近似值，`results.ber` 保存独立通道驱动仿真的统计值；二者不混用。
将 `channelOptions.source` 设置为 `"bellhop"`，可切回由环境假设生成的 Bellhop 后端；
若取得论文的原始复信道数据，可替换该数字化输入。

Bellhop 模式的结果单独保存在 `results/sc_tde_bellhop_reproduction/`。该模式使用
Bellhop 输出的复路径增益，并将 RLS 初始逆相关矩阵设为 `P0=0.003I`；这是针对
8 路、50 抽头 McDFE 的 450 维系数向量和 512 符号训练长度采用的数值正则化，
避免原 `P0=100I` 在低中信噪比下过拟合。显式传入
`rlsInitialInverseCorrelation` 可覆盖该默认值。

DFE 默认设置 `normalizeDfeBranches=true`，按每路估计信道的二范数同时缩放接收
支路和信道支路。该 AGC 不改变支路 SNR，用于消除 Bellhop 阵元及两个 PTR 子阵间
明显的能量尺度差异，防止多通道 RLS 被单个强支路支配。

`scaleRlsInitializationByDimension=true` 按均衡器系数数目缩放 `P0`。以 8 路
McDFE 的 450 个系数为基准，两个 PTR 子阵的 150 维 McDFE 使用约 `0.009I`，
单路 PTR-DFE 的 100 维滤波器使用约 `0.0135I`，使不同结构具有可比较的训练裕量。

PTR 等效信道近似以相关峰对称，因此 `ptrDecisionDelayOffset=0` 将 PTR-DFE 和
Sub-PTR-McDFE 的判决延迟放在相关主峰；普通 McDFE 默认仍将主峰放在前馈窗中部，
可通过 `mcDecisionDelayOffset` 覆盖。

两个 PTR 子阵由 `subarrayGroups` 配置，默认采用交错阵元
`{1:2:8, 2:2:8}`；连续子阵可设置为 `{1:4, 5:8}`。

阵列噪声默认使用 `arrayNoiseMode="per-branch"`，与原文按接收支路定义 SNR 的
比较口径一致。若需要各水听器使用相同绝对噪声方差，可设置
`arrayNoiseMode="common"`。

Bellhop 水体声速剖面的两个端点可通过 `waterSoundSpeedSurface` 和
`waterSoundSpeedBottom` 设置，默认分别为 `1500 m/s` 和 `1490 m/s`。

`residualDopplerSpanHz` 用于在静态 Bellhop CIR 上加入阵元间线性分布的残余频移，
模拟前后训练序列之间的帧内相位演化；设为 `0` 时保持严格静态信道。

仅修改绘图样式或标题时，可从保存结果直接重绘而不重复运行仿真：

```matlab
reproduce_chapter2_sc_tde_paper(struct( ...
    "replotResultPath", "results/sc_tde_bellhop_reproduction/chapter2_sc_tde_reproduction.mat"));
```

## 端到端发射帧

文本链路先构造数据链路层包：

```text
A5 5A | payload length | sequence | payload | CRC16
```

随后执行 LDPC 编码和星座映射，最后由物理层封装为：

当前纠错码按标准 `LDPC(n,k)` 记为 `LDPC(192,128)`：128个信息位编码为
192位码字，增加64个校验位，码率为 `128/192=2/3`。

```text
UW1（帧捕获）| UW2（信道估计）| 数据符号 | UW3（块尾循环保护）
```

`A5 5A` 包头和 UW 不属于同一协议层。UW 虽然在程序中于调制后拼接，但在实际
发送波形中仍位于物理帧最前面。默认脉冲成形为 RRC，滚降系数 0.35、跨度 8 个
符号；接收端使用匹配 RRC。设置 `pulseShape="rectangular"` 可恢复原矩形保持模式。

## 全链路可视化

设置 `makePlot=true` 后，结果中的 `figurePaths` 返回六张图。建议按两层阅读：
非通信专业读者先看第 1 张，理解“文字—水声信号—文字”的整体过程；需要检查
算法和数值变化时，再看后续技术图。

1. `00_beginner_overview.png`：用日常语言解释 11 个步骤，并在图底部翻译专业术语。
2. `text_end_to_end_diagnostics.png`：接收波形、同步、星座和信道总览。
3. `01_digital_framing.png`：包字节、信息位、LDPC码字、QPSK和UW帧。
4. `02_transmit_channel.png`：RRC、上采样、频谱、多径、基带和通带。
5. `03_sync_channel_estimation.png`：ADC、下变频、匹配滤波、同步、频偏和LS信道。
6. `04_equalization_decoding.png`：SC-FDE、星座、LLR、硬判决、译码包和CRC。

```matlab
result = run_text_scfde_demo("A", struct("makePlot", true));
disp(result.figurePaths.')
```

详细图同时输出220 DPI PNG和矢量PDF，保存在
`results/text_link_stages/`。每帧结构还保存 `txPacketBits`、`txCodeBits`、
`txSymbolLabels`、`matchedFilterSamples`、`correctedSymbols`、
`channelImpulse`、`receivedBlockSpectrum` 和 `demodulation.llr`，便于自定义绘图。
