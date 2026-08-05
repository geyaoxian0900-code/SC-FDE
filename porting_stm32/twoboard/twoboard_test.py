#!/usr/bin/env python3
"""twoboard_test.py - Two-board automated SC-FDE over-the-wire test.

Board A: transmitter node (role 2). Board B: receiver node (role 3).
Controls both serial ports, runs batch test groups, parses firmware output,
classifies failures, writes CSV + text log, and reports an acceptance
summary. Exit code 0 = all selected groups passed.

Test groups:
  A  fixed payload, N frames                          (repeat stability)
  B  sequence sweep, N frames (firmware auto-increments seq)
  C  payload lengths [0,1,4,10,18] x N frames each
  D  TX amplitude sweep  (requires firmware variants with different
     SCFDE_TX_AMPLITUDE; pass --amplitude-label per run to annotate)
  E  independent-clock CFO statistics, N frames

NOTE: the firmware does not print ADC min/max or channel taps; those CSV
columns are recorded as "NA" (scope measurement needed, see
WIRE_LOOPBACK_GUIDE.md).

Usage:
    python twoboard_test.py --tx-port COM5 --rx-port COM6 --test A B C E
                            [--frames 100] [--payload "HELLO-SCFDE"]
    python twoboard_test.py --tx-port COM5 --rx-port COM6 --test D \
                            --amplitude-label "amp700"
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
RE_TX_START = re.compile(rb"TX start: seq=(\d+) len=(\d+)")
RE_TX_OK = re.compile(rb"TX OK: samples=(\d+)")
RE_RX_ARMED = re.compile(rb"RX armed")
RE_RX_TIMEOUT = re.compile(rb"RX timeout")
RE_RX_CAPTURED = re.compile(rb"RX captured: (\d+) samples")

CSV_FIELDS = ["timestamp", "frame_index", "group", "tx_sequence", "rx_sequence",
              "payload_length", "sync_metric", "frame_start", "cfo_hz",
              "crc_ok", "payload_match", "timeout", "adc_min", "adc_max",
              "equalizer", "fail_reason"]

CFO_LIMIT_HZ = 10.0   # documented sync+CFO capture range


class Board:
    def __init__(self, port, baud, logf, name):
        self.name = name
        self.ser = serial.Serial(port, baud, timeout=0.05)
        self.buf = b""
        self.logf = logf

    def log(self, text):
        stamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.logf.write(f"[{stamp}] [{self.name}] {text}\n")
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
        raise TimeoutError(f"{fail_text} (patterns={[p[:20] for p in patterns]})")

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

    def setup_role(self, role_char, role_keyword):
        self.expect([ROLE_PROMPT], 10, "no role prompt")
        self.send(role_char.encode() + b"\r")
        self.expect([role_keyword], 10, "role select failed")
        self.expect([CMD_PROMPT], 10, "no cmd prompt")


class TestRunner:
    def __init__(self, a: Board, b: Board, args, writer, csvf, logf):
        self.a = a
        self.b = b
        self.args = args
        self.writer = writer
        self.csvf = csvf
        self.logf = logf
        self.stats = {}   # group -> dict

    def row(self, **kw):
        base = dict.fromkeys(CSV_FIELDS, "")
        base.update(kw)
        base["timestamp"] = datetime.datetime.now().isoformat(timespec="milliseconds")
        if base.get("adc_min") == "":
            base["adc_min"] = "NA"
        if base.get("adc_max") == "":
            base["adc_max"] = "NA"
        self.writer.writerow([base[k] for k in CSV_FIELDS])
        self.csvf.flush()

    def frame(self, group, frame_index, payload: bytes) -> dict:
        """One TX/RX cycle. Uses the TX board's actual reported sequence
        (firmware g_sequence increments across groups and never resets, so
        the PC must not guess expected sequence numbers)."""
        row = {"group": group, "frame_index": frame_index,
               "tx_sequence": "", "rx_sequence": "",
               "payload_length": len(payload), "sync_metric": "",
               "frame_start": "", "cfo_hz": "", "crc_ok": 0,
               "payload_match": 0, "timeout": 0, "equalizer": "",
               "fail_reason": ""}
        try:
            # arm receiver first
            self.b.send(b"2\r")
            self.b.expect_regex(RE_RX_ARMED, 5, "B: RX armed")
            # transmit
            self.a.send(b"1\r")
            tx = self.a.expect_regex(RE_TX_START, 5, "A: TX start line")
            actual_tx_seq = int(tx.group(1))
            row["tx_sequence"] = actual_tx_seq
            self.a.send(payload + b"\r")
            self.a.expect_regex(RE_TX_OK, 5, "A: TX OK")
            # wait for receiver result
            m = self.b.expect_regex(RE_SYNC, 8, "B: sync line")
            row["sync_metric"] = round(float(m.group(1)) + float(m.group(2)) / 1000.0, 4)
            row["frame_start"] = int(m.group(3))
            row["cfo_hz"] = int(m.group(4))
            row["equalizer"] = m.group(5).decode()
            try:
                ok = self.b.expect_regex(RE_OK, 5, "B: RX OK line")
                row["rx_sequence"] = int(ok.group(1))
                row["crc_ok"] = 1
                rx_len = int(ok.group(2))
                row["payload_match"] = 1 if rx_len == len(payload) else 0
                if row["payload_match"]:
                    hexstr = ok.group(3).decode().replace(" ", "")
                    try:
                        row["payload_match"] = 1 if bytes.fromhex(hexstr) == payload else 0
                    except ValueError:
                        row["payload_match"] = -1
                if row["rx_sequence"] != actual_tx_seq:
                    row["fail_reason"] = "seq_mismatch"
                elif row["payload_match"] != 1:
                    row["fail_reason"] = "length_or_payload_mismatch"
                elif abs(row["cfo_hz"]) > CFO_LIMIT_HZ:
                    row["fail_reason"] = "cfo_out_of_range"
            except TimeoutError:
                f = self.b.expect_regex(RE_FAIL, 5, "B: RX FAIL line")
                row["crc_ok"] = 0
                detail = f.group(1).decode()
                row["fail_reason"] = ("sync_failed" if "synchronization" in detail
                                      else "crc_or_header_failed")
                if isinstance(row["sync_metric"], (int, float)) and \
                        row["sync_metric"] < 0.18:
                    row["fail_reason"] = "no_frame_detected"
        except TimeoutError as e:
            row["timeout"] = 1
            row["fail_reason"] = "serial_timeout"
            self.logf.write(f"[warn] frame {frame_index} timeout: {e}\n")
            self.logf.flush()
        except RuntimeError as e:
            raise e
        return row

    def run_group(self, group, frames, payload):
        self.stats[group] = {"frames": 0, "crc_ok": 0, "payload_match": 0,
                             "seq_ok": 0, "timeouts": 0, "fail": 0,
                             "cfo": []}
        s = self.stats[group]
        for i in range(frames):
            row = self.frame(group, i, payload)
            self.row(**row)
            s["frames"] += 1
            if row.get("crc_ok") == 1:
                s["crc_ok"] += 1
            if row.get("payload_match") == 1:
                s["payload_match"] += 1
            if row.get("fail_reason", "") == "":
                s["seq_ok"] += 1
            if row.get("timeout"):
                s["timeouts"] += 1
            if row.get("fail_reason"):
                s["fail"] += 1
            if row.get("cfo_hz") not in (None, ""):
                s["cfo"].append(float(row["cfo_hz"]))
        self.print_group_summary(group)

    def print_group_summary(self, group):
        s = self.stats[group]
        cfo = s["cfo"]
        line = (f"group {group}: {s['frames']} frames, CRC {s['crc_ok']}/{s['frames']}, "
                f"payload_match {s['payload_match']}/{s['frames']}, "
                f"clean {s['seq_ok']}/{s['frames']}, timeouts {s['timeouts']}, "
                f"fail {s['fail']}")
        if cfo:
            mean = sum(cfo) / len(cfo)
            var = sum((x - mean) ** 2 for x in cfo) / len(cfo)
            mx = max(abs(x) for x in cfo)
            line += f" | CFO mean {mean:+.2f} Hz, std {var ** 0.5:.2f} Hz, max|.| {mx:.2f} Hz"
        print(line)
        self.logf.write(line + "\n")
        self.logf.flush()


def main():
    ap = argparse.ArgumentParser(description="two-board SC-FDE automated test")
    ap.add_argument("--tx-port", required=True, help="Board A (transmitter) COM port")
    ap.add_argument("--rx-port", required=True, help="Board B (receiver) COM port")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--test", nargs="+", choices=["A", "B", "C", "D", "E"],
                    default=["A", "B", "C", "E"])
    ap.add_argument("--frames", type=int, default=100, help="frames per case")
    ap.add_argument("--payload", default="HELLO-SCFDE-1234", help="fixed payload (A/B/E)")
    ap.add_argument("--amplitude-label", default="", help="annotation for group D runs")
    ap.add_argument("--outdir", default="results")
    args = ap.parse_args()

    Path(args.outdir).mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = Path(args.outdir) / f"twoboard_{stamp}.csv"
    log_path = Path(args.outdir) / f"twoboard_{stamp}.log"

    with open(log_path, "w", encoding="utf-8") as logf, \
         open(csv_path, "w", newline="", encoding="utf-8") as csvf:

        writer = csv.writer(csvf)
        writer.writerow(CSV_FIELDS)
        a = Board(args.tx_port, args.baud, logf, "A(TX)")
        b = Board(args.rx_port, args.baud, logf, "B(RX)")
        runner = TestRunner(a, b, args, writer, csvf, logf)

        logf.write(f"=== two-board test {stamp} tests={args.test} "
                   f"frames={args.frames} payload={args.payload!r} ===\n")
        print(f"ports: A(TX)={args.tx_port} B(RX)={args.rx_port}")

        try:
            a.expect([BANNER], 10, "A: no banner")
            b.expect([BANNER], 10, "B: no banner")
            a.setup_role("2", b"transmitter")
            b.setup_role("3", b"receiver")
        except (TimeoutError, RuntimeError) as e:
            print(f"SETUP FAILED: {e}")
            return 1

        payload = args.payload.encode()
        groups = args.test
        try:
            for g in groups:
                if g == "A":
                    runner.run_group("A", args.frames, payload)
                elif g == "B":
                    runner.run_group("B", args.frames, payload)
                elif g == "C":
                    for length in (0, 1, 4, 10, 18):
                        p = bytes(range(65, 65 + length)) if length else b""
                        runner.run_group(f"C-{length}", args.frames, p)
                elif g == "D":
                    label = args.amplitude_label or "?"
                    runner.run_group(f"D-{label}", args.frames, payload)
                    print("note: group D compares runs across firmware variants with "
                          "different SCFDE_TX_AMPLITUDE; run once per variant and "
                          "merge CSVs.")
                elif g == "E":
                    runner.run_group("E", args.frames, payload)
        except RuntimeError as e:
            print(f"BOARD RESET: {e}")
            import json
            summary = {
                "script": "twoboard_test",
                "timestamp": stamp,
                "tx_port": args.tx_port,
                "rx_port": args.rx_port,
                "baud": args.baud,
                "aborted": "board_reset",
                "error": str(e),
                "groups": {g: s for g, s in runner.stats.items()},
                "csv": str(csv_path),
                "log": str(log_path),
            }
            summary_path = Path(args.outdir) / f"twoboard_{stamp}.summary.json"
            with open(summary_path, "w", encoding="utf-8") as sf:
                json.dump(summary, sf, indent=2)
            print(f"SUMMARY: {summary_path}")
            return 2

        # acceptance summary
        print("\n=== ACCEPTANCE SUMMARY ===")
        ok_all = True
        for g, s in runner.stats.items():
            ok = (s["crc_ok"] == s["frames"] and s["payload_match"] == s["frames"]
                  and s["fail"] == 0)
            ok_all &= ok
            print(f"  {g:8s}: CRC {s['crc_ok']}/{s['frames']}  "
                  f"payload_match {s['payload_match']}/{s['frames']}  "
                  f"{'PASS' if ok else 'FAIL'}")
        print(f"CSV: {csv_path}")
        print(f"LOG: {log_path}")

        import json
        summary = {
            "script": "twoboard_test",
            "timestamp": stamp,
            "tx_port": args.tx_port,
            "rx_port": args.rx_port,
            "baud": args.baud,
            "payload": args.payload,
            "amplitude_label": args.amplitude_label,
            "groups": {},
            "csv": str(csv_path),
            "log": str(log_path),
        }
        for g, s in runner.stats.items():
            entry = {
                "frames": s["frames"],
                "crc_ok": s["crc_ok"],
                "fer": (s["frames"] - s["crc_ok"]) / s["frames"] if s["frames"] else 0,
                "payload_match": s["payload_match"],
                "clean": s["seq_ok"],
                "timeouts": s["timeouts"],
                "fail": s["fail"],
                "hardfault_resets": 0,
            }
            if s["cfo"]:
                mean = sum(s["cfo"]) / len(s["cfo"])
                var = sum((x - mean) ** 2 for x in s["cfo"]) / len(s["cfo"])
                entry["cfo_mean_hz"] = round(mean, 3)
                entry["cfo_std_hz"] = round(var ** 0.5, 3)
                entry["cfo_max_abs_hz"] = round(max(abs(x) for x in s["cfo"]), 3)
            summary["groups"][g] = entry
        summary_path = Path(args.outdir) / f"twoboard_{stamp}.summary.json"
        with open(summary_path, "w", encoding="utf-8") as sf:
            json.dump(summary, sf, indent=2)
        print(f"SUMMARY: {summary_path}")
        return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
