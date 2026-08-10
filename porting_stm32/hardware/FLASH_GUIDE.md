# 烧录说明（Flash Guide）—— GD32E503CE SC-FDE 水声调制解调器

适用：`Projects/02_SC_FDE_UWA_MODEM`，基线版本（QPSK + rectangular + LS + MMSE-FDE + CRC，LDPC OFF）。

## 1. 固件信息（本批次）

| 项 | 值 |
|---|---|
| 目标芯片 | **GD32E508VET6**（Cortex-M33 @200MHz 器件，工作于 180MHz；烧录工具实测识别） |
| 固件文件 | `Projects\02_SC_FDE_UWA_MODEM\MDK-ARM\output\Project.hex`（**41 模式版**，待 Keil 激活后生成） |
| 模式覆盖 | **41 种**：AUTO + 31 种均衡器（ch2/ch3/ch4 + PTR/MC）+ CCK 7 接收机 + CSK 3 接收机（见 §1.1） |
| Keil 构建结果 | MDK 5.42 / ARMCLANG 6：编译 0 Error 0 Warning；**链接受评估版 32KB 限制**（当前镜像 ≈ 37KB，见 §6） |
| 工程配置 | **Cortex-M33、FPU3(SFPU)、`GD32E508` 宏、core_cm33.h、25MHz HXTAL → 180MHz PLL**（与板载 25MHz 晶振匹配；原工程配置，勿改回 HD/8MHz） |
| 基线 | QPSK 4 ksym/s / 12 kHz 载波 / 96k 发射 / 48k 接收 / UW(32)×3 / 28 抽头 LS / MMSE-FDE / CRC-16 / 24 字节包（payload ≤ 18） |
| **LDPC** | **OFF**（`SCFDE_LDPC_ENABLED=0`；不要重新启用——码结构 d_min=2 缺陷，见 AUDIT_REPORT P14） |
| RX 捕获 | **8192 采样**（`SCFDE_RX_CAPTURE_LENGTH`，BSP DMA 缓冲 8192）——容纳 CCK 224 符号 / CSK 512 符号帧 |
| 源码版本 | 本机工作副本（对应 `scfde_porting_review.zip` 2026-08-04 版 + C 级 15 种移植） |

### 1.1 模式清单（菜单 4 循环 / 菜单 3 回环）

| 族 | 模式 | 帧 | 说明 |
|---|---|---|---|
| 基线 | AUTO | 标准 UW 帧 | 固定模式尝试直到 CRC 通过 |
| ch2 DFE 族 | DFE / LMS-DFE / NLMS-DFE / RLS-DFE / DPLL-DFE | 标准帧 | 时域判决反馈族 |
| ch3 FDE 族 | MMSE-FDE / ZF-FDE / MF-FDE / IB-DFE / NLMS-TDE | 标准帧 | 频域均衡 |
| ch3 A 级 | HTFDE / SD-IBDFE / HD-IBDFE / ICE-SD-IBDFE / ICE-HD-IBDFE | 标准帧 | 混合时频/迭代块 DFE |
| ch4 turbo | FD-TURBO / FD-DFE / TF-TURBO / BITF-TURBO / BLMS-TF-TURBO / TD-TURBO | 卷积编码帧 | BCJR 软反馈（payload ≤ 6B） |
| ch4 FDDA | FDDA-TEQ / TDDA-TEQ / FDDA-DFE-TEQ | 标准帧 | 判决导向自适应 |
| ch2 C 级 | FBLMS / PTR-DFE / SUBBAND-PTR-DFE / MC-LMS-DFE / MC-NLMS-DFE / MC-RLS-DFE | 标准帧 | 频域块 LMS / 被动时反 / 多通道（2 伪分支） |
| ch5 CCK | CCK-MFB / CCK-RAKE / CCK-DFE / CCK-BIDFE / CCK-BIDFE2 / CCK-TR-DIV / CCK-FDE | **CCK 帧**（224 符号，8-bit 码字 ×16，payload ≤ 10B） | 802.11b 互补码键控，独立调制解调器 |
| ch6 CSK | CSK-MF / CSK-SOFT-SIC / CSK-ESE | **CSK 帧**（512 符号，8-chip 循环移位 ×48，payload ≤ 6B） | 扩频循环移位键控，独立调制解调器 |

## 2. 烧录准备

### 2.1 下载器与接线（SWD）

推荐 **GD-Link**（开发板板载）或 **J-Link**（SWD 模式）。SWD 需 4 线 + 可选复位：

| 信号 | 目标引脚 | 说明 |
|---|---|---|
| SWDIO | PA13（SWDIO） | 必需 |
| SWCLK | PA14（SWCLK） | 必需 |
| GND | GND | 必需，与目标共地 |
| 3.3V | VDD 3.3V 参考 | 下载器需目标电压参考；若下载器自带 3.3V 输出可省略 |
| NRST | NRST | **建议连接**，避免复位时序问题 |

- 目标电压：3.3 V。**严禁 5V**。
- 若板载 GD-Link 与目标共用电源，直接插 USB 即可，无需外部 SWD。

### 2.2 擦除与下载设置（Keil）

- Project → Options → Utilities → Settings（Flash Download）：
  - **全片擦除（Erase Full Chip）**——首次烧录/换版本时使用；后续可扇区擦除
  - 烧录地址：**0x08000000**
  - 勾选 **Program** + **Verify**（烧录后校验）
  - Reset and Run：勾选（或烧录后手动复位）

### 2.3 烧录执行

1. Keil 打开 `02_SC_FDE_UWA_MODEM\MDK-ARM\GD32E503C_START.uvprojx`
2. 菜单 Flash → Download（或工具栏下载按钮）
3. 等待 "Verify OK" / "Application running"
4. 若失败：检查 SWD 接线、目标电压、下载器驱动（Keil Pack `GigaDevice.GD32E50x_DFP` 已随工程配置）

## 3. 烧录后最低验收（串口）

### 3.1 串口参数（**必须**与自动化脚本一致）

| 参数 | 值 |
|---|---|
| 波特率 | **9600** |
| 数据位 | 8 |
| 停止位 | 1 |
| 校验 | 无 |
| 流控 | 无 |
| 行结束 | `\r\n`（回车即可触发；文本输入用 `\r` 结束） |

引脚：PA9=TX，PA10=RX（USART0）。用 USB-TTL 适配器（3.3V 电平）连接，共地。

### 3.2 验收内容

上电/复位后串口应输出（逐字一致）：

```
========================================
 GD32E508VE SC-FDE Underwater Modem
========================================
PHY : QPSK, 4 ksym/s, 12 kHz carrier
FEC : none (baseline), payload <= 18 bytes
EQ  : MMSE-FDE (baseline)

Select node role:
  1: local diagnostic (no external wiring)
  2: transmitter node
  3: receiver node
  4: manual transceiver
role>
```

验收点：
- [ ] 横幅出现（QPSK / **LDPC OFF**（"FEC : none"）/ **MMSE-FDE**）
- [ ] 无 HardFault（无卡死、无横幅重复重启）
- [ ] 输入 `1` 回车 → 进入 local diagnostic，出现 `[local diagnostic] equalizer=MMSE-FDE` 菜单
- [ ] 菜单可响应（`4` 切换均衡器应显示 MMSE-FDE/ZF-FDE/MF-FDE/IB-DFE/NLMS-TDE 循环，但**解码始终固定 MMSE**；`0` 返回角色选择）

## 4. 常见问题

| 现象 | 处理 |
|---|---|
| 无横幅输出 | 检查串口参数 9600 8-N-1；PA9/PA10 是否接反；USB-TTL 是否 3.3V；共地 |
| 乱码 | 波特率不符或电平不匹配 |
| 下载失败 | SWD 四线齐全；目标 3.3V；全片擦除重试 |
| 烧录后反复重启（HardFault 循环） | 检查栈溢出迹象（当前最大栈 428B/4KB 不应触发）；重新全片擦除烧录 |

## 5. 下一步

烧录验收通过后，按顺序执行：

1. **单板纯数字回环**：菜单 `3`（digital loopback），或运行 `hardware/single_board_loopback.py` 自动跑 300 帧
2. **单板 DAC–ADC 有线回环**：见 `hardware/WIRE_LOOPBACK_GUIDE.md`
3. **两板自动对测**：`twoboard/twoboard_test.py`（见 `twoboard/README.md`）
4. **26+ 模式全量回环扫**：`hardware/mode_sweep_loopback.py --menu 3|5`（自动遍历 41 种模式，输出 CSV/日志）

## 6. Keil 评估版 32KB 限制（重要）

当前镜像约 **37.2KB** 代码（37172 B，编译 0 Error 0 Warning），超过 MDK 未激活
（评估版）的 32KB 链接限制（`L6050U: code size exceeds the maximum allowed`）。
**需要激活 Keil MDK**（Project → License Management 填入有效序列号，或联网激活
MDK-Professional）后才能完成链接并生成 `Project.hex`。激活后重新构建：

```
UV4 -b MDK-ARM\GD32E503C_START.uvprojx -j0 -o build_log.txt
```

全部算法代码已通过 PC 单元测试（`porting_stm32/pc_tests`，GCC 编译，
**7 项测试全 PASS**：fft/ldpc/equalizer/end_to_end(41 模式)/turbo/cck/csk）。
