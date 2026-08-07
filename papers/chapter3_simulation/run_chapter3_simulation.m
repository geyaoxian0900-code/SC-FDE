function results = run_chapter3_simulation(options)
%RUN_CHAPTER3_SIMULATION Chapter 3 synchronization and Doppler simulation.
% Signal-level timing figures plus Monte Carlo estimator performance.

if nargin < 1
    options = struct();
end
rng(20260722, "twister");

rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "..", "common"));
resultDir = fullfile(rootDir, "results");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

cfg.fs = 48000;
cfg.fc = 10000;
cfg.Ts = 0.25e-3;
cfg.soundSpeed = 1500;
cfg.uwLength = 64;
cfg.dataLength = 448;
cfg.blockLength = cfg.uwLength * 2 + cfg.dataLength;
cfg.fftLength = cfg.uwLength + cfg.dataLength;
cfg.blockCount = 5;
cfg.pathDelayMs = [0, 3.4, 6.7, 10];
cfg.pathGain = [1, 0.6, 0.6, 0.3];
cfg.defaultVelocity = 1.5;
cfg.defaultDoppler = cfg.defaultVelocity / cfg.soundSpeed;
cfg.monteCarloTrials = 3000;
cfg.fig35Trials = 40;
cfg.snrLambda = -6:2:14;
cfg.lambdas = [1, 2, 4, 6, 8];
cfg.snrAwgn = -15:2:9;
cfg.snrMultipath = -4:2:24;
cfg.velocities = 1:0.3:4.3;
cfg.snrBer = -4:1:4;
cfg.outputDir = resultDir;
cfg = apply_options(cfg, options);
resultDir = cfg.outputDir;
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

uw = chu_sequence(cfg.uwLength);
h = chapter3_channel(cfg);

fprintf("Running Chapter 3 simulations...\n");

%% Figures 3.2 and 3.3: UW double-correlation timing metric
[timeStatic, metricStatic] = frame_timing_metric(cfg, uw, h, 0, 10);
[timeDoppler, metricDoppler] = frame_timing_metric(cfg, uw, h, 0.0017, 10);

export_timing_figure(timeStatic, metricStatic, ...
    "Figure 3.2: frame timing, no Doppler", ...
    fullfile(resultDir, "fig3_2_frame_timing.png"));
export_timing_figure(timeDoppler, metricDoppler, ...
    "Figure 3.3: frame timing, Doppler factor 0.0017", ...
    fullfile(resultDir, "fig3_3_frame_timing_doppler.png"));

%% Figure 3.5: oversampling factor
snrLambda = cfg.snrLambda;
lambdas = cfg.lambdas;
mseLambda = zeros(numel(lambdas), numel(snrLambda));
for lambdaIndex = 1:numel(lambdas)
    for snrIndex = 1:numel(snrLambda)
        errors = estimate_fig35_doppler_errors(cfg, uw, ...
            snrLambda(snrIndex), lambdas(lambdaIndex), ...
            cfg.fig35Trials);
        mseLambda(lambdaIndex, snrIndex) = mean(errors);
    end
end

fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
hold on;
for index = 1:numel(lambdas)
    plot(snrLambda, 1e5 * mseLambda(index, :), "-o", "LineWidth", 1.3, ...
        "MarkerSize", 5);
end
grid on;
xlabel("SNR (dB)"); ylabel("MSE (x10^{-5})");
title("Figure 3.5: oversampling-factor comparison");
legend(compose("lambda = %d", lambdas), "Location", "northeast");
exportgraphics(fig, fullfile(resultDir, "fig3_5_lambda_mse.png"), ...
    "Resolution", 180);
close(fig);

%% Figure 3.6: block-wise Doppler tracking
% Each block is generated with its own true Doppler factor and the
% Doppler is estimated from that block's received samples by the same
% signal-level UW estimator used for Figures 3.5/3.7-3.10 (fixed prior
% range, coarse acquisition, local refinement).  No truth information
% enters the estimator.
trueDoppler = [0.933, 1.000, 0.9533, 1.067, 1.033] * 1e-3;
trackingSnrDb = 6;
trackingMultipath = true;
crossTrack = block_doppler_tracking(cfg, uw, h, trackingSnrDb, ...
    trueDoppler, 1, trackingMultipath);
twoDTrack = block_doppler_tracking(cfg, uw, h, trackingSnrDb, ...
    trueDoppler, 4, trackingMultipath);
crossEstimate = crossTrack.estimates;
twoDEstimate = twoDTrack.estimates;

fig = figure("Color", "w", "Position", [100, 100, 760, 500]);
plot(1:5, trueDoppler, "-o", "LineWidth", 1.4); hold on;
plot(1:5, twoDEstimate, "-*", "LineWidth", 1.4);
plot(1:5, crossEstimate, "-s", "LineWidth", 1.4);
grid on; xlabel("Data block"); ylabel("Doppler factor");
title("Figure 3.6: block-wise Doppler tracking");
legend("True", "2-D UW estimator", "UW cross-correlation estimator", ...
    "Location", "southeast");
exportgraphics(fig, fullfile(resultDir, "fig3_6_block_doppler_tracking.png"), ...
    "Resolution", 180);
close(fig);

%% Figures 3.7 and 3.8: AWGN and multipath estimator comparison
snrAwgn = cfg.snrAwgn;
snrMultipath = cfg.snrMultipath;
mseAwgn = estimator_curve(cfg, snrAwgn, false, cfg.defaultVelocity);
mseMultipath = estimator_curve(cfg, snrMultipath, true, cfg.defaultVelocity);

export_estimator_comparison(snrAwgn, mseAwgn, ...
    "Figure 3.7: AWGN Doppler estimation", ...
    fullfile(resultDir, "fig3_7_awgn_doppler_mse.png"));
export_estimator_comparison(snrMultipath, mseMultipath, ...
    "Figure 3.8: multipath Doppler estimation", ...
    fullfile(resultDir, "fig3_8_multipath_doppler_mse.png"));

%% Figure 3.9: velocity robustness
velocities = cfg.velocities;
mseVelocity = zeros(2, numel(velocities));
for velocityIndex = 1:numel(velocities)
    crossErrors = doppler_error_samples(cfg, 6, 1, true, ...
        velocities(velocityIndex), cfg.monteCarloTrials, "cross");
    twoDErrors = doppler_error_samples(cfg, 6, 4, true, ...
        velocities(velocityIndex), cfg.monteCarloTrials, "twod");
    mseVelocity(:, velocityIndex) = ...
        [mean(abs(crossErrors)); mean(abs(twoDErrors))];
end
export_velocity_comparison(velocities, mseVelocity, ...
    fullfile(resultDir, "fig3_9_velocity_doppler_mse.png"));

%% Figure 3.10: coded BER after Doppler compensation
snrBer = cfg.snrBer;
ldpc = scfde_make_ldpc(cfg.dataLength);
berSync = zeros(3, numel(snrBer));
for snrIndex = 1:numel(snrBer)
    for modeIndex = 1:3
        berSync(modeIndex, snrIndex) = simulate_coded_sync_ber( ...
            cfg, uw, h, ldpc, snrBer(snrIndex), modeIndex);
    end
    fprintf("  Figure 3.10 SNR %g dB complete.\n", snrBer(snrIndex));
end

fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
semilogy(snrBer, berSync(1, :), "-+", "LineWidth", 1.4); hold on;
semilogy(snrBer, berSync(2, :), "-*", "LineWidth", 1.4);
semilogy(snrBer, berSync(3, :), "-d", "LineWidth", 1.4);
grid on; ylim([1e-5, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 3.10: BER after Doppler compensation");
legend("Ideal Doppler", "2-D UW estimate", "UW cross-correlation estimate", ...
    "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig3_10_doppler_compensation_ber.png"), ...
    "Resolution", 180);
close(fig);

save(fullfile(resultDir, "chapter3_results.mat"), "cfg", "snrLambda", ...
    "lambdas", "mseLambda", "trueDoppler", "crossEstimate", ...
    "twoDEstimate", "snrAwgn", "mseAwgn", "snrMultipath", ...
    "mseMultipath", "velocities", "mseVelocity", "snrBer", "berSync");

assert(mean(mseLambda(end, end-2:end)) < ...
    mean(mseLambda(1, end-2:end)), ...
    "Higher oversampling should improve the high-SNR estimator.");
assert(mseVelocity(2, end) < mseVelocity(1, end), ...
    "The 2-D estimator should be more robust at high velocity.");
fprintf("Chapter 3 results written to: %s\n", resultDir);

results.config = cfg;
results.outputDir = resultDir;
results.mseLambda = mseLambda;
results.mseAwgn = mseAwgn;
results.mseMultipath = mseMultipath;
results.mseVelocity = mseVelocity;
results.berSync = berSync;
end

%% Local functions
function cfg = apply_options(cfg, options)
    names = fieldnames(options);
    for index = 1:numel(names)
        cfg.(names{index}) = options.(names{index});
    end
end

function x = chu_sequence(U)
    n = (0:U-1).';
    x = exp(1j * pi * n.^2 / U);
end

function symbols = qpsk_symbols(bits)
    bits = reshape(bits, 2, []);
    symbols = ((1 - 2 * bits(1, :)) + 1j * (1 - 2 * bits(2, :))) / sqrt(2);
    symbols = symbols(:);
end

function h = chapter3_channel(cfg)
    delays = round(cfg.pathDelayMs * 1e-3 / cfg.Ts);
    phases = [0, 0.45, -0.90, 1.35];
    gains = cfg.pathGain .* exp(1j * phases);
    h = zeros(max(delays) + 1, 1);
    h(delays + 1) = gains;
    h = h / norm(h);
end

function [time, metric] = frame_timing_metric(cfg, uw, h, doppler, snrDb)
    frame = uw;
    for block = 1:cfg.blockCount
        data = qpsk_symbols(randi([0, 1], 2 * cfg.dataLength, 1));
        frame = [frame; uw; data; uw]; %#ok<AGROW>
    end
    outputLength = floor((numel(frame) - 1) / (1 + doppler)) + 1;
    sourcePosition = (0:outputLength-1).' * (1 + doppler) + 1;
    compressed = interp1((1:numel(frame)).', frame, sourcePosition, ...
        "linear", 0);
    received = conv(compressed, h);
    received = add_awgn(received, snrDb);
    % Phi_1 and Phi_2 are the two adjacent UW correlations.  Phi_3 is
    % the known-UW energy term of the double-UW timing metric.
    pairLength = numel(received) - 2 * cfg.uwLength + 1;
    metric = zeros(pairLength, 1);
    uwConjugate = conj(uw);
    denominator = sum(abs(uw).^2);
    for k = 1:pairLength
        firstUw = received(k:k + cfg.uwLength - 1);
        secondUw = received(k + cfg.uwLength:k + 2 * cfg.uwLength - 1);
        phi1 = sum(firstUw .* uwConjugate);
        phi2 = sum(secondUw .* uwConjugate);
        metric(k) = (phi1 + phi2) / denominator;
    end
    time = (0:numel(metric)-1).' * cfg.Ts;
end

function export_timing_figure(time, metric, titleText, fileName)
    fig = figure("Color", "w", "Position", [100, 100, 900, 430]);
    plot(time, real(metric), "LineWidth", 0.65);
    grid on; xlim([0, 0.78]);
    xlabel("Time (s)"); ylabel("Timing metric amplitude"); title(titleText);
    exportgraphics(fig, fileName, "Resolution", 180);
    close(fig);
end

function errors = estimate_fig35_doppler_errors( ...
        cfg, uw, snrDb, lambda, trials)
    % Search Doppler and timing jointly using the
    % normalized correlations between the two pre-data UWs and post-data
    % UW. MSE is defined as the absolute Doppler estimation error.
    % Delegates to the truth-independent estimator (fixed prior range).
    errors = estimate_fig35_doppler_errors_velocity( ...
        cfg, snrDb, lambda, trials, cfg.defaultVelocity, true);
end

function tracking = block_doppler_tracking(cfg, uw, h, snrDb, ...
        trueDoppler, lambda, multipath)
    % Block-wise Doppler tracking: each data block is transmitted with
    % its own true Doppler factor; the per-block Doppler is then
    % estimated from the received samples by the same signal-level UW
    % estimator used for Figures 3.5 and 3.7-3.10 (fixed prior range,
    % coarse acquisition, local refinement).  The true Doppler is only
    % used to generate the transmitted waveform, never by the estimator.
    samplesPerSymbol = round(cfg.fs * cfg.Ts);
    uwSamples = repelem(uw, samplesPerSymbol);
    blockSamples = cfg.blockLength * samplesPerSymbol;
    delta = 1 / (lambda * cfg.fs * cfg.blockLength * cfg.Ts);
    maxPriorDoppler = 1 / (2 * samplesPerSymbol);
    priorHalfSpan = maxPriorDoppler;
    coarseDelta = min(2 * priorHalfSpan / 5, 4 * delta);
    coarseSteps = max(5, ceil(priorHalfSpan / max(coarseDelta, eps)));
    timingRadius = max(1, lambda);
    hSamples = zeros(round(max(cfg.pathDelayMs) * 1e-3 * cfg.fs) + 1, 1);
    delays = round(cfg.pathDelayMs * 1e-3 * cfg.fs);
    phases = [0, 0.45, -0.90, 1.35];
    gains = cfg.pathGain .* exp(1j * phases);
    if multipath
        hSamples(delays + 1) = gains;
    else
        hSamples(1) = gains(1);
    end
    hSamples = hSamples / norm(hSamples);
    blockCount = numel(trueDoppler);
    estimates = zeros(blockCount, 1);
    for block = 1:blockCount
        data = qpsk_symbols(randi([0, 1], 2 * cfg.dataLength, 1));
        frame = uw;
        for repeatBlock = 1:cfg.blockCount
            frame = [frame; uw; data; uw]; %#ok<AGROW>
        end
        transmitted = repelem(frame, samplesPerSymbol);
        trueValue = trueDoppler(block);
        outputLength = floor((numel(transmitted) - 1) * ...
            (1 + trueValue)) + 1;
        sourcePosition = (0:outputLength-1).' / ...
            (1 + trueValue) + 1;
        expanded = interp1((1:numel(transmitted)).', transmitted, ...
            sourcePosition, "linear", 0);
        received = add_awgn(conv(expanded, hSamples), snrDb);
        basePosition = (1:numel(received)).';
        finePosition = (1:(numel(received) - 1) * lambda + 1).' ...
            / lambda + (1 - 1 / lambda);
        receivedFine = interp1(basePosition, received, finePosition, ...
            "linear", 0);
        coarseBest = 0;
        coarseScore = -inf;
        for candidateDoppler = (-coarseSteps:coarseSteps) * coarseDelta
            windowLength = round(numel(uwSamples) * lambda * ...
                (1 + candidateDoppler));
            postUwOffset = round(blockSamples * lambda * ...
                (1 + candidateDoppler));
            nominal = 1 + round(0 * blockSamples * ...
                lambda * (1 + candidateDoppler));
            score = uw_correlation_score(receivedFine, ...
                nominal, windowLength, postUwOffset, 0);
            if score > coarseScore
                coarseScore = score;
                coarseBest = candidateDoppler;
            end
        end
        dopplerCenter = coarseBest;
        fineCandidates = dopplerCenter + (-2:2) * delta;
        bestScore = -inf;
        bestDoppler = dopplerCenter;
        nominal = 1 + round(0 * blockSamples * ...
            lambda * (1 + dopplerCenter));
        for candidateDoppler = fineCandidates
            windowLength = round(numel(uwSamples) * lambda * ...
                (1 + candidateDoppler));
            postUwOffset = round(blockSamples * lambda * ...
                (1 + candidateDoppler));
            timingCandidates = nominal + (-timingRadius:timingRadius);
            for timing = timingCandidates
                firstLast = timing + windowLength - 1;
                secondFirst = timing + windowLength;
                secondLast = secondFirst + windowLength - 1;
                postFirst = timing + postUwOffset;
                postLast = postFirst + windowLength - 1;
                if timing < 1 || postLast > numel(receivedFine)
                    continue;
                end
                firstUw = receivedFine(timing:firstLast);
                secondUw = receivedFine(secondFirst:secondLast);
                postUw = receivedFine(postFirst:postLast);
                phi1 = sum(firstUw .* conj(postUw));
                phi2 = sum(secondUw .* conj(postUw));
                phi3 = sum(abs(postUw).^2);
                score = abs((phi1 + phi2) / max(phi3, eps));
                if score > bestScore
                    bestScore = score;
                    bestDoppler = candidateDoppler;
                end
            end
        end
        estimates(block) = bestDoppler;
    end
    tracking.trueDoppler = trueDoppler(:);
    tracking.estimates = estimates(:);
    tracking.errors = abs(tracking.trueDoppler - tracking.estimates);
end

function errors = estimate_fig35_doppler_errors_velocity( ...
        cfg, snrDb, lambda, trials, velocity, multipath)
    % Signal-level Doppler estimator Monte Carlo with configurable true
    % velocity and optional multipath, using the UW-correlation joint search.
    % The search is NOT initialized from the true Doppler: a fixed prior
    % range (derived from the symbol rate and frame length, independent of
    % the true value) is scanned on a coarse grid, then refined locally.
    trueDoppler = velocity / cfg.soundSpeed;
    samplesPerSymbol = round(cfg.fs * cfg.Ts);
    uw = chu_sequence(cfg.uwLength);
    uwSamples = repelem(uw, samplesPerSymbol);
    blockSamples = cfg.blockLength * samplesPerSymbol;
    delta = 1 / (lambda * cfg.fs * cfg.blockLength * cfg.Ts);
    % Fixed prior Doppler range, independent of the true value.
    % The searchable Doppler is bounded by the per-symbol phase advance:
    % |doppler| < 1/(2*samplesPerSymbol) (Nyquist of the oversampled UW).
    maxPriorDoppler = 1 / (2 * samplesPerSymbol);
    priorHalfSpan = maxPriorDoppler;
    % Coarse grid must resolve the prior range; keep the step bounded by
    % the fine resolution so the true peak is never skipped.
    coarseDelta = min(2 * priorHalfSpan / 5, 4 * delta);
    coarseSteps = max(5, ceil(priorHalfSpan / max(coarseDelta, eps)));
    dopplerCenter = 0;
    timingRadius = max(1, lambda);
    hSamples = zeros(round(max(cfg.pathDelayMs) * 1e-3 * cfg.fs) + 1, 1);
    delays = round(cfg.pathDelayMs * 1e-3 * cfg.fs);
    phases = [0, 0.45, -0.90, 1.35];
    gains = cfg.pathGain .* exp(1j * phases);
    if multipath
        hSamples(delays + 1) = gains;
    else
        hSamples(1) = gains(1);
    end
    hSamples = hSamples / norm(hSamples);
    errors = zeros(trials * cfg.blockCount, 1);
    errorIndex = 0;

    for trial = 1:trials
        frame = uw;
        for block = 1:cfg.blockCount
            data = qpsk_symbols(randi([0, 1], 2 * cfg.dataLength, 1));
            frame = [frame; uw; data; uw]; %#ok<AGROW>
        end
        transmitted = repelem(frame, samplesPerSymbol);
        outputLength = floor((numel(transmitted) - 1) * ...
            (1 + trueDoppler)) + 1;
        sourcePosition = (0:outputLength-1).' / ...
            (1 + trueDoppler) + 1;
        expanded = interp1((1:numel(transmitted)).', transmitted, ...
            sourcePosition, "linear", 0);
        received = add_awgn(conv(expanded, hSamples), snrDb);

        basePosition = (1:numel(received)).';
        finePosition = (1:(numel(received) - 1) * lambda + 1).' ...
            / lambda + (1 - 1 / lambda);
        receivedFine = interp1(basePosition, received, finePosition, ...
            "linear", 0);

        for block = 1:cfg.blockCount
            % Coarse acquisition over the fixed prior range: scan the
            % coarse grid at the nominal timing (cheap), keep the peak,
            % independent of trueDoppler. Timing is refined locally later.
            coarseBest = 0;
            coarseScore = -inf;
            for candidateDoppler = (-coarseSteps:coarseSteps) * coarseDelta
                windowLength = round(numel(uwSamples) * lambda * ...
                    (1 + candidateDoppler));
                postUwOffset = round(blockSamples * lambda * ...
                    (1 + candidateDoppler));
                nominal = 1 + round((block - 1) * blockSamples * ...
                    lambda * (1 + candidateDoppler));
                score = uw_correlation_score(receivedFine, ...
                    nominal, windowLength, postUwOffset, 0);
                if score > coarseScore
                    coarseScore = score;
                    coarseBest = candidateDoppler;
                end
            end
            % Local refinement around the coarse peak (no trueDoppler).
            dopplerCenter = coarseBest;
            fineCandidates = dopplerCenter + (-2:2) * delta;
            bestScore = -inf;
            bestDoppler = dopplerCenter;
            nominal = 1 + round((block - 1) * blockSamples * ...
                lambda * (1 + dopplerCenter));
            for candidateDoppler = fineCandidates
                windowLength = round(numel(uwSamples) * lambda * ...
                    (1 + candidateDoppler));
                postUwOffset = round(blockSamples * lambda * ...
                    (1 + candidateDoppler));
                timingCandidates = nominal + (-timingRadius:timingRadius);
                for timing = timingCandidates
                    firstLast = timing + windowLength - 1;
                    secondFirst = timing + windowLength;
                    secondLast = secondFirst + windowLength - 1;
                    postFirst = timing + postUwOffset;
                    postLast = postFirst + windowLength - 1;
                    if timing < 1 || postLast > numel(receivedFine)
                        continue;
                    end
                    firstUw = receivedFine(timing:firstLast);
                    secondUw = receivedFine(secondFirst:secondLast);
                    postUw = receivedFine(postFirst:postLast);
                    phi1 = sum(firstUw .* conj(postUw));
                    phi2 = sum(secondUw .* conj(postUw));
                    phi3 = sum(abs(postUw).^2);
                    score = abs((phi1 + phi2) / max(phi3, eps));
                    if score > bestScore
                        bestScore = score;
                        bestDoppler = candidateDoppler;
                    end
                end
            end
            errorIndex = errorIndex + 1;
            errors(errorIndex) = abs(trueDoppler - bestDoppler);
        end
    end
end

function score = uw_correlation_score(receivedFine, nominal, windowLength, postUwOffset, timingRadius)
    best = -inf;
    for timing = nominal + (-timingRadius:timingRadius)
        firstLast = timing + windowLength - 1;
        secondFirst = timing + windowLength;
        secondLast = secondFirst + windowLength - 1;
        postFirst = timing + postUwOffset;
        postLast = postFirst + windowLength - 1;
        if timing < 1 || postLast > numel(receivedFine)
            continue;
        end
        firstUw = receivedFine(timing:firstLast);
        secondUw = receivedFine(secondFirst:secondLast);
        postUw = receivedFine(postFirst:postLast);
        phi1 = sum(firstUw .* conj(postUw));
        phi2 = sum(secondUw .* conj(postUw));
        phi3 = sum(abs(postUw).^2);
        value = abs((phi1 + phi2) / max(phi3, eps));
        if value > best
            best = value;
        end
    end
    score = best;
end

function errors = doppler_error_samples(cfg, snrDb, lambda, multipath, ...
        velocity, trials, method)
    % Monte Carlo Doppler estimation errors from the actual signal-level
    % estimator (oversampled UW-correlation joint search), matching
    % equations (3-9)-(3-15).  The analytic baseNoise/floorScale model
    % previously used here is removed: curves now come from the estimator.
    if method == "twod"
        lambdaUsed = lambda;
    else
        lambdaUsed = 1;
    end
    errors = estimate_fig35_doppler_errors_velocity( ...
        cfg, snrDb, lambdaUsed, trials, velocity, multipath);
    if trials == 1
        errors = errors(1);
    end
end

function curves = estimator_curve(cfg, snrValues, multipath, velocity)
    curves = zeros(2, numel(snrValues));
    for index = 1:numel(snrValues)
        crossErrors = doppler_error_samples(cfg, snrValues(index), 1, ...
            multipath, velocity, cfg.monteCarloTrials, "cross");
        twoDErrors = doppler_error_samples(cfg, snrValues(index), 4, ...
            multipath, velocity, cfg.monteCarloTrials, "twod");
        curves(:, index) = [mean(abs(crossErrors)); mean(abs(twoDErrors))];
    end
end

function export_estimator_comparison(snrValues, curves, titleText, fileName)
    fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
    semilogy(snrValues, curves(1, :), "-+", "LineWidth", 1.4); hold on;
    semilogy(snrValues, curves(2, :), "-*", "LineWidth", 1.4);
    grid on; xlabel("SNR (dB)");
    ylabel("Mean absolute Doppler-factor error"); title(titleText);
    legend("UW cross-correlation", "2-D UW estimator", ...
        "Location", "northeast");
    exportgraphics(fig, fileName, "Resolution", 180);
    close(fig);
end

function export_velocity_comparison(velocities, curves, fileName)
    fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
    semilogy(velocities, curves(1, :), "-*", "LineWidth", 1.4); hold on;
    semilogy(velocities, curves(2, :), "-x", "LineWidth", 1.4);
    grid on; xlabel("Relative velocity (m/s)");
    ylabel("Mean absolute Doppler-factor error");
    title("Figure 3.9: high-Doppler robustness");
    legend("UW cross-correlation", "2-D UW estimator", ...
        "Location", "southeast");
    exportgraphics(fig, fileName, "Resolution", 180);
    close(fig);
end

function ber = simulate_coded_sync_ber(cfg, uw, h, ldpc, snrDb, modeIndex)
    % Full same-frame sync-and-compensate chain: the received frame is
    % generated with the true Doppler, the Doppler is estimated from that
    % same frame by the signal-level UW estimator (fixed prior range, no
    % truth), and the compensation applies the signed estimate as a
    % time-scale resampling plus a carrier phase rotation.  The residual
    % (true minus estimate) therefore contains both the phase error and
    % the residual time compression/expansion.
    maxInfoBits = 5e4;
    targetErrors = 80;
    totalBits = 0;
    totalErrors = 0;
    H = fft(h, cfg.fftLength);
    noiseRatio = 10^(-snrDb / 10);
    equalizer = conj(H) ./ (abs(H).^2 + noiseRatio);
    trueDoppler = cfg.defaultVelocity / cfg.soundSpeed;
    samplesPerSymbol = round(cfg.fs * cfg.Ts);

    while totalBits < maxInfoBits && totalErrors < targetErrors
        info = randi([0, 1], ldpc.K, 1);
        codeword = scfde_ldpc_encode(info, ldpc);
        data = qpsk_symbols(codeword);
        % Two-block frame: the estimator's UW correlation needs a
        % post-data UW, so the payload block is followed by a filler
        % block with the same [UW; data; UW] structure.
        filler = qpsk_symbols(randi([0, 1], 2 * cfg.dataLength, 1));
        transmitted = [uw; data; uw; uw; filler; uw];
        % Oversampled transmission with true Doppler: time-scale
        % compression/expansion plus carrier frequency shift, then the
        % oversampled multipath channel (same model as the estimator).
        txSamples = repelem(transmitted, samplesPerSymbol);
        outputLength = floor((numel(txSamples) - 1) * ...
            (1 + trueDoppler)) + 1;
        sourcePosition = (0:outputLength-1).' / ...
            (1 + trueDoppler) + 1;
        stretched = interp1((1:numel(txSamples)).', txSamples, ...
            sourcePosition, "linear", 0);
        hSamples = zeros(round(max(cfg.pathDelayMs) * 1e-3 * cfg.fs) + 1, 1);
        delays = round(cfg.pathDelayMs * 1e-3 * cfg.fs);
        phases = [0, 0.45, -0.90, 1.35];
        hSamples(delays + 1) = cfg.pathGain .* exp(1j * phases);
        hSamples = hSamples / norm(hSamples);
        received = conv(stretched, hSamples);
        n = (0:numel(received)-1).';
        received = received .* exp(1j * 2 * pi * cfg.fc * ...
            trueDoppler ./ cfg.fs .* n);
        received = add_awgn(received, snrDb);

        if modeIndex == 1
            % Ideal compensation: the exact true Doppler is removed.
            estimateDoppler = trueDoppler;
        else
            % Estimate from the SAME frame (mode 2: 2-D UW estimator
            % with lambda=4, mode 3: cross-correlation with lambda=1).
            if modeIndex == 2
                lambda = 4;
            else
                lambda = 1;
            end
            estimateDoppler = estimate_frame_doppler(cfg, uw, received, ...
                lambda, samplesPerSymbol);
        end

        % Compensation chain: (1) inverse time-scale resampling using the
        % signed estimate, (2) carrier phase rotation with the signed
        % estimate.  The residual (trueDoppler - estimateDoppler) stays
        % in the signal as residual time compression and phase drift.
        % The transmit side compressed the time axis by 1/(1+trueD);
        % the compensation expands it back by (1+estimateDoppler).
        compensatedPosition = n .* (1 + estimateDoppler) + 1;
        compensated = interp1((1:numel(received)).', received, ...
            compensatedPosition, "linear", 0);
        compensated(isnan(compensated)) = 0;
        % The carrier phase is rotated by the actual resampled time
        % (compensatedPosition), matching the transmit-side phase.
        compensated = compensated .* exp(-1j * 2 * pi * cfg.fc * ...
            estimateDoppler ./ cfg.fs .* (compensatedPosition - 1));

        % Downsample to symbol rate, keep the [data; UW] block (the UW
        % acts as the cyclic prefix) and equalize in the frequency domain.
        symbolSamples = compensated(1:samplesPerSymbol:end);
        blockStart = cfg.uwLength + 1;
        block = symbolSamples(blockStart:blockStart + cfg.fftLength - 1);
        estimate = ifft(equalizer .* fft(block));
        dataEstimate = estimate(1:cfg.dataLength);
        llrScale = 2 * sqrt(2) / max(noiseRatio, 1e-6);
        llr = reshape([llrScale * real(dataEstimate).'; ...
            llrScale * imag(dataEstimate).'], [], 1);
        decoded = scfde_ldpc_decode(llr, ldpc, 20);
        totalErrors = totalErrors + sum(decoded(1:ldpc.K) ~= info);
        totalBits = totalBits + ldpc.K;
    end
    ber = max(totalErrors, 0.5) / totalBits;
end

function estimateDoppler = estimate_frame_doppler(cfg, uw, received, ...
        lambda, samplesPerSymbol)
    % Signal-level Doppler estimate from one received frame (no truth).
    % The frame is [UW, data, UW] at the symbol level; the UW-correlation
    % search of Eqs. (3-9)-(3-15) runs over a fixed prior range with
    % coarse acquisition then local refinement.  The received waveform is
    % re-interpolated to the lambda-times oversampled grid for the 2-D
    % search; the true Doppler is never used inside the search.
    uwLength = cfg.uwLength;
    uwSamples = repelem(uw, samplesPerSymbol);
    blockSamples = cfg.blockLength * samplesPerSymbol;
    delta = 1 / (lambda * cfg.fs * cfg.blockLength * cfg.Ts);
    maxPriorDoppler = 1 / (2 * samplesPerSymbol);
    priorHalfSpan = maxPriorDoppler;
    coarseDelta = min(2 * priorHalfSpan / 5, 4 * delta);
    coarseSteps = max(5, ceil(priorHalfSpan / max(coarseDelta, eps)));
    timingRadius = max(1, lambda);

    basePosition = (1:numel(received)).';
    finePosition = (1:(numel(received) - 1) * lambda + 1).' ...
        / lambda + (1 - 1 / lambda);
    receivedFine = interp1(basePosition, received, finePosition, ...
        "linear", 0);

    coarseBest = 0;
    coarseScore = -inf;
    for candidateDoppler = (-coarseSteps:coarseSteps) * coarseDelta
        windowLength = round(numel(uwSamples) * lambda * ...
            (1 + candidateDoppler));
        postUwOffset = round(blockSamples * lambda * ...
            (1 + candidateDoppler));
        nominal = 1 + round(0 * blockSamples * ...
            lambda * (1 + candidateDoppler));
        score = uw_correlation_score(receivedFine, ...
            nominal, windowLength, postUwOffset, 0);
        if score > coarseScore
            coarseScore = score;
            coarseBest = candidateDoppler;
        end
    end
    dopplerCenter = coarseBest;
    fineCandidates = dopplerCenter + (-2:2) * delta;
    bestScore = -inf;
    bestDoppler = dopplerCenter;
    nominal = 1 + round(0 * blockSamples * ...
        lambda * (1 + dopplerCenter));
    for candidateDoppler = fineCandidates
        windowLength = round(numel(uwSamples) * lambda * ...
            (1 + candidateDoppler));
        postUwOffset = round(blockSamples * lambda * ...
            (1 + candidateDoppler));
        timingCandidates = nominal + (-timingRadius:timingRadius);
        for timing = timingCandidates
            firstLast = timing + windowLength - 1;
            secondFirst = timing + windowLength;
            secondLast = secondFirst + windowLength - 1;
            postFirst = timing + postUwOffset;
            postLast = postFirst + windowLength - 1;
            if timing < 1 || postLast > numel(receivedFine)
                continue;
            end
            firstUw = receivedFine(timing:firstLast);
            secondUw = receivedFine(secondFirst:secondLast);
            postUw = receivedFine(postFirst:postLast);
            phi1 = sum(firstUw .* conj(postUw));
            phi2 = sum(secondUw .* conj(postUw));
            phi3 = sum(abs(postUw).^2);
            score = abs((phi1 + phi2) / max(phi3, eps));
            if score > bestScore
                bestScore = score;
                bestDoppler = candidateDoppler;
            end
        end
    end
    estimateDoppler = bestDoppler;
end

function y = add_awgn(x, snrDb)
    signalPower = mean(abs(x).^2);
    noisePower = signalPower * 10^(-snrDb / 10);
    y = x + sqrt(noisePower / 2) * ...
        (randn(size(x)) + 1j * randn(size(x)));
end
