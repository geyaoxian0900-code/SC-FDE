# GD32E503 SC-FDE Underwater Acoustic Modem

For board wiring, flashing, serial commands, equalizer selection, and test
procedures, see [操作手册.md](操作手册.md).

This project is an embedded, resource-bounded implementation derived from the
single-carrier frequency-domain equalization chain in Yang Siqi's thesis. It
keeps the original `01_GPIO_Running_LED` project unchanged.

## Air Interface

- Frame: `UW(32) | UW(32) | DATA(96) | UW(32)`
- Modulation: QPSK
- Unique word: length-32 Chu sequence
- Symbol rate: 4 ksym/s
- Carrier: 12 kHz
- DAC sample rate: 96 kHz on PA4, TIMER6
- ADC sample rate: 48 kHz on PA0, TIMER2 and DMA0 channel 0
- Packet: magic, length, sequence, up to 10 payload bytes, CRC16-CCITT
- Error correction: embedded-compatible short LDPC (192,128), rate 2/3, 10 min-sum iterations

The second UW is channel-estimation training. The preceding UW acts as its
cyclic prefix. The `DATA | trailing UW` block has 128 symbols and is processed
by a 128-point FFT. LDPC reduces the application payload to 10 bytes per frame
because the 128 information bits are expanded to 192 coded bits.

## Receiver

1. Passband downconversion and integrate-and-dump symbol sampling.
2. Joint sample-phase and UW frame search.
3. Start/end Doppler estimation from the three UWs and linear phase-rate compensation.
4. 32-point LS channel estimation, 28-tap truncation, and conversion to a 128-bin response.
5. Runtime-selectable MMSE-FDE, ZF-FDE, matched-filter FDE, IB-DFE, or NLMS-TDE.
6. QPSK soft metrics, (192,128) LDPC min-sum decoding, packet parsing, and CRC16 validation.

The Doppler tracker estimates the phase rate between UW1/UW2 and UW2/UW3,
then applies a linear phase-rate correction over the frame. This targets the
current passband model's Doppler frequency shift; a wide-range time-scale
resampler is still needed for very large physical Doppler factors.

## Serial Menu

USART0 is 9600 baud, 8-N-1.

At startup, select one node role:

- `1`: local diagnostic, with digital loopback only
- `2`: transmitter node
- `3`: receiver node
- `4`: manual transceiver

Each role then shows only the commands that apply to it. Command numbers stay
consistent: `1` transmit, `2` receive, `3` selected-equalizer loopback, `4`
cycle equalizer, `5` test all equalizers, and `0` return to role selection.

The equalizer modes are `AUTO`, `MMSE-FDE`, `ZF-FDE`, `MF-FDE`, `IB-DFE`,
and `NLMS-TDE`. `AUTO` tries MMSE, IB-DFE, NLMS-TDE, ZF, and matched filtering in that order
and accepts the first packet that passes LDPC, header, and CRC checks. IB-DFE
uses two QPSK decision-feedback iterations and constrains the final 32 symbols
to the known trailing UW. NLMS-TDE is a true time-domain equalizer: it trains
a 16-tap complex FIR inverse filter for six epochs on the repeated 32-symbol
UW, then filters the 128-symbol data block without an FFT. The equalizer
workspace remains below approximately 4 KB.

The current GD32E503CE frame does not directly host the Chapter 4 BCJR/Turbo,
Chapter 5 CCK-SM, or Chapter 6 multiuser CSK detectors. Those require a
different coded frame, multiple antenna/user observations, or substantially
more soft-state memory; they remain MATLAB reference simulations.

Use menu item 3 before connecting the analog front end. For two-board tests,
connect the transmitter DAC chain to the receiver ADC chain through suitable
biasing, filtering, attenuation, and a common ground. Do not connect PA4
directly to PA0 without checking voltage range and ADC bias.

## Firmware Structure

- `main.c`: board initialization only
- `scfde_app.c`: node roles, serial menus, transmit/receive workflows, tests
- `scfde_modem.c`: framing, synchronization, Doppler, channel estimation, LDPC/CRC
- `scfde_equalizer.c`: frequency-domain and time-domain equalizers
- `bsp_*.c`: USART, DAC, ADC/DMA, and half-duplex hardware drivers

## Build

Open `MDK-ARM/GD32E503C_START.uvprojx` in Keil MDK or
`EWARM/GD32E503C_START.eww` in IAR. The target is GD32E503CE.

## MATLAB End-to-End Text Simulation

For a project-wide structural check and a quick Chapter 2-6 regression run:

```matlab
cd matlab
verification = verify_scfde_project();
summary = run_all_scfde_simulations(struct("profile","quick"));
```

Use `profile="full"` for the default chapter settings. See `matlab/README.md`
for the complete simulation index and `matlab/results/README.md` for artifacts.

The `matlab/run_text_scfde_demo.m` function implements the complete path from
UTF-8 text to recovered text. It includes packet fragmentation, CRC16, QPSK,
the passband waveform, time-varying multipath, ADC quantization, UW timing,
frequency-offset correction, LS channel estimation, and MMSE FDE.

```matlab
cd matlab
result = run_text_scfde_demo("Hello SC-FDE");

options.snrDb = 15;
options.dopplerHz = [12, 11, 13, 10];
result = run_text_scfde_demo("A longer UTF-8 message", options);
```

The text demo uses up to three CRC-triggered frame attempts by default so a
multi-frame message can be reconstructed under moderate noise. Set
`options.maxFrameAttempts = 1` to match the current one-shot firmware behavior.

To simulate a time-domain single-carrier equalizer and compare it with
SC-FDE:

```matlab
options.equalizerDomain = "time";
options.tdeTaps = 24;
options.tdeDelay = 12;
tdeResult = run_text_scfde_demo("Time-domain SC equalizer", options);
comparison = compare_scfde_tde("Strong multipath", options);
```

The time-domain mode uses a causal linear MMSE FIR equalizer. The default
frequency-domain mode remains the recommended choice for long,
frequency-selective underwater channels.

For an interactive, stage-by-stage display, run:

```matlab
cd matlab
launch_scfde_text_app
```

The app displays packet bits, the mapped transmit constellation, DAC transmit
waveform, ADC receive waveform, UW timing metric, equalized constellation,
CRC state, and reconstructed text while advancing through the link stages.

### Chapter 2 Time-Domain Equalizer Suite

Run the following script to simulate the Chapter 2 equalizer family under one
identical time-varying multipath realization:

```matlab
cd matlab
chapter2 = simulate_chapter2_single_carrier_tde();
```

The script compares conventional DFE, adaptive NLMS DFE, PLL-assisted DFE,
multichannel DFE, passive time-reversal DFE, and subband passive time-reversal
DFE. It saves `results/chapter2_single_carrier_tde.png`. The main controls are
`snrDb`, `dopplerHz`, `pathDelays`, `pathGains`, `trainingSymbols`,
`feedforwardTaps`, and `feedbackTaps`.

### Chapter 3 SC-FDE Suite

```matlab
chapter3 = simulate_chapter3_scfde();
```

This suite covers the SC-FDE system model, residual Doppler and initial-phase
estimation, frame processing, joint time-frequency equalization, IB-DFE, and
a replaceable lake-style impulse-response processing interface. It exports
`results/chapter3_scfde_simulation.png`.

### Chapter 4 Iterative Equalizer Suite

```matlab
chapter4 = simulate_chapter4_iterative_equalization();
```

The suite includes a rate-1/2 convolutional encoder, random interleaver,
BCJR Log-MAP and Max-Log-MAP decoders, time-domain Turbo equalization,
frequency-domain decision feedback, unidirectional and bidirectional
time-frequency Turbo processing, and normalized BLMS channel adaptation. It
exports `results/chapter4_iterative_equalization.png`.

### Chapter 5 CCK Suite

```matlab
chapter5 = simulate_chapter5_cck();
```

This suite covers FR-CCK, HR-CCK, GCCK, extended CCK, ISI-aware reception,
full-list and reduced-list iterative detection, and 2x2 CCK spatial
modulation. It exports `results/chapter5_cck_simulation.png`.

### Chapter 6 Cyclic-Shift Spread-Spectrum Suite

```matlab
chapter6 = simulate_chapter6_csk_multiuser();
```

This suite compares direct-sequence BPSK, M-ary orthogonal spreading, and
cyclic-shift keying (CSK). It also simulates conventional multiuser CSK with
matched-filter and iterative interference-cancellation receivers, plus
traditional IDMA and CSK-IDMA iterative reception. It exports
`results/chapter6_csk_multiuser.png` and
`results/chapter6_csk_channel_profile.png`.

To use a measured lake impulse response, store it as `h`, `ir`, or
`impulseResponse` in a MAT file and run:

```matlab
options.measuredChannelFile = 'D:\path\to\lake_channel.mat';
chapter6 = simulate_chapter6_csk_multiuser(options);
```

### Configurable Physical Layer

The `Physical-layer parameters` dialog controls:

- modulation: BPSK, QPSK, or 16QAM
- FFT length: 64, 128, 256, or 512
- UW length: 8, 16, 32, 64, or 128 symbols
- symbol rate and passband carrier frequency
- transmit and receive sample rates

The app derives `dataSymbols = fftSize - uwLength`, packet length, maximum
UTF-8 payload, frame duration, and samples per symbol. It rejects settings
that violate byte alignment, UW/FFT ordering, integer sampling ratios, delay
protection, or the receiver Nyquist limit. These settings affect the MATLAB
simulation; the MCU firmware remains at its compiled 128/32/QPSK profile
until the corresponding C constants and timing peripherals are rebuilt.

The channel dialog enables automatic delay protection by default. If a
configured analytic-path delay or Bellhop delay window exceeds the current UW
duration, the app selects the next power-of-two UW, expands the FFT while
preserving useful data capacity, and increases the LS channel-tap count. For
example, a 15 ms path at 4 ksym/s changes the default 32/128 UW/FFT profile to
64/256, giving 16 ms of protection and at least 61 channel taps. Disable the
automatic option to enforce strict validation instead.

### Bellhop Channel

Select `Bellhop ray-arrival channel` in the app to run the locally installed
Acoustics Toolbox. The default executable is:

`D:\MATLAB\atWin10_2020_11_4\atWin10_2020_11_4\windows-bin-20201102\bellhop.exe`

The advanced dialog exposes water depth, source/receiver depth, horizontal
range, maximum retained ray count, and maximum relative delay spread. For each
simulation, the app writes a 12 kHz shallow-water `.env` file, runs Bellhop,
reads the ASCII `.arr` file, references delays to the earliest arrival, merges
rays on the 96 kHz sample grid, and normalizes the resulting complex channel.
