# SC-FDE 移植修复方案（可执行清单）

配套文件：`AUDIT_REPORT.md`（审计证据）、`golden_vectors/FORMAT.md`（向量格式）、`pc_tests/`（测试工程）。

按优先级分 6 步。每一步都有"验证方法"；未经验证不得进入下一步。

---

## 修复 1（阻塞项）：Keil 工程 M33→M4F 配置错配

**证据**：`MDK-ARM/GD32E503C_START.uvprojx` 的 `<Cpu>` 行为
`CPUTYPE("Cortex-M33") FPU3(SFPU)`；`<Define>GD32E50X,GD32E508,...`；
`GD32E50x_Firmware_Library/CMSIS/GD/GD32E50x/Include/gd32e50x.h:44` 无条件
`#include "core_cm33.h"`；而板载芯片是 Cortex-M4F 的 GD32E503CE，
启动文件引用的是 M4F 的 `startup_gd32e50x_hd.s`。EWARM 工程却配了 FPU2（M4F）——
两个 IDE 配置互相矛盾。另：`MDK-ARM/output/` 只有 `main.o`，从未完整构建。

**操作（Keil MDK 中）**：
1. 打开工程 → Options for Target → Device 保持 `GD32E503CE`。
2. Target 页：确认 `Cortex-M4`、`Use FPU: Single precision`（勾选）、
   `IRAM1: 0x20000000 size 0x18000`（96KB，若芯片确认 96KB SRAM）、
   `IROM1: 0x08000000 size 0x080000`。
   （若 `<Cpu>` 行仍含 M33，直接编辑 uvprojx 或重建工程设置）
3. C/C++ 页 Define 改为：`GD32E50X,GD32E50X_HD,USE_STDPERIPH_DRIVER`
   （**删除 GD32E508**；GD32E503C 属于 HD 系列。`system_gd32e50x.c` 已含
   `#if (defined(GD32EPRT) || defined(GD32E50X_HD))` 分支，改宏后自动走 M4F
   时钟/复位配置）
4. `gd32e50x.h` 第 44 行：`#include "core_cm33.h"` → `#include "core_cm4.h"`
   （CMSIS 目录里已有 core_cm4.h，无需下载）
5. 确认链接的是 `startup_gd32e50x_hd.s`（保持现状，无需改）。
6. **完整构建并保留日志**：命令行 `C:\Keil_v5\UV4\UV4.exe -b GD32E503C_START.uvprojx -o build_log.txt`，
   或 Keil GUI Build Output → 全选复制。**构建日志是本步唯一的验收物**。

**验证**：构建 0 error 0 warning（至少 0 error）；产出 `.axf/.hex/.map`；
`.map` 中 RAM 用量 < 96KB、ROM < 512KB；烧录后串口出现角色菜单，
`SystemCoreClock`（debugger watch）= 180000000。

**若第 4 步报错或出现外设寄存器缺失**：把完整 build_log.txt 回传，逐条处理。

---

## 修复 2（一致性）：RRC 决策 + 尾 UW 增益归一化

**证据**：`scfde_modem.c:191-196`（矩形发射）、`scfde_modem.c:466-479`（I&D 接收）；
MATLAB 默认 RRC（`run_text_scfde_demo.m:154-156`）。C 无尾 UW 增益归一化，
MATLAB 有（`run_text_scfde_demo.m:499-503`）。

**短期决策（推荐先做 a）**：
- (a) 黄金向量与两板对测统一走"矩形"配置：MATLAB 侧
  `options.pulseShape="rectangular"`（`export_golden_vectors.m` 已强制）；
- (b) 中期在 C 侧补 RRC：`scfde_modem.c` 发射处加 24 倍过采样 RRC FIR
  （48kHz 符号侧可用 CMSIS-DSP `arm_fir_f32`），接收加匹配滤波，参数
  rolloff 0.35、span 8 与 MATLAB 对齐。改动集中在 `scfde_modem.c` 两处，
  需重新跑黄金向量。

**尾 UW 增益归一化补丁（C 侧，`scfde_equalizer.c` 或 `scfde_modem.c` 均衡后）**：
```c
/* 在 frequency_equalize + ifft 之后（scfde_equalizer.c:173 之后等效位置）：
   gain = sum(equalized_tail .* conj(uw)) / (sum(|uw|^2)+eps);
   equalized /= gain;   实现与 run_text_scfde_demo.m:499-503 相同 */
```
**验证**：`pc_tests/test_export_golden` 重新导出 → `compare_golden.py` 阶段 18/19
容差内通过（尾增益修正前，星座整体缩放超差）。

---

## 修复 3（一致性）：IB-DFE / NLMS-TDE 标定基线

**证据**：`scfde_equalizer.c:91-146`（IB-DFE β=0.65/2 迭代）、`scfde_equalizer.c:188-266`
（NLMS 16 抽头/6 epoch/μ=0.35）；MATLAB 黄金模型无对应（`AUDIT_REPORT.md` §3-17/18）。

- 不需要改代码；用 `pc_tests/test_end_to_end`（全部 6 种模式回环）+ 后续两板
  对测建立"每种均衡器在典型信道下的 BER"基线，写进移植报告；
- 若未来要数值级比对，需先在 MATLAB 补一份与 C 相同的 IB-DFE/NLMS 参考实现。

---

## 修复 4（偶发错误风险）：定时与常量

| # | 问题 | 修复 | 验证 |
|---|---|---|---|
| 4a | `bsp_usart.c:46-59` delay_ms 忙等未校准（实测约 0.1ms/ms） | 改 SysTick 计数延时：`systick.c` 已实现 `delay_1ms`，在 `main.c` 调用 `systick_config()`，`delay_ms` 改为 `delay_1ms` | 串口超时提示 5s 与实测一致；半双工保护时间用示波器测 |
| 4b | RX 缓冲 8192 与 modem 上限 4096 不一致（`bsp_passband_rx.h:6` vs `scfde_modem.h:30`） | 统一为 4096（省 8KB SRAM） | .map 文件 RAM 减少 |
| 4c | `app_read_line` 无超时（`scfde_app.c:51-68`） | 加 30s 超时后回菜单 | 操作验证 |
| 4d | 预卷→DMA 切换采样间隙（`bsp_passband_rx.c:311-402`） | 首版接受（单帧应用，误帧可重发）；流式版改 DMA 双缓冲 | 两板连续发 100 帧统计同步成功率 |

---

## 修复 5：黄金向量全流程执行（验证基线）

前置：本机有 MATLAB 2025（已生成 `matlab_export/`，23 阶段全部 PASS）。

```bash
# 1) MATLAB（已完成，可重跑）
matlab -batch "cd golden_vectors; export_golden_vectors();"

# 2) PC 测试（需安装 MinGW-w64 + CMake；本机暂缺）
cmake -S pc_tests -B pc_tests/build
cmake --build pc_tests/build
ctest --test-dir pc_tests/build --output-on-failure
pc_tests/build/test_export_golden golden_vectors/c_export

# 3) 对比
python compare/compare_golden.py golden_vectors/matlab_export golden_vectors/c_export
```

**验收标准**：ctest 全 PASS；对比脚本 23 阶段全 PASS（容差表见 FORMAT.md）。
若阶段 07/08 超差 ≤4.0 DAC 码为载波表量化（已知，记录即可）；阶段 18/19 超差
按修复 2 处理。

---

## 修复 6：STM32 移植（目标 STM32F407VGT6，按 AUDIT_REPORT §6）

前置：修复 1-5 全部通过。

1. 建 STM32CubeMX 工程：HSE 8M → 168MHz；TIM2(ARR=1749, TRGO) 触发 ADC1、
   DMA2 Stream0 Ch0；TIM6(ARR=874, TRGO) 触发 DAC1、DMA1 Stream5 Ch7；
   USART1 9600 8-N-1；SysTick 1ms。
2. 复制 `firmware_gd32/algorithm/` 四个文件原样进工程（零修改），
   `scfde_app.c` 改为调 STM32 BSP 同构 API（函数签名不变）。
3. 重写 6 个 BSP 文件（HAL 版），引脚：PA0(ADC1_IN0)、PA4(DAC1_OUT1)、
   PA9/PA10(USART1)、PB0/PB1(半双工控制)。
4. 复用黄金向量：STM32 版 PC 离线测试（同一套 pc_tests 编译 arm 版本）
   → 板上数字回环（菜单 3）→ DAC/ADC 直连对测（菜单 5 全均衡器）。
5. 修 4a/4d 后进入水中测试。

---

## 验收总门（全部满足才可称"可移植"）

- [ ] Keil 工程以 Cortex-M4/GD32E50X_HD 完整构建 0 error，产出 .map/.axf
- [ ] `pc_tests` 全测试 PASS（本机补装 GCC/CMake 后执行）
- [ ] `compare_golden.py` 23 阶段 PASS（允许记录在案的载波表量化差）
- [ ] 两板数字回环 100 帧同步成功率 100%、CRC 全过
- [ ] STM32 版回环/对测结果与 GD32 版一致（容差内）
