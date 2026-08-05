# SC-FDE 水声通信项目 → STM32 移植审计报告

审计日期：2026-08-04
审计对象（本地，非 GitHub）：
- MATLAB 仿真：`papers\`（黄金模型 `papers\engineering_simulation\run_text_scfde_demo.m`，836 行）
- GD32E503C 固件：`GD32E503C_START_Demo_Suites\Projects\02_SC_FDE_UWA_MODEM\`（16 个 .c/.h 算法+BSP 文件）

行号均按审计时读取的实际文件内容。无法核实的内容一律标注「未确认」。

---

## 1. 项目结构与实现能力清单

### 1.1 目录树（仅源码）

```
papers/                                    ← MATLAB 仿真工程
├── engineering_simulation/
│   ├── run_text_scfde_demo.m              ← 端到端黄金模型（836 行）
│   ├── simulate_chapter2_single_carrier_tde.m / simulate_chapter3_scfde.m
│   ├── simulate_chapter4_iterative_equalization.m
│   ├── scfde_bellhop_channel.m / sc_tde_bellhop_array_channel.m
│   ├── compare_scfde_tde.m / run_all_scfde_simulations.m / launch_scfde_text_app.m
│   └── verify_scfde_project.m             ← 仅结构检查（文件存在+目标芯片），非数值比对
├── modules\+scfde\                       ← 模块化流水线（source/channel/receiver/equalizer/metric）
├── chapter2..6_simulation\ common\ tests\ ← 论文复现与测试
GD32E503C_START_Demo_Suites\Projects\02_SC_FDE_UWA_MODEM\   ← GD32 固件
├── main.c / main.h                        （25/13 行，仅初始化+主循环）
├── scfde_app.c / .h                       （231/10 行，串口菜单+角色状态机）
├── scfde_modem.c / .h                     （545/84 行，帧、同步、CFO、LS、解码调度）
├── scfde_fft.c / .h                       （117/23 行，radix-2 FFT 32/128 点）
├── scfde_ldpc.c / .h                      （153/23 行，LDPC(192,128) 编码+最小和译码）
├── scfde_equalizer.c / .h                 （267/64 行，MMSE/ZF/MF/IB-DFE/NLMS-TDE）
├── bsp_passband_tx.c / .h                 （283/20 行，DAC0+PA4+TIMER6+DMA1_CH2 @96kHz）
├── bsp_passband_rx.c / .h                 （443/51 行，ADC0+PA0+TIMER2+DMA0_CH0 @48kHz）
├── bsp_usart.c / .h                       （81 行，USART0 9600 8-N-1）
├── bsp_half_duplex.c / .h                 （212 行，PB0/PB1 半双工+同步）
├── systick.c / .h  gd32e50x_it.c / .h  gd32e50x_libopt.h
├── MDK-ARM\GD32E503C_START.uvprojx        ← Keil 工程
├── EWARM\  third_party\  tools\  matlab\（仿真副本）
GD32E50x_Firmware_Library\                  ← GD32 标准外设库（CMSIS + 外设驱动）
```

### 1.2 关键构建证据（实测）

| 项目 | 证据 |
|---|---|
| Keil 目标芯片声明 | uvprojx `<Device>GD32E503CE</Device>` |
| **Keil CPU 类型配置** | uvprojx `<Cpu>CPUTYPE("Cortex-M33") FPU3(SFPU) ... IRAM(0x20000000,0x20000) IROM(0x08000000,0x080000)` |
| **预处理宏** | uvprojx `<Define>GD32E50X,GD32E508,USE_STDPERIPH_DRIVER</Define>` |
| CMSIS 内核头 | `GD32E50x_Firmware_Library\CMSIS\GD\GD32E50x\Include\gd32e50x.h:44` → `#include "core_cm33.h"` |
| 启动文件（工程引用） | `...\Source\ARM\startup_gd32e50x_hd.s`（M4F/ARMv7-M 启动文件） |
| 编译产物 | `MDK-ARM\output\` 仅有 `main.o/main.d/main.__i`，**无 .axf/.hex/.map** → 工程从未完整构建过 |

**发现的问题 A（严重）**：Keil 工程按 **Cortex-M33 + GD32E508 宏** 配置，而板载芯片为 **GD32E503CE（Cortex-M4F @200MHz）**；C 代码按 ARMv8-M/SFPU 指令集生成（`core_cm33.h`），却链接 M4F 的启动文件、烧录到 M4F 芯片，且从未完整编译验证。IRAM 按 128KB 配置（GD32E508 规格），GD32E503C 官方 SRAM 为 96KB（未在本仓库核验数据手册，标「未确认」），链接器允许的地址范围可能超出芯片实际容量。

### 1.3 功能逐项核实表（16 项）

| # | 功能 | 文件:函数:行号 | 状态 | 与 MATLAB 一致 |
|---|---|---|---|---|
| 1 | 固定大小静态内存 | `scfde_modem.c:34-41`（g_uw/g_tx_data/g_phase_symbols/g_frame_symbols/g_fft_a/g_fft_b 全 static）；`scfde_fft.c:15`；`scfde_equalizer.c:22-24`；`bsp_passband_rx.c:32-33`；`scfde_app.c:26`；模块注释声明非重入 `scfde_modem.c:20-21` | ✅ 实现 | — |
| 2 | NCO/载波查表 | TX：`scfde_modem.c:31-32` 8 点 int16 表（256·cos(kπ/4)），使用 `scfde_modem.c:189-196`；RX：`scfde_modem.c:472-475` 4 点 int8 表 | ✅ 实现 | TX 表量化（±0.5/256）；RX 表精确 |
| 3 | RRC FIR | **无 RRC 函数**。TX 为矩形保持（`scfde_modem.c:191` symbol=index/24）；RX 为 12 点积分清零（`scfde_modem.c:466-479`） | ❌ 未实现 | **不一致**：MATLAB 默认 RRC(0.35, span8) `run_text_scfde_demo.m:154-156,326-334,407-411` |
| 4 | ADC/DAC/DMA/定时器 | RX：`bsp_passband_rx.c:15-30,78-89,162-215,217-270,311-402,435-443`；TX：`bsp_passband_tx.c:13-28,146-190,192-283` | ✅ 实现 | — |
| 5 | UW 帧同步 | `scfde_modem.c:213-232`（scfde_sync_metric），搜索循环 `scfde_modem.c:452-495` | ✅ 实现 | ✅ 公式同 `run_text_scfde_demo.m:598-603` |
| 6 | 采样相位搜索 | `scfde_modem.c:452-495`（phase 0..11 × offset 全窗口） | ✅ 实现 | ✅ 结构同 `run_text_scfde_demo.m:413-440` |
| 7 | CFO/相位补偿 | `scfde_modem.c:242-263`（UW1/2、UW2/3 两段相位率）+ `scfde_modem.c:265-284`（线性斜率→二次相位） | ✅ 实现 | ✅ 公式同 `run_text_scfde_demo.m:460-470` |
| 8 | 32/128 点 FFT/IFFT | `scfde_fft.c:45-117`（radix-2 DIT 原地，逆变换 1/N 缩放 108-116，共用 64 项 twiddle） | ✅ 实现 | ✅ 符号/缩放同 MATLAB fft/ifft |
| 9 | LS 信道估计 | `scfde_modem.c:286-342`（32 点 FFT→相除→IFFT→28 抽头截断→补零 128 点） | ✅ 实现 | ✅ 公式同 `run_text_scfde_demo.m:472-478` |
| 10 | MMSE-FDE | `scfde_equalizer.c:45-89`（denom=\|H\|²+λ） | ✅ 实现 | ≈（差异：C 无尾 UW 增益归一化，见 §3） |
| 11 | IB-DFE | `scfde_equalizer.c:91-146`（2 次迭代、β=0.65、硬判决、尾 UW 注入） | ✅ 实现 | ⚠️ 固件特有，MATLAB 黄金模型无对应（§3-17） |
| 12 | NLMS-TDE | `scfde_equalizer.c:188-266`（16 抽头、6 epoch、μ=0.35、循环训练） | ✅ 实现 | ⚠️ 固件特有（§3-18） |
| 13 | CRC-16 | `scfde_modem.c:62-84`（init 0xFFFF、poly 0x1021、MSB-first）；放置 `scfde_modem.c:137-139` | ✅ 实现 | ✅ 同 `run_text_scfde_demo.m:723-736,277-279` |
| 14 | LDPC(192,128) | `scfde_ldpc.c:19-22`（移位表 {0,5,11,17}/{1,7,13,19}）、编码 43-57、分层归一化最小和 0.80（126-135）、10 次迭代（modem.c:384） | ✅ 实现 | ✅ 同 `run_text_scfde_demo.m:652,668,691,615` |
| 15 | QPSK/BPSK/16QAM | C 仅 QPSK：`scfde_modem.c:149-156`（bit0→I，bit1→Q，1→+1） | ✅（固定 QPSK） | ✅ 与 MATLAB 默认一致（`run_text_scfde_demo.m:149,304`）；BPSK/16QAM 仅 MATLAB 有 |
| 16 | 串口控制/结果输出 | `bsp_usart.c:29-44`（9600 8-N-1 PA9/PA10）；`scfde_app.c:217-231` 角色/命令菜单 | ✅ 实现 | — |

---

## 2. 算法层 / BSP 层分类

### A. 平台无关算法层（可移植）

| 文件 | 内容 | 外部依赖（仅算法） |
|---|---|---|
| `scfde_fft.c/.h` | FFT/IFFT、复数结构体 | `<math.h>` `<stdint.h>` |
| `scfde_ldpc.c/.h` | LDPC 编码/译码 | `<string.h>` `<stdint.h>` |
| `scfde_equalizer.c/.h` | MMSE/ZF/MF/IB-DFE/NLMS-TDE | `scfde_fft.h` `<string.h>` |
| `scfde_modem.c/.h` | 帧、同步、CFO、LS、调制/解调、CRC、解码调度 | `scfde_fft.h` `scfde_ldpc.h` `scfde_equalizer.h` `<math.h>` `<string.h>` |

→ **四个文件均不含任何 GD32 头文件，可直接在 PC/STM32 上编译**（实测头文件依赖链干净）。

### B. GD32 平台相关层（必须重写/适配）

| 文件 | 内容 | 移植动作 |
|---|---|---|
| `main.c` | 初始化顺序 | 少量修改（换成 STM32 初始化） |
| `scfde_app.c` | 串口菜单/角色状态机 | 少量修改（usart 抽象） |
| `bsp_usart.c` | USART0 9600、fputc、delay_ms | 重写（HAL 版） |
| `bsp_passband_tx.c` | DAC0+PA4+TIMER6+DMA1_CH2 96kHz | 重写 |
| `bsp_passband_rx.c` | ADC0+PA0+TIMER2+DMA0_CH0 48kHz、信号检测/预卷 | 重写 |
| `bsp_half_duplex.c` | PB0/PB1 方向控制 | 重写 |
| `systick.c` | SysTick 延时 | 重写/删除（systick_config 从未被调用，见 §9-P7） |
| `gd32e50x_it.c` | 中断向量 | 重写（STM32 向量） |
| `gd32e50x_libopt.h` | 外设选择 | 重写 |

### C. 表面无关、实际含 GD32 依赖的文件

- **`scfde_app.c`**：注释称"不含 DSP"，但它 include `main.h`（`main.h:6` include `gd32e50x.h`），并调用 `usart_get_byte`/`passband_tx_send_blocking`/`passband_rx_*`/`half_duplex_*`——**通过 BSP 间接依赖 GD32**。移植时必须同时替换 BSP。
- **`bsp_usart.c` 的 `delay_ms`（46-59 行）**：忙等循环，依赖主频（未校准，见 §9-P6）。

---

## 3. MATLAB/C 参数一致性矩阵

黄金模型：`papers\engineering_simulation\run_text_scfde_demo.m`。C 侧常量：`scfde_modem.h:18-30`、`scfde_modem.c:24-29`。

| # | 参数 | MATLAB 当前值 | C 当前值 | 一致 | 差异后果/建议/修改位置 |
|---|---|---|---|---|---|
| 1 | FFT 长度 | 128（`run_text_scfde_demo.m:147`） | 128（`scfde_modem.h:24`） | ✅ | — |
| 2 | UW 长度/序列 | 32，Chu：`exp(-1j·π·n²/32)`（:66） | 32，`-π·n²/32` 的 cosf/sinf（`scfde_modem.c:91-96`） | ✅ | — |
| 3 | 帧符号排列 | `[UW UW DATA(96) UW]`（:69） | 同（`scfde_modem.c:165-176`） | ✅ | — |
| 4 | 符号率 | 4000（:150） | 4000（`scfde_modem.h:21`） | ✅ | — |
| 5 | TX/RX 采样率 | 96000/48000（:151-152） | 96000/48000（`scfde_modem.h:18-19`） | ✅ | — |
| 6 | 载波频率 | 12000（:153） | 12000（`scfde_modem.h:20`） | ✅ | — |
| 7 | **RRC 成形** | 默认 RRC，滚降 0.35、跨度 8 符号（:154-156）；`conv` 实现（:334） | **无 RRC**：TX 矩形保持（`scfde_modem.c:191-196`），RX 12 点 I&D（:466-479） | ❌ | 后果：C 发射频谱约 8-16kHz（ZOH 主瓣），比 MATLAB RRC（±5.4kHz）宽约 50%，邻道/带外干扰更大，两板对测性能与 MATLAB 不严格可比。建议：a) 黄金向量统一用 `pulseShape="rectangular"`（此时 C 与 MATLAB 波形一致，可用）；b) 长期在 C 侧补 RRC（CMSIS-DSP `arm_fir_f32`）并以 MATLAB 为准。修改位置：`scfde_modem.c` 发射符号生成 + 接收匹配滤波 |
| 8 | QPSK 星座/比特序 | `[-1-1j,1-1j,-1+1j,1+1j]`，LSB-first，bit0→I（:291,304；:317-322） | 同（`scfde_modem.c:144-156`） | ✅ | — |
| 9 | 数据包头 | `A5 5A 长度 序号`（:271-274） | `scfde_modem.c:129-132` | ✅ | — |
| 10 | 长度字段 | 第 3 字节（:273） | 同（:131） | ✅ | — |
| 11 | 帧序号 | 第 4 字节（:274） | 同（:132） | ✅ | — |
| 12 | CRC 字节序 | 高字节在前（:278-279） | 高字节在前（`scfde_modem.c:138-139`） | ✅ | — |
| 13 | LDPC 矩阵/比特排列 | 移位表 {0,5,11,17}/{1,7,13,19}，系统位在前，LSB-first（:652,668；:639-711） | 同（`scfde_ldpc.c:19-22,43-57`；`scfde_modem.c:143-147`） | ✅ | — |
| 14 | FFT 符号/缩放/排列 | 正变换不缩放，逆变换 1/N（MATLAB 语义） | 同（`scfde_fft.c:108-116`，自然序输入） | ✅ | — |
| 15 | LS 信道估计公式 | `Y·conj(X)/(\|X\|²+eps)`（:472-478） | 分母 +1e-9（`scfde_modem.c:311`） | ✅ | eps≈2.2e-16 vs 1e-9，仅影响 |X|²≈0 时，可忽略 |
| 16 | MMSE 正则化 | `0.5·mean\|r1-r2\|²·(N/2)`，下限 `sum\|H\|²·0.01/N`（:481-488） | 完全同式（`scfde_modem.c:300-341`） | ✅ | — |
| 17 | **IB-DFE** | 黄金模型无 IB-DFE；chapter3 `ibdfe_equalize`（`simulate_chapter3_scfde.m:517+`）为 SD/HD+可靠性加权结构，无 β=0.65 | β=0.65、2 次迭代、硬判决（`scfde_equalizer.c:15-16,108-145`） | ⚠️ 未确认 | C 为独立简化实现，无 MATLAB 黄金对应。建议：用黄金向量/回环标定其行为，或在 MATLAB 补对应实现后再比对 |
| 18 | **NLMS-TDE** | 黄金模型无；chapter2 `nlmsStep=0.35`（`simulate_chapter2_single_carrier_tde.m:27`）但为 DFE 结构 | 16 抽头、6 epoch、μ=0.35、循环训练（`scfde_equalizer.c:17-19,188-266`） | ⚠️ 未确认 | 抽头数/训练方式无 MATLAB 对应，同上建议 |
| 19 | 同步门限 | 0.18（:183） | 0.18（`scfde_modem.c:28`） | ✅ | — |
| 20 | ADC/DAC 中点/幅度 | 2048/2048/700（:184,361） | 2048/2048/700（`scfde_modem.c:27`；`bsp_passband_tx.c:23`） | ✅ | TX 载波表量化 ±0.5/256≈0.2% |
| 21 | 信道抽头 | 28（:179） | 28（`scfde_modem.c:26`） | ✅ | — |

### 附加不一致（矩阵外）

| # | 项 | MATLAB | C | 后果/建议 |
|---|---|---|---|---|
| X1 | 尾 UW 增益归一化 | 有：`/residualGain`（:499-503） | 无 | 星座残余复增益未校准；QPSK 硬判决下影响小，但黄金向量逐点比对必超差。建议 C 侧按 MATLAB 补上（1 处，`scfde_equalizer.c` 或 `scfde_modem.c` 均衡后） |
| X2 | 判决导向更新 | 有（0.65/0.35 混合，:510-534） | 无（以 IB-DFE 代替） | 行为差异，非错误；文档化即可 |
| X3 | AUTO 多均衡器重试 | 无 | 有（`scfde_modem.c:423-429,522-530`） | C 特有增强，CRC 门控，安全 |
| X4 | 帧重试 | maxFrameAttempts=3（:213） | 1 次（`scfde_app.c:146-160`） | README 已声明；测 FER 时 MATLAB 用 1 |
| X5 | RX 捕获长度 | 动态（帧+前后导） | `SCFDE_RX_CAPTURE_LENGTH 4096`（`scfde_modem.h:30`） vs BSP 缓冲 `8192`（`bsp_passband_rx.h:6`） | 常量不一致，白占 8KB SRAM（见 §9-P4） |
| X6 | 下行复基带 | 双精度 | float32 | 需黄金向量定量（见交付物） |
| X7 | 发射载波 | `exp(j2πfct)` 精确（:353） | 8 点表 ×256 量化（`scfde_modem.c:31-32,194-196`） | 逐点误差 ≤ 700/256≈2.7 DAC 码；黄金向量容差见 FORMAT.md |

---

## 4. 数值格式与稳定性检查

- **格式**：全部 `float32`（`scfde_fft.h:8-9` 复数结构体 2×float），无 Q15/Q31。M4F 带 FPU，合理。
- 复数结构体：`{float re; float im;}` 8 字节，与 CMSIS-DSP 交错 float 缓冲布局兼容（仅需类型转换）。
- FFT 缩放：无中间缩放，纯 float；I&D 输出幅度 ≤ 2048×12≈24576，float32 相对误差 ~1e-6，安全。
- 除零保护（均有）：LS 分母 +1e-9（`scfde_modem.c:311`）；MMSE λ 下限 `channel_power·0.01/128`（:335-339）；ZF floor `mean·1e-4` 下限 1e-12（`scfde_equalizer.c:62-66`）；同步能量下限 1e-12（`scfde_modem.c:224-227`）；NLMS ε=1e-6（:217）。
- NaN/Inf：无直接产生路径；atan2f/cosf/sinf 输入有界。低风险。
- 数组越界：`g_phase_symbols` 上限 342（=4096/12+1，`scfde_modem.c:29,457-460`）；offset ≤ 150 时拷贝 192 符号（:484-491）安全。
- 栈：`scfde_demodulate_packet` 局部 `llr[192]`=768B + 小数组 ≈1.1KB；主循环栈需求 <2KB。静态区估算 ≈35KB（含 BSP 缓冲，见 §5），低于 96KB SRAM 上限。
- 共享变量：`g_passband_rx_capture_done/busy` 均为 `volatile`（`bsp_passband_rx.c:34-35`）✅；ISR 只置标志（:435-443）✅。
- 非重入：模块级静态缓冲，注释声明（`scfde_modem.c:20-21`），单线程主循环使用，安全。
- 未初始化：`scfde_modem_init` 清零 `g_tx_data`（:97）；其余静态区由启动文件清零。OK。

---

## 5. 资源与实时性分析

> 依据：算法计数 + 芯片规格估算。固件从未完整编译，**Flash/RAM 实测值不可得（未确认）**，以下为静态估算。

### 5.1 静态 RAM 估算（近似）

| 缓冲 | 大小 |
|---|---|
| RX 捕获缓冲（BSP 分配 8192 但 modem 只用 4096） | 16,384 B |
| g_phase_symbols（342×8B） | 2,736 B |
| g_frame_symbols / g_fft_a / g_fft_b（192/128/128×8B） | 1,536+1,024+1,024 B |
| 均衡器 3×128×8B | 3,072 B |
| LDPC messages 320×4B + twiddle 64×8B + 其余 | ~2,000 B |
| TX DMA 512×2B + app 回环 2304×2B | 5,632 B |
| **合计（含全量 BSP）** | **≈35 KB**（若把 RX 缓冲收敛到 4096 则为 ≈27 KB） |

### 5.2 单帧计算量（最坏 AUTO 模式，5 个均衡器都试）

- 同步搜索：12 相位 × ~150 偏移 × 约 250 次浮点 ≈ **45 万次**
- FFT：32 点×2 + 128 点；AUTO 5 种均衡器共约 20 次 128 点变换 ≈ 7.2 万蝶形
- LDPC：10 迭代 × 64 校验 × 5 边 ≈ 32 万次浮点（最坏不收敛）
- 合计 ≈ 100 万次浮点 → GD32E503C @200MHz（M4F FPU，单周期 FMAC 估算）**约 5~15 ms**

### 5.3 两种架构

**① 当前 burst 架构（整帧捕获后处理）**
- 捕获：4096 采样 / 48kHz = **85 ms**（含信号检测等待）；解码 ≈ 5-15 ms。
- 发射：4608 采样 / 96kHz = **48 ms**（阻塞逐点输出）。
- 单帧收发往返 ≈ 150-200 ms（含保护时间）。**无丢帧窗口**——解码发生在捕获完成之后、下一次用户触发之前。
- **结论：对"单次消息突发通信"完全满足实时性，无需改为流式。** 84 与 MATLAB 帧长（192 符号=48ms）一致。

**② 连续接收流式**
- 需求：48k 采样/秒 实时处理（每符号 12 采样、4k 符号/秒）；同步需改造为滑动状态机 + 环形缓冲 + 定时恢复；当前 `scfde_modem_decode` 的"12 相位×全窗口"搜索不可直接流式化。
- 计算量估算 0.8~2M flops/s，200MHz 下 CPU 占用 <5%，**算力足够，缺的是软件结构**。
- 结论：流式是未来增强，不是当前突发应用的先决条件。

---

## 6. STM32 移植方案（目标：STM32F407VGT6，168MHz，Cortex-M4F）

### 6.1 接口映射表

| GD32 文件/接口 | 当前外设 | STM32F407 替代 | 修改范围 |
|---|---|---|---|
| `gd32e50x.h` + `core_cm33.h` | CM33 内核头 | `core_cm4.h`（CMSIS 自带，仓库已有） | 头文件替换 |
| `startup_gd32e50x_hd.s` | M4F 启动 | `startup_stm32f407xx.s`（Keil 内置） | 替换 |
| `gd32e50x_*.c` 标准外设库 | GD32 驱动 | STM32 HAL（`stm32f4xx_hal_*.c`） | 替换整个库 |
| `bsp_passband_rx.c` | ADC0/PA0/TIMER2 TRGO/DMA0_CH0/`DMA0_Channel0_IRQn` | ADC1 IN0(PA0)、TIM2 TRGO 触发、DMA2 Stream0 Ch0（ADC1）、`DMA2_Stream0_IRQHandler`；48kHz：APB1 84MHz→ARR=1749 | 重写 |
| `bsp_passband_tx.c` | DAC0/PA4/TIMER6 TRGO/DMA1_CH2 | DAC1 OUT1(PA4)、TIM6 TRGO 触发、DMA1 Stream5 Ch7（DAC1）；96kHz：ARR=874 | 重写 |
| `bsp_usart.c` | USART0 PA9/PA10 9600 | USART1 PA9/PA10 | 重写 |
| `bsp_half_duplex.c` | PB0/PB1 | PB0/PB1（任意 GPIO） | 重写（逻辑不变） |
| `systick.c` | SysTick | HAL_Delay 或 SysTick 中断 | 重写/删除 |
| `gd32e50x_it.c` | 向量 | `stm32f4xx_it.c` | 重写 |
| `scfde_*.c/.h`（4 个算法文件） | 无芯片依赖 | **原样复用** | 零修改 |
| `scfde_app.c` | 调 BSP API | 改调 STM32 BSP 同构 API | 少量修改（保持函数签名） |

### 6.2 时钟配置（CubeMX）

- 时钟树：HSE 8MHz → PLL → SYSCLK 168MHz；APB1=84MHz（定时器时钟 168MHz，因 APB1 预分频 ×2）；APB2=84MHz。
- ADC1：分辨率 12bit，采样时间 55.5+ 周期，外部触发 `TIM2 TRGO`，DMA 循环/普通模式，16bit 半字。
- TIM2：PSC=0，ARR=1749（168M/48000-1），TRGO=Update。
- DAC1：OUT1（PA4），`TIM6 TRGO` 触发，DMA1 Stream5 Ch7，12bit 右对齐，输出缓冲开。
- TIM6：ARR=874（168M/96000-1），TRGO=Update。
- USART1：9600 8-N-1，PA9/PA10，中断关闭（阻塞收发即可）。
- 双缓冲建议：RX 首版维持单缓冲整帧捕获（85ms）；如需流式再改 DMA 半传输中断双缓冲。

### 6.3 CMSIS-DSP 使用方式

- FFT：`arm_cfft_f32`（128 点，若启用 CMSIS 需改缓冲布局为交错 float 数组并注意 `arm_cfft_radix4` 缩放语义）；也可继续用现有自研 FFT（已验证一致）。
- FIR（若补 RRC）：`arm_fir_f32`（状态缓冲 + 系数表）。
- 建议：首版不引入 CMSIS-DSP，直接复用自研算法文件，减少差异面；流式版再加。

---

## 7. 问题分级清单

| 级别 | 问题 | 证据 | 建议 | 验证方法 |
|---|---|---|---|---|
| 阻止编译/运行 | P1: Keil 工程按 Cortex-M33+GD32E508 配置，与板载 M4F 的 GD32E503CE 不符；且从未完整构建（output 仅 main.o） | uvprojx `<Cpu>CPUTYPE("Cortex-M33")`、`<Define>GD32E50X,GD32E508`；`gd32e50x.h:44` core_cm33.h；`MDK-ARM\output\` 内容 | 改 `<Cpu>` 为 `Cortex-M4`、宏改 `GD32E503C`（库需配 GD32E50X_HD 或对应器件宏）、核对 IRAM=0x18000(96KB)；先完整构建 | Keil 完整编译 + 烧录跑角色菜单 |
| 阻止编译 | P2: `systick_config()` 从未被调用（`main.c:12-25` 无调用；`bsp_usart.c:23-27` system_init 为空） | `systick.c:46`；`main.c` | 删除或接入 | 编译 + 功能确认 |
| MATLAB/C 数值不一致 | P3: RRC 缺失（C 矩形成形） | §3-7 | 黄金向量用 rectangular 对齐，或 C 补 RRC | 黄金向量 PASS/FAIL |
| MATLAB/C 数值不一致 | P4: 尾 UW 增益归一化缺失（C） | §3-X1 | C 均衡后补 `/residualGain` | 黄金向量 |
| MATLAB/C 数值不一致 | P5: IB-DFE/NLMS-TDE 无 MATLAB 黄金对应 | §3-17,18 | 回环标定 + 文档化；或 MATLAB 补实现 | 回环测试 + 误码对比 |
| MATLAB/C 数值不一致 | P6: TX 载波查表量化（±2.7 DAC 码）、float32 全链路 | `scfde_modem.c:31-32,194-196` | 黄金向量容差放行；评估后可用 16 位表升级 | 对比脚本 |
| 偶发解码错误 | P7: `delay_ms` 忙等未校准（3000 次迭代，@200MHz 估算约 0.1ms 而非 1ms）→ 超时 5s 实际约 0.5s、半双工保护时间缩短 | `bsp_usart.c:46-59` | 改用 SysTick 计数延时 | 实测超时/保护时间 |
| 偶发解码错误 | P8: 信号预卷(256)与 DMA 追加切换存在采样间隙（无覆盖缓冲），帧头可能落入间隙 | `bsp_passband_rx.c:91-107→217-270` 切换 | 预卷期间 DMA 双缓冲；或延长预卷并接受重试 | 两板对测连续发帧 |
| 实时性不足 | P9: 无（burst 架构满足；见 §5） | — | — | — |
| 代码质量 | P10: RX 缓冲 8192 与 modem 上限 4096 常量不一致，白占 8KB SRAM | `bsp_passband_rx.h:6` vs `scfde_modem.h:30` | 统一为 4096 | 编译后 map 检查 |
| 代码质量 | P11: 串口 `app_read_line` 无超时（阻塞挂死）；`app_transmit` 用 `delay_ms` 忙等 | `scfde_app.c:51-68` | 加超时 | 操作验证 |
| 连续流式 | P12: 无流式接收结构（当前为整帧捕获） | §5.3 | 按需开发状态机 | 流式回环 |
| 真实水声环境 | P13: 无宽带多普勒重采样/时变信道/实测数据/AGC（README 已声明） | `README.md:36-39` | 后续阶段 | 湖试 |
| 偶发解码错误（未来启用 LDPC 时） | P14: **LDPC(192,128) d_min=2 构造缺陷**——QC 移位仅在 32 位块内，同一 residue mod 32 的信息位列重复（重复列）→ 单比特翻转纠错率实测仅 33%，且 67% 单错场景译码器返回 syndrome=0 的错误结果（静默误纠） | `scfde_ldpc.c:19-30`；2000 次随机探针实测（33.1%/11.3%） | 基线已关闭 LDPC 不受影响；**重新启用前必须重设计码**（随机 4-正则/QC 加环长约束），并给译码器加 CRC 级联确认 | 重设计后跑纠错率测试 ≥99%（单错） |
| 实时性/水声 | P15: 同步+CFO 估计有效范围约 ±10Hz（@4ksym，12kHz 载波 ≈1.25m/s 径向速度）；≥20Hz 时 MATLAB 与 C 一致失锁（已实证） | `test_sync` 10Hz PASS/30Hz 失锁 + MATLAB 同场景复现（start=118、CFO≈14 完全一致） | 静态实验可用；移动平台需重采样级多普勒补偿 | 湖试移动场景专项测试 |

---

## 8. 交付物索引

| 交付物 | 位置 |
|---|---|
| 本报告 | `porting_stm32\AUDIT_REPORT.md` |
| 黄金向量生成脚本（MATLAB） | `porting_stm32\golden_vectors\export_golden_vectors.m` |
| 黄金向量文件格式规范 | `porting_stm32\golden_vectors\FORMAT.md` |
| PC 端 C 单元测试工程（CMake+GCC） | `porting_stm32\pc_tests\`（直接编译固件算法源文件，零拷贝） |
| 自动对比脚本 | `porting_stm32\compare\compare_golden.py` |

---

## 9. 推荐实施顺序

1. **阶段 0（立即）**：修正 Keil 工程 M33→M4F 配置，完整编译固件（P1、P2）。
2. **阶段 1（验证基线）**：运行 `export_golden_vectors.m` 导出 23 阶段向量；在 PC 上编译 `pc_tests`，运行 `test_end_to_end` + 各模块测试；`compare_golden.py` 输出逐阶段误差 → 修复 P3/P4。
3. **阶段 2（标定 C 特有算法）**：IB-DFE/NLMS-TDE 回环标定（P5），建立误码基线。
4. **阶段 3（移植）**：按 §6 映射表重写 BSP，算法文件原样复用；Keil 或 CMake+arm-none-eabi-gcc 构建。
5. **阶段 4（硬件）**：两板对测（DAC→ADC 衰减直连→水中换能器），P7/P8 实测修复。
6. **阶段 5（增强，可选）**：RRC、流式接收（P12）、宽带多普勒、实测信道（P13）。

---

## 10. 最终结论

1. **可复用算法代码**：`scfde_fft.c`、`scfde_ldpc.c`、`scfde_equalizer.c`、`scfde_modem.c` 四个文件（约 1080 行）为纯平台无关 C，**100% 可直接复用**；`scfde_app.c` 逻辑可复用约 80%（仅 BSP 调用需换）。
2. **STM32 是否只需重写 BSP**：**是**，算法层零修改；BSP（USART/DAC/ADC/DMA/Timer/中断/延时）需重写，工作量为 6 个文件。
3. **仍需修改算法层的地方**：a) 补尾 UW 增益归一化（对齐 MATLAB，1 处）；b) 决定 RRC 或明确矩形成形（波形级差异，影响对外指标表述）；c) IB-DFE/NLMS-TDE 需建立标定基线（不是必须修改，但必须验证）。
4. **当前固件与 MATLAB 数值一致吗**：**结构/公式 21 项参数中 19 项一致、2 项未确认（IB-DFE、NLMS-TDE）+ 3 项附加差异（RRC、尾增益、DD 更新）**。逐点数值一致性**尚未建立**——黄金向量体系（本交付物）建成之前，不能声称一致。
5. **适合突发通信还是连续接收**：**适合突发（单帧消息）**；burst 架构处理时间 5-15ms 远小于捕获时间 85ms，无丢帧窗口。连续流式需另建状态机，算力充裕但结构未做。
6. **是否适合进入 STM32 实机移植（未经修改）**：**暂不适合，有 3 个前置条件**：
   - 必须修正 Keil 工程 CPU/宏配置（M33→M4F）并通过完整编译（P1）；
   - 必须先跑通黄金向量比对，量化 float32/查表量化差异（P3/P4/P6）；
   - 必须先决定 RRC 处置（P3）——这同时决定对外频带指标。
   满足这三项后，算法文件可直接搬入 STM32 工程，BSP 按 §6 映射表重写即可。
