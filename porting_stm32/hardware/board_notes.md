# hardware/ —— 板级信息（引脚与未确认项）

以下引脚/参数全部**从 BSP 源码反推**（`bsp_passband_rx.c`、`bsp_passband_tx.c`、
`bsp_usart.c`、`bsp_half_duplex.c`），未经原理图/万用表核验。

## 已确认（源码证据）

| 功能 | 引脚 | 外设 | 参数 | 证据 |
|---|---|---|---|---|
| 接收 ADC | PA0 | ADC0 通道0 | 12bit、右对齐、48kHz（TIMER2 TRGO 触发）、采样时间 55.5 周期 | `bsp_passband_rx.c:15-30,203` |
| 接收 DMA | — | DMA0 通道0 | 16bit、外设→内存、FIFO 满中断 | `bsp_passband_rx.c:21,250-265` |
| 发射 DAC | PA4 | DAC0 通道 | 12bit 右对齐、96kHz（TIMER6 TRGO 触发）、输出缓冲开、中点 2048 | `bsp_passband_tx.c:14-23,157-166` |
| 发射 DMA | — | DMA1 通道2 | 内存→外设、512 采样暂存 | `bsp_passband_tx.c:18,26,253-267` |
| 串口 | PA9 TX / PA10 RX | USART0 | 9600 8-N-1、阻塞收发 | `bsp_usart.c:34-43` |
| 半双工控制 | PB0 / PB1 | GPIO 输出 | 高有效；`HALF_DUPLEX_CTRL_ENABLE` 关闭时仅逻辑切换 | `bsp_half_duplex.c:12-20,56-75` |
| 信号检测 | — | 32 采样峰峰值 ≥600 × 2 批，256 采样环形预卷 | | `bsp_passband_rx.c:27-30,376-385` |
| 捕获窗 | — | 4096 采样（modem 上限）/ BSP 缓冲 8192 | | `scfde_modem.h:30` vs `bsp_passband_rx.h:6` |

## 未确认（需原理图/实物）

- [ ] **晶振频率**：`system_gd32e50x.c` 按 HD 系列注释取 8MHz HXTAL，
      目标 `SystemCoreClock = 180MHz`（`__SYSTEM_CLOCK_180M_PLL_HXTAL`）。
      若板载晶振非 8MHz，串口/ADC/DAC 采样率全部按比例错误——烧录前必须确认。
- [ ] 芯片完整丝印（GD32E503CET6?）与 SRAM 容量（96KB 假设，Keil 现配 128KB）
- [ ] 开发板原理图（GD32E503C_START）
- [ ] 功放（TX 侧）与接收前端（增益/带通/偏置）接口：PA4 输出幅度 700/4096
      码、PA0 输入偏置是否 1.65V/2048 码量级
- [ ] 半双工方向控制是否实际接线（`HALF_DUPLEX_CTRL_ENABLE` 默认状态见
      `bsp_half_duplex.h`）

## 对 STM32 映射的影响

- PA0/PA4/PA9/PA10/PB0/PB1 在 STM32F407 上均有等价功能（ADC1_IN0、
  DAC1_OUT1、USART1、通用 GPIO），**映射可行**；但 ADC 输入偏置与 DAC
  驱动级需按实际前端调整（AUDIT_REPORT §6）。
- 若晶振不是 8MHz，STM32 侧 CubeMX 时钟树按实际晶振配置即可（与 GD32 无耦合）。
