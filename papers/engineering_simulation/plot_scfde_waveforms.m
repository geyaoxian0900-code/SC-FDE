function plot_scfde_waveforms(options)
%PLOT_SCFDE_WAVEFORMS Generate the SC-FDE transmit waveform and the
% theoretical received waveform with the SAME physical-layer profile as
% the GD32E503C Keil firmware (scfde_modem.h):
%
%   Frame: UW1(32) | UW2(32) | QPSK DATA(96) | UW3(32)   = 192 symbols
%   Symbol rate 4 ksym/s, carrier 12 kHz, TX 96 kHz (24 samples/symbol,
%   rectangular hold), RX 48 kHz (12 samples/symbol integrate-and-dump)
%
% The transmit passband waveform is synthesized exactly as the firmware
% does (packet -> QPSK -> three-UW frame -> rectangular pulses -> 12 kHz
% real passband).  The theoretical receive waveform is the transmitted
% signal convolved with the configured channel impulse response (the
% project synthetic 3-path profile by default, or the Bellhop channel
% with channelMode="bellhop") plus AWGN at the configured SNR, sampled
% at the 48 kHz RX rate.
%
% Outputs (written under papers/results/scfde_waveforms/):
%   tx_waveform.mat/.csv    - 96 kHz transmit passband samples
%   rx_waveform.mat/.csv    - 48 kHz received passband samples
%   waveforms.png           - time-domain transmit/receive, spectra and
%                             baseband constellation
%
% OPTIONS (struct):
%   payload       - text payload (default "SC-FDE")
%   channelMode   - "synthetic" (default) or "bellhop"
%   bellhopOptions- options for scfde_bellhop_channel
%   snrDb         - SNR for the theoretical RX (default 15)
%   makePlot      - save the figure (default true)

if nargin < 1
    options = struct();
end
payload = field_default(options, "payload", "SC-FDE");
channelMode = field_default(options, "channelMode", "synthetic");
bellhopOptions = field_default(options, "bellhopOptions", struct());
snrDb = field_default(options, "snrDb", 15);
makePlot = field_default(options, "makePlot", true);

% --- firmware profile ---------------------------------------------------
txFs = 96000;                 % SCFDE_TX_SAMPLE_RATE_HZ
rxFs = 48000;                 % SCFDE_RX_SAMPLE_RATE_HZ
carrierHz = 12000;            % SCFDE_CARRIER_FREQ_HZ
symbolRate = 4000;            % SCFDE_SYMBOL_RATE_HZ
txSamplesPerSymbol = 24;      % SCFDE_TX_SAMPLES_PER_SYMBOL
rxSamplesPerSymbol = 12;      % SCFDE_RX_SAMPLES_PER_SYMBOL
uwLength = 32;                % SCFDE_UW_LENGTH
dataSymbols = 96;             % SCFDE_DATA_SYMBOLS
frameSymbols = 192;           % SCFDE_FRAME_SYMBOLS
channelTaps = 28;             % SCFDE_CHANNEL_TAPS

% --- packet: magic(2) | length(1) | seq(1) | payload | CRC16-CCITT ----
packetBytes = 24;
payloadBytes = uint8(payload);
assert(numel(payloadBytes) <= 18, "payload must be <= 18 bytes");
packet = zeros(1, packetBytes, "uint8");
packet(1) = 0xA5; packet(2) = 0x5A;
packet(3) = numel(payloadBytes);
packet(4) = 0x55;                                   % sequence
packet(5:4 + numel(payloadBytes)) = payloadBytes;
crc = crc16_ccitt(packet(1:packetBytes - 2));
packet(packetBytes - 1) = bitshift(crc, -8);
packet(packetBytes) = bitand(crc, 255);

% --- QPSK mapping (bit 1 -> positive I/Q) -------------------------------
bits = double(reshape(de2bi(double(packet), 8, "left-msb")', 1, []));
symbols = complex(zeros(1, dataSymbols));
for s = 1:dataSymbols
    symbols(s) = (1 - 2 * bits(2 * s - 1)) + 1j * (1 - 2 * bits(2 * s));
end

% --- Chu UW (same formula as scfde_modem_init) ---------------------------
uw = complex(zeros(1, uwLength));
for n = 1:uwLength
    angle = -pi * (n - 1)^2 / uwLength;
    uw(n) = cos(angle) + 1j * sin(angle);
end
frame = [uw, uw, symbols, uw];                      % 192 symbols

% --- rectangular pulse shaping + 12 kHz passband (96 kHz TX) -------------
txSymbols = upsample(frame, txSamplesPerSymbol);
txSymbols = txSymbols(1:frameSymbols * txSamplesPerSymbol);
txBaseband = conv(txSymbols, ones(1, txSamplesPerSymbol), "same");
nTx = numel(txBaseband);
txTime = (0:nTx - 1) / txFs;
txWaveform = 700 * real(txBaseband .* exp(1j * 2 * pi * carrierHz * txTime));

% --- channel -------------------------------------------------------------
switch lower(channelMode)
    case "bellhop"
        [delaysMs, gains] = scfde_bellhop_channel(bellhopOptions);
        delaysSamples = round(delaysMs / 1000 * txFs);
        impulse = zeros(1, max(delaysSamples) + 1);
        for p = 1:numel(delaysSamples)
            impulse(delaysSamples(p) + 1) = impulse(delaysSamples(p) + 1) + gains(p);
        end
        impulse = impulse / norm(impulse);
        channelName = "Bellhop";
    otherwise
        % Synthetic 3-path profile matching the firmware impulse table.
        impulse = zeros(1, channelTaps);
        impulse(1) = 1;
        impulse(2) = 0.5 * exp(1j * 0.4);
        impulse(4) = 0.2 * exp(-1j * 0.8);
        impulse = impulse / norm(impulse);
        channelName = "3-path synthetic";
end

% --- theoretical RX at 48 kHz (firmware ADC rate) -------------------------
txAtRxRate = txWaveform(1:2:end);                   % 96k -> 48k decimate
nRx = numel(txAtRxRate);
rxTime = (0:nRx - 1) / rxFs;
% Filter the channel at the RX sample rate (resample the impulse).
impulseRx = resample(impulse, 1, 2);
impulseRx = impulseRx(1:min(numel(impulseRx), 16));
rxClean = conv(txAtRxRate, real(impulseRx), "same");
noisePower = 10^(-snrDb / 10) * mean(rxClean.^2);
rxWaveform = rxClean + sqrt(noisePower) * randn(1, nRx);

% --- baseband demodulated constellation (integrate-and-dump) --------------
cos4 = [1, 0, -1, 0];
sin4 = [0, 1, 0, -1];
rxBaseband = complex(zeros(1, floor(nRx / rxSamplesPerSymbol)));
for s = 1:numel(rxBaseband)
    inPhase = 0; quadrature = 0;
    for k = 0:rxSamplesPerSymbol - 1
        idx = (s - 1) * rxSamplesPerSymbol + k + 1;
        if idx > nRx, break; end
        carrier = mod(idx - 1, 4) + 1;
        inPhase = inPhase + rxWaveform(idx) * cos4(carrier);
        quadrature = quadrature - rxWaveform(idx) * sin4(carrier);
    end
    rxBaseband(s) = inPhase + 1j * quadrature;
end

% --- save ----------------------------------------------------------------
outDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "scfde_waveforms");
if ~exist(outDir, "dir"), mkdir(outDir); end
txTable = table(txTime.', txWaveform.', 'VariableNames', {'t_s', 'tx'});
rxTable = table(rxTime.', rxWaveform.', 'VariableNames', {'t_s', 'rx'});
save(fullfile(outDir, "tx_waveform.mat"), "txTime", "txWaveform", ...
    "frame", "symbols", "uw", "txFs", "carrierHz");
save(fullfile(outDir, "rx_waveform.mat"), "rxTime", "rxWaveform", ...
    "rxClean", "impulse", "rxFs", "carrierHz", "snrDb", "channelName");
writetable(txTable, fullfile(outDir, "tx_waveform.csv"));
writetable(rxTable, fullfile(outDir, "rx_waveform.csv"));

fprintf("TX waveform : %d samples @ %d Hz, %.1f ms\n", nTx, txFs, nTx / txFs * 1e3);
fprintf("RX waveform : %d samples @ %d Hz, %.1f ms (channel: %s, SNR %g dB)\n", ...
    nRx, rxFs, nRx / rxFs * 1e3, channelName, snrDb);
fprintf("Saved under papers/results/scfde_waveforms/\n");

% --- figure --------------------------------------------------------------
if makePlot
    fig = figure("Color", "w", "Position", [60, 60, 1200, 800], "Visible", "off");
    % TX time domain (first 10 ms)
    subplot(4, 1, 1);
    plot(txTime * 1e3, txWaveform, "b");
    xlim([0, 10]); grid on;
    xlabel("t (ms)"); ylabel("TX amplitude");
    title(sprintf("SC-FDE transmit passband (%d Hz carrier, %d Hz, payload ""%s"")", ...
        carrierHz, txFs, payload));
    % RX time domain (first 10 ms)
    subplot(4, 1, 2);
    plot(rxTime * 1e3, rxWaveform, "r"); hold on;
    plot(rxTime * 1e3, rxClean, "k", "LineWidth", 1);
    xlim([0, 10]); grid on; legend("RX + noise", "RX clean", "Location", "northeast");
    xlabel("t (ms)"); ylabel("RX amplitude");
    title(sprintf("Theoretical RX passband (channel: %s, SNR %g dB)", channelName, snrDb));
    % Spectra
    subplot(4, 1, 3);
    nfft = 4096;
    fTx = (0:nfft - 1) / nfft * txFs;
    fRx = (0:nfft - 1) / nfft * rxFs;
    plot(fTx / 1000, 20 * log10(abs(fft(txWaveform, nfft)) + eps), "b"); hold on;
    plot(fRx / 1000, 20 * log10(abs(fft(rxWaveform, nfft)) + eps), "r");
    xlim([0, 30]); grid on; legend("TX", "RX");
    xlabel("Frequency (kHz)"); ylabel("Magnitude (dB)");
    title("Spectra (carrier 12 kHz, symbol 4 ksym/s)");
    % Baseband constellation
    subplot(4, 1, 4);
    plot(real(rxBaseband), imag(rxBaseband), ".", "MarkerSize", 4);
    hold on; plot([-1 1 1 -1 -1] * 400, [-1 -1 1 1 -1] * 400, "r--");
    grid on; axis equal; xlabel("I"); ylabel("Q");
    title("Demodulated baseband constellation (RX integrate-and-dump)");
    pngPath = fullfile(outDir, "waveforms.png");
    exportgraphics(fig, pngPath, "Resolution", 150);
    close(fig);
    fprintf("Figure saved: %s\n", pngPath);
end
end

function crc = crc16_ccitt(data)
crc = uint16(hex2dec("FFFF"));
for k = 1:numel(data)
    crc = bitxor(crc, bitshift(uint16(data(k)), 8));
    for bit = 1:8
        if bitand(crc, uint16(hex2dec("8000"))) ~= 0
            crc = bitxor(bitshift(crc, 1), uint16(hex2dec("1021")));
        else
            crc = bitshift(crc, 1);
        end
    end
end
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
