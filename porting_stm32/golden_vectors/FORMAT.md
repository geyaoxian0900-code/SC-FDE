# 黄金向量文件格式规范（Golden Vector Format Specification）

## 1. 总体约定

- 所有二进制文件：**小端序（little-endian）**，与 Cortex-M 一致。
- 浮点数：IEEE-754 **float32**（MATLAB 侧导出时用 `single`）。
- 复数：实部、虚部**交替存储**（`re0,im0, re1,im1, ...`）。
- 整数：`uint8` 原始字节；`uint16` 小端 2 字节。
- 命名：`NN_<stage>.bin`（二进制）/ `NN_<stage>.txt`（文本），NN 为两字符序号。
- 每份向量目录：`matlab_export/`（MATLAB 生成）、`c_export/`（C 测试程序生成）。
- 固定种子：MATLAB `rng(20260723,"twister")`；C 侧无随机（回环确定性）。

## 2. 黄金场景（基线方案，与 C 固件数字回环严格对齐）

```
文本:      "SC-FDE1234"（10 字节，单帧）
方案:      基础 SC-FDE + MMSE-FDE（无 LDPC、无 IB-DFE/NLMS-TDE、无判决导向）
调制:      QPSK | fftSize=128 | uwLength=32 | dataSymbols=96 | frameSymbols=192
采样:      TX 96000 Hz / RX 48000 Hz / symbolRate 4000 / carrier 12000
成形:      rectangular（矩形发射 24 采样保持 + 接收 12 点积分清零，与 C 固件一致）
信道:      无多径、无多普勒、无噪声（snrDb 取 120 使噪声≈0）
前导:      leadingSamples=0
重试:      maxFrameAttempts=1
LDPC:      关闭（C 侧 SCFDE_LDPC_ENABLED=0，MATLAB ldpcEnabled=false）
捕获:      ADC 捕获长度 2304 采样（192 符号 × 12），尾部补零 512 采样（与 MATLAB 一致）
```

> 恢复 LDPC 时：C 侧 `SCFDE_LDPC_ENABLED=1` + MATLAB `ldpcEnabled=true`，
> 02/19/20 阶段含义回到"LDPC 输入 128 位 + 码字 192 位"，并需重新导出。

## 3. 文件清单（23 阶段）

| 序号 | 文件 | 内容 | 格式 | 长度 |
|---|---|---|---|---|
| 01 | `01_packet_bytes.bin` | 数据包字节（A5 5A len seq payload CRC16，24 字节） | uint8 | 24 |
| 02 | `02_qpsk_input_bits.bin` | QPSK 输入 192 比特（LSB-first 打包） | uint8 打包 | 24 |
| 03 | `03_modulated_symbols.bin` | QPSK 数据符号（bit0→I，bit1→Q，1→+1） | complex float32 | 96 |
| 04 | `04_uw.bin` | Chu UW：exp(-jπn²/32)，n=0..31 | complex float32 | 32 |
| 05 | `05_frame_symbols.bin` | 完整帧 [UW UW DATA UW] | complex float32 | 192 |
| 06 | `06_tx_baseband_96k.bin` | 96 kHz 发射基带（矩形保持，RRC 未启用） | complex float32 | 4608 |
| 07 | `07_passband_tx_96k.bin` | 96 kHz 实通带波形（×700 幅度，等效 DAC 码-2048） | float32 | 4608 |
| 08 | `08_adc_capture.bin` | 48 kHz ADC 码（含 2048 中点、饱和截断、尾补零） | uint16 LE | 2816 |
| 09 | `09_downconverted.bin` | 下变频复基带（48 kHz，12 kHz LO） | complex float32 | 2816 |
| 10 | `10_integrated_symbols.bin` | 12 点积分清零符号流（矩形模式下即"匹配滤波输出"） | complex float32 | 234 |
| 11 | `11_sync_result.txt` | 帧起点采样、同步度量、CFO 估计（3 行） | 文本 | 3 行 |
| 12 | `12_phase_correction.bin` | 相位校正量（192 符号） | float32 | 192 |
| 13 | `13_corrected_symbols.bin` | 相位校正后帧符号 | complex float32 | 192 |
| 14 | `14_channel_impulse.bin` | LS 信道冲激响应（32 点，28 抽头后置零） | complex float32 | 32 |
| 15 | `15_channel_response.bin` | 128 点信道频率响应 H[k] | complex float32 | 128 |
| 16 | `16_fft_block_in.bin` | FDE 块输入（DATA\|UW3，时域） | complex float32 | 128 |
| 17 | `17_fft_block_out.bin` | 同一块的 128 点 FFT 输出 Y[k] | complex float32 | 128 |
| 18 | `18_equalized_symbols.bin` | MMSE-FDE 输出（96 个数据符号） | complex float32 | 96 |
| 19 | `19_ldpc_llr.bin` | QPSK LLR（-re/-im，192 个；无 LDPC 时为判决输入） | float32 | 192 |
| 20 | `20_decoded_bits.bin` | 硬判决输出 192 比特（LSB-first 打包） | uint8 打包 | 24 |
| 21 | `21_rx_packet.bin` | 恢复数据包 | uint8 | 24 |
| 22 | `22_crc_result.txt` | headerOk/crcOk/valid/bitErrors（4 行） | 文本 | 4 行 |
| 23 | `23_final_text.txt` | 恢复文本 | UTF-8 文本 | — |

> 阶段 06 说明：MATLAB 默认 RRC 与 C 固件不符（见审计报告 §3-7），黄金向量**强制 rectangular** 以便逐点对齐；RRC 阶段向量如需保留，另存 `06b_rrc_output.bin` 仅作参考，不参与比对。

## 4. 比对指标与容差（`compare_golden.py`，已按实测量化标定）

C 发射侧使用 8 点 int16 载波查表 + int32 混频（`scfde_modem.c:31-32,194-196`），
引入**有界确定性量化**：通带最大偏差实测 5.63 码（约 0.25% 相对误差），
下游波形阶段按同一比例传播。以下容差 = 实测最大值 + 裕量。

| 阶段 | 指标 | 容差（实测 max） |
|---|---|---|
| 01/02/03/05/20/21/22/23 | 逐位/逐字节相等 | 0（全部实测 0） |
| 04/06（UW/基带） | max 绝对误差 | 1e-5 / 5e-3（实测 5.3e-6） |
| 07（通带波形） | max 绝对误差 | 6.5（实测 5.63，载波表量化） |
| 08/09（ADC/下变频） | max 绝对误差 | 4（实测 3.0） |
| 10/13/16（符号域） | max 绝对误差 | 24（实测 21.6） |
| 14/15（信道估计） | max 绝对误差 | 18 / 27（实测 15.2 / 24.3） |
| 17（FFT 输出） | max 绝对误差 | 170（实测 152） |
| 18/19（均衡/LLR） | max 绝对误差 | 2e-2（实测 1.4e-2，量化相对 0.25%） |
| 11（同步） | 起点相等；度量 ≤1e-4；CFO ≤0.1 Hz | 实测：起点 0=0、度量差 6e-6、CFO 0 |
| 12（相位校正） | max 绝对误差 | 1e-4（实测 1.8e-13） |

**原则**：超过上表的差异必须定位到具体阶段；阶段 18/19 若超差优先怀疑尾 UW
增益归一化缺失（审计 §3-X1）。若未来把 C 发射混频改为浮点（消除 int32 截断），
07/08 容差可收紧到 ~2.5/2。
