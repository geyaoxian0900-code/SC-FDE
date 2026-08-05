# firmware_gd32/build_logs/

## 现状（审计时实测）

`MDK-ARM/output/` 目录内容仅有：

```
main.d      3039 B
main.o      2256 B
main.__i    1024 B
```

**没有任何 .axf / .hex / .map，也没有完整构建日志** —— 该工程从未完整构建成功过。

本目录当前没有构建日志文件，原因见上。请按以下步骤补充并回传：

## 如何产生完整构建日志

```bat
"C:\Keil_v5\UV4\UV4.exe" -b GD32E503C_START.uvprojx -o build_log.txt -j0
```

或在 Keil GUI：Project → Build Target（F7）→ Build Output 窗口 → 全选复制粘贴到
`build_log.txt`。日志中通常直接给出第一个阻止完整编译的错误（
预期与 FIX_PLAN 修复 1 的 M33/M4F 错配相关）。

## 应同时回传的构建产物（用于核对链接地址/资源）

- `MDK-ARM\output\*.map`
- `MDK-ARM\output\*.axf` 或 `.hex`
- `MDK-ARM\list\*.lst`

## 硬件信息缺口（见 hardware/board_notes.md）

晶振频率、原理图、功放/前端接口均未确认，构建与烧录前请补齐。
