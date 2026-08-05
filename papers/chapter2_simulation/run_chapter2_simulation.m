function results = run_chapter2_simulation(options)
%RUN_CHAPTER2_SIMULATION Chapter 2 UW and SC-FDE simulation.
% Trend-level reproduction of Figures 2.3-2.8 in Yang Siqi's thesis.
% The thesis does not provide exact channel taps, coding parameters, or
% random seeds. All assumptions added here are listed in README.md.

if nargin < 1
    options = struct();
end

rng(20260722, "twister");

cfg.N = 512;
cfg.Ts_ms = 0.25;
cfg.uwLength = 64;
cfg.structureSnrDb = -2:3:19;
cfg.fig23MaxDopplerHz = 12;
cfg.sequenceSnrDb = -2:2:30;
cfg.berSnrDb = 1:2:19;
cfg.maxDelayMs = [5, 15];
cfg.berMaxDelayMs = [15, 25];
cfg.uwLengths = [32, 48, 64, 128];
cfg.mseTrials = 600;
cfg.berTargetErrors = 200;
cfg.berMaxBits = 1e6;
cfg.berBlocksPerBatch = 100;
cfg = apply_options(cfg, options);

resultDir = cfg.outputDir;
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

fprintf("Running Chapter 2 simulations...\n");

%% Figures 2.4-2.6: UW sequence properties
U = cfg.uwLength;
sequenceNames = ["Chu", "Frank-Zadoff", "Zadoff-Chu"];
sequences = {chu_sequence(U), frank_zadoff_sequence(U), ...
    zadoff_chu_sequence(U, 3)};

fig = figure("Color", "w", "Position", [100, 100, 1280, 940]);
tiledlayout(3, 3, "TileSpacing", "compact", "Padding", "compact");

spectralRipple = zeros(1, numel(sequences));
for i = 1:numel(sequences)
    x = sequences{i};
    X = fft(x);
    centeredMagnitude = abs(X) - mean(abs(X));
    spectralRipple(i) = max(abs(centeredMagnitude));

    nexttile;
    plot(real(x), imag(x), ".", "MarkerSize", 11);
    axis equal;
    grid on;
    xlabel("In-phase");
    ylabel("Quadrature");
    title(sequenceNames(i) + " time-domain constellation");

    nexttile;
    plot(real(X), imag(X), ".", "MarkerSize", 11);
    axis equal;
    grid on;
    xlabel("In-phase");
    ylabel("Quadrature");
    title(sequenceNames(i) + " frequency-domain constellation");

    nexttile;
    stem(0:U-1, centeredMagnitude, ".", "MarkerSize", 6);
    grid on;
    xlabel("FFT bin");
    ylabel("|X[k]| - mean(|X[k]|)");
    title(sprintf("%s spectral ripple (max %.1e)", ...
        sequenceNames(i), spectralRipple(i)));
end
exportgraphics(fig, fullfile(resultDir, "fig2_4_to_2_6_uw_sequences.png"), ...
    "Resolution", 180);
close(fig);

%% Figure 2.3: one-UW versus two-UW channel estimation
structureMseStatic = zeros(numel(cfg.maxDelayMs), 2, ...
    numel(cfg.structureSnrDb));
structureMseTimeVarying = zeros(size(structureMseStatic));
for channelIndex = 1:numel(cfg.maxDelayMs)
    h = four_path_channel(cfg.maxDelayMs(channelIndex), cfg.Ts_ms);
    for snrIndex = 1:numel(cfg.structureSnrDb)
        snrDb = cfg.structureSnrDb(snrIndex);
        [dualMse, singleMse] = estimate_structure_mse(sequences{2}, h, ...
            snrDb, cfg.mseTrials, cfg.Ts_ms, 0);
        structureMseStatic(channelIndex, :, snrIndex) = ...
            [dualMse, singleMse];

        [dualMse, singleMse] = estimate_structure_mse(sequences{2}, h, ...
            snrDb, cfg.mseTrials, cfg.Ts_ms, cfg.fig23MaxDopplerHz);
        structureMseTimeVarying(channelIndex, :, snrIndex) = ...
            [dualMse, singleMse];
    end
end

export_structure_mse_figure(structureMseStatic, cfg, resultDir, ...
    "fig2_3_block_structure_mse.png", "Static channel");
export_structure_mse_figure(structureMseTimeVarying, cfg, resultDir, ...
    "fig2_3_time_varying_block_structure_mse.png", ...
    sprintf("Time-varying channel, max |f_D| = %g Hz", ...
    cfg.fig23MaxDopplerHz));

% Keep the original variable name as the active Figure 2.3 result.
structureMse = structureMseTimeVarying;

%% Figure 2.7: LS channel-estimation MSE for three UW sequences
sequenceMse = zeros(numel(cfg.maxDelayMs), numel(sequences), ...
    numel(cfg.sequenceSnrDb));
for channelIndex = 1:numel(cfg.maxDelayMs)
    h = four_path_channel(cfg.maxDelayMs(channelIndex), cfg.Ts_ms);
    for sequenceIndex = 1:numel(sequences)
        for snrIndex = 1:numel(cfg.sequenceSnrDb)
            sequenceMse(channelIndex, sequenceIndex, snrIndex) = ...
                estimate_protected_uw_mse(sequences{sequenceIndex}, h, ...
                cfg.sequenceSnrDb(snrIndex), cfg.mseTrials);
        end
    end
end

fig = figure("Color", "w", "Position", [100, 100, 1120, 460]);
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
lineStyles = ["-x", "-^", "-<"];
for channelIndex = 1:numel(cfg.maxDelayMs)
    nexttile;
    hold on;
    for sequenceIndex = 1:numel(sequences)
        semilogy(cfg.sequenceSnrDb, ...
            squeeze(sequenceMse(channelIndex, sequenceIndex, :)), ...
            lineStyles(sequenceIndex), "LineWidth", 1.3, "MarkerSize", 5);
    end
    set(gca, "YScale", "log");
    grid on;
    xlabel("SNR (dB)");
    ylabel("Channel-estimation NMSE");
    title(sprintf("Maximum path delay: %g ms", cfg.maxDelayMs(channelIndex)));
    legend(sequenceNames, "Location", "southwest");
end
exportgraphics(fig, fullfile(resultDir, "fig2_7_uw_sequence_mse.png"), ...
    "Resolution", 180);
close(fig);

%% Figure 2.8: BER versus UW length
ber = zeros(numel(cfg.berMaxDelayMs), numel(cfg.uwLengths), ...
    numel(cfg.berSnrDb));
bitCount = zeros(size(ber));
errorCount = zeros(size(ber));

for channelIndex = 1:numel(cfg.berMaxDelayMs)
    h = four_path_channel(cfg.berMaxDelayMs(channelIndex), cfg.Ts_ms);
    for uwIndex = 1:numel(cfg.uwLengths)
        uw = chu_sequence(cfg.uwLengths(uwIndex));
        for snrIndex = 1:numel(cfg.berSnrDb)
            [berValue, nBits, nErrors] = simulate_sc_fde_ber( ...
                cfg.N, uw, h, cfg.berSnrDb(snrIndex), ...
                cfg.berTargetErrors, cfg.berMaxBits, cfg.berBlocksPerBatch);
            ber(channelIndex, uwIndex, snrIndex) = berValue;
            bitCount(channelIndex, uwIndex, snrIndex) = nBits;
            errorCount(channelIndex, uwIndex, snrIndex) = nErrors;
        end
        fprintf("  BER: %g ms channel, UW length %d complete.\n", ...
            cfg.berMaxDelayMs(channelIndex), cfg.uwLengths(uwIndex));
    end
end

fig = figure("Color", "w", "Position", [100, 100, 1120, 460]);
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
markers = ["-x", "-^", "-<", "-s"];
for channelIndex = 1:numel(cfg.berMaxDelayMs)
    nexttile;
    hold on;
    for uwIndex = 1:numel(cfg.uwLengths)
        semilogy(cfg.berSnrDb, squeeze(ber(channelIndex, uwIndex, :)), ...
            markers(uwIndex), "LineWidth", 1.3, "MarkerSize", 6);
    end
    set(gca, "YScale", "log");
    grid on;
    ylim([1e-6, 1]);
    xlabel("SNR (dB)");
    ylabel("BER");
    title(sprintf("Maximum path delay: %g ms", ...
        cfg.berMaxDelayMs(channelIndex)));
    legend(compose("UW length = %d", cfg.uwLengths), ...
        "Location", "southwest");
end
exportgraphics(fig, fullfile(resultDir, "fig2_8_uw_length_ber.png"), ...
    "Resolution", 180);
close(fig);

save(fullfile(resultDir, "chapter2_results.mat"), "cfg", ...
    "sequenceNames", "spectralRipple", "structureMse", ...
    "structureMseStatic", "structureMseTimeVarying", "sequenceMse", ...
    "ber", "bitCount", "errorCount");

summaryTable = table(sequenceNames.', spectralRipple.', ...
    'VariableNames', {'Sequence', 'MaxSpectralRipple'});
writetable(summaryTable, fullfile(resultDir, "uw_spectral_ripple.csv"));

assert(all(squeeze(ber(:, end, end)) < squeeze(ber(:, 1, end))), ...
    "Expected the longest UW to outperform the shortest UW at high SNR.");

fprintf("Results written to: %s\n", resultDir);

results.config = cfg;
results.outputDir = resultDir;
results.sequenceNames = sequenceNames;
results.spectralRipple = spectralRipple;
results.structureMse = structureMse;
results.sequenceMse = sequenceMse;
results.ber = ber;
results.bitCount = bitCount;
results.errorCount = errorCount;
end

%% Local functions
function cfg = apply_options(cfg, options)
    cfg.outputDir = fullfile(fileparts(mfilename("fullpath")), "results");
    names = fieldnames(options);
    for index = 1:numel(names)
        cfg.(names{index}) = options.(names{index});
    end
end

function export_structure_mse_figure(mseData, cfg, resultDir, ...
        fileName, modelName)
    fig = figure("Color", "w", "Position", [100, 100, 1120, 460]);
    tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
    for channelIndex = 1:numel(cfg.maxDelayMs)
        nexttile;
        semilogy(cfg.structureSnrDb, squeeze(mseData(channelIndex, 1, :)), ...
            "-^", "LineWidth", 1.4, "MarkerSize", 6);
        hold on;
        semilogy(cfg.structureSnrDb, squeeze(mseData(channelIndex, 2, :)), ...
            "-s", "LineWidth", 1.4, "MarkerSize", 6);
        grid on;
        xlabel("SNR (dB)");
        ylabel("Channel-estimation NMSE");
        title(sprintf("%s, delay %g ms", modelName, ...
            cfg.maxDelayMs(channelIndex)));
        legend("Two adjacent UW sequences", "One UW sequence", ...
            "Location", "southwest");
    end
    exportgraphics(fig, fullfile(resultDir, fileName), "Resolution", 180);
    close(fig);
end

function x = chu_sequence(U)
    n = (0:U-1).';
    x = exp(1j * pi * n.^2 / U);
end

function x = frank_zadoff_sequence(U)
    side = sqrt(U);
    assert(side == floor(side), ...
        "Frank-Zadoff sequence length must be a perfect square.");
    n = (0:U-1).';
    p = mod(n, side);
    q = floor(n / side);
    x = exp(1j * 2 * pi * p .* q / side);
end

function x = zadoff_chu_sequence(P, root)
    assert(gcd(P, root) == 1, ...
        "Zadoff-Chu root and sequence length must be coprime.");
    k = (0:P-1).';
    if mod(P, 2) == 0
        x = exp(1j * pi * root * k.^2 / P);
    else
        x = exp(1j * pi * root * k .* (k + 1) / P);
    end
end

function h = four_path_channel(maxDelayMs, TsMs)
    maxDelaySamples = round(maxDelayMs / TsMs);
    delays = unique(round([0, 0.30, 0.68, 1.00] * maxDelaySamples));
    gains = [1.00, 0.72 * exp(1j * 0.45), ...
        0.55 * exp(-1j * 0.90), 0.40 * exp(1j * 1.35)];
    gains = gains(1:numel(delays));
    h = zeros(maxDelaySamples + 1, 1);
    h(delays + 1) = gains;
    h = h / norm(h);
end

function [dualMse, singleMse] = estimate_structure_mse( ...
        uw, h, snrDb, trials, TsMs, maxDopplerHz)
    U = numel(uw);
    assert(numel(h) <= U, "UW must cover the channel for this experiment.");
    pathDopplerHz = path_doppler_profile(h, maxDopplerHz);
    referenceSample = U + (U - 1) / 2;
    referenceTime = referenceSample * TsMs * 1e-3;
    hReference = h .* exp(1j * 2 * pi * pathDopplerHz * referenceTime);
    Htrue = [hReference; zeros(U - numel(h), 1)];
    dualAccum = 0;
    singleAccum = 0;

    for trial = 1:trials
        precedingData = qpsk_symbols(randi([0, 1], 2 * U, 1));
        dualClean = apply_time_varying_channel( ...
            [uw; uw], h, pathDopplerHz, TsMs);
        singleClean = apply_time_varying_channel( ...
            [precedingData; uw], h, pathDopplerHz, TsMs);
        dualObs = dualClean(U + (1:U));
        singleObs = singleClean(U + (1:U));

        dualObs = add_awgn(dualObs, snrDb);
        singleObs = add_awgn(singleObs, snrDb);
        dualEstimate = ifft(fft(dualObs) ./ fft(uw));
        singleEstimate = ifft(fft(singleObs) ./ fft(uw));

        dualAccum = dualAccum + normalized_error(dualEstimate, Htrue);
        singleAccum = singleAccum + normalized_error(singleEstimate, Htrue);
    end

    dualMse = dualAccum / trials;
    singleMse = singleAccum / trials;
end

function pathDopplerHz = path_doppler_profile(h, maxDopplerHz)
    activeTaps = find(abs(h) > 0);
    baseProfile = [0.25, -0.55, 1.00, -0.80];
    if numel(activeTaps) <= numel(baseProfile)
        normalizedDoppler = baseProfile(1:numel(activeTaps));
    else
        normalizedDoppler = linspace(-1, 1, numel(activeTaps));
    end
    pathDopplerHz = zeros(size(h));
    pathDopplerHz(activeTaps) = maxDopplerHz * normalizedDoppler;
end

function y = apply_time_varying_channel(x, h, pathDopplerHz, TsMs)
    outputLength = numel(x) + numel(h) - 1;
    time = (0:outputLength-1).' * TsMs * 1e-3;
    y = zeros(outputLength, 1);
    activeTaps = find(abs(h) > 0);

    for tapIndex = activeTaps.'
        delay = tapIndex - 1;
        outputIndices = delay + (1:numel(x));
        phase = exp(1j * 2 * pi * pathDopplerHz(tapIndex) * ...
            time(outputIndices));
        y(outputIndices) = y(outputIndices) + h(tapIndex) * phase .* x;
    end
end

function mse = estimate_protected_uw_mse(uw, h, snrDb, trials)
    U = numel(uw);
    assert(numel(h) <= U, "UW must cover the channel for this experiment.");
    Htrue = [h; zeros(U - numel(h), 1)];
    clean = conv([uw; uw], h);
    clean = clean(U + (1:U));
    accum = 0;

    for trial = 1:trials
        observation = add_awgn(clean, snrDb);
        estimate = ifft(fft(observation) ./ fft(uw));
        accum = accum + normalized_error(estimate, Htrue);
    end
    mse = accum / trials;
end

function value = normalized_error(estimate, truth)
    value = sum(abs(estimate - truth).^2) / sum(abs(truth).^2);
end

function y = add_awgn(x, snrDb)
    signalPower = mean(abs(x).^2);
    noisePower = signalPower * 10^(-snrDb / 10);
    noise = sqrt(noisePower / 2) * ...
        (randn(size(x)) + 1j * randn(size(x)));
    y = x + noise;
end

function symbols = qpsk_symbols(bits)
    bits = reshape(bits, 2, []);
    symbols = ((1 - 2 * bits(1, :)) + 1j * (1 - 2 * bits(2, :))) / sqrt(2);
    symbols = symbols(:);
end

function bits = qpsk_demodulate(symbols)
    symbols = symbols(:);
    bits = zeros(2, numel(symbols));
    bits(1, :) = real(symbols) < 0;
    bits(2, :) = imag(symbols) < 0;
    bits = bits(:);
end

function [ber, totalBits, totalErrors] = simulate_sc_fde_ber( ...
        N, uw, h, snrDb, targetErrors, maxBits, blocksPerBatch)
    U = numel(uw);
    dataLength = N - U;
    assert(dataLength > 0, "UW must be shorter than the FFT block.");
    H = fft(h, N);
    noiseRatio = 10^(-snrDb / 10);
    equalizer = conj(H) ./ (abs(H).^2 + noiseRatio);
    totalBits = 0;
    totalErrors = 0;

    while totalErrors < targetErrors && totalBits < maxBits
        remainingBlocks = ceil((maxBits - totalBits) / (2 * dataLength));
        batchBlocks = min(blocksPerBatch, remainingBlocks);
        txBits = randi([0, 1], 2 * dataLength * batchBlocks, 1);
        dataSymbols = reshape(qpsk_symbols(txBits), dataLength, batchBlocks);
        blocks = [dataSymbols; repmat(uw, 1, batchBlocks)];

        stream = [uw; blocks(:)];
        clean = conv(stream, h);
        received = add_awgn(clean, snrDb);
        blockSamples = received(U + (1:N * batchBlocks));
        receivedBlocks = reshape(blockSamples, N, batchBlocks);

        estimate = ifft(fft(receivedBlocks, N, 1) .* equalizer, N, 1);
        rxBits = qpsk_demodulate(estimate(1:dataLength, :));
        totalErrors = totalErrors + sum(rxBits ~= txBits);
        totalBits = totalBits + numel(txBits);
    end

    if totalErrors == 0
        ber = 0.5 / totalBits;
    else
        ber = totalErrors / totalBits;
    end
end
