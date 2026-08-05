# matlab/ —— 黄金模型及其依赖（ZIP 快照）

| 文件 | 来源 | 用途 |
|---|---|---|
| `run_text_scfde_demo.m` | `papers\engineering_simulation\` | 端到端黄金模型（836 行），`export_golden_vectors.m` 的唯一入口 |
| `verify_scfde_project.m` | 同目录 | 项目结构检查（文件存在性 + Keil 目标芯片），非数值比对 |
| `scfde_bellhop_channel.m` | 同目录 | `run_text_scfde_demo.m` 在 `channelModel="bellhop"` 时调用（黄金场景用 `"analytic"`，不依赖它） |
| `export_golden_vectors.m` | `porting_stm32\golden_vectors\` | 黄金向量导出脚本（已在 MATLAB 2025 实机运行通过） |

## 依赖关系

- `export_golden_vectors.m` 只调用 `run_text_scfde_demo.m`（运行时 addpath 到
  `papers\engineering_simulation`）。黄金场景为 `pulseShape="rectangular"`、
  单径、无噪声，因此**不依赖** Bellhop / 章节仿真模块。
- 若审阅者要复跑章节级仿真（chapter2-6），需要 `papers\modules\+scfde\`
  与 `papers\chapter*_simulation\` 全量源码，未随本 ZIP 附带（体量较大，
  需要时可再打包）。

## 复跑命令

```matlab
cd porting_stm32/golden_vectors
export_golden_vectors();
```

预期输出（已实测）：
```
Frame 1: PASS, seq=0, payload=10 bytes, attempts=1, sync=1.000, CFO=0.00 Hz
RX text: SC-FDE1234
Golden vectors written to ...matlab_export
```
