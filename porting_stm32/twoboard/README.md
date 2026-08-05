# 两板自动对测（Two-Board Automated Test）

控制两块板：**A=发送节点（role 2），B=接收节点（role 3）**，自动完成批量收发、
解析、判错与统计。Python + pyserial。

## 环境

```bash
pip install pyserial
```

## 快速开始

```bash
# 默认跑 A/B/C/E 四组（C 组 = 0/1/4/10/18 字节 × N 帧）
python twoboard_test.py --tx-port COM5 --rx-port COM6 --frames 100

# 只跑固定包 1000 帧（序号递增，用于发现漏帧/重复/乱序）
python twoboard_test.py --tx-port COM5 --rx-port COM6 --test B --frames 1000

# 幅度扫描：每组幅度变体固件跑一次，并标注
python twoboard_test.py --tx-port COM5 --rx-port COM6 --test D --amplitude-label amp700
```

## 测试组

| 组 | 内容 | 发现的问题 |
|---|---|---|
| A | 固定载荷 N 帧 | 重复稳定性 |
| B | 序号自动递增 N 帧 | 漏帧、重复帧、乱序（rx_seq ≠ 期望） |
| C | 0/1/4/10/18 字节各 N 帧 | 边界载荷、空载荷 |
| D | 幅度扫描（需不同 `SCFDE_TX_AMPLITUDE` 固件变体，每次运行标注） | 削顶、FER vs 幅度 |
| E | 独立时钟 CFO 统计 N 帧 | CFO 均值/标准差/最大绝对值是否接近 ±10 Hz 边界 |

## 输出

- `results/twoboard_<时间戳>.csv`：每帧一行，字段见 CSV_FIELDS（含
  timestamp/frame_index/group/tx_sequence/rx_sequence/payload_length/
  sync_metric/frame_start/cfo_hz/crc_ok/payload_match/timeout/
  adc_min/adc_max/equalizer/fail_reason）
- `results/twoboard_<时间戳>.log`：串口原始收发全量日志

> `adc_min/adc_max` 固件不输出（记 NA）——需示波器测量（见
> hardware/WIRE_LOOPBACK_GUIDE.md）。

## 失败分类（fail_reason）

| 值 | 含义 |
|---|---|
| `serial_timeout` | 串口未在时限内响应 |
| `no_frame_detected` | 同步度量 < 0.18（未检测到帧） |
| `sync_failed` | 同步行出现但固件报 RX FAIL（synchronization） |
| `crc_or_header_failed` | 同步成功但包头/CRC 失败 |
| `seq_mismatch` | rx_sequence ≠ 期望序号（漏帧/重复/乱序） |
| `length_or_payload_mismatch` | 载荷长度或内容不一致 |
| `cfo_out_of_range` | \|CFO\| > 10 Hz（超出同步+CFO 捕获范围） |
| 进程异常退出 + "board reset detected" | HardFault/复位（横幅重现） |

## 第一轮验收标准

| 指标 | 标准 |
|---|---|
| 固定有线链路 FER | 0 |
| 1000 帧 CRC 通过率 | 100% |
| Payload 匹配率 | 100% |
| CFO | 约 ±10 Hz 内（E 组统计） |
| ADC 削顶 | 0（示波器确认） |
| HardFault/复位 | 0 |
| 丢帧/重复帧 | 0 |
| 均衡器 | 始终 MMSE-FDE |

## 测试时序（脚本内）

```
每帧：B 发 '2' → 等 "RX armed"
      A 发 '1' → 等 "Text (max 18 bytes): " → 发 payload+CR → 等 "TX OK"
      等 B 的 sync= 行 → RX OK / RX FAIL / RX timeout
```

- 串口 9600 8-N-1，行结束 CRLF（输入用 CR）
- B 的 RX 等待超时 5s（固件），脚本外层再兜底 8s
- 建议先 `--frames 10` 冒烟，再跑全量

## 硬件前提

- 两板各自烧录 `output/Project.hex`（FLASH_GUIDE.md）
- A 的 PA4(DAC) → B 的 PA0(ADC) 经衰减电阻连接、共地（WIRE_LOOPBACK_GUIDE.md）
- 两板 USART0 分别接 USB-TTL，识别两个 COM 口
