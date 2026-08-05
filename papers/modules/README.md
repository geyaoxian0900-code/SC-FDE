# 可替换模块契约

MATLAB 包名为 `scfde`。调用前把本目录加入路径：

```matlab
addpath(fullfile(papersDir, "modules"));
```

## SC-TDE 流水线

| 模块 | 调用 | 必需输出 |
|---|---|---|
| `source` | `state = source(cfg)` | `training`、`data`、`tx` |
| `channel` | `state = channel(tx,cfg)` | `received`、`branches`、`impulse` |
| `receiverBank` | `state = receiverBank(channel,source,cfg)` | `names`、`outputs`、`learningMse` |
| `metric` | `state = metric(receiver,source,cfg)` | 默认使用 `ber` |
| `plot` | `path = plot(result)` | 可选，返回输出文件路径 |

`scfde.default_modules(overrides)` 对覆盖项进行递归合并并验证必需函数句柄。
模块状态使用结构体传递，因此自定义实现可以增加诊断字段而不会改变主流程。

默认第二章接收机库可通过 `cfg.methods` 选择：`dfe`、`nlms-dfe`、
`pll-dfe`、`mcdfe`、`ptr-dfe`、`subband-ptr-dfe`；设置为 `"all"` 时运行全部。

## 替换原则

1. 模块只通过参数和返回值通信，不读取基础工作区。
2. 随机数种子由实验入口统一设置。
3. 信道模块不负责生成信源；接收机模块不修改真实发送数据。
4. 指标模块只读取接收机输出，便于替换为 FER、EVM 或复杂度统计。
5. 新模块优先放入 `+scfde` 包；一次性实验模块可以放在 `examples`。
