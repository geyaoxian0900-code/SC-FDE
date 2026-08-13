# BOOK TRANSCRIPTION MANIFEST — 原图转录清单

事实源：`book/*.png`（48 张四页拼图，覆盖书页 1–188 及书末）。
转写：`papers/book_transcripts/book_N.md`（主转写）+ `book_N_supplement.md`（补转写遗漏页）。

本清单由**唯一可执行生成器** `build_manifest.m` 计算（验收器 `run_book_acceptance.m` 与
本 README 共用同一解析路径；任何覆盖数字以 `build_manifest.m` 输出为准）：

```matlab
cd('papers/book_transcripts'); build_manifest();
```

**状态语义**：

- `TRANSCRIBED`：公式编号在至少一个转录文件中出现（人工转录存在，仍须逐式核对实现）
- `TRANSCRIPTION-PENDING`：图片存在但转录未覆盖该公式（含已转录区内的漏项，
  如 book/6.png 第 23 页仅转写了 (2-18)~(2-25)，(2-16)/(2-17) 仍未转录）

## 覆盖统计（2026-08-13 最终基线，由 build_manifest.m 生成）

```text
trace 登记 ID：394
covered：      228（57.9%）
pending：      166
duplicates：   67（同一公式出现在多份转录中，取首个文件）
out-of-trace： 6（转录中出现但 trace 未登记的编号）
```

验收器交叉统计：213 个 trace 状态为 TRANSCRIPTION-PENDING 的公式中，
82 个已被转录文本覆盖（pending-in-trace transcribed），131 个真正未转录。

## 待转录区间（图片存在，页码可定位）

| 区间 | 图片 | 说明 |
|---|---|---|
| 2-15 ~ 2-17（部分） | book/6.png | RLS 推导 (2-16)/(2-17) 缺失 |
| 2-38 ~ 2-46（部分） | book/7.png | PTR-DFE 推导 |
| 3-9 ~ 3-26（部分） | book/12.png~13.png | UW/帧/同步 |
| 3-47 ~ 3-63（部分） | book/15.png | HTF-DFE 推导 |
| 4-11 ~ 4-15、4-24 ~ 4-41 | book/19.png~20.png | BCJR/时域 LMMSE |
| 4-50 ~ 4-63（部分） | book/21.png~22.png | 频域权重 |
| 4-76 ~ 4-82（部分） | book/26.png | FDDA 更新式 |
| 5-2 ~ 5-22（部分） | book/29.png | CCK 码本 |
| 5-33 ~ 5-39、5-48 ~ 5-56 | book/30.png~31.png | Rake/DFE/TR |
| 5-67 ~ 5-74（部分） | book/32.png~33.png | RSSE/EXIT |
| 5-90 ~ 5-92（部分） | book/35.png | CCK-SM |
| 6-13 ~ 6-15（部分）、6-30 ~ 6-37 | book/40.png~42.png | CSK/ESE |
| 6-46 ~ 6-50、6-60 ~ 6-63 | book/43.png | IDMA 后验 |

## 完整性检查

转录文件禁止出现工具日志内容（`injected env`、`dotenvx`、`secrets for agents`）；
build_manifest.m 解析时自动跳过，独立检查：

```powershell
Get-ChildItem papers/book_transcripts -Filter 'book_*.md' | ForEach-Object {
  if (Get-Content $_.FullName -Raw -Encoding UTF8 -match 'injected env|dotenvx|secrets for agents') { $_.Name }
}
```
