# 烧录说明（Flash Guide）—— GD32E503CE SC-FDE 水声调制解调器

适用：`Projects/02_SC_FDE_UWA_MODEM`，基线版本（QPSK + rectangular + LS + MMSE-FDE + CRC，LDPC OFF）。

## 1. 固件信息（本批次）

| 项 | 值 |
|---|---|
| 目标芯片 | **GD32E508VET6**（Cortex-M33 @200MHz 器件，工作于 180MHz；烧录工具实测识别） |
| 固件文件 | `Projects\02_SC_FDE_UWA_MODEM\MDK-ARM\output\Project.hex` |
| **Project.hex SHA-256** | `0AA08A0767E58939F8B8B51DC37E27CE66393C2F49B2D89B68FBE7FD6A90294E`（E508 配置 + 横幅修正版，2026-08-04） |
| 编译日期 | 2026-08-04 17:04:37（本地） |
| Keil 构建结果 | MDK 5.42 / ARMCLANG 6：**0 Error, 0 Warning**（Rebuild All） |
| Flash / RAM | Code 14012 + RO 1340 ≈ **16.7 KB** / ZI 35528 + RW 20 + 栈 4KB ≈ **38.7 KB**（E508VET6：512KB Flash / 128KB SRAM） |
| 工程配置 | **Cortex-M33、FPU3(SFPU)、`GD32E508` 宏、core_cm33.h、25MHz HXTAL → 180MHz PLL**（与板载 25MHz 晶振匹配；原工程配置，勿改回 HD/8MHz） |
| 基线 | QPSK 4 ksym/s / 12 kHz 载波 / 96k 发射 / 48k 接收 / UW(32)×3 / 28 抽头 LS / MMSE-FDE / CRC-16 / 24 字节包（payload ≤ 18） |
| **LDPC** | **OFF**（`SCFDE_LDPC_ENABLED=0`；不要重新启用——码结构 d_min=2 缺陷，见 AUDIT_REPORT P14） |
| 源码版本 | 本机工作副本（对应 `scfde_porting_review.zip` 2026-08-04 版） |

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
