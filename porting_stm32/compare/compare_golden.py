"""compare_golden.py - Automatic MATLAB vs C golden-vector comparison.

Usage:
    python compare_golden.py [matlab_dir] [c_dir]

Reads stage files per golden_vectors/FORMAT.md, computes max absolute error,
MSE, and relative error per stage, applies the tolerance table, and prints
PASS/FAIL per stage. Exit code 0 = all stages pass.

Prerequisites: run golden_vectors/export_golden_vectors.m (MATLAB) and
pc_tests/test_export_golden (C) first.
"""

import math
import struct
import sys
from pathlib import Path

DEFAULT_MATLAB = Path(__file__).resolve().parent.parent / "golden_vectors" / "matlab_export"
DEFAULT_C = Path(__file__).resolve().parent.parent / "golden_vectors" / "c_export"
# Stage -> (type, tolerance) ; type in {u8, u16, f32, cplx, text}
#
# Waveform-stage tolerances are calibrated to the documented C TX carrier
# lookup quantization (8-point int16 table + int32 mixing: <= ~5.6 DAC codes,
# ~0.25% relative, deterministic and bounded; see golden_vectors/FORMAT.md).
STAGES = [
    ("01_packet_bytes.bin", "u8", 0),
    ("02_qpsk_input_bits.bin", "u8", 0),
    ("03_modulated_symbols.bin", "cplx", 1e-5),
    ("04_uw.bin", "cplx", 1e-5),
    ("05_frame_symbols.bin", "cplx", 1e-4),
    ("06_tx_baseband_96k.bin", "cplx", 5e-3),
    ("07_passband_tx_96k.bin", "f32", 6.5),
    ("08_adc_capture.bin", "u16", 4),
    ("09_downconverted.bin", "cplx", 4.0),
    ("10_integrated_symbols.bin", "cplx", 24.0),
    ("11_sync_result.txt", "text", None),
    ("12_phase_correction.bin", "f32", 1e-4),
    ("13_corrected_symbols.bin", "cplx", 24.0),
    ("14_channel_impulse.bin", "cplx", 18.0),
    ("15_channel_response.bin", "cplx", 27.0),
    ("16_fft_block_in.bin", "cplx", 24.0),
    ("17_fft_block_out.bin", "cplx", 170.0),
    ("18_equalized_symbols.bin", "cplx", 2e-2),
    ("19_ldpc_llr.bin", "f32", 2e-2),
    ("20_decoded_bits.bin", "u8", 0),
    ("21_rx_packet.bin", "u8", 0),
    ("22_crc_result.txt", "text", None),
    ("23_final_text.txt", "text", None),
]

# Special text-stage checks
def check_text(name, matlab, c):
    m = matlab.read_text().strip().splitlines()
    v = c.read_text().strip().splitlines()
    if name == "11_sync_result.txt":
        if len(m) != 3 or len(v) != 3:
            return False, f"line count {len(v)} != {len(m)}"
        ok = (int(v[0]) == int(m[0])
              and abs(float(v[1]) - float(m[1])) <= 1e-4
              and abs(float(v[2]) - float(m[2])) <= 0.1)
        detail = f"start {v[0]} vs {m[0]}, metric {v[1]} vs {m[1]}, CFO {v[2]} vs {m[2]}"
        return ok, detail
    if name == "22_crc_result.txt":
        if len(m) != 4 or len(v) != 4:
            return False, f"line count {len(v)} != {len(m)}"
        ok = [int(a) == int(b) for a, b in zip(v, m)]
        return all(ok), f"header/crc/valid/bitErrors = {v} vs {m}"
    ok = (v == m)
    detail = f"lines {len(v)} vs {len(m)}" if not ok else "text identical"
    return ok, detail


def read_values(path, kind):
    data = path.read_bytes()
    if kind == "u8":
        return list(data)
    if kind == "u16":
        return [int.from_bytes(data[i:i + 2], "little") for i in range(0, len(data) - 1, 2)]
    if kind == "f32":
        return list(struct.unpack(f"<{len(data) // 4}f", data))
    if kind == "cplx":
        vals = struct.unpack(f"<{len(data) // 4}f", data)
        return [complex(vals[2 * i], vals[2 * i + 1]) for i in range(len(vals) // 2)]
    raise ValueError(kind)


def metrics(m, v):
    """max abs error, MSE, relative error (of vector norms), length check."""
    n = min(len(m), len(v))
    max_abs = 0.0
    mse = 0.0
    for a, b in zip(m[:n], v[:n]):
        d = abs(a - b)
        if d > max_abs:
            max_abs = d
        mse += d * d
    mse = math.sqrt(mse / n) if n else float("inf")
    mnorm = math.sqrt(sum(abs(a) * abs(a) for a in m)) or 1.0
    rel = math.sqrt(sum(abs(a - b) ** 2 for a, b in zip(m[:n], v[:n]))) / mnorm
    return max_abs, mse, rel, len(m), len(v)


def main():
    matlab_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_MATLAB
    c_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_C
    print(f"MATLAB: {matlab_dir}\nC     : {c_dir}\n")

    failed = False
    for name, kind, tol in STAGES:
        mf = matlab_dir / name
        cf = c_dir / name
        if not mf.exists() or not cf.exists():
            print(f"  {name}: MISSING (matlab={mf.exists()}, c={cf.exists()})")
            failed = True
            continue
        if kind == "text":
            ok, detail = check_text(name, mf, cf)
            print(f"  {name}: {'PASS' if ok else 'FAIL'}  {detail}")
            failed |= not ok
            continue
        m = read_values(mf, kind)
        v = read_values(cf, kind)
        max_abs, mse, rel, lm, lv = metrics(m, v)
        ok = (lm == lv) and (max_abs <= tol)
        status = "PASS" if ok else "FAIL"
        print(f"  {name}: {status}  max_abs={max_abs:.3e} mse={mse:.3e} "
              f"rel={rel:.3e} len={lv}/{lm} tol={tol}")
        failed |= not ok

    print(f"\nOverall: {'PASS' if not failed else 'FAIL'}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
