#!/usr/bin/env python3
"""single_board_loopback.py - Automated single-board digital loopback test.

Drives the firmware's built-in digital loopback (role 1 "local diagnostic",
command 3) for N frames and records sync metric, frame start, CFO,
equalizer, CRC, payload and text for every frame.

The firmware loopback always uses the fixed payload b"SC-FDE" (6 bytes,
seq 0x55). Variable payloads and sequence sweeps are covered by the
two-board test (twoboard/twoboard_test.py, groups B/C).

Usage:
    python single_board_loopback.py --port COM3 [--frames 300] [--baud 9600]

Outputs:
    outdir/single_loopback_<timestamp>.csv
    outdir/single_loopback_<timestamp>.log
Exit code 0 = all frames passed, 1 = any failure.
"""

import argparse
import csv
import datetime
import re
import sys
import time
from pathlib import Path

import serial  # pyserial

BANNER = b"GD32E503CE SC-FDE Underwater Modem"
ROLE_PROMPT = b"role> "
CMD_PROMPT = b"cmd> "

RE_SYNC = re.compile(rb"sync=(\d+)\.(\d{3}) start=(\d+) CFO=([-\d]+) Hz EQ=(\S+)")
RE_OK = re.compile(rb"RX OK: seq=(\d+) len=(\d+) hex=(.*?)  text=(.*?)\r\n")
RE_FAIL = re.compile(rb"RX FAIL: (.*?)\r\n")
RE_ADC = re.compile(rb"ADC min=(\d+) max=(\d+) mean=(\d+) clipped=(\d+) samples=(\d+)")

# Firmware loopback contract (scfde_app.c app_digital_loopback):
# payload b"SC-FDE", sequence 0x55, len 6, equalizer always MMSE-FDE.
EXPECTED_SEQ = 0x55
EXPECTED_LEN = 6
EXPECTED_HEX = "53 43 2D 46 44 45"
EXPECTED_TEXT = "SC-FDE"
EXPECTED_EQ = "MMSE-FDE"


class Board:
    def __init__(self, port, baud, timeout, logf):
        self.ser = serial.Serial(port, baud, timeout=0.05)
        self.buf = b""
        self.logf = logf

    def log(self, text):
        stamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        line = f"[{stamp}] {text}"
        self.logf.write(line + "\n")
        self.logf.flush()

    def pump(self):
        self.buf += self.ser.read(4096)

    def send(self, data):
        self.ser.write(data)
        self.ser.flush()
        self.log(f"TX>> {data!r}")

    def expect(self, patterns, timeout_s, fail_text="timeout"):
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            self.pump()
            for pat in patterns:
                idx = self.buf.find(pat)
                if idx >= 0:
                    matched = self.buf[: idx + len(pat)]
                    self.buf = self.buf[idx + len(pat):]
                    self.log("RX<< " + matched.decode("utf-8", "replace").rstrip())
                    return matched
            if BANNER in self.buf:
                raise RuntimeError("board reset detected (banner re-appeared)")
            time.sleep(0.005)
        raise TimeoutError(f"{fail_text} (patterns={[p[:24] for p in patterns]})")

    def expect_regex(self, regex, timeout_s, fail_text="timeout"):
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            self.pump()
            m = regex.search(self.buf)
            if m:
                matched = self.buf[: m.end()]
                self.buf = self.buf[m.end():]
                self.log("RX<< " + matched.decode("utf-8", "replace").rstrip())
                return m
            if BANNER in self.buf:
                raise RuntimeError("board reset detected (banner re-appeared)")
            time.sleep(0.005)
        raise TimeoutError(f"{fail_text} (regex={regex.pattern[:40]})")


def main():
    ap = argparse.ArgumentParser(description="single-board digital loopback")
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--frames", type=int, default=300)
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--command", type=int, choices=[3, 5], default=3,
                    help="firmware menu command: 3=digital loopback, "
                         "5=DAC-ADC analog self-loopback")
    ap.add_argument("--outdir", default="results")
    args = ap.parse_args()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = Path(args.outdir) / f"single_loopback_{stamp}.csv"
    log_path = Path(args.outdir) / f"single_loopback_{stamp}.log"

    with open(log_path, "w", encoding="utf-8") as logf, \
         open(csv_path, "w", newline="", encoding="utf-8") as csvf:

        writer = csv.writer(csvf)
        writer.writerow(["frame_index", "sync_metric", "frame_start", "cfo_hz",
                         "equalizer", "crc_ok", "payload_hex", "text",
                         "adc_min", "adc_max", "adc_mean", "adc_clipped",
                         "timeout", "fail_reason"])
        exp = EXPECTED[args.command]

        board = Board(args.port, args.baud, args.timeout, logf)
        board.log(f"=== single-board loopback cmd={args.command}, "
                  f"{args.frames} frames ===")

        try:
            # banner is optional: the board may already be past it
            board.expect([BANNER], 5, "no banner")
        except TimeoutError:
            pass
        # State-agnostic wake-up: '0' returns to role selection from any
        # role menu, and is ignored at the role prompt (harmless).
        board.send(b"0\r")
        try:
            board.expect([ROLE_PROMPT], 10, "no role prompt")
            board.send(b"1\r")
            board.expect([b"local diagnostic"], 10, "role select failed")
            board.expect([CMD_PROMPT], 10, "no cmd prompt")
        except (TimeoutError, RuntimeError) as e:
            print(f"SETUP FAILED: {e}")
            return 1

        passed = 0
        for i in range(args.frames):
            timeout = 0
            reason = ""
            crc_ok = 0
            seq = plen = 0
            phex = text = ""
            sync = start = cfo = 0.0
            eq = ""
            adc_min = adc_max = adc_mean = adc_clipped = "NA"
            try:
                board.send(str(args.command).encode() + b"\r")
                if args.command == 5:
                    try:
                        a = board.expect_regex(RE_ADC, 5, "ADC line")
                        adc_min, adc_max, adc_mean, adc_clipped = (
                            int(a.group(1)), int(a.group(2)),
                            int(a.group(3)), int(a.group(4)))
                    except TimeoutError:
                        adc_min = adc_max = adc_mean = adc_clipped = "NA"
                m = board.expect_regex(RE_SYNC, args.timeout, "sync line")
                sync = float(m.group(1)) + float(m.group(2)) / 1000.0
                start = int(m.group(3))
                cfo = int(m.group(4))
                eq = m.group(5).decode()
                try:
                    ok = board.expect_regex(RE_OK, args.timeout, "RX OK line")
                    seq = int(ok.group(1))
                    plen = int(ok.group(2))
                    phex = ok.group(3).decode()
                    text = ok.group(4).decode()
                    crc_ok = 1
                except TimeoutError:
                    # sync line present but RX FAIL (sync/header/CRC failed)
                    f = board.expect_regex(RE_FAIL, args.timeout, "RX FAIL line")
                    reason = f.group(1).decode()
            except TimeoutError:
                timeout = 1
                reason = "serial_timeout"
            except RuntimeError as e:
                print(f"BOARD RESET at frame {i}: {e}")
                return 2

            passed_frame = (
                crc_ok == 1
                and seq == exp["seq"]
                and plen == exp["length"]
                and phex.strip() == exp["hexstr"]
                and text == exp["text"]
                and eq == EXPECTED_EQ
            )
            row = [i, f"{sync:.3f}", start, cfo, eq,
                   1 if passed_frame else 0, phex, text,
                   adc_min, adc_max, adc_mean, adc_clipped,
                   timeout, reason if not passed_frame else ""]
            writer.writerow(row)
            csvf.flush()
            if passed_frame:
                passed += 1
                board.expect([CMD_PROMPT], 5, "cmd prompt after frame")
            else:
                print(f"frame {i}: FAIL ({reason or 'content mismatch'})")
                board.expect([CMD_PROMPT], 5, "cmd prompt after fail")

        total = args.frames
        fer = (total - passed) / total if total else 0.0
        print(f"\nResult: {passed}/{total} frames PASS (FER {fer:.4f})")
        print(f"CSV: {csv_path}")
        print(f"LOG: {log_path}")

        summary = {
            "script": "single_board_loopback",
            "timestamp": stamp,
            "port": args.port,
            "baud": args.baud,
            "command": args.command,
            "frames": total,
            "passed": passed,
            "fer": fer,
            "crc_pass": passed,
            "hardfault_resets": 0,
            "csv": str(csv_path),
            "log": str(log_path),
        }
        summary_path = Path(args.outdir) / f"single_loopback_{stamp}.summary.json"
        import json
        with open(summary_path, "w", encoding="utf-8") as sf:
            json.dump(summary, sf, indent=2)
        print(f"SUMMARY: {summary_path}")
        return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
