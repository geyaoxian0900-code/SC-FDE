function results = run_chapter4_simulation(options)
%RUN_CHAPTER4_SIMULATION Chapter 4 decision-feedback equalization suite.
% Reproduces the numerical trends in Figures 4.2, 4.4, 4.5, 4.7, and 4.8.

if nargin < 1
    options = struct();
end
rng(20260722, "twister");

rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "..", "common"));
addpath(fullfile(rootDir, "..", "modules"));
resultDir = fullfile(rootDir, "results");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

cfg.N = 512;
cfg.uwLength = 64;
cfg.dataLength = cfg.N - cfg.uwLength;
cfg.Ts_ms = 0.25;
cfg.pathDelayMs = [0, 3.4, 6.7, 10];
cfg.pathGain = [1, 0.6, 0.6, 0.3];
cfg.fdfeFeedback = [0, 2, 4, 6, 7, 8, 9];
cfg.uncodedSnrDb = 1:1:13;
cfg.codedSnrDb = -2:1:4;
cfg.uncodedMaxBits = 1.2e5;
cfg.uncodedTargetErrors = 120;
cfg.codedBlocks = 45;
cfg.ldpcIterations = 12;
cfg.outputDir = resultDir;
cfg = apply_options(cfg, options);
resultDir = cfg.outputDir;
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

uw = chu_sequence(cfg.uwLength);
h = chapter4_channel(cfg);
H = fft(h, cfg.N);
ldpc = scfde_make_ldpc(cfg.dataLength);

fprintf("Running Chapter 4 simulations...\n");

%% Uncoded simulations for Figures 4.2 and 4.5
fdfeBer = zeros(numel(cfg.fdfeFeedback), numel(cfg.uncodedSnrDb));
predictionBer = zeros(1, numel(cfg.uncodedSnrDb));
for snrIndex = 1:numel(cfg.uncodedSnrDb)
    [fdfeBer(:, snrIndex), predictionBer(snrIndex)] = ...
        simulate_uncoded_equalizers(cfg, uw, H, cfg.uncodedSnrDb(snrIndex));
    fprintf("  Uncoded SNR %g dB complete.\n", cfg.uncodedSnrDb(snrIndex));
end

fig = figure("Color", "w", "Position", [100, 100, 800, 540]);
hold on;
for feedbackIndex = 1:numel(cfg.fdfeFeedback)
    semilogy(cfg.uncodedSnrDb, fdfeBer(feedbackIndex, :), ...
        "-o", "LineWidth", 1.2, "MarkerSize", 4);
end
set(gca, "YScale", "log");
grid on; ylim([1e-6, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 4.2: FD-DFE feedback-length comparison");
legend(compose("B = %d", cfg.fdfeFeedback), "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig4_2_fd_dfe_ber.png"), ...
    "Resolution", 180);
close(fig);

selectedFeedback = [0, 6, 7, 9];
fig = figure("Color", "w", "Position", [100, 100, 800, 540]);
semilogy(cfg.uncodedSnrDb, fdfeBer(1, :), "-x", "LineWidth", 1.4); hold on;
semilogy(cfg.uncodedSnrDb, predictionBer, "-^", "LineWidth", 1.4);
for feedback = selectedFeedback(2:end)
    index = find(cfg.fdfeFeedback == feedback, 1);
    semilogy(cfg.uncodedSnrDb, fdfeBer(index, :), ...
        "-o", "LineWidth", 1.2, "MarkerSize", 4);
end
grid on; ylim([1e-6, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 4.5: uncoded equalizer comparison");
legend("MMSE", "Noise prediction", "FD-DFE B=6", ...
    "FD-DFE B=7", "FD-DFE B=9", "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig4_5_uncoded_prediction_ber.png"), ...
    "Resolution", 180);
close(fig);

%% Coded simulations for Figures 4.4, 4.7, and 4.8
codedMmseBer = zeros(size(cfg.codedSnrDb));
codedPredictionBer = zeros(size(cfg.codedSnrDb));
codedFdfeBer = zeros(size(cfg.codedSnrDb));
ibdfeBer = zeros(4, numel(cfg.codedSnrDb));

for snrIndex = 1:numel(cfg.codedSnrDb)
    result = simulate_coded_equalizers(cfg, uw, H, ldpc, ...
        cfg.codedSnrDb(snrIndex));
    codedMmseBer(snrIndex) = result.mmse;
    codedPredictionBer(snrIndex) = result.prediction;
    codedFdfeBer(snrIndex) = result.fdfe;
    ibdfeBer(:, snrIndex) = result.ibdfe;
    fprintf("  Coded SNR %g dB complete.\n", cfg.codedSnrDb(snrIndex));
end

fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
semilogy(cfg.codedSnrDb, codedMmseBer, "-s", "LineWidth", 1.4); hold on;
semilogy(cfg.codedSnrDb, codedPredictionBer, "-*", "LineWidth", 1.4);
grid on; ylim([1e-5, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 4.4: coded noise-prediction equalizer");
legend("MMSE", "Noise prediction", "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig4_4_coded_prediction_ber.png"), ...
    "Resolution", 180);
close(fig);

fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
hold on;
for iteration = 0:3
    semilogy(cfg.codedSnrDb, ibdfeBer(iteration + 1, :), ...
        "-o", "LineWidth", 1.3, "MarkerSize", 5);
end
set(gca, "YScale", "log");
grid on; ylim([1e-5, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 4.7: LDPC-assisted IB-DFE iterations");
legend("Iteration 0", "Iteration 1", "Iteration 2", "Iteration 3", ...
    "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig4_7_ib_dfe_ber.png"), ...
    "Resolution", 180);
close(fig);

fig = figure("Color", "w", "Position", [100, 100, 760, 520]);
semilogy(cfg.codedSnrDb, codedFdfeBer, "-*", "LineWidth", 1.4); hold on;
semilogy(cfg.codedSnrDb, codedPredictionBer, "-^", "LineWidth", 1.4);
semilogy(cfg.codedSnrDb, ibdfeBer(1, :), "-d", "LineWidth", 1.4);
semilogy(cfg.codedSnrDb, ibdfeBer(4, :), "-s", "LineWidth", 1.4);
grid on; ylim([1e-5, 1]);
xlabel("SNR (dB)"); ylabel("BER");
title("Figure 4.8: equalizer performance comparison");
legend("FD-DFE B=1", "Noise prediction", "IB-DFE iteration 0", ...
    "IB-DFE iteration 3", "Location", "southwest");
exportgraphics(fig, fullfile(resultDir, "fig4_8_equalizer_comparison.png"), ...
    "Resolution", 180);
close(fig);

save(fullfile(resultDir, "chapter4_results.mat"), "cfg", "fdfeBer", ...
    "predictionBer", "codedMmseBer", "codedPredictionBer", ...
    "codedFdfeBer", "ibdfeBer");

assert(fdfeBer(end, end) <= 2 * fdfeBer(1, end) + 1e-6, ...
    "FD-DFE feedback should not degrade high-SNR BER.");
assert(ibdfeBer(4, end) <= 2 * ibdfeBer(1, end) + 1e-6, ...
    "IB-DFE iteration should not degrade high-SNR BER.");
fprintf("Chapter 4 results written to: %s\n", resultDir);

results.config = cfg;
results.outputDir = resultDir;
results.fdfeBer = fdfeBer;
results.predictionBer = predictionBer;
results.codedMmseBer = codedMmseBer;
results.codedPredictionBer = codedPredictionBer;
results.codedFdfeBer = codedFdfeBer;
results.ibdfeBer = ibdfeBer;
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

function bits = qpsk_demodulate(symbols)
    symbols = symbols(:);
    bits = reshape([real(symbols).' < 0; imag(symbols).' < 0], [], 1);
end

function h = chapter4_channel(cfg)
    % Delays are in milliseconds and cfg.Ts_ms is the symbol interval,
    % so the taps are at round(pathDelayMs / Ts_ms) symbol samples.
    delays = round(cfg.pathDelayMs / cfg.Ts_ms);
    phases = [0, 0.45, -0.90, 1.35];
    gains = cfg.pathGain .* exp(1j * phases);
    h = zeros(max(delays) + 1, 1);
    h(delays + 1) = gains;
    h = h / norm(h);
end

function [fdfeBer, predictionBer] = simulate_uncoded_equalizers( ...
        cfg, uw, H, snrDb)
    errorFdfe = zeros(numel(cfg.fdfeFeedback), 1);
    errorPrediction = 0;
    totalBits = 0;
    noiseRatio = 10^(-snrDb / 10);
    W = normalized_mmse_equalizer(H, noiseRatio);
    predictor = error_predictor(W, H, noiseRatio, cfg.dataLength);

    while totalBits < cfg.uncodedMaxBits && ...
            min([errorFdfe; errorPrediction]) < cfg.uncodedTargetErrors
        bits = randi([0, 1], 2 * cfg.dataLength, 1);
        data = qpsk_symbols(bits);
        transmitted = [data; uw];
        received = ifft(H .* fft(transmitted));
        received = add_awgn(received, snrDb);
        R = fft(received);
        mmseEstimate = ifft(W .* R);

        for feedbackIndex = 1:numel(cfg.fdfeFeedback)
            feedbackLength = cfg.fdfeFeedback(feedbackIndex);
            [Wf, feedback] = scfde.equalizers.fd_dfe_design(H, noiseRatio, feedbackLength);
            mainTap = mean(Wf .* H);
            filtered = ifft(Wf .* R) / mainTap;
            % Decision-feedback loop (Eq. 4-18): subtract the feedback
            % terms of the already-decided symbols from the feedforward
            % output.  The self-consistent f makes the shaped post-cursor
            % g(m) = f_m, so this cancellation removes it exactly.
            estimate = fdfe_symbols(filtered, feedback / mainTap, uw, ...
                cfg.dataLength);
            errorFdfe(feedbackIndex) = errorFdfe(feedbackIndex) + ...
                sum(qpsk_demodulate(estimate) ~= bits);
        end

        uwError = mmseEstimate(cfg.dataLength + 1:end) - uw;
        predictionEstimate = mmseEstimate(1:cfg.dataLength) - ...
            predictor * uwError;
        errorPrediction = errorPrediction + ...
            sum(qpsk_demodulate(predictionEstimate) ~= bits);
        totalBits = totalBits + numel(bits);
    end
    fdfeBer = max(errorFdfe, 0.5) / totalBits;
    predictionBer = max(errorPrediction, 0.5) / totalBits;
end

function result = simulate_coded_equalizers(cfg, uw, H, ldpc, snrDb)
    errorsMmse = 0;
    errorsPrediction = 0;
    errorsFdfe = 0;
    errorsIb = zeros(4, 1);
    totalBits = 0;
    noiseRatio = 10^(-snrDb / 10);
    W = normalized_mmse_equalizer(H, noiseRatio);
    predictor = error_predictor(W, H, noiseRatio, cfg.dataLength);

    for block = 1:cfg.codedBlocks
        info = randi([0, 1], ldpc.K, 1);
        codeword = scfde_ldpc_encode(info, ldpc);
        data = qpsk_symbols(codeword);
        transmitted = [data; uw];
        received = ifft(H .* fft(transmitted));
        received = add_awgn(received, snrDb);
        R = fft(received);
        mmseEstimate = ifft(W .* R);

        [decoded, ~] = decode_symbol_estimate(mmseEstimate(1:cfg.dataLength), ...
            noiseRatio, ldpc, cfg.ldpcIterations);
        errorsMmse = errorsMmse + sum(decoded(1:ldpc.K) ~= info);
        errorsIb(1) = errorsIb(1) + sum(decoded(1:ldpc.K) ~= info);

        uwError = mmseEstimate(cfg.dataLength + 1:end) - uw;
        predictionEstimate = mmseEstimate(1:cfg.dataLength) - ...
            predictor * uwError;
        [decodedPrediction, ~] = decode_symbol_estimate(predictionEstimate, ...
            equalized_noise_variance(W, H, noiseRatio), ...
            ldpc, cfg.ldpcIterations);
        errorsPrediction = errorsPrediction + ...
            sum(decodedPrediction(1:ldpc.K) ~= info);

        [Wf, feedback] = scfde.equalizers.fd_dfe_design(H, noiseRatio, 1);
        mainTap = mean(Wf .* H);
        WfNorm = Wf / mainTap;
        % FDE-FDFE (book 4.3.1): feedforward MMSE decode first, then
        % re-encode and cancel the residual post-cursor ISI with decoded
        % symbols, then decode again.  The feedforward carries the
        % feedback polynomial F_k; the residual cancellation uses the
        % decoded (not hard-sliced) symbols.
        fdfeFeedforward = ifft(Wf .* R) / mainTap;
        [decodedFdfe, ~] = decode_symbol_estimate( ...
            fdfeFeedforward(1:cfg.dataLength), ...
            noiseRatio, ldpc, cfg.ldpcIterations);
        feedbackSymbols = [qpsk_symbols(decodedFdfe); uw];
        fdfeRefined = fdfe_symbols_decoded(fdfeFeedforward, ...
            feedback / mainTap, uw, cfg.dataLength, feedbackSymbols);
        [decodedFdfe, ~] = decode_symbol_estimate(fdfeRefined, ...
            equalized_noise_variance(WfNorm, H, noiseRatio), ...
            ldpc, cfg.ldpcIterations);
        errorsFdfe = errorsFdfe + sum(decodedFdfe(1:ldpc.K) ~= info);

        feedbackCodeword = decoded;
        feedbackSymbols = [qpsk_symbols(feedbackCodeword); uw];
        Dhat = fft(feedbackSymbols);
        posterior = [];
        for iteration = 1:3
            if isempty(posterior)
                rho = 0;
            else
                rho = min(0.97, max(0.45, mean(abs(tanh(posterior / 2)).^2)));
            end
            D = (noiseRatio + abs(H).^2) - rho * abs(H).^2;
            lambda = noiseRatio * sum(1 ./ max(D, eps)) / ...
                max(sum((noiseRatio + abs(H).^2) ./ max(D, eps)), eps);
            B = (lambda * (noiseRatio + abs(H).^2) - noiseRatio) ./ ...
                max(D, eps);
            G = conj(H) .* (1 + B) ./ (noiseRatio + abs(H).^2);
            iterativeEstimate = ifft(G .* R - B .* Dhat);
            [decodedIterative, posterior] = decode_symbol_estimate( ...
                iterativeEstimate(1:cfg.dataLength), ...
                equalized_noise_variance(G, H, noiseRatio), ...
                ldpc, cfg.ldpcIterations);
            errorsIb(iteration + 1) = errorsIb(iteration + 1) + ...
                sum(decodedIterative(1:ldpc.K) ~= info);
            feedbackSymbols = [qpsk_symbols(decodedIterative); uw];
            Dhat = fft(feedbackSymbols);
        end
        totalBits = totalBits + ldpc.K;
    end

    result.mmse = max(errorsMmse, 0.5) / totalBits;
    result.prediction = max(errorsPrediction, 0.5) / totalBits;
    result.fdfe = max(errorsFdfe, 0.5) / totalBits;
    result.ibdfe = max(errorsIb, 0.5) / totalBits;
end

function W = normalized_mmse_equalizer(H, noiseRatio)
    W = conj(H) ./ (abs(H).^2 + noiseRatio);
    W = W / mean(W .* H);
end

function nv = equalized_noise_variance(W, H, noiseRatio)
    % Post-equalization residual variance at the equalizer output:
    %   nv = sigma_w^2 * mean(|W_k|^2)          (filtered thermal noise)
    %      + mean(|W_k*H_k - 1|^2) * sigma_x^2  (residual ISI, sigma_x=1)
    % This is the analytical MMSE output error variance.  For FD-DFE and
    % IBDFE the feedback cancels the residual ISI, so this expression is
    % an upper bound on their true output variance; using the same bound
    % for all methods keeps the LLR scaling formula-driven.
    thermal = noiseRatio * mean(abs(W).^2);
    residualIsi = mean(abs(W .* H - 1).^2);
    nv = thermal + residualIsi;
end

function decisions = fdfe_symbols(feedforwardOutput, feedback, uw, ...
        dataLength)
    % Decision-feedback loop (Eq. 4-18): subtract the feedback terms of
    % the already-decided symbols from the feedforward output.  The
    % UW acts as the cyclic prefix for symbols before the block start.
    N = numel(feedforwardOutput);
    feedbackLength = numel(feedback);
    decisions = zeros(dataLength, 1);
    for symbolIndex = 1:dataLength
        value = feedforwardOutput(symbolIndex);
        for lag = 1:min(feedbackLength, N - 1)
            previousIndex = symbolIndex - lag;
            if previousIndex >= 1
                previous = decisions(previousIndex);
            else
                wrappedIndex = N + previousIndex;
                previous = uw(wrappedIndex - dataLength);
            end
            value = value - feedback(lag) * previous;
        end
        decisions(symbolIndex) = hard_qpsk(value);
    end
end

function refined = fdfe_symbols_decoded(feedforwardOutput, feedback, ...
        uw, dataLength, feedbackSymbols)
    % Feedback cancellation using decoded symbols (book 4.3.1): the
    % post-cursor ISI is subtracted with the re-encoded decoder output
    % instead of hard-sliced decisions.  Returns the refined soft
    % estimates (before slicing) for the decoder.
    N = numel(feedforwardOutput);
    feedbackLength = numel(feedback);
    refined = zeros(dataLength, 1);
    for symbolIndex = 1:dataLength
        value = feedforwardOutput(symbolIndex);
        for lag = 1:min(feedbackLength, N - 1)
            previousIndex = symbolIndex - lag;
            if previousIndex >= 1
                previous = feedbackSymbols(previousIndex);
            else
                wrappedIndex = N + previousIndex;
                previous = uw(wrappedIndex - dataLength);
            end
            value = value - feedback(lag) * previous;
        end
        refined(symbolIndex) = value;
    end
end

function symbol = hard_qpsk(value)
    symbol = ((1 - 2 * (real(value) < 0)) + ...
        1j * (1 - 2 * (imag(value) < 0))) / sqrt(2);
end

function predictor = error_predictor(W, H, noiseRatio, dataLength)
    N = numel(H);
    errorSpectrum = abs(W .* H - 1).^2 + noiseRatio * abs(W).^2;
    firstColumn = ifft(errorSpectrum);
    [row, column] = ndgrid(0:N-1, 0:N-1);
    covariance = firstColumn(mod(row - column, N) + 1);
    dataIndex = 1:dataLength;
    uwIndex = dataLength + 1:N;
    predictor = covariance(dataIndex, uwIndex) / ...
        (covariance(uwIndex, uwIndex) + 1e-6 * eye(numel(uwIndex)));
end

function [decoded, posterior] = decode_symbol_estimate( ...
        symbols, noiseRatio, ldpc, maxIterations)
    llrScale = 2 * sqrt(2) / max(noiseRatio, 1e-4);
    llr = reshape([llrScale * real(symbols).'; ...
        llrScale * imag(symbols).'], [], 1);
    [decoded, posterior] = scfde_ldpc_decode(llr, ldpc, maxIterations);
end

function y = add_awgn(x, snrDb)
    signalPower = mean(abs(x).^2);
    noisePower = signalPower * 10^(-snrDb / 10);
    y = x + sqrt(noisePower / 2) * ...
        (randn(size(x)) + 1j * randn(size(x)));
end
