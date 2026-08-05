function export_golden_vectors(outputDir)
%EXPORT_GOLDEN_VECTORS Export the 23-stage golden vectors for the SC-FDE
%STM32 port (see FORMAT.md for the file spec).
%
%   export_golden_vectors()                 writes to ./matlab_export
%   export_golden_vectors("path/to/dir")
%
% The exported scene is deliberately aligned with the GD32 firmware digital
% loopback: rectangular pulse shape (no RRC), no multipath/Doppler/noise,
% single frame, LDPC on, one attempt.
%
% Requires run_text_scfde_demo.m (papers/engineering_simulation).

if nargin < 1
    outputDir = fullfile(fileparts(mfilename("fullpath")), "matlab_export");
end
if ~exist(outputDir, "dir")
    mkdir(outputDir);
end

papersDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), "..", ...
    "papers", "engineering_simulation");
if isempty(which("run_text_scfde_demo"))
    addpath(papersDir);
end

options = struct();
options.pulseShape     = "rectangular";   % match C firmware TX hold + I&D RX
options.leadingSamples = 0;               % no artificial leading silence
options.maxFrameAttempts = 1;             % one-shot, like the firmware
options.snrDb          = 120;             % noise effectively zero
options.dopplerHz      = 0;               % static channel
options.pathDelaysMs   = 0;               % single direct path
options.pathGains      = 1;               % unit gain
options.modulation     = "QPSK";
options.fftSize        = 128;
options.uwLength       = 32;
options.symbolRate     = 4000;
options.txSampleRate   = 96000;
options.rxSampleRate   = 48000;
options.carrierHz      = 12000;
options.ldpcEnabled    = false;   % baseline scheme: no LDPC
options.makePlot       = false;
options.randomSeed     = 20260723;

text = "SC-FDE1234";                      % 10 bytes, exactly one frame

result = run_text_scfde_demo(text, options);
assert(numel(result.frames) == 1, "Golden scene must produce exactly one frame.");
frame = result.frames(1);
cfg   = result.config;

fprintf("Golden scene: payload %d bytes, frame decoded %s (attempts=%d)\n", ...
    numel(frame.txPacket), pass_fail(frame.valid), frame.attempts);

% ---- stage 01: packet bytes -------------------------------------------
write_uint8(fullfile(outputDir, "01_packet_bytes.bin"), frame.txPacket);

% ---- stage 02: QPSK input bits (192 = packet bytes, LSB-first packed) ---
assert(numel(frame.txPacketBits) == 192, "Expected 192 QPSK input bits.");
write_uint8(fullfile(outputDir, "02_qpsk_input_bits.bin"), ...
    pack_bits(frame.txPacketBits));

% ---- stage 03: modulated QPSK symbols ---------------------------------
write_complex(fullfile(outputDir, "03_modulated_symbols.bin"), frame.txDataSymbols);

% ---- stage 04: UW (Chu) ------------------------------------------------
uw = exp(-1j * pi * (0:cfg.uwLength-1).^2 / cfg.uwLength);
write_complex(fullfile(outputDir, "04_uw.bin"), uw);

% ---- stage 05: full frame symbols --------------------------------------
write_complex(fullfile(outputDir, "05_frame_symbols.bin"), frame.txFrameSymbols);

% ---- stage 06: 96 kHz baseband (rectangular hold, complex) -------------
write_complex(fullfile(outputDir, "06_tx_baseband_96k.bin"), frame.channel.txBaseband);

% ---- stage 07: 96 kHz passband -----------------------------------------
write_float(fullfile(outputDir, "07_passband_tx_96k.bin"), frame.channel.txPassband96k);

% ---- stage 08: 48 kHz ADC codes (with 2048 midpoint, clipped) ----------
adc = double(frame.adcSamples);          % already 0..4095 uint16
assert(numel(adc) == 2816, "Unexpected capture length %d", numel(adc));
write_uint16(fullfile(outputDir, "08_adc_capture.bin"), adc);

% ---- stage 09: downconverted complex baseband --------------------------
write_complex(fullfile(outputDir, "09_downconverted.bin"), frame.downconvertedSamples);

% ---- stage 10: integrated symbols (12-point I&D at phase 0) ------------
baseband = frame.matchedFilterSamples;   % 48 kHz complex baseband
symbolCount = floor(numel(baseband) / cfg.rxSamplesPerSymbol);
integrated = complex(zeros(1, symbolCount));
for symbolIndex = 1:symbolCount
    range = (symbolIndex-1)*cfg.rxSamplesPerSymbol + 1 : ...
        symbolIndex*cfg.rxSamplesPerSymbol;
    integrated(symbolIndex) = sum(baseband(range));
end
write_complex(fullfile(outputDir, "10_integrated_symbols.bin"), integrated);

% ---- stage 11: sync result ---------------------------------------------
write_text(fullfile(outputDir, "11_sync_result.txt"), ...
    sprintf("%d\n%.6f\n%.3f\n", frame.frameStartSample, frame.syncMetric, ...
    frame.frequencyOffsetHz));

% ---- stage 12/13: phase correction / corrected symbols -----------------
write_float(fullfile(outputDir, "12_phase_correction.bin"), frame.phaseCorrection);
write_complex(fullfile(outputDir, "13_corrected_symbols.bin"), frame.correctedSymbols);

% ---- stage 14/15: channel impulse / frequency response -----------------
write_complex(fullfile(outputDir, "14_channel_impulse.bin"), frame.channelImpulse);
write_complex(fullfile(outputDir, "15_channel_response.bin"), frame.channelResponse);

% ---- stage 16/17: FDE block time input / FFT output --------------------
write_complex(fullfile(outputDir, "16_fft_block_in.bin"), frame.receivedFdeBlock);
write_complex(fullfile(outputDir, "17_fft_block_out.bin"), frame.receivedBlockSpectrum);

% ---- stage 18: equalized symbols (96) ----------------------------------
write_complex(fullfile(outputDir, "18_equalized_symbols.bin"), frame.equalizedSymbols);

% ---- stage 19: QPSK LLR (baseline: -re/-im of equalized symbols) -------
llr = zeros(1, 192);
llr(1:2:end) = -real(frame.equalizedSymbols);
llr(2:2:end) = -imag(frame.equalizedSymbols);
write_float(fullfile(outputDir, "19_ldpc_llr.bin"), llr);

% ---- stage 20: hard-decision bits (192, LSB-first packed) ---------------
write_uint8(fullfile(outputDir, "20_decoded_bits.bin"), ...
    pack_bits(frame.demodulation.decodedBits));

% ---- stage 21: received packet -----------------------------------------
write_uint8(fullfile(outputDir, "21_rx_packet.bin"), frame.rxPacket);

% ---- stage 22: CRC result ----------------------------------------------
write_text(fullfile(outputDir, "22_crc_result.txt"), ...
    sprintf("%d\n%d\n%d\n%d\n", frame.headerOk, frame.crcOk, frame.valid, ...
    frame.bitErrors));

% ---- stage 23: final text ----------------------------------------------
write_text(fullfile(outputDir, "23_final_text.txt"), result.outputText);

fprintf("Golden vectors written to %s\n", outputDir);
end

% ------------------------------------------------------------------------
function write_uint8(path, values)
fid = fopen(path, "wb");
assert(fid >= 0, "Cannot open %s", path);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint8(values(:)), "uint8");
end

function write_uint16(path, values)
fid = fopen(path, "wb");
assert(fid >= 0, "Cannot open %s", path);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, uint16(values(:)), "uint16", "l");
end

function write_float(path, values)
fid = fopen(path, "wb");
assert(fid >= 0, "Cannot open %s", path);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, single(values(:)), "float32", "l");
end

function write_complex(path, values)
fid = fopen(path, "wb");
assert(fid >= 0, "Cannot open %s", path);
cleanup = onCleanup(@() fclose(fid));
data = complex(values(:));
fwrite(fid, single([real(data), imag(data)]).', "float32", "l");
end

function write_text(path, text)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "Cannot open %s", path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", text);
end

function packed = pack_bits(bits)
bits = logical(bits(:).');
byteCount = ceil(numel(bits) / 8);
packed = zeros(1, byteCount, "uint8");
for byteIndex = 0:byteCount-1
    for bitIndex = 1:8
        source = byteIndex * 8 + bitIndex;
        if (source <= numel(bits)) && bits(source)
            packed(byteIndex + 1) = bitset(packed(byteIndex + 1), bitIndex);
        end
    end
end
end

function label = pass_fail(valid)
if valid
    label = "PASS";
else
    label = "FAIL";
end
end
