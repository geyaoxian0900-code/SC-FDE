# 水声单载波统一仿真工程

本目录统一管理原论文复现脚本和 `02_SC_FDE_UWA_MODEM` 工程配套仿真。
所有数值实验从 `run_all_simulations.m` 进入，实验清单由
`list_simulations.m` 查询。

## 目录

```text
papers/
├── run_all_simulations.m       统一批处理入口
├── list_simulations.m          实验 ID 清单
├── modules/+scfde/             可替换模块和公共流水线
├── engineering_simulation/     从 MCU 工程整理来的仿真
├── chapter2_simulation/        论文第2章 UW/SC-FDE
├── chapter3_simulation/        论文第3章同步/多普勒
├── chapter4_simulation/        论文第4章判决反馈均衡
├── common/                     论文仿真共用 LDPC
├── examples/                   模块替换示例
└── tests/                      轻量回归测试
```

## 运行

```matlab
cd('D:\Keli5\project\GD32E503C_START_Demo_Suites\papers')
list_simulations

% 默认快速运行全部数值实验
summary = run_all_simulations;

% 仅运行 SC-TDE 和论文第4章
options = struct("profile", "quick", ...
    "experiments", ["engineering.sc_tde", "paper.chapter4"]);
summary = run_all_simulations(options);

% 完整参数
summary = run_all_simulations(struct("profile", "full"));
```

统一入口默认捕获单个实验的错误并继续运行。开发和回归时可设置
`stopOnError=true`，让第一个错误立即中止。

## 模块替换

SC-TDE 使用以下流水线：

```text
source(cfg)
  -> channel(tx, cfg)
  -> receiverBank(channelState, sourceState, cfg)
  -> metric(receiverState, sourceState, cfg)
```

模块通过 `options.modules` 中的函数句柄注入。默认模块在
`modules/+scfde/default_modules.m` 注册。替换模块只需维持契约，不需要修改
`simulate_chapter2_single_carrier_tde.m` 或统一入口。

```matlab
modules.channel = @custom_flat_channel;
options = struct("profile", "quick", ...
    "experiments", "engineering.sc_tde", "modules", modules);
summary = run_all_simulations(options);
```

完整示例见 `examples/run_module_swap_example.m`。模块结构允许继续增加新的
信源、实测信道、神经网络均衡器或指标计算器；不同实验可以通过
`experimentOptions.<实验ID转换后的字段名>` 覆盖参数，例如
`experimentOptions.engineering_sc_tde.snrDb = 8`。

### 均衡器即插即用

接收机模块 `receiver_bank_pluggable` 将每个均衡器视为独立模块，统一契约：

```text
receiver = equalizer(channel, source, cfg)
```

返回值只需包含 `outputs{1}`（与 `source.tx` 对齐的符号估计）、`ids`、
`names`；`traces`/`learningMse`/`estimates` 可选。内置 37 个均衡器注册在
`modules/+scfde/equalizer_registry.m`，实现位于 `+scfde/+equalizers/`。

运行契约（`FORMULA_TRACEABILITY.md`「37 均衡器运行契约审计」）：

- 每个 ID 由其声明场景驱动：QPSK 17 / Turbo 10 / CCK 7 / CSK 3。
- Turbo 场景输出为 512 信息位判决（BCJR 仅处理 1024 编码数据，训练符号不进译码器；帧契约 `ch4_turbo_frame_contract`）。
- `outputs{1}` 的度量域随场景而定（qpsk 符号估计 / turbo 信息判决 / cck-csk 码片估计 + trace 索引），并非普遍与 `source.tx` 对齐。
- `errorBits`/`totalBits`/Clopper-Pearson 95% 区间为逐方法精确向量（`ber = errorBits ./ totalBits`，不用 `round` 重建）。
- `run_all_equalizers` 独立运行全部 37 个 ID 并返回 37 行审计表（含 gitCommit 元数据）。
- 每个方法在 `trace` 中记录 `formulaStatus/formulaMode/bookExperimentEquivalent/
  effectiveParameters`；统一入口另汇总 `results.formulaStatus`。
- 曲线评级（批次12）：`curve_reference/run_37_curve_grading.m` 对 37 法按场景跑
  多点 SNR × 多种子并记录整数 errorBits/totalBits 与 Clopper-Pearson 95% 区间；
  仅存在**原文数字化曲线**的方法（当前仅 fdda-teq，图 4-31）获得
  `curve_benchmark` 等级，其余明确写“不适用（无原文数字化曲线）”——场景银行曲线
  是工程证据，不是原文曲线复现，公式测试不能代替曲线复现。

### 数字化参考曲线约定（`curve_reference/`）

任何进入 `curve_benchmark` 评级的数字化数据文件必须随 `.mat` 结构记录：
`source`（book 图片文件名与图号）、`figure`、`digitizer`（数字化方式/工具）、
`date`、`modulation`、`channel`、`frame length`、`iteration count`、
`known mismatch`（已知与原文条件的差异）。示例：
`curve_reference/make_ch4_fig431_reference.m`（图 4-31，book/27.png）。
不满足该约定的数字化文件不得用于等级计算。
- 公式状态、剩余扫描复核项与未公开参数清单见 `FORMULA_TRACEABILITY.md` 与仓库根
  `SOURCE_REVIEW_REQUEST.md`。

通过 `cfg.equalizers` 选择要运行的均衡器：

```matlab
% 全部内置（默认）
options.equalizers = "all";

% 内置子集（按 ID）
options.equalizers = ["dfe", "nlms-dfe", "ptr-dfe"];

% 单个自定义均衡器（函数句柄，即插即用）
options.equalizers = @custom_matched_filter;

% 混合：自定义模块 + 内置 ID
options.equalizers = { @custom_matched_filter, "rls-dfe" };
```

完整示例见 `examples/run_custom_equalizer_example.m`。添加新均衡器只需在
`+scfde/+equalizers/` 放一个契约函数并（可选）在注册表中登记 ID。

## 兼容性

原 MCU 工程下的 MATLAB 文件暂时保留，避免影响 GUI、固件验证脚本和已有调用。
新的开发和批处理应使用本目录。论文第2至第4章入口已由脚本改为带可选参数的
函数，但 `run_chapter2_simulation` 这类无参数调用仍然兼容。

当前仿真使用合成信道和可重复构造的 LDPC。论文未公开的校验矩阵以及缺失的
水池原始录音不能由这些脚本恢复，输出用于趋势验证而非逐点复制原论文曲线。
