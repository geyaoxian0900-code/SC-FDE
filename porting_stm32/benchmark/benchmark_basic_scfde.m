function results = benchmark_basic_scfde(options)
%BENCHMARK_BASIC_SCFDE Baseline SC-FDE performance curves.
%   results = benchmark_basic_scfde()          defaults
%   results = benchmark_basic_scfde(options)
%
% Baseline scheme (identical to GD32 firmware with SCFDE_LDPC_ENABLED=0):
% QPSK, UW(32)|UW(32)|DATA(96)|UW(32), rectangular pulses, 12 kHz carrier,
% 4 ksym/s, 96 kHz TX / 48 kHz RX, UW sync, linear CFO correction,
% 28-tap LS channel estimate, MMSE-FDE, hard decisions, CRC-16.
%
% Outputs (saved to benchmark/results/):
%   BER-SNR / FER-SNR (unequalized vs MMSE-FDE), FER vs multipath delay,
%   sync success vs carrier offset, constellations before/after equalization.

if nargin < 1
    options = struct();
end
o.berSnrDb     = get_opt(options, "berSnrDb", 0:2:18);
o.framesPerSnr = get_opt(options, "framesPerSnr", 100);
o.snrSweep     = get_opt(options, "snrSweep", 14);
o.delaySweep   = get_opt(options, "delaySweep", [0.5 1 2 3 4 6 8]);
o.cfoSweep     = get_opt(options, "cfoSweep", [0 10 25 50 75 100]);
o.pathDelaysMs = get_opt(options, "pathDelaysMs", [0 0.5 1.0 2.0]);
o.pathGains    = get_opt(options, "pathGains", ...
    [1.0, 0.55*exp(1j*0.7), 0.35*exp(-1j*1.1), 0.20*exp(1j*2.0)]);
o.dopplerHz    = get_opt(options, "dopplerHz", 0);
o.randomSeed   = get_opt(options, "randomSeed", 20260804);
o.outputDir    = get_opt(options, "outputDir", ...
    fullfile(fileparts(mfilename("fullpath")), "results"));
o.makePlot     = get_opt(options, "makePlot", true);

rng(o.randomSeed, "twister");
if ~exist(o.outputDir, "dir")
    mkdir(o.outputDir);
end
cfg = baseline_config();
results = struct();

%% 1) BER/FER vs SNR (4-path static channel)
berEq = zeros(size(o.berSnrDb)); berNoEq = zeros(size(o.berSnrDb));
ferEq = zeros(size(o.berSnrDb)); ferNoEq = zeros(size(o.berSnrDb));
for snrIndex = 1:numel(o.berSnrDb)
    ber = [0 0]; fer = [0 0];
    for frameIndex = 1:o.framesPerSnr
        stats = run_one_frame(cfg, o.berSnrDb(snrIndex), o.pathDelaysMs, ...
            o.pathGains, o.dopplerHz, 0.0);
        ber(1) = ber(1) + stats.berEq;    ber(2) = ber(2) + stats.berNoEq;
        fer(1) = fer(1) + (1 - stats.crcOkEq);
        fer(2) = fer(2) + (1 - stats.crcOkNoEq);
    end
    berEq(snrIndex)  = ber(1) / (o.framesPerSnr * cfg.packetBits);
    berNoEq(snrIndex) = ber(2) / (o.framesPerSnr * cfg.packetBits);
    ferEq(snrIndex)  = fer(1) / o.framesPerSnr;
    ferNoEq(snrIndex) = fer(2) / o.framesPerSnr;
    fprintf("SNR %3d dB: FER_eq=%.3f FER_noeq=%.3f BER_eq=%.2e\n", ...
        o.berSnrDb(snrIndex), ferEq(snrIndex), ferNoEq(snrIndex), berEq(snrIndex));
end
results.berSnrDb = o.berSnrDb;
results.berEq = berEq; results.berNoEq = berNoEq;
results.ferEq = ferEq; results.ferNoEq = ferNoEq;

%% 2) FER vs second-path delay (2-path, gain 0.7)
ferDelay = zeros(size(o.delaySweep));
for dIndex = 1:numel(o.delaySweep)
    delays = [0, o.delaySweep(dIndex)];
    gains = [1, 0.7*exp(1j*0.3)];
    fail = 0;
    for frameIndex = 1:o.framesPerSnr
        stats = run_one_frame(cfg, o.snrSweep, delays, gains, 0.0, 0.0);
        fail = fail + (1 - stats.crcOkEq);
    end
    ferDelay(dIndex) = fail / o.framesPerSnr;
    fprintf("delay %4.1f ms: FER_eq=%.3f\n", o.delaySweep(dIndex), ferDelay(dIndex));
end
results.delaySweep = o.delaySweep;
results.ferDelay = ferDelay;

%% 3) Sync success vs carrier offset (4-path)
syncSuccess = zeros(size(o.cfoSweep));
for cIndex = 1:numel(o.cfoSweep)
    ok = 0;
    for frameIndex = 1:o.framesPerSnr
        stats = run_one_frame(cfg, o.snrSweep, o.pathDelaysMs, ...
            o.pathGains, o.dopplerHz, o.cfoSweep(cIndex));
        ok = ok + stats.synced;
    end
    syncSuccess(cIndex) = ok / o.framesPerSnr;
    fprintf("CFO %4d Hz: sync=%.3f\n", o.cfoSweep(cIndex), syncSuccess(cIndex));
end
results.cfoSweep = o.cfoSweep;
results.syncSuccess = syncSuccess;

%% 4) Constellation snapshot at 12 dB (4-path)
stats = run_one_frame(cfg, 12, o.pathDelaysMs, o.pathGains, o.dopplerHz, 0.0);
results.constellationBefore = stats.rawSymbols;
results.constellationAfter = stats.equalizedSymbols;
results.channelImpulse = stats.channelImpulse;

save(fullfile(o.outputDir, "benchmark_basic_scfde.mat"), "results");
if o.makePlot
    plot_results(o, results);
end
end

% ------------------------------------------------------------------------
function cfg = baseline_config()
cfg.fftSize = 128;
cfg.uwLength = 32;
cfg.dataSymbols = 96;
cfg.frameSymbols = 192;
cfg.symbolRate = 4000;
cfg.rxSampleRate = 48000;
cfg.carrierHz = 12000;
cfg.samplesPerSymbol = cfg.rxSampleRate / cfg.symbolRate;
cfg.channelTaps = 28;
cfg.txAmplitude = 700;
cfg.syncThreshold = 0.18;
cfg.packetBytes = 24;
cfg.maxPayload = 18;
cfg.packetBits = cfg.packetBytes * 8;
cfg.uw = exp(-1j * pi * (0:cfg.uwLength-1).^2 / cfg.uwLength);
end

function [packet, bits] = build_packet(cfg)
length = randi([1 cfg.maxPayload], 1, 1);
payload = randi([0 255], 1, length, "uint8");
packet = zeros(1, cfg.packetBytes, "uint8");
packet(1:4) = uint8([hex2dec("A5"), hex2dec("5A"), length, randi([0 255], 1, 1)]);
packet(5:4+length) = payload;
crcIndex = cfg.packetBytes - 1;
check = crc16_ccitt(packet(1:crcIndex-1));
packet(crcIndex) = uint8(bitshift(check, -8));
packet(crcIndex+1) = uint8(bitand(check, uint16(255)));
bits = false(1, 8*numel(packet));
for bitIndex = 0:numel(bits)-1
    bits(bitIndex+1) = bitget(packet(floor(bitIndex/8)+1), mod(bitIndex, 8)+1);
end
end

function stats = run_one_frame(cfg, snrDb, delaysMs, gains, dopplerHz, cfoHz)
if isscalar(dopplerHz)
    dopplerHz = repmat(dopplerHz, size(delaysMs));
end
[packet, txBits] = build_packet(cfg);
labels = sum(reshape(double(txBits), 2, []) .* (2.^(0:1)'), 1);
symbols = (2*mod(labels, 2) - 1) + 1j*(2*floor(labels/2) - 1);
frame = [cfg.uw, cfg.uw, symbols, cfg.uw];

hold = repelem(frame, cfg.samplesPerSymbol);
n = 0:numel(hold)-1;
carrier = exp(1j*2*pi*cfg.carrierHz*n/cfg.rxSampleRate);
txPassband = cfg.txAmplitude * real(hold .* carrier);

delaySamples = round(delaysMs * 1e-3 * cfg.rxSampleRate);
rx = zeros(1, numel(txPassband) + max(delaySamples));
n2 = 0:numel(rx)-1;
for pathIndex = 1:numel(delaySamples)
    delayed = zeros(size(rx));
    first = delaySamples(pathIndex) + 1;
    delayed(first:first+numel(txPassband)-1) = txPassband;
    phase = exp(1j*2*pi*(dopplerHz(pathIndex) + cfoHz)*n2/cfg.rxSampleRate);
    rx = rx + gains(pathIndex) * delayed .* phase;
end
rx = rx(1:numel(txPassband));
activePower = mean(rx.^2);
noisePower = activePower / 10^(snrDb/10);
rx = rx + sqrt(noisePower) * randn(size(rx));
adc = uint16(min(4095, max(0, round(2048 + [rx, zeros(1, 512)]))));

x = double(adc) - mean(double(adc));
down = x .* exp(-1j*2*pi*cfg.carrierHz*(0:numel(x)-1)/cfg.rxSampleRate);

stats = struct();
stats.synced = 0; stats.crcOkEq = 0; stats.crcOkNoEq = 0;
stats.berEq = 0; stats.berNoEq = 0;

bestMetric = 0; bestPhase = 0; bestOffset = 0;
for phase = 0:cfg.samplesPerSymbol-1
    symbolCount = floor((numel(x)-phase)/cfg.samplesPerSymbol);
    if symbolCount < cfg.frameSymbols
        continue;
    end
    idx = phase + 1 + (0:symbolCount-1)*cfg.samplesPerSymbol;
    sym = zeros(1, symbolCount);
    for k = 0:cfg.samplesPerSymbol-1
        sym = sym + down(idx + k);
    end
    c1 = conv(sym, conj(fliplr(cfg.uw)), "valid");
    c2 = conv(sym, conj(fliplr(cfg.uw)), "valid");
    c2 = c2(cfg.uwLength+1:end);
    energy = conv(abs(sym).^2, ones(1, 2*cfg.uwLength), "valid");
    maxOffset = symbolCount - cfg.frameSymbols;   % full frame must fit
    len = min([numel(c1), numel(c2), numel(energy), maxOffset + 1]);
    metric = (abs(c1(1:len)).^2 + abs(c2(1:len)).^2) ./ ...
        (cfg.uwLength*energy(1:len) + eps);
    [m, mi] = max(metric);
    if m > bestMetric
        bestMetric = m;
        bestPhase = phase;
        bestOffset = mi - 1;
    end
end
if bestMetric < cfg.syncThreshold
    stats.syncMetric = bestMetric;
    return;
end
stats.synced = 1;
phase = bestPhase;
symbolCount = floor((numel(x)-phase)/cfg.samplesPerSymbol);
idx = phase + 1 + (0:symbolCount-1)*cfg.samplesPerSymbol;
sym = zeros(1, symbolCount);
for k = 0:cfg.samplesPerSymbol-1
    sym = sym + down(idx + k);
end
bestSymbols = sym(bestOffset+1:bestOffset+cfg.frameSymbols);

firstUw = bestSymbols(1:cfg.uwLength);
secondUw = bestSymbols(cfg.uwLength+1:2*cfg.uwLength);
thirdStart = 2*cfg.uwLength + cfg.dataSymbols + 1;
thirdUw = bestSymbols(thirdStart:thirdStart+cfg.uwLength-1);
startOmega = angle(sum(secondUw .* conj(firstUw))) / cfg.uwLength;
endOmega = angle(sum(thirdUw .* conj(secondUw))) / (cfg.uwLength + cfg.dataSymbols);
omegaSlope = (endOmega - startOmega) / max(cfg.frameSymbols-1, 1);
sampleIndex = 0:cfg.frameSymbols-1;
corrected = bestSymbols .* exp(-1j*(startOmega*sampleIndex + ...
    0.5*omegaSlope*sampleIndex.^2));
stats.frequencyOffsetHz = 0.5*(startOmega + endOmega)*cfg.symbolRate/(2*pi);

uwSpectrum = fft(cfg.uw);
receivedUw = fft(corrected(cfg.uwLength+1:2*cfg.uwLength));
channel32 = receivedUw .* conj(uwSpectrum) ./ (abs(uwSpectrum).^2 + eps);
impulse32 = ifft(channel32);
impulse32(cfg.channelTaps+1:end) = 0;
channelResponse = fft([impulse32, zeros(1, cfg.fftSize-cfg.uwLength)]);
steadyStart = min(cfg.channelTaps+1, cfg.uwLength-3);
steadyRange = steadyStart:cfg.uwLength;
differenceEnergy = 0.5*mean(abs(corrected(steadyRange) - ...
    corrected(cfg.uwLength+steadyRange)).^2);
regularization = max(differenceEnergy*cfg.fftSize/2, ...
    sum(abs(channelResponse).^2)*0.01/cfg.fftSize);

block = corrected(2*cfg.uwLength+1:2*cfg.uwLength+cfg.fftSize);
blockSpectrum = fft(block);
equalized = ifft(blockSpectrum .* conj(channelResponse) ./ ...
    (abs(channelResponse).^2 + regularization));
tailUw = equalized(cfg.dataSymbols+1:cfg.fftSize);
residualGain = sum(tailUw .* conj(cfg.uw)) / (sum(abs(cfg.uw).^2) + eps);
if abs(residualGain) > 1e-6
    equalized = equalized / residualGain;
end
stats.equalizedSymbols = equalized(1:cfg.dataSymbols);
stats.rawSymbols = block(1:cfg.dataSymbols);
stats.channelImpulse = impulse32;

stats.berEq = decode_bits(cfg, equalized(1:cfg.dataSymbols), packet);
stats.crcOkEq = crc_pass(cfg, decode_packet(cfg, equalized(1:cfg.dataSymbols)), packet);
stats.berNoEq = decode_bits(cfg, block(1:cfg.dataSymbols), packet);
stats.crcOkNoEq = crc_pass(cfg, decode_packet(cfg, block(1:cfg.dataSymbols)), packet);
end

function packet = decode_packet(cfg, dataSymbols)
bits = false(1, 2*numel(dataSymbols));
bits(1:2:end) = real(dataSymbols) > 0;
bits(2:2:end) = imag(dataSymbols) > 0;
packet = zeros(1, numel(bits)/8, "uint8");
for bitIndex = 0:numel(bits)-1
    if bits(bitIndex+1)
        packet(floor(bitIndex/8)+1) = bitset(packet(floor(bitIndex/8)+1), mod(bitIndex, 8)+1);
    end
end
end

function ber = decode_bits(cfg, dataSymbols, txPacket)
different = bitxor(decode_packet(cfg, dataSymbols), txPacket);
ber = 0;
for bitPosition = 1:8
    ber = ber + sum(bitget(different, bitPosition));
end
end

function ok = crc_pass(cfg, rxPacket, txPacket)
ok = (rxPacket(1) == hex2dec("A5")) && (rxPacket(2) == hex2dec("5A")) && ...
    (rxPacket(3) <= cfg.maxPayload);
if ~ok
    return;
end
crcIndex = cfg.packetBytes - 1;
receivedCrc = bitor(bitshift(uint16(rxPacket(crcIndex)), 8), ...
    uint16(rxPacket(crcIndex+1)));
ok = crc16_ccitt(rxPacket(1:crcIndex-1)) == receivedCrc;
end

function crc = crc16_ccitt(data)
crc = uint16(65535);
polynomial = uint16(hex2dec("1021"));
for value = data
    crc = bitxor(crc, bitshift(uint16(value), 8));
    for bitIndex = 1:8
        if bitand(crc, uint16(hex2dec("8000"))) ~= 0
            crc = bitxor(bitshift(crc, 1), polynomial);
        else
            crc = bitshift(crc, 1);
        end
    end
end
end

function value = get_opt(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function plot_results(o, results)
set(0, "DefaultAxesFontName", "Microsoft YaHei");
fig = figure("Color", "w", "Position", [60, 60, 1400, 900], "Visible", "off");
tiledlayout(2, 3, "TileSpacing", "compact", "Padding", "compact");

nexttile; hold on;
semilogy(results.berSnrDb, max(results.berNoEq, 1e-6), "-o", "DisplayName", "锟睫撅拷锟斤拷 BER");
semilogy(results.berSnrDb, max(results.berEq, 1e-6), "-s", "DisplayName", "MMSE-FDE BER");
grid on; xlabel("SNR (dB)"); ylabel("BER"); title("BER锟紺SNR锟斤拷4 锟斤拷锟斤拷态锟脚碉拷锟斤拷");
legend("Location", "southwest");

nexttile; hold on;
semilogy(results.berSnrDb, max(results.ferNoEq, 1e-3), "-o", "DisplayName", "锟睫撅拷锟斤拷 FER");
semilogy(results.berSnrDb, max(results.ferEq, 1e-3), "-s", "DisplayName", "MMSE-FDE FER");
grid on; xlabel("SNR (dB)"); ylabel("FER"); title("FER锟紺SNR");
legend("Location", "southwest");

nexttile;
semilogy(results.delaySweep, max(results.ferDelay, 1e-3), "-o");
grid on; xlabel("锟节讹拷锟斤拷时锟斤拷 (ms)"); ylabel("FER");
title(sprintf("FER锟紺锟洁径时锟接ｏ拷SNR %d dB锟斤拷", o.snrSweep));

nexttile;
plot(results.cfoSweep, results.syncSuccess, "-o");
grid on; xlabel("锟截诧拷频偏 (Hz)"); ylabel("同锟斤拷锟缴癸拷锟斤拷");
title(sprintf("同锟斤拷锟缴癸拷锟绞–频偏锟斤拷SNR %d dB锟斤拷", o.snrSweep));
ylim([0 1.05]);

nexttile;
plot(real(results.constellationBefore), imag(results.constellationBefore), ...
    ".", "MarkerSize", 8);
grid on; axis equal; xlabel("I"); ylabel("Q"); title("锟斤拷锟斤拷前锟斤拷锟斤拷锟斤拷SNR 12 dB锟斤拷");

nexttile;
plot(real(results.constellationAfter), imag(results.constellationAfter), ...
    ".", "MarkerSize", 8);
grid on; axis equal; xlabel("I"); ylabel("Q"); title("MMSE-FDE 锟斤拷锟斤拷锟斤拷锟斤拷SNR 12 dB锟斤拷");

exportgraphics(fig, fullfile(o.outputDir, "benchmark_basic_scfde.png"), ...
    "Resolution", 180);
close(fig);
end
