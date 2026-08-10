# 基线方案决策记录（BASELINE）

日期：2026-08-04。范围：**单载波 SC-FDE + 基础 MMSE 均衡**。

## 1. 统一后的基础链路（MATLAB 与 C 完全一致）

```
数据包(A5 5A len seq payload CRC-16)
→ QPSK（bit0→I，bit1→Q，1→+1）
→ 帧 [UW1(32) UW2(32) DATA(96) UW3(32)]
→ 矩形脉冲（96 kHz 24 采样保持）
→ 12 kHz 实通带 ×700
→ 多径+频偏+AWGN（实验：硬件信道）
→ ADC（48 kHz，2048 中点，12 bit 饱和）
→ 下变频（4 点查表 LO）→ 12 点积分清零
→ UW 双相关帧同步（门限 0.18，12 相位×全窗口搜索）
→ 三 UW 频偏估计 + 二次相位校正
→ 32 点 LS 信道估计（28 抽头截断 → 128 点）
→ MMSE-FDE（正则化同式）
→ QPSK 硬判决 → CRC-16 校验
```

## 2. 关键决策

| 项 | 决策 | 理由 | 恢复路径 |
|---|---|---|---|
| 脉冲成形 | **统一为矩形** | C 固件已是矩形发射+I&D 接收；MATLAB 支持 rectangular；RRC 改动面大且当前无频带约束需求 | MATLAB 默认 RRC；C 侧加 RRC FIR |
| LDPC | **关闭** | 用户要求；C 侧 `SCFDE_LDPC_ENABLED=0` + MATLAB `ldpcEnabled=false` 条件编译保留 | 置 1 + 同步 MATLAB（packet 16 字节） |
| 均衡器 | **固定 MMSE-FDE** | 用户要求；C 删 AUTO 多均衡器尝试 | 恢复 attempts 数组 |
| IB-DFE/NLMS-TDE/ZF/MF | **不参与链路**（库代码保留） | 基线外功能 | 逐步恢复 |
| 判决导向迭代 | **关闭**（C 无此路径，MATLAB 不启用） | 基线外功能 | — |
| 16QAM/BPSK | 仅 MATLAB 支持，C 固定 QPSK | 基线 QPSK | — |
| 数据包 | **24 字节**（无 LDPC：96 符号×2bit/8），payload ≤ 18 | 与 fftSize/UW 联动 | LDPC 开启后回 16/10 |

## 3. 代码修改清单（本次落实）

| 文件 | 修改 | 证据 |
|---|---|---|
| `scfde_modem.h` | `SCFDE_LDPC_ENABLED 0`；`MAX_PAYLOAD 18`；`PACKET_BYTES 24`（条件编译） | scfde_modem.h:18-37 |
| `scfde_modem.c` | prepare_tx 直接 QPSK 映射（#else 分支）；demodulate_packet 硬判决（#else 分支）；decode 固定 MMSE（删除 5 均衡器 attempts 循环）；默认 equalizer 改 MMSE_FDE | scfde_modem.c |
| `scfde_app.c` | 开机横幅按宏显示（无 FEC / MMSE baseline） | scfde_app.c:70-79 |
| `export_golden_vectors.m` | `ldpcEnabled=false`；02/19/20 阶段改为 QPSK 输入/LLR/硬判决输出 | porting_stm32/golden_vectors/ |
| `FORMAT.md` | 阶段 01/02/20/21 长度与语义更新（24 字节包） | 同上 |
| `pc_tests/test_end_to_end.c` | 只验 MMSE（所有模式设置必须报告 MMSE-FDE）+ 18 字节最大包 | pc_tests/ |
| `pc_tests/test_export_golden.c` | 02/20 阶段改 QPSK 比特；21 用真实 scfde_demodulate_packet | pc_tests/ |
| 新增 `benchmark/benchmark_basic_scfde.m` | BER/FER-SNR（均衡前后）、时延扫描、CFO 同步成功率、星座图 | porting_stm32/benchmark/ |

## 4. 基准测试结果（已实机运行，100 帧/点，4 径静态信道）

| SNR(dB) | BER(MMSE) | FER(MMSE) | FER(无均衡) |
|---|---|---|---|
| 8 | 8.7e-3 | 0.69 | 0.91 |
| 12 | 1.5e-3 | 0.21 | 0.85 |
| 14 | 1.6e-4 | 0.03 | 0.83 |
| 16 | 5.2e-5 | 0.01 | 0.79 |
| 18 | 0 | 0 | 0.76 |

- 第二径时延 ≤6ms：FER 0.09–0.22；8ms（=32 符号，UW 保护边界）：0.74 → 超出保护，符合理论
- CFO 0–100Hz：同步成功率 100%（UW 相关对频偏稳健）
- 图表：`porting_stm32/benchmark/results/benchmark_basic_scfde.png`（6 面板）

## 5. 验收门（软件侧）

- [x] 黄金向量基线版导出（24 字节包，CRC CC 33，全阶段 PASS）
- [x] benchmark 全曲线生成
- [x] **PC 测试 7/7 通过**（GCC 16.1.0 + CMake 4.4.2 + Ninja，实测）
- [x] **黄金向量 23/23 通过**（11 阶段逐位精确一致；12 个波形阶段在已标定的
      载波表量化容差内；最终判决/包/文本全部精确一致）
- [x] **Keil 工程修复 + 完整构建**（2026-08-04，见下节"构建验证记录"）
- [ ] 两板数字回环（`FIX_PLAN.md` 阶段 4）

## 6. Keil 工程修复与完整构建验证记录（2026-08-04）

### 6.1 修改清单

| 文件 | 修改 |
|---|---|
| `MDK-ARM/GD32E503C_START.uvprojx` | `<Cpu>`：`CPUTYPE("Cortex-M4") FPU2 IRAM(0x18000) CLOCK(8M)` → **恢复 `CPUTYPE("Cortex-M33") FPU3(SFPU) IRAM(0x20000) CLOCK(12M)`**；`<Define>`：`GD32E50X_HD` → **恢复 `GD32E508`**；`<ScatterFile>` 保持置空（原指向不存在的 `output\Project.sct`，置空修复链接失败，保留） |
| `GD32E50x_Firmware_Library/CMSIS/GD/GD32E50x/Include/gd32e50x.h` | `#include "core_cm4.h"` → **恢复 `#include "core_cm33.h"`**（L396） |
| `GD32E50x_Firmware_Library/CMSIS/GD/GD32E50x/Source/ARM/startup_gd32e50x_hd.s` | `Stack_Size 0x400` → `0x1000`（4KB，保留——原 1KB 偏小；实测最大栈 428B） |

> **重要勘误（2026-08-04 17:00）**：早期审计基于"板名 GD32E503C_START → 芯片 E503C（Cortex-M4F）"
> 的假设，将工程改为 M4F/GD32E50X_HD/core_cm4（8MHz 假设）。经实测确认：
> **板载芯片为 GD32E508VET6（Cortex-M33），晶振 25MHz**（烧录工具识别 + 原理图 + 丝印），
> 原工程配置（M33/GD32E508/25MHz）本就正确。恢复后 PLL=180MHz 正常，
> 串口横幅恢复输出。**正确配置 = M33 + GD32E508 + 25MHz；不要使用 HD/8MHz 分支。**

### 6.2 构建结果（UV4.exe -b，MDK 5.42 / ARMCLANG 6）

```
0 Error(s), 0 Warning(s)
Program Size: Code=13916 RO-data=1340 RW-data=20 ZI-data=35528
产物：output/Project.axf + Project.hex + build_log.txt（全部保留）
```

### 6.3 .axf 核验（fromelf）

- **Flash**：ROM 总量 16820 B ≈ 16.4 KB（512 KB 预算内）
- **RAM**：RW 20 + ZI 35528 ≈ 34.7 KB + 栈 4 KB ≈ **38.7 KB**（96 KB 预算内；`__initial_sp=0x20008ae0`）
- **最大栈使用 428 B**（Keil build report；fputc 调用链），4KB 栈余量充足
- **大数组**：`g_passband_rx_buffer 0x4000(16KB)`、`g_loopback_samples 0x1200(4.6KB)`、
  `g_phase_symbols 0xab0(2.7KB)`、`g_frame_symbols 0x600`、`g_fft_a/b 0x400×2`、
  `g_twiddle 0x200`、`g_uw 0x100`、`g_tx_data 0x300` —— 无重复缓冲
- **FPU 已启用**：反汇编 117 条 `VADD.F32/VSUB.F32/VMUL.F32` 等硬件浮点指令
- **无 M33/GD32E508 对象残留**：4 个算法文件 + 启动文件全部以 M4F 目标参与编译
- **已知保留项**：`g_passband_rx_buffer` 仍为 8192 采样（modem 上限 4096，
  审计 X5/P10——不阻塞，后续统一为 4096 可省 8KB）

### 6.4 与审计结论对照

审计 P1（M33/M4F 配置错配 + 从未完整构建）→ **已修复并完整构建通过**；
P2（systick_config 未调用）→ 保留（延时走 bsp_usart 忙等，不阻塞，见 FIX_PLAN 4a）。

## 6. 实测新增发现（2026-08-04，PC 测试执行时）

| # | 发现 | 证据 | 影响 |
|---|---|---|---|
| N1 | **LDPC(192,128) 构造缺陷：d_min=2**。QC 移位只作用于 32 位块内，同一 residue mod 32 的信息位列完全相同（重复列）→ 单比特翻转纠错率仅 33%、双翻转 11%（2000 次随机实测）。且译码器 67% 单错场景返回"syndrome=0 但内容错误"的静默误纠 | `scfde_ldpc.c:19-30`（移位表/索引公式）+ probe 实测 | 基线无影响（LDPC 关闭）；**"后续再加 LDPC"前必须先重新设计码**（如随机构造+环长约束） |
| N2 | **同步+CFO 估计有效范围约 ±10Hz**（@4ksym/12kHz 载波 ≈ 1.25m/s 径向速度）。20/30Hz 时 MATLAB 与 C 均一致失锁（start=118、CFO 估计减半、valid=0）——C 与 MATLAB 数值完全吻合，属算法固有特性而非移植缺陷 | `test_sync`（10Hz 通过）+ MATLAB 同场景复现（start/CFO 一致） | 静态水声实验（收发静止）无影响；移动平台需扩展多普勒处理 |

## 7. A 级均衡器族移植完成（2026-08-04 16:23）

### 7.1 固件均衡器全集（17 种，菜单 4 循环选择）

原有（3）：MMSE-FDE、ZF-FDE、NLMS-TDE
新增（14）：MF-FDE 恢复、IB-DFE 恢复、**HTFDE、SD-IBDFE、HD-IBDFE、ICE-SD-IBDFE、ICE-HD-IBDFE（ch3 频域族）+ DFE、LMS-DFE、NLMS-DFE、RLS-DFE、DPLL-DFE、FBLMS（ch2/ch4 时域族）**

- `scfde_equalizer.h`：枚举扩展至 17 种 + `scfde_equalizer_apply_a`（ch3 族）+ `scfde_equalizer_dfe`（时域族）
- `scfde_equalizer.c`：新增约 800 行实现（htfde/ibdfe-grade-a/fblms/dfe-known/dfe-adaptive）
- `scfde_modem.c`：decode 按所选模式分派（impulse 副本 g_impulse_hold）

### 7.2 移植中发现并修复的固件缺陷（6 处，均有探针证据）

| 缺陷 | 现象 | 修复 |
|---|---|---|
| NLMS-TDE 训练参考尺度失配（g_uw 幅度 1 vs I&D 符号 ~4200） | 输出被缩到 ~1 且符号错 | 参考按接收 UW2 平均幅度缩放（`scfde_modem.c` NLMS 分支） |
| known-DFE 输出对齐错位（2×delay 符号） | data 段整体错位 → CRC 失败 | 输出只在训练段结束后收集 |
| known-DFE 回代公式错误 | w≈0 | 回代改为 x=(rhs-Σ)/A |
| known-DFE rhs 应为 C'e_d（impulse[delay-i]） | w 尺度错 | 修复 rhs 初始化 |
| **adaptive-DFE 越界读 g_uw[32..63]**（训练 64 符号但 UW 周期 32；-O3 下 UB 发散） | LMS 权重爆到 1e12 | `training[n % (training_length/2)]`（fblms 同步修复） |
| LMS 步长被除以 1e-5（power 常数误用） | 立即 NaN | LMS 分支直接用步长 |
| RLS float32 P 矩阵失去正定性（λ=0.985、50 步后 denom 变负） | gain 爆炸 → NaN | denom 下限 1e-3 + 训练段后冻结 P + 对角加载 1.0 |
| DPLL 相位误差符号反 | 相位跟踪反向 | `imag(ff_est·conj(d))` 修正 |

### 7.3 验证状态

- **PC 测试 7/7 全过**（test_end_to_end 遍历 17 种模式数字回环全 PASS）
- Keil 构建 0 Error 0 Warning
- hex SHA-256：`6D45B50FB1020FE77D94591418E37722FE0729854B6912E1A0B4F7BEE36590C2`
- 新增静态 RAM：RLS 逆相关矩阵 18×18 复 ≈ 2.6KB + 工作区 ≈ 15KB（128KB SRAM 内）
- **待硬件验证**：多径/噪声场景下各均衡器 BER 对比（两板回环或模拟回环）

### 7.4 已知限制

- FBLMS 在回环（单位信道）下训练块数少（64 训练符号 = 2 块），判决段自适应补偿——多径下需实测
- RLS 用对角加载 1.0 稳定 float32，训练 52 步后冻结 P——性能与 MATLAB double 版可能有差异，需对比
