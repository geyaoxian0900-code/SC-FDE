"""Reference check for the embedded SC-FDE frame and equalizer."""

import numpy as np


N = 128
UW_LEN = 32
DATA_LEN = 96
PACKET_LEN = 24


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def make_packet(payload: bytes, sequence: int) -> bytes:
    packet = bytearray(PACKET_LEN)
    packet[:4] = bytes((0xA5, 0x5A, len(payload), sequence))
    packet[4 : 4 + len(payload)] = payload
    check = crc16(packet[:22])
    packet[22:] = check.to_bytes(2, "big")
    return bytes(packet)


def qpsk_map(packet: bytes) -> np.ndarray:
    bits = np.unpackbits(np.frombuffer(packet, dtype=np.uint8), bitorder="little").astype(float)
    return (2 * bits[0::2] - 1) + 1j * (2 * bits[1::2] - 1)


def qpsk_demod(symbols: np.ndarray) -> bytes:
    bits = np.empty(DATA_LEN * 2, dtype=np.uint8)
    bits[0::2] = symbols.real >= 0
    bits[1::2] = symbols.imag >= 0
    return np.packbits(bits, bitorder="little").tobytes()


def main() -> None:
    rng = np.random.default_rng(503)
    payload = b"SC-FDE"
    packet = make_packet(payload, 0x55)
    data = qpsk_map(packet)
    n = np.arange(UW_LEN)
    uw = np.exp(-1j * np.pi * n * n / UW_LEN)
    frame = np.concatenate((uw, uw, data, uw))

    channel = np.array((0.90 + 0.10j, 0.0, 0.28 - 0.18j, 0.12 + 0.05j))
    frequency_offset_hz = 18.0
    omega = 2 * np.pi * frequency_offset_hz / 4000.0
    received = np.convolve(frame, channel)[: len(frame)]
    received *= np.exp(1j * omega * np.arange(len(frame)))
    received += 0.025 * (rng.standard_normal(len(frame)) + 1j * rng.standard_normal(len(frame)))

    cross = np.vdot(received[:UW_LEN], received[UW_LEN : 2 * UW_LEN])
    omega_hat = np.angle(cross) / UW_LEN
    corrected = received * np.exp(-1j * omega_hat * np.arange(len(frame)))

    uw_spectrum = np.fft.fft(uw)
    received_uw = np.fft.fft(corrected[UW_LEN : 2 * UW_LEN])
    impulse = np.fft.ifft(received_uw / uw_spectrum)
    impulse[24:] = 0
    response = np.fft.fft(np.pad(impulse, (0, N - UW_LEN)))

    block = corrected[2 * UW_LEN : 2 * UW_LEN + N]
    spectrum = np.fft.fft(block)
    equalized = np.fft.ifft(spectrum * np.conj(response) / (np.abs(response) ** 2 + 0.002))
    decoded = qpsk_demod(equalized[:DATA_LEN])

    assert decoded == packet, (decoded.hex(), packet.hex())
    assert crc16(decoded[:22]) == int.from_bytes(decoded[22:], "big")
    print("SC-FDE reference test: PASS")
    print(f"payload={decoded[4:4 + decoded[2]]!r}")
    print(f"CFO actual={frequency_offset_hz:.2f} Hz, estimated={omega_hat * 4000 / (2*np.pi):.2f} Hz")


if __name__ == "__main__":
    main()
