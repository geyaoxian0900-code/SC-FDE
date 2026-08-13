# BOOK TRANSCRIPTION MANIFEST — 原图转录清单

事实源：`book/*.png`（48 张四页拼图，覆盖书页 1–188 及书末）。
转写：`papers/book_transcripts/book_N.md`（主转写）+ `book_N_supplement.md`（补转写遗漏页）。

本清单由脚本从转写文件提取公式编号生成（`book_acceptance.parse_equation_ids` 同款编号）。
**状态语义**：

- `TRANSCRIBED`：公式编号在至少一个转录文件中出现（人工转录存在，仍须逐式核对实现）
- `TRANSCRIPTION-PENDING`：图片存在但转录未覆盖该公式

## 覆盖统计（2026-08-13 基线）

```text
trace 登记 ID：394
已转录：      228（主转写 + supplement）
待转录：      166
```

## 待转录区间（图片存在，页码可定位）

| 区间 | 图片 | 说明 |
|---|---|---|
| 2-15 ~ 2-25（部分） | book/6.png | RLS 推导补充 |
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

## 生成命令

```matlab
% 重新生成覆盖统计与索引（见仓库脚本）
run('porting_stm32/golden_vectors/../.. 无独立脚本；覆盖检查见
% papers/book_transcripts/README.md 说明的 MATLAB 片段）
```
