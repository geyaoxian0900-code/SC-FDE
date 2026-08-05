# c_export/（C 侧黄金向量输出目录）

本目录由 PC 测试程序生成，当前为空。

```bash
cd pc_tests
cmake -S . -B build && cmake --build build
./build/test_export_golden ../golden_vectors/c_export
```

生成后运行 `compare/compare_golden.py` 与 `matlab_export/` 逐阶段比对。

> 本机当前无 GCC/CMake，C 侧导出与比对尚未执行（见 AUDIT_REPORT §8 与 FIX_PLAN 修复 5）。
