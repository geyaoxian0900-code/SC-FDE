
---

## **第 3 章 单载波频域均衡 ·75·**

### 参考文献 [18]–[29]

> （注：此页为参考文献列表，无公式、无图、无表，仅列出文献条目。以下为原文转录）

[18] 何成兵, 朱建路, 孟庆春, 等. 基于扩频码的单载波迭代频域均衡水声通信[J]. 物理学报, 2013, 62 (23): 207-213.

[19] He C B, Hao S Y, Han W, et al. Single carrier with multi-channel time-frequency domain equalization for underwater acoustic communications[C]. 2015 IEEE International Conference on Acoustics, Speech and Signal Processing (ICASSP). South Brisbane, 2015: 3009-3013.

[20] Xu M L, Rouseff D, Price J A, et al. Underwater acoustic communication in a highly refractive environment using SC-FDE[J]. IEEE Journal of Oceanic Engineering, 2013, 39 (3): 491-499.

[21] Yang T C. Correlation-based decision-feedback equalizer for underwater acoustic communications[J]. IEEE Journal of Oceanic Engineering, 2005, 30 (4): 865-880.

[22] Ariyaratne S. A decision-feedback equalizer with selective time-reversal operation for high-time indoor radio communications[J]. GLOBECOM'96. IEEE Global Telecommunications Conference and Exhibition, 1996, 3: 2035-2039.

[23] Nelson J K, Singer A C, Madhow U, et al. Bidirectional arbitrated decision-feedback equalization[J]. IEEE Transactions on Communications, 2005, 53 (12): 2114-2118.

[24] Balakrishnan J, Johnson C R. Bidirectional decision feedback equalizers: Infinite length results[J]. Conference Record of Thirty-Fifth Asilomar Conference on Signals, Systems and Computers, 2001, 2: 1450-1454.

[25] 景益友. 水声通信中信道估计与均衡及信号检测技术研究[D]. 西安: 西北工业大学, 2017.

[26] Huang G, Nix A, Armour S. DFT-based channel estimation and noise variance estimation techniques for single-carrier FDMA[C]. Vehicular Technology Conference, Ottawa, 2010: 1-5.

[27] Lam C T, Falconer D D. Double-Laminar F iterative frequency domain channel estimation for DFT-precoded OFDM systems using in-band pilots[J]. IEEE Journal on Selected Areas in Communications, 2008, 26 (2): 348-358.

[28] Sun H X, Gao Y H, Xiao X Y, et al. Iterative block DFE for underwater acoustic single-carrier system[J]. China Communications, 2012, (7): 129-134.

[29] 景益友, 柯成兵, 张玲玲, 等. 水声通信中基于软判决的级迭代码先后向均衡器[J]. 电子与信息学报, 2016, 38 (4): 885-890.

---

## **第 4 章 单载波迭代均衡 ·77·**

### 4.1 Turbo 均衡

#### 判决反馈均衡器（DFE）作为水声通信中常用的均衡器，其性能已得到大量海试验证。判决反馈均衡器的主要思想是利用已判决的符号来提高后续符号的估计性能。典型的自适应判决反馈均衡器是在后部跟着一个解交织器和一个解码器作为纠正错误输出的一种方法。然而，均衡器中反馈回来的错误有可能会产生更多的符号错误，导致错误扩展。

Turbo 均衡结构的主要思想是在解码器和均衡器之间（通过一个交织器）迭代地交换信息（硬信息
