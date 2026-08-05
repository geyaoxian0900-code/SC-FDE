# PC 端 C 单元测试工程（SC-FDE 算法层）

直接编译 GD32 固件中的平台无关算法源文件（单一事实源，零拷贝、零修改）：

```
scfde_fft.c / scfde_ldpc.c / scfde_equalizer.c / scfde_modem.c
```

## 构建与运行

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

需要 GCC + CMake（Windows 下可用 MinGW-w64 或 WSL）。算法层不依赖任何 GD32 库。

## 测试清单

| 测试 | 内容 | 断言 |
|---|---|---|
| `test_crc` | CRC-16/CCITT 标准向量 `"123456789"→0x29B1` + 黄金包自检 | 逐字节 |
| `test_fft` | δ(n) 频谱、单音峰值、128/32 点往返 | max err < 1e-4 |
| `test_ldpc` | 8 组干净信道译码、2 比特翻转纠错、迭代终止 | 逐位相等 |
| `test_equalizer` | 合成频选信道下 MMSE/ZF/IB-DFE 恢复、NLMS 防护 | 恢复误差 |
| `test_sync` | 零偏移同步起点=0；注入 30Hz+120 采样前导 → 起点=120、CFO≈30Hz | 起点/CFO |
| `test_end_to_end` | 6 种均衡器 + AUTO 全回环，10 字节载荷逐字节恢复 | payload/CRC |
| `test_export_golden` | 导出 23 阶段黄金向量到 `golden_vectors/c_export/` | 与真实 decode 交叉核对 |

## 静态包含技巧（static-include）

`test_crc.c` / `test_sync.c` / `test_export_golden.c` 用 `#define static` + `#include "scfde_*.c"`
把固件内部 `static` 函数（CRC、同步度量、LS 信道估计、LLR 等）暴露给测试，
使被测对象是**固件真实代码**而非测试副本。代价是每个这类测试是独立 TU，不链接 `scfde_core`。

## 黄金向量工作流

1. MATLAB：`golden_vectors/export_golden_vectors.m` → `golden_vectors/matlab_export/`
2. PC：`test_export_golden` → `golden_vectors/c_export/`
3. 比对：`python compare/compare_golden.py`

格式与容差见 `golden_vectors/FORMAT.md`。
