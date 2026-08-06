# SC-FDE 水声单载波频域均衡通信系统

基于 GD32E503 的水声单载波频域均衡（SC-FDE）通信项目，包含：

- **GD32 固件**：完整的 SC-FDE 水声调制解调器（调制/同步/均衡/LDPC/串口应用）
- **MATLAB 仿真**：对照教材《单载波水声通信技术》六章的公式级仿真（约 1.9 万行代码）
- **STM32 移植工作区**：算法黄金向量、PC 单元测试、硬件回环验证

---

## 目录结构

```
├── GD32E503C_START_Demo_Suites/
│   └── Projects/
│       ├── 01_GPIO_Running_LED/           LED 示例
│       └── 02_SC_FDE_UWA_MODEM/            SC-FDE 水声调制解调器固件
├── GD32E50x_Firmware_Library/              GD32 标准外设库
├── papers/                                 MATLAB 仿真工程（主工作区）
│   ├── run_all_simulations.m               论文复现统一批处理入口
│   ├── run_unified_equalizer.m             均衡器统一运行入口（4 场景）
│   ├── run_unified_equalizer_interactive.m 均衡器交互式选择器
│   ├── modules/+scfde/                     模块化流水线与均衡器包
│   ├── chapter2~6_simulation/              各章论文复现与结果
│   ├── engineering_simulation/             MCU 配套仿真（黄金模型）
│   ├── common/                             LDPC 编解码共用
│   ├── examples/                           模块替换示例
│   └── tests/                              回归测试
├── porting_stm32/                          STM32 移植工作区
│   ├── AUDIT_REPORT.md                     移植审计报告
│   ├── golden_vectors/                     黄金向量（MATLAB + C 双侧）
│   ├── pc_tests/                           PC 端 C 单元测试（CMake）
│   ├── hardware/                           单板回环测试
│   └── twoboard/                           双板对测方案
├── book/                                   教材《单载波水声通信技术》截图
└── results/                                硬件回环实测记录
```

---

## 一、GD32 固件（02_SC_FDE_UWA_MODEM）

平台无关算法层（4 个文件，约 1090 行，可直接移植到任意平台）：

| 文件 | 功能 |
|---|---|
| `scfde_modem.c` | 帧组装、UW 双相关同步、CFO 估计、LS 信道估计、CRC-16、解码调度 |
| `scfde_equalizer.c` | MMSE/ZF/MF 频域均衡、IB-DFE、NLMS-TDE |
| `scfde_ldpc.c` | LDPC(192,128) 编码 + 分层归一化最小和译码 |
| `scfde_fft.c` | radix-2 FFT/IFFT（32/128 点） |

BSP 层（GD32 平台）：DAC 发射（96kHz）、ADC 接收（48kHz）、USART 串口菜单、半双工控制。

> 注意：`scfde_ldpc.c` 的 QC-LDPC 构造存在 d_min=2 缺陷（纠错率约 33%），基线默认关闭 LDPC（`SCFDE_LDPC_ENABLED=0`），重新启用前需重设计码。

---

## 二、MATLAB 仿真（papers/）

### 论文复现

对照《单载波水声通信技术》六章，全部核心公式实现并附自校验：

| 章 | 内容 | 关键实现 |
|---|---|---|
| 2 | 单载波时域均衡 | LMS/NLMS/RLS-DFE、DPLL 相位跟踪、PTR 时反、子带 PTR |
| 3 | 单载波频域均衡 | ZF/MMSE-FDE、HTFDE、SD/HD-IBDFE、ICE 迭代信道估计、CP/ZP/UW |
| 4 | 单载波迭代均衡 | BCJR（MAP/Log-MAP/Max-Log-MAP）、FD-Turbo、TF-Turbo、BLMS、FDDA-TEQ |
| 5 | 互补码键控扩频 | CCK/GCCK 码本、Rake、DFE、双向 DFE、TR 分集、CCK-SM MIMO-IBDFE |
| 6 | 循环移位扩频 | CSK 相关检测、软 PIC/SIC、ESE 迭代、CSK-IDMA |

```matlab
cd papers
run_all_simulations                       % 全部 11 个实验（quick 档）
run_all_simulations(struct("profile","full"))
```

### 均衡器即插即用（36 个）

所有 6 章均衡器统一契约为 `receiver = equalizer(channel, source, cfg)`，通过 `cfg.equalizers` 任意选择/混用：

```matlab
% 统一入口：4 种场景（qpsk/turbo/cck/csk）
r = run_unified_equalizer(struct("equalizers", "all"));
r = run_unified_equalizer(struct("equalizers", ["htfde","cck-rake","csk-ese"], ...
    "scenario", "auto"));

% 交互式选择器：菜单编号选择
run_unified_equalizer_interactive

% 自定义均衡器（只需满足契约）
cfg.equalizers = @my_equalizer;
```

内置均衡器清单（`modules/+scfde/equalizer_registry.m`）：

- 第2章（10）：dfe, lms-dfe, nlms-dfe, rls-dfe, dpll-dfe, mc-lms-dfe, mc-nlms-dfe, mc-rls-dfe, ptr-dfe, subband-ptr-dfe
- 第3章（7）：mmse-fde, zf-fde, htfde, sd-ibdfe, hd-ibdfe, ice-sd-ibdfe, ice-hd-ibdfe
- 第4章（9）：td-turbo, fd-dfe, fd-turbo, tf-turbo, bitf-turbo, blms-tf-turbo, tdda-teq, fdda-teq, fdda-dfe-teq
- 第5章（7）：cck-rake, cck-dfe, cck-bidfe, cck-bidfe2, cck-tr-diversity, cck-fde, cck-mfb
- 第6章（3）：csk-matched-filter, csk-soft-sic, csk-ese

### 模块化流水线

```text
source(cfg) → channel(tx,cfg) → receiverBank(channel,source,cfg) → metric(receiver,source,cfg)
```

模块通过函数句柄注入（`modules/+scfde/default_modules.m`），可整体替换（见 `examples/`）。

---

## 三、STM32 移植（porting_stm32/）

| 目录 | 内容 |
|---|---|
| `AUDIT_REPORT.md` | 详细审计：16 项功能核实、21 项参数一致性矩阵、P1-P15 问题清单 |
| `golden_vectors/` | 23 阶段黄金向量（MATLAB 与 C 双侧导出，已生成） |
| `pc_tests/` | CMake 工程直接编译固件算法源码，7 个测试全过 |
| `compare/` | 黄金向量自动比对脚本 |
| `hardware/` | 单板数字回环测试（300/300 帧 CRC 通过） |
| `twoboard/` | 双板对测方案与脚本 |

---

## 四、硬件实测

`results/` 记录单板数字回环（COM6 @9600，每批 300 帧）：

- 300/300 帧 CRC 全过，FER=0，同步度量 0.999，CFO=0Hz
- 均衡器：MMSE-FDE；载荷：`SC-FDE` 文本

---

## 五、运行要求

- **MATLAB**：R2023a 或更新（使用 string 数组、arguments 块、exportgraphics）
- **GD32 固件**：Keil MDK（GD32E503C_START 工程）
- **PC 测试**：CMake ≥ 3.10 + GCC（支持 C99）

---

## 六、已知限制

1. LDPC(192,128) 码构造缺陷（d_min=2），已默认关闭
2. 同步+CFO 估计有效范围约 ±10Hz（@4ksym，12kHz 载波），移动平台需宽带多普勒补偿
3. C 侧无 RRC 成形（矩形脉冲），发射频谱比 MATLAB（RRC 0.35）宽约 50%
4. 仿真用合成信道（Bellhop 可选），未含实测水声信道数据
5. CCK 双向 DFE（bi1/bi2）与 TR 分集在短帧下存在边界性能损失（与原实现一致）
