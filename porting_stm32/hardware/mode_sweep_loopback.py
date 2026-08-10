#!/usr/bin/env python3
"""mode_sweep_loopback.py - sweep all 26 firmware equalizer modes through
menu 4 (next equalizer) + menu 3 (digital loopback).

Requires the B2-B5 firmware (26 modes: 20 base + 6 turbo). Turbo modes
automatically use the conv-coded frame inside the digital loopback.

Usage:
    python mode_sweep_loopback.py --port COM6 [--repeats 1]

Outputs CSV + log; exit 0 = every mode passed every repeat.
"""

import argparse
import csv
import datetime
import re
import sys
import time
from pathlib import Path

import serial

BANNER = b"GD32E508VE SC-FDE Underwater Modem"
ROLE_PROMPT = b"role> "
CMD_PROMPT = b"cmd> "

RE_SYNC = re.compile(rb"sync=(\d+)\.(\d{3}) start=(\d+) CFO=([-\d]+) Hz EQ=(\S+)")
RE_OK = re.compile(rb"RX OK: seq=(\d+) len=(\d+) hex=(.*?)  text=(.*?)\r\n")
RE_FAIL = re.compile(rb"RX FAIL: (.*?)\r\n")
RE_EQ = re.compile(rb"Equalizer selected: (\S+)\r\n")

EXPECTED = {
    "AUTO": dict(seq=0x55, length=6, text="SC-FDE"),
    "MMSE-FDE": dict(seq=0x55, length=6, text="SC-FDE"),
    "ZF-FDE": dict(seq=0x55, length=6, text="SC-FDE"),
    "MF-FDE": dict(seq=0x55, length=6, text="SC-FDE"),
    "IB-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "NLMS-TDE": dict(seq=0x55, length=6, text="SC-FDE"),
    "HTFDE": dict(seq=0x55, length=6, text="SC-FDE"),
    "SD-IBDFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "HD-IBDFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "ICE-SD-IBDFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "ICE-HD-IBDFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "LMS-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "NLMS-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "RLS-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "DPLL-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "FBLMS": dict(seq=0x55, length=6, text="SC-FDE"),
    "FD-TURBO": dict(seq=0x55, length=6, text="SC-FDE"),
    "FD-DFE": dict(seq=0x55, length=6, text="SC-FDE"),
    "TF-TURBO": dict(seq=0x55, length=6, text="SC-FDE"),
    "BITF-TURBO": dict(seq=0x55, length=6, text="SC-FDE"),
    "BLMS-TF-TURBO": dict(seq=0x55, length=6, text="SC-FDE"),
    "TD-TURBO": dict(seq=0x55, length=6, text="SC-FDE"),
    "FDDA-TEQ": dict(seq=0x55, length=6, text="SC-FDE"),
    "TDDA-TEQ": dict(seq=0x55, length=6, text="SC-FDE"),
    "FDDA-DFE-TEQ": dict(seq=0x55, length=6, text="SC-FDE"),
}
EXPECTED_EQ = "MMSE-FDE"


class Board:
    def __init__(self, port, baud, logf):
        self.ser = serial.Serial(port, baud, timeout=0.05)
        self.buf = b""
        self.logf = logf

    def log(self, text):
        stamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.logf.write(f"[{stamp}] {text}\n")
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
                raise RuntimeError("board reset detected")
            time.sleep(0.005)
        raise TimeoutError(f"{fail_text}")

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
                raise RuntimeError("board reset detected")
            time.sleep(0.005)
        raise TimeoutError(f"{fail_text}")


def main():
    ap = argparse.ArgumentParser(description="26-mode loopback sweep")
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--repeats", type=int, default=1)
    ap.add_argument("--timeout", type=float, default=8.0)
    ap.add_argument("--outdir", default="results")
    args = ap.parse_args()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = Path(args.outdir) / f"mode_sweep_{stamp}.csv"
    log_path = Path(args.outdir) / f"mode_sweep_{stamp}.log"

    with open(log_path, "w", encoding="utf-8") as logf, \
         open(csv_path, "w", newline="", encoding="utf-8") as csvf:
        writer = csv.writer(csvf)
        writer.writerow(["mode", "repeat", "sync", "start", "cfo", "eq",
                         "crc_ok", "payload_hex", "text", "fail_reason"])
        board = Board(args.port, args.baud, logf)

        try:
            board.expect([BANNER], 5, "no banner")
        except TimeoutError:
            pass
        board.send(b"0\r")
        try:
            board.expect([ROLE_PROMPT], 10, "no role prompt")
            board.send(b"1\r")
            board.expect([b"local diagnostic"], 10, "role select failed")
            board.expect([CMD_PROMPT], 10, "no cmd prompt")
        except (TimeoutError, RuntimeError) as e:
            print(f"SETUP FAILED: {e}")
            return 1

        total = len(EXPECTED) * args.repeats
        passed = 0
        for repeat in range(args.repeats):
            for mode in EXPECTED:
                exp = EXPECTED[mode]
                try:
                    board.send(b"4\r")
                    m = board.expect_regex(RE_EQ, 5, "equalizer line")
                    eq_name = m.group(1).decode()
                    board.send(b"3\r")
                    m = board.expect_regex(RE_SYNC, args.timeout, "sync line")
                    sync = float(m.group(1)) + float(m.group(2)) / 1000.0
                    start = int(m.group(3))
                    cfo = int(m.group(4))
                    eq = m.group(5).decode()
                    ok = board.expect_regex(RE_OK, args.timeout, "RX OK")
                    seq = int(ok.group(1))
                    plen = int(ok.group(2))
                    phex = ok.group(3).decode()
                    text = ok.group(4).decode()
                    crc_ok = 1
                    reason = ""
                except TimeoutError:
                    try:
                        m = board.expect_regex(RE_SYNC, args.timeout, "sync")
                        sync = float(m.group(1)) + float(m.group(2)) / 1000.0
                        start = int(m.group(3)); cfo = int(m.group(4))
                        eq = m.group(5).decode()
                        f = board.expect_regex(RE_FAIL, args.timeout, "RX FAIL")
                        crc_ok = 0
                        reason = f.group(1).decode()
                        seq = plen = 0
                        phex = text = ""
                    except (TimeoutError, RuntimeError):
                        crc_ok = 0
                        reason = "serial_timeout"
                        sync = start = cfo = 0.0
                        eq = seq = plen = 0
                        phex = text = ""
                    except RuntimeError as e:
                        print(f"BOARD RESET: {e}")
                        return 2
                except RuntimeError as e:
                    print(f"BOARD RESET: {e}")
                    return 2

                ok_frame = (crc_ok == 1 and seq == exp["seq"]
                            and plen == exp["length"]
                            and text == exp["text"])
                if ok_frame:
                    passed += 1
                else:
                    print(f"FAIL {mode}: {reason or 'content mismatch'}")
                writer.writerow([mode, repeat, f"{sync:.3f}", start, cfo, eq,
                                 crc_ok, phex, text,
                                 "" if ok_frame else (reason or "mismatch")])
                csvf.flush()
                board.expect([CMD_PROMPT], 5, "cmd prompt")

        print(f"\nResult: {passed}/{total} mode-loopbacks PASS")
        print(f"CSV: {csv_path}\nLOG: {log_path}")
        return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
