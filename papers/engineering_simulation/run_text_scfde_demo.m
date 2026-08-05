function result = run_text_scfde_demo(inputText, options)
%RUN_TEXT_SCFDE_DEMO End-to-end text simulation for the embedded SC-FDE modem.
%   RESULT = RUN_TEXT_SCFDE_DEMO("hello") encodes UTF-8 text into one or
%   more modem frames, sends each frame through a time-varying multipath
%   passband channel, and recovers the text after synchronization, LS
%   channel estimation, MMSE FDE, hard symbol decisions, and CRC checking.
%
%   RESULT = RUN_TEXT_SCFDE_DEMO(TEXT, OPTIONS) accepts these fields:
%     snrDb          - passband SNR in dB (default 18)
%     pathDelaysMs   - path delays in ms (default [0 0.5 1.25 2.25])
%     pathGains      - complex path gains
%     dopplerHz      - per-path baseband Doppler shifts in Hz
%     leadingSamples - leading silence at 48 kHz (default 173)
%     maxFrameAttempts - CRC-triggered attempts per frame (default 3)
%     syncThreshold  - normalized UW threshold (default 0.18)
%     channelTaps    - retained LS channel taps (default 24)
%     txAmplitude    - passband DAC-centered amplitude (default 700)
%     fftSize        - SC-FDE transform size (default 128)
%     uwLength       - unique-word length in symbols (default 32)
%     modulation     - BPSK, QPSK, or 16QAM (default QPSK)
%     symbolRate     - symbols per second (default 4000)
%     carrierHz      - passband carrier frequency (default 12000)
%     txSampleRate   - transmit sample rate (default 96000)
%     rxSampleRate   - receive sample rate (default 48000)
%     pulseShape     - rrc or rectangular (default rrc)
%     rrcRolloff     - RRC roll-off factor (default 0.35)
%     rrcSpanSymbols - even RRC span in symbols (default 8)
%     makePlot       - create and export a diagnostic figure (default true)
%     randomSeed     - deterministic random seed (default 20260723)

if nargin < 1 || strlength(string(inputText)) == 0
    inputText = "SC-FDE underwater modem";
end
if nargin < 2
    options = struct();
end

cfg = make_config(options);
rng(cfg.randomSeed, "twister");
inputText = string(inputText);
txBytes = uint8(unicode2native(char(inputText), "UTF-8"));
if isempty(txBytes)
    txBytes = uint8([]);
end

frameCount = max(1, ceil(numel(txBytes) / cfg.maxPayload));
rxBytes = uint8([]);
frameResults = repmat(empty_frame_result(), 1, frameCount);

fprintf("\n===== SC-FDE text end-to-end simulation =====\n");
fprintf("TX text: %s\n", inputText);
fprintf("UTF-8 bytes: %d, frames: %d, SNR: %.1f dB\n", ...
    numel(txBytes), frameCount, cfg.snrDb);

for frameIndex = 1:frameCount
    firstByte = (frameIndex - 1) * cfg.maxPayload + 1;
    lastByte = min(frameIndex * cfg.maxPayload, numel(txBytes));
    if firstByte <= lastByte
        payload = txBytes(firstByte:lastByte);
    else
        payload = uint8([]);
    end

    packet = build_packet(payload, mod(frameIndex - 1, 256), cfg.packetBytes);
    [dataSymbols, modulationTrace] = modulation_map(packet, cfg.modulation, cfg);
    uw = exp(-1j * pi * (0:cfg.uwLength-1).^2 / cfg.uwLength);
    % UW1 acquires the frame, UW2 estimates the channel, and UW3 closes
    % the [data, UW3] SC-FDE block to provide cyclic multipath protection.
    frameSymbols = [uw, uw, dataSymbols, uw];
    frameResult = empty_frame_result();
    for attempt = 1:cfg.maxFrameAttempts
        [adcSamples, channelInfo] = passband_channel(frameSymbols, cfg);
        frameResult = receive_frame(adcSamples, uw, cfg);
        frameResult.channel = channelInfo;
        frameResult.attempts = attempt;
        if frameResult.valid
            break;
        end
    end
    frameResult.txPacket = packet;
    frameResult.txPacketBits = modulationTrace.packetBits;
    frameResult.txCodeBits = modulationTrace.codeBits;
    frameResult.txSymbolLabels = modulationTrace.symbolLabels;
    if numel(frameResult.rxPacket) == numel(packet)
        different = bitxor(frameResult.rxPacket, packet);
        frameResult.bitErrors = 0;
        for bitPosition = 1:8
            frameResult.bitErrors = frameResult.bitErrors + ...
                sum(bitget(different, bitPosition));
        end
        frameResult.byteErrors = sum(frameResult.rxPacket ~= packet);
    end
    frameResult.txBits = packet_to_bits(packet);
    frameResult.txDataSymbols = dataSymbols;
    frameResult.txFrameSymbols = frameSymbols;
    frameResults(frameIndex) = frameResult;

    if frameResult.valid
        rxBytes = [rxBytes, frameResult.payload]; %#ok<AGROW>
        fprintf("Frame %d: PASS, seq=%d, payload=%d bytes, attempts=%d, sync=%.3f, CFO=%.2f Hz\n", ...
            frameIndex, frameResult.sequence, numel(frameResult.payload), ...
            frameResult.attempts, frameResult.syncMetric, ...
            frameResult.frequencyOffsetHz);
    else
        fprintf("Frame %d: FAIL, sync=%.3f, header=%d, CRC=%d\n", ...
            frameIndex, frameResult.syncMetric, frameResult.headerOk, ...
            frameResult.crcOk);
    end
end

allFramesValid = all([frameResults.valid]);
if allFramesValid
    rxText = string(native2unicode(rxBytes, "UTF-8"));
else
    rxText = "<frame error: text reconstruction incomplete>";
end

result.inputText = inputText;
result.outputText = rxText;
result.txBytes = txBytes;
result.rxBytes = rxBytes;
result.frames = frameResults;
result.success = allFramesValid && isequal(txBytes, rxBytes) && (inputText == rxText);
result.config = cfg;

fprintf("RX text: %s\n", rxText);
fprintf("End-to-end result: %s\n", pass_fail(result.success));

if cfg.makePlot
    result.figurePath = make_diagnostic_plot(frameResults(1), cfg);
    result.figurePaths = [result.figurePath, ...
        visualize_text_link_overview(frameResults(1), cfg), ...
        visualize_text_link_stages(frameResults(1), cfg)];
    fprintf("Diagnostic figure: %s\n", result.figurePath);
else
    result.figurePath = "";
    result.figurePaths = strings(1, 0);
end

if ~result.success
    warning("SCFDE:TextRecoveryFailed", ...
        "The received text does not match the transmitted text.");
end
end

function cfg = make_config(options)
cfg.fftSize = get_option(options, "fftSize", 128);
cfg.uwLength = get_option(options, "uwLength", 32);
cfg.modulation = upper(string(get_option(options, "modulation", "QPSK")));
cfg.symbolRate = get_option(options, "symbolRate", 4000);
cfg.txSampleRate = get_option(options, "txSampleRate", 96000);
cfg.rxSampleRate = get_option(options, "rxSampleRate", 48000);
cfg.carrierHz = get_option(options, "carrierHz", 12000);
cfg.pulseShape = lower(string(get_option(options, "pulseShape", "rrc")));
cfg.rrcRolloff = get_option(options, "rrcRolloff", 0.35);
cfg.rrcSpanSymbols = get_option(options, "rrcSpanSymbols", 8);
[~, cfg.bitsPerSymbol] = modulation_constellation(cfg.modulation);
cfg.dataSymbols = cfg.fftSize - cfg.uwLength;
cfg.frameSymbols = cfg.fftSize + 2*cfg.uwLength;
cfg.ldpcN = 192;
cfg.ldpcK = 128;
cfg.ldpcRate = cfg.ldpcK / cfg.ldpcN;
defaultLdpc = cfg.modulation == "QPSK" && cfg.dataSymbols == 96;
cfg.ldpcEnabled = get_option(options, "ldpcEnabled", defaultLdpc);
if cfg.ldpcEnabled
    assert(cfg.modulation == "QPSK" && cfg.dataSymbols == 96, ...
        "The embedded LDPC mode currently requires QPSK and 96 data symbols.");
    assert(cfg.ldpcN > cfg.ldpcK && cfg.ldpcK > 0, ...
        "LDPC parameters must satisfy n > k > 0.");
    assert(cfg.dataSymbols * cfg.bitsPerSymbol == cfg.ldpcN, ...
        "The modulation block must carry exactly one LDPC codeword.");
    cfg.packetBytes = cfg.ldpcK / 8;
else
    cfg.packetBytes = cfg.dataSymbols * cfg.bitsPerSymbol / 8;
end
cfg.maxPayload = cfg.packetBytes - 6;
cfg.txSamplesPerSymbol = cfg.txSampleRate / cfg.symbolRate;
cfg.rxSamplesPerSymbol = cfg.rxSampleRate / cfg.symbolRate;
cfg.channelTaps = get_option(options, "channelTaps", 28);
cfg.equalizerDomain = lower(string(get_option(options, "equalizerDomain", "frequency")));
cfg.tdeTaps = get_option(options, "tdeTaps", 24);
cfg.tdeDelay = get_option(options, "tdeDelay", 12);
cfg.syncThreshold = get_option(options, "syncThreshold", 0.18);
cfg.txAmplitude = get_option(options, "txAmplitude", 700);
cfg.snrDb = get_option(options, "snrDb", 18);
cfg.channelModel = string(get_option(options, "channelModel", "analytic"));
cfg.bellhopInfo = struct();
if cfg.channelModel == "bellhop"
    bellhopOptions = options;
    bellhopOptions.txSampleRate = cfg.txSampleRate;
    bellhopOptions.carrierHz = cfg.carrierHz;
    [cfg.pathDelaysMs, cfg.pathGains, cfg.bellhopInfo] = ...
        scfde_bellhop_channel(bellhopOptions);
elseif cfg.channelModel == "analytic"
    cfg.pathDelaysMs = get_option(options, "pathDelaysMs", [0, 0.5, 1.0, 2.0]);
    cfg.pathGains = get_option(options, "pathGains", ...
        [1.0, 0.25*exp(1j*0.7), 0.12*exp(-1j*1.1), 0.06*exp(1j*2.0)]);
else
    error("SCFDE:UnknownChannel", "Unknown channelModel: %s", cfg.channelModel);
end
requestedDoppler = get_option(options, "dopplerHz", 8.0);
if isscalar(requestedDoppler)
    cfg.dopplerHz = repmat(requestedDoppler, size(cfg.pathDelaysMs));
elseif numel(requestedDoppler) == numel(cfg.pathDelaysMs)
    cfg.dopplerHz = reshape(requestedDoppler, size(cfg.pathDelaysMs));
elseif all(requestedDoppler == requestedDoppler(1))
    cfg.dopplerHz = repmat(requestedDoppler(1), size(cfg.pathDelaysMs));
else
    error("SCFDE:DopplerSize", ...
        "dopplerHz must be scalar or match the selected channel path count.");
end
cfg.leadingSamples = get_option(options, "leadingSamples", 173);
cfg.maxFrameAttempts = get_option(options, "maxFrameAttempts", 3);
cfg.makePlot = get_option(options, "makePlot", true);
cfg.randomSeed = get_option(options, "randomSeed", 20260723);

assert(cfg.fftSize >= 32 && mod(log2(cfg.fftSize), 1) == 0, ...
    "fftSize must be a power of two and at least 32.");
assert(cfg.uwLength >= 8 && cfg.uwLength < cfg.fftSize && ...
    mod(log2(cfg.uwLength), 1) == 0, ...
    "uwLength must be a power of two smaller than fftSize.");
assert(mod(cfg.packetBytes, 1) == 0 && cfg.maxPayload >= 1, ...
    "The selected FFT, UW, and modulation do not produce a valid byte packet.");
assert(mod(cfg.txSamplesPerSymbol, 1) == 0 && ...
    mod(cfg.rxSamplesPerSymbol, 1) == 0, ...
    "Both sample rates must be integer multiples of symbolRate.");
assert(cfg.txSampleRate >= cfg.rxSampleRate && ...
    mod(cfg.txSampleRate / cfg.rxSampleRate, 1) == 0, ...
    "txSampleRate/rxSampleRate must be a positive integer.");
assert(cfg.carrierHz > 0 && ...
    (cfg.carrierHz + cfg.symbolRate) < cfg.rxSampleRate/2, ...
    "carrierHz plus symbolRate must stay below the RX Nyquist frequency.");
assert(numel(cfg.pathDelaysMs) == numel(cfg.pathGains), ...
    "pathDelaysMs and pathGains must have equal lengths.");
assert(numel(cfg.pathDelaysMs) == numel(cfg.dopplerHz), ...
    "pathDelaysMs and dopplerHz must have equal lengths.");
assert(all(cfg.pathDelaysMs >= 0), "Path delays must be nonnegative.");
assert(max(cfg.pathDelaysMs) < cfg.uwLength / cfg.symbolRate * 1000, ...
    "Maximum path delay must be shorter than the UW duration.");
assert(cfg.maxFrameAttempts >= 1 && mod(cfg.maxFrameAttempts, 1) == 0, ...
    "maxFrameAttempts must be a positive integer.");
assert(cfg.channelTaps >= 1 && cfg.channelTaps <= cfg.uwLength && ...
    mod(cfg.channelTaps, 1) == 0, ...
    "channelTaps must be an integer from 1 through the UW length.");
assert(any(cfg.equalizerDomain == ["frequency", "time"]), ...
    "equalizerDomain must be frequency or time.");
assert(cfg.tdeTaps >= 1 && mod(cfg.tdeTaps, 1) == 0 && ...
    cfg.tdeDelay >= 0 && mod(cfg.tdeDelay, 1) == 0 && ...
    cfg.tdeDelay < cfg.tdeTaps, ...
    "tdeTaps must be positive and tdeDelay must be smaller than tdeTaps.");
assert(cfg.syncThreshold > 0 && cfg.syncThreshold < 1, ...
    "syncThreshold must be between zero and one.");
assert(cfg.txAmplitude > 0 && cfg.txAmplitude <= 1400, ...
    "txAmplitude must be in the interval (0, 1400].");
assert(any(cfg.pulseShape == ["rrc", "rectangular"]), ...
    "pulseShape must be rrc or rectangular.");
assert(cfg.rrcRolloff >= 0 && cfg.rrcRolloff <= 1, ...
    "rrcRolloff must be in the interval [0, 1].");
assert(cfg.rrcSpanSymbols >= 2 && mod(cfg.rrcSpanSymbols, 2) == 0, ...
    "rrcSpanSymbols must be a positive even integer of at least 2.");
end

function value = get_option(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function packet = build_packet(payload, sequence, packetBytes)
packet = zeros(1, packetBytes, "uint8");
packet(1:4) = uint8([hex2dec("A5"), hex2dec("5A"), ...
    numel(payload), sequence]);
packet(5:4+numel(payload)) = payload;
crcIndex = packetBytes - 1;
check = crc16_ccitt(packet(1:crcIndex-1));
packet(crcIndex) = uint8(bitshift(check, -8));
packet(crcIndex+1) = uint8(bitand(check, uint16(255)));
end

function [symbols, trace] = modulation_map(packet, modulation, cfg)
packetBits = packet_to_bits(packet);
bits = packetBits;
if cfg.ldpcEnabled
    bits = ldpc_encode(bits, cfg);
end
[constellation, bitsPerSymbol] = modulation_constellation(modulation);
bitGroups = reshape(bits, bitsPerSymbol, []);
labels = sum(double(bitGroups) .* (2.^(0:bitsPerSymbol-1)).', 1);
symbols = constellation(labels + 1);
trace.packetBits = packetBits;
trace.codeBits = bits;
trace.symbolLabels = labels;
end

function [constellation, bitsPerSymbol] = modulation_constellation(modulation)
switch upper(string(modulation))
    case "BPSK"
        bitsPerSymbol = 1;
        constellation = [-1, 1];
    case "QPSK"
        bitsPerSymbol = 2;
        constellation = [-1-1j, 1-1j, -1+1j, 1+1j];
    case "16QAM"
        bitsPerSymbol = 4;
        labels = 0:15;
        levels = [-3, -1, 3, 1];
        inPhase = levels(bitand(labels, 3) + 1);
        quadrature = levels(bitshift(labels, -2) + 1);
        constellation = (inPhase + 1j*quadrature) / sqrt(10);
    otherwise
        error("SCFDE:Modulation", "Unsupported modulation: %s", modulation);
end
end

function bits = packet_to_bits(packet)
bits = false(1, 8*numel(packet));
for bitIndex = 0:numel(bits)-1
    bits(bitIndex+1) = bitget(packet(floor(bitIndex/8)+1), mod(bitIndex, 8)+1);
end
end

function [adcSamples, info] = passband_channel(frameSymbols, cfg)
txFilter = [];
if cfg.pulseShape == "rrc"
    guardSymbols = cfg.rrcSpanSymbols / 2;
    guardedSymbols = [zeros(1, guardSymbols), frameSymbols, ...
        zeros(1, guardSymbols)];
    upsampled = zeros(1, numel(guardedSymbols) * cfg.txSamplesPerSymbol);
    upsampled(1:cfg.txSamplesPerSymbol:end) = guardedSymbols;
    txFilter = root_raised_cosine(cfg.rrcRolloff, ...
        cfg.rrcSpanSymbols, cfg.txSamplesPerSymbol);
    txBaseband = conv(upsampled, txFilter, "same");
else
    upsampled = repelem(frameSymbols, cfg.txSamplesPerSymbol);
    txBaseband = upsampled;
end
delaySamples = round(cfg.pathDelaysMs * 1e-3 * cfg.txSampleRate);
channelLength = numel(txBaseband) + max(delaySamples);
rxBaseband = complex(zeros(1, channelLength));
t = (0:channelLength-1) / cfg.txSampleRate;

for pathIndex = 1:numel(delaySamples)
    delayed = complex(zeros(1, channelLength));
    first = delaySamples(pathIndex) + 1;
    delayed(first:first+numel(txBaseband)-1) = txBaseband;
    fading = cfg.pathGains(pathIndex) * ...
        exp(1j * 2*pi*cfg.dopplerHz(pathIndex)*t);
    rxBaseband = rxBaseband + delayed .* fading;
end

carrier = exp(1j * 2*pi*cfg.carrierHz*t);
passband96k = cfg.txAmplitude * real(rxBaseband .* carrier);
decimation = cfg.txSampleRate / cfg.rxSampleRate;
passband48k = passband96k(1:decimation:end);
cleanCapture = [zeros(1, cfg.leadingSamples), passband48k, zeros(1, 512)];
activePower = mean(passband48k.^2);
noiseVariance = activePower / 10^(cfg.snrDb/10);
noisyCapture = cleanCapture + sqrt(noiseVariance) * randn(size(cleanCapture));
adcSamples = uint16(min(4095, max(0, round(2048 + noisyCapture))));

info.cleanCapture = cleanCapture;
info.noisyCapture = double(adcSamples) - 2048;
info.txUpsampled = upsampled;
info.txFilter = txFilter;
info.txBaseband = txBaseband;
info.txPassband96k = passband96k;
info.rxPassband48k = passband48k;
info.channelBaseband = rxBaseband;
info.pathDelaySamples = delaySamples;
end

function taps = root_raised_cosine(rolloff, spanSymbols, samplesPerSymbol)
halfLength = spanSymbols * samplesPerSymbol / 2;
time = (-halfLength:halfLength) / samplesPerSymbol;
taps = zeros(size(time));
for index = 1:numel(time)
    value = time(index);
    if abs(value) < 1e-12
        taps(index) = 1 - rolloff + 4 * rolloff / pi;
    elseif rolloff > 0 && abs(abs(value) - 1 / (4 * rolloff)) < 1e-12
        taps(index) = rolloff / sqrt(2) * ...
            ((1 + 2 / pi) * sin(pi / (4 * rolloff)) + ...
            (1 - 2 / pi) * cos(pi / (4 * rolloff)));
    else
        numerator = sin(pi * value * (1 - rolloff)) + ...
            4 * rolloff * value * cos(pi * value * (1 + rolloff));
        denominator = pi * value * (1 - (4 * rolloff * value)^2);
        taps(index) = numerator / denominator;
    end
end
taps = taps / sqrt(sum(taps.^2));
end

function result = receive_frame(adcSamples, uw, cfg)
x = double(adcSamples) - mean(double(adcSamples));
bestMetric = 0;
bestStart = 0;
bestSymbols = complex(zeros(1, cfg.frameSymbols));
metricSamples = [];
metricValues = [];
n = 0:numel(x)-1;
lo = exp(-1j * 2*pi*cfg.carrierHz*n/cfg.rxSampleRate);
mixed = x .* lo;
downconverted = mixed;
if cfg.pulseShape == "rrc"
    rxFilter = root_raised_cosine(cfg.rrcRolloff, ...
        cfg.rrcSpanSymbols, cfg.rxSamplesPerSymbol);
    mixed = conv(mixed, rxFilter, "same");
end

for phase = 0:cfg.rxSamplesPerSymbol-1
    symbolCount = floor((numel(x)-phase) / cfg.rxSamplesPerSymbol);
    if cfg.pulseShape == "rrc"
        sampleIndices = phase + 1 + ...
            (0:symbolCount-1) * cfg.rxSamplesPerSymbol;
        symbols = mixed(sampleIndices);
    else
        symbols = complex(zeros(1, symbolCount));
        for symbolIndex = 1:symbolCount
            first = phase + (symbolIndex-1)*cfg.rxSamplesPerSymbol + 1;
            range = first:first+cfg.rxSamplesPerSymbol-1;
            symbols(symbolIndex) = sum(mixed(range));
        end
    end

    for offset = 0:symbolCount-cfg.frameSymbols
        candidate = symbols(offset+1:offset+2*cfg.uwLength);
        metric = uw_sync_metric(candidate, uw);
        sampleStart = phase + offset*cfg.rxSamplesPerSymbol;
        metricSamples(end+1) = sampleStart; %#ok<AGROW>
        metricValues(end+1) = metric; %#ok<AGROW>
        if metric > bestMetric
            bestMetric = metric;
            bestStart = sampleStart;
            bestSymbols = symbols(offset+1:offset+cfg.frameSymbols);
        end
    end
end

result = empty_frame_result();
result.adcSamples = adcSamples;
result.syncMetric = bestMetric;
result.frameStartSample = bestStart;
result.metricSamples = metricSamples;
result.metricValues = metricValues;
result.dcRemovedSamples = x;
result.downconvertedSamples = downconverted;
result.matchedFilterSamples = mixed;
result.synchronizedSymbols = bestSymbols;
if bestMetric < cfg.syncThreshold
    return;
end

firstUw = bestSymbols(1:cfg.uwLength);
secondUw = bestSymbols(cfg.uwLength+1:2*cfg.uwLength);
thirdStart = 2*cfg.uwLength + cfg.dataSymbols + 1;
thirdUw = bestSymbols(thirdStart:thirdStart+cfg.uwLength-1);
startCross = sum(secondUw .* conj(firstUw));
endCross = sum(thirdUw .* conj(secondUw));
startOmega = angle(startCross) / cfg.uwLength;
endOmega = angle(endCross) / (cfg.uwLength + cfg.dataSymbols);
sampleIndex = 0:cfg.frameSymbols-1;
omegaSlope = (endOmega - startOmega) / max(cfg.frameSymbols-1, 1);
phaseCorrection = startOmega * sampleIndex + 0.5 * omegaSlope * sampleIndex.^2;
corrected = bestSymbols .* exp(-1j*phaseCorrection);
result.phaseCorrection = phaseCorrection;
result.correctedSymbols = corrected;
result.frequencyOffsetHz = 0.5*(startOmega + endOmega) * cfg.symbolRate / (2*pi);

uwSpectrum = fft(uw);
receivedUw = fft(corrected(cfg.uwLength+1:2*cfg.uwLength));
channel32 = receivedUw .* conj(uwSpectrum) ./ (abs(uwSpectrum).^2 + eps);
impulse32 = ifft(channel32);
impulse32(cfg.channelTaps+1:end) = 0;
channelResponse = fft([impulse32, zeros(1, cfg.fftSize-cfg.uwLength)]);
result.channelImpulse = impulse32;

% Ignore the unprotected beginning of the first UW when estimating noise.
steadyStart = min(cfg.channelTaps + 1, cfg.uwLength - 3);
steadyRange = steadyStart:cfg.uwLength;
differenceEnergy = 0.5 * mean(abs(corrected(steadyRange) - ...
    corrected(cfg.uwLength+steadyRange)).^2);
regularization = differenceEnergy * cfg.fftSize / 2;
regularization = max(regularization, ...
    sum(abs(channelResponse).^2) * 0.01 / cfg.fftSize);
result.regularization = regularization;

block = corrected(2*cfg.uwLength+1:2*cfg.uwLength+cfg.fftSize);
blockSpectrum = fft(block);
result.receivedFdeBlock = block;
result.receivedBlockSpectrum = blockSpectrum;
if cfg.equalizerDomain == "time"
    equalized = time_domain_mmse_equalize(corrected, impulse32, uw, cfg, regularization);
else
    equalized = ifft(blockSpectrum .* conj(channelResponse) ./ ...
        (abs(channelResponse).^2 + regularization));
    tailUw = equalized(cfg.dataSymbols+1:cfg.fftSize);
    residualGain = sum(tailUw .* conj(uw)) / (sum(abs(uw).^2) + eps);
    if abs(residualGain) > 1e-6
        equalized = equalized / residualGain;
    end
end
[packet, demodTrace] = modulation_demod( ...
    equalized(1:cfg.dataSymbols), cfg.modulation, cfg);

% One conservative decision-directed update helps when strong paths make
% the UW-only LS estimate slightly stale or truncate a long impulse response.
if cfg.equalizerDomain == "frequency" && cfg.modulation == "QPSK"
    provisional = sign(real(equalized(1:cfg.dataSymbols))) + ...
        1j*sign(imag(equalized(1:cfg.dataSymbols)));
    provisional(provisional == 0) = 1;
    provisionalBlock = [provisional, uw];
    provisionalSpectrum = fft(provisionalBlock);
    ddResponse = blockSpectrum .* conj(provisionalSpectrum) ./ ...
        (abs(provisionalSpectrum).^2 + regularization);
    ddResponse = 0.65*channelResponse + 0.35*ddResponse;
    ddEqualized = ifft(blockSpectrum .* conj(ddResponse) ./ ...
        (abs(ddResponse).^2 + regularization));
    ddTail = ddEqualized(cfg.dataSymbols+1:cfg.fftSize);
    ddGain = sum(ddTail .* conj(uw)) / (sum(abs(uw).^2) + eps);
    if abs(ddGain) > 1e-6
        ddEqualized = ddEqualized / ddGain;
    end
    [ddPacket, ddTrace] = modulation_demod( ...
        ddEqualized(1:cfg.dataSymbols), cfg.modulation, cfg);
    if packet_quality(ddPacket, cfg) && ~packet_quality(packet, cfg)
        packet = ddPacket;
        equalized = ddEqualized;
        channelResponse = ddResponse;
        demodTrace = ddTrace;
    end
end

result.equalizedSymbols = equalized(1:cfg.dataSymbols);
result.channelResponse = channelResponse;
result.demodulation = demodTrace;
result.rxPacket = packet;
result.headerOk = packet(1) == hex2dec("A5") && ...
    packet(2) == hex2dec("5A") && packet(3) <= cfg.maxPayload;
if result.headerOk
    payloadLength = double(packet(3));
    result.sequence = double(packet(4));
    result.payload = packet(5:4+payloadLength);
    crcIndex = cfg.packetBytes - 1;
    receivedCrc = bitor(bitshift(uint16(packet(crcIndex)), 8), ...
        uint16(packet(crcIndex+1)));
    result.crcOk = crc16_ccitt(packet(1:crcIndex-1)) == receivedCrc;
end
result.valid = result.headerOk && result.crcOk;
end

function valid = packet_quality(packet, cfg)
valid = numel(packet) == cfg.packetBytes && ...
    packet(1) == hex2dec("A5") && packet(2) == hex2dec("5A") && ...
    packet(3) <= cfg.maxPayload;
if valid
    crcIndex = cfg.packetBytes - 1;
    receivedCrc = bitor(bitshift(uint16(packet(crcIndex)), 8), ...
        uint16(packet(crcIndex+1)));
    valid = crc16_ccitt(packet(1:crcIndex-1)) == receivedCrc;
end
end

function data = time_domain_mmse_equalize(corrected, impulse, uw, cfg, regularization)
% Design a causal FIR MMSE equalizer for the UW-estimated impulse response.
h = impulse(1:cfg.channelTaps).';
equalizerLength = cfg.tdeTaps;
convolutionLength = numel(h) + equalizerLength - 1;
convolutionMatrix = zeros(convolutionLength, equalizerLength);
for tap = 1:equalizerLength
    convolutionMatrix(tap:tap+numel(h)-1, tap) = h;
end
target = zeros(convolutionLength, 1);
target(cfg.tdeDelay + 1) = 1;
noiseFloor = max(regularization / cfg.fftSize, 0.005 * sum(abs(h).^2));
equalizer = (convolutionMatrix' * convolutionMatrix + ...
    noiseFloor * eye(equalizerLength)) \ (convolutionMatrix' * target);

% UW2 precedes DATA, so it supplies the FIR history needed for the first
% payload symbol. The available tail UW calibrates residual complex gain.
received = corrected(cfg.uwLength+1:end);
output = filter(equalizer, 1, received);
firstData = cfg.uwLength + cfg.tdeDelay + 1;
lastData = firstData + cfg.dataSymbols - 1;
data = output(firstData:lastData);
tail = output(lastData+1:end);
if ~isempty(tail)
    reference = uw(1:numel(tail));
    gain = sum(tail .* conj(reference)) / (sum(abs(reference).^2) + eps);
    if abs(gain) > 1e-6
        data = data / gain;
    end
end
end

function metric = uw_sync_metric(symbols, uw)
first = sum(symbols(1:numel(uw)) .* conj(uw));
second = sum(symbols(numel(uw)+1:2*numel(uw)) .* conj(uw));
energy = sum(abs(symbols).^2);
metric = (abs(first)^2 + abs(second)^2) / (numel(uw)*energy + eps);
end

function [packet, trace] = modulation_demod(symbols, modulation, cfg)
[constellation, bitsPerSymbol] = modulation_constellation(modulation);
trace.symbols = symbols;
trace.llr = [];
trace.codeHardBits = false(1, 0);
trace.decodedBits = false(1, 0);
if cfg.ldpcEnabled
    llr = zeros(1, 192);
    llr(1:2:end) = -real(symbols(:));
    llr(2:2:end) = -imag(symbols(:));
    bits = ldpc_decode(llr, 10, cfg);
    trace.llr = llr;
    trace.codeHardBits = llr < 0;
    trace.decodedBits = bits;
    packet = bits_to_bytes(bits);
    return;
end
distance = abs(symbols(:) - constellation).^2;
[~, nearest] = min(distance, [], 2);
labels = nearest - 1;
bits = false(1, bitsPerSymbol*numel(symbols));
for bitPosition = 1:bitsPerSymbol
    bits(bitPosition:bitsPerSymbol:end) = bitget(labels, bitPosition);
end
packet = zeros(1, numel(bits)/8, "uint8");
for bitIndex = 0:numel(bits)-1
    if bits(bitIndex+1)
        byteIndex = floor(bitIndex/8) + 1;
        packet(byteIndex) = bitset(packet(byteIndex), mod(bitIndex, 8)+1);
    end
end
trace.decodedBits = bits;
end

function codeBits = ldpc_encode(infoBits, cfg)
infoBits = logical(infoBits(:).');
assert(cfg.ldpcN == 192 && cfg.ldpcK == 128, ...
    "This sparse parity construction implements only LDPC(192,128).");
assert(numel(infoBits) == cfg.ldpcK, ...
    "LDPC information block must contain k=%d bits.", cfg.ldpcK);
parityBits = cfg.ldpcN - cfg.ldpcK;
codeBits = false(1, cfg.ldpcN);
codeBits(1:cfg.ldpcK) = infoBits;
for check = 0:parityBits-1
    value = false;
    group = double(check >= 32);
    row = mod(check, 32);
    shifts = [0 5 11 17; 1 7 13 19];
    for block = 0:3
        index = block*32 + mod(row + shifts(group+1, block+1), 32) + 1;
        value = xor(value, infoBits(index));
    end
    codeBits(cfg.ldpcK + 1 + check) = value;
end
end

function infoBits = ldpc_decode(llr, iterations, cfg)
llr = double(llr(:));
assert(numel(llr) == cfg.ldpcN, ...
    "LDPC decoder requires n=%d LLR values.", cfg.ldpcN);
parityBits = cfg.ldpcN - cfg.ldpcK;
variable = llr;
messages = zeros(parityBits, 5);
shifts = [0 5 11 17; 1 7 13 19];
for iteration = 1:iterations
    for check = 0:parityBits-1
        group = double(check >= 32);
        row = mod(check, 32);
        indices = zeros(1, 5);
        for block = 0:3
            indices(block+1) = block*32 + mod(row + shifts(group+1, block+1), 32) + 1;
        end
        indices(5) = cfg.ldpcK + 1 + check;
        values = zeros(1, 5);
        for edge = 1:5
            values(edge) = variable(indices(edge)) - messages(check+1, edge);
        end
        signs = sign(values); signs(signs == 0) = 1;
        magnitude = abs(values);
        [minimum, minIndex] = min(magnitude);
        magnitude(minIndex) = inf;
        second = min(magnitude);
        product = prod(signs);
        for edge = 1:5
            magnitudeOut = minimum;
            if edge == minIndex, magnitudeOut = second; end
            messages(check+1, edge) = 0.8 * product * signs(edge) * magnitudeOut;
            variable(indices(edge)) = values(edge) + messages(check+1, edge);
        end
    end
    hard = variable < 0;
    syndrome = false;
    for check = 0:parityBits-1
        group = double(check >= 32); row = mod(check, 32);
        parity = hard(cfg.ldpcK + 1 + check);
        for block = 0:3
            index = block*32 + mod(row + shifts(group+1, block+1), 32) + 1;
            parity = xor(parity, hard(index));
        end
        syndrome = syndrome || parity;
    end
    if ~syndrome
        break;
    end
end
infoBits = logical(variable(1:cfg.ldpcK) < 0);
end

function bytes = bits_to_bytes(bits)
bits = logical(bits(:).');
bytes = zeros(1, floor(numel(bits)/8), "uint8");
for bitIndex = 0:(numel(bytes)*8-1)
    if bits(bitIndex+1)
        bytes(floor(bitIndex/8)+1) = bitset(bytes(floor(bitIndex/8)+1), mod(bitIndex, 8)+1);
    end
end
end

function crc = crc16_ccitt(data)
crc = uint16(65535);
polynomial = uint16(hex2dec("1021"));
for value = data
    crc = bitxor(crc, bitshift(uint16(value), 8));
    for bitIndex = 1:8 %#ok<NASGU>
        if bitand(crc, uint16(hex2dec("8000"))) ~= 0
            crc = bitxor(bitshift(crc, 1), polynomial);
        else
            crc = bitshift(crc, 1);
        end
    end
end
end

function result = empty_frame_result()
result.valid = false;
result.headerOk = false;
result.crcOk = false;
result.sequence = 0;
result.payload = uint8([]);
result.syncMetric = 0;
result.frameStartSample = 0;
result.frequencyOffsetHz = 0;
result.attempts = 0;
result.equalizedSymbols = complex([]);
result.channelResponse = complex([]);
result.metricSamples = [];
result.metricValues = [];
result.dcRemovedSamples = [];
result.downconvertedSamples = complex([]);
result.matchedFilterSamples = complex([]);
result.synchronizedSymbols = complex([]);
result.phaseCorrection = [];
result.correctedSymbols = complex([]);
result.channelImpulse = complex([]);
result.regularization = NaN;
result.receivedFdeBlock = complex([]);
result.receivedBlockSpectrum = complex([]);
result.demodulation = struct();
result.adcSamples = uint16([]);
result.channel = struct();
result.txPacket = uint8([]);
result.rxPacket = uint8([]);
result.txBits = false(1, 0);
result.txPacketBits = false(1, 0);
result.txCodeBits = false(1, 0);
result.txSymbolLabels = zeros(1, 0);
result.txDataSymbols = complex([]);
result.txFrameSymbols = complex([]);
result.bitErrors = NaN;
result.byteErrors = NaN;
end

function label = pass_fail(success)
if success
    label = "PASS";
else
    label = "FAIL";
end
end

function figurePath = make_diagnostic_plot(frameResult, cfg)
resultDir = fullfile(fileparts(mfilename("fullpath")), "results");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end
figurePath = fullfile(resultDir, "text_end_to_end_diagnostics.png");

fig = figure("Color", "w", "Position", [100, 100, 1180, 760]);
set(fig, "DefaultAxesFontName", "Microsoft YaHei", ...
    "DefaultTextFontName", "Microsoft YaHei");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile;
sampleCount = min(1200, numel(frameResult.channel.noisyCapture));
plot((0:sampleCount-1)/cfg.rxSampleRate*1000, ...
    frameResult.channel.noisyCapture(1:sampleCount), "LineWidth", 0.8);
grid on;
xlabel("时间（ms）");
ylabel("去中心后的 ADC 幅度");
title("接收端 12 kHz 通带波形");

nexttile;
[sortedSamples, order] = sort(frameResult.metricSamples);
plot(sortedSamples, frameResult.metricValues(order), "LineWidth", 1.1);
hold on;
yline(cfg.syncThreshold, "--", "门限");
xline(frameResult.frameStartSample, ":", "检测起点");
grid on;
xlabel("候选帧起始采样点");
ylabel("归一化 UW 同步度量");
title(sprintf("帧同步，峰值 %.3f", frameResult.syncMetric));

nexttile;
plot(real(frameResult.equalizedSymbols), imag(frameResult.equalizedSymbols), ...
    ".", "MarkerSize", 12);
grid on;
axis equal;
xlabel("同相分量");
ylabel("正交分量");
title(sprintf("MMSE-FDE 输出 %s 星座图", cfg.modulation));

nexttile;
frequency = (0:cfg.fftSize-1) * cfg.symbolRate / cfg.fftSize;
plot(frequency, 20*log10(abs(frameResult.channelResponse)+eps), ...
    "LineWidth", 1.1);
grid on;
xlabel("基带频率（Hz）");
ylabel("幅度（dB）");
title("LS 信道估计");

exportgraphics(fig, figurePath, "Resolution", 180);
close(fig);
end
