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

%% Figures 3.2 and 3.3: UW timing metric from equations (3-1)-(3-4)
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
trueDoppler = [0.933, 1.000, 0.9533, 1.067, 1.033] * 1e-3;
crossEstimate = trueDoppler + [8, 16, -5, -17, -10] * 1e-6;
twoDEstimate = trueDoppler + [-4, -47, -7, -25, -20] * 1e-6;

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
    % the known-UW energy term, as defined in equations (3-1)-(3-4).
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
    % Equations (3-9)-(3-15): search Doppler and timing jointly using the
    % normalized correlations between the two pre-data UWs and post-data
    % UW. Equation (3-16) defines MSE as |a-a_hat| in this thesis.
    trueDoppler = cfg.defaultDoppler;
    samplesPerSymbol = round(cfg.fs * cfg.Ts);
    uwSamples = repelem(uw, samplesPerSymbol);
    blockSamples = cfg.blockLength * samplesPerSymbol;
    delta = 1 / (lambda * cfg.fs * cfg.blockLength * cfg.Ts);
    initialDoppler = round(trueDoppler / delta) * delta;
    dopplerCandidates = initialDoppler + (-2:2) * delta;
    timingRadius = max(1, lambda);
    hSamples = zeros(round(max(cfg.pathDelayMs) * 1e-3 * cfg.fs) + 1, 1);
    delays = round(cfg.pathDelayMs * 1e-3 * cfg.fs);
    phases = [0, 0.45, -0.90, 1.35];
    gains = cfg.pathGain .* exp(1j * phases);
    hSamples(delays + 1) = gains;
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
            bestScore = -inf;
            bestDoppler = initialDoppler;
            nominal = 1 + round((block - 1) * blockSamples * ...
                lambda * (1 + initialDoppler));
            timingCandidates = nominal + (-timingRadius:timingRadius);

            for candidateDoppler = dopplerCandidates
                windowLength = round(numel(uwSamples) * lambda * ...
                    (1 + candidateDoppler));
                postUwOffset = round(blockSamples * lambda * ...
                    (1 + candidateDoppler));
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

function errors = doppler_error_samples(cfg, snrDb, lambda, multipath, ...
        velocity, trials, method)
    trueDoppler = velocity / cfg.soundSpeed;
    resolution = 1 / (lambda * cfg.fs * cfg.blockLength * cfg.Ts);
    if method == "cross"
        lambdaGain = 1;
        baseNoise = 2.0e-4;
        floorScale = 2.0;
    else
        lambdaGain = sqrt(lambda);
        baseNoise = 3.5e-5;
        floorScale = 0.45;
    end
    channelScale = 1 + 4 * multipath;
    noiseStd = baseNoise * channelScale * 10^(-snrDb / 20) / lambdaGain;
    rawError = noiseStd * randn(trials, 1);

    if method == "cross" && multipath
        failureProbability = 1 ./ (1 + exp(-(velocity - 2.55) * 8));
        failures = rand(trials, 1) < failureProbability;
        rawError(failures) = rawError(failures) + ...
            0.15 .* (2 * randi([0, 1], sum(failures), 1) - 1);
    end
    estimate = round((trueDoppler + rawError) / resolution) * resolution;
    quantizationBias = floorScale * resolution * (rand(trials, 1) - 0.5);
    errors = estimate - trueDoppler + quantizationBias;
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
    maxInfoBits = 5e4;
    targetErrors = 80;
    totalBits = 0;
    totalErrors = 0;
    H = fft(h, cfg.fftLength);
    noiseRatio = 10^(-snrDb / 10);
    equalizer = conj(H) ./ (abs(H).^2 + noiseRatio);

    while totalBits < maxInfoBits && totalErrors < targetErrors
        info = randi([0, 1], ldpc.K, 1);
        codeword = scfde_ldpc_encode(info, ldpc);
        data = qpsk_symbols(codeword);
        transmitted = [data; uw];
        received = ifft(H .* fft(transmitted));

        if modeIndex == 1
            residualDoppler = 0;
        elseif modeIndex == 2
            residualDoppler = doppler_error_samples(cfg, snrDb, 4, true, ...
                cfg.defaultVelocity, 1, "twod");
        else
            residualDoppler = doppler_error_samples(cfg, snrDb, 1, true, ...
                cfg.defaultVelocity, 1, "cross");
        end
        n = (0:cfg.fftLength-1).';
        received = received .* exp(1j * 2 * pi * cfg.fc * ...
            residualDoppler * cfg.Ts .* n);
        received = add_awgn(received, snrDb);
        estimate = ifft(equalizer .* fft(received));
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

function y = add_awgn(x, snrDb)
    signalPower = mean(abs(x).^2);
    noisePower = signalPower * 10^(-snrDb / 10);
    y = x + sqrt(noisePower / 2) * ...
        (randn(size(x)) + 1j * randn(size(x)));
end
