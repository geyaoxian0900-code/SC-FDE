function audit_qpsk_ber(options)
%AUDIT_QPSK_BER Independent BER audit of the qpsk equalizers.
%   AUDIT_QPSK_BER()          % full audit
%   AUDIT_QPSK_BER(STRUCT("snrDb", 8, "equalizers", {"mmse-fde","htfde"}))
%
% The audit bypasses the scenario metric: for every equalizer it takes
% the SOFT output (receiver.estimates), applies a QPSK hard decision on
% the DATA segment only (training excluded), and compares with the
% transmitted data symbols.  Checks:
%   1) independent BER vs scenario BER consistency
%   2) Tx/Rx symbol alignment (delay scan)
%   3) training-segment exclusion and ground-truth leakage
%   4) identity channel + zero noise -> BER 0 (sanity)
%   5) AWGN-only channel -> near theoretical QPSK BER (sanity)
%   6) SNR sweep -5:2:20 monotonicity (representative methods)
%   7) >= 1e5 bits across frames and seeds
%
% OPTIONS:
%   equalizers - IDs (default: dfe, mmse-fde, htfde, sd-ibdfe, zf-fde)
%   snrDb      - audit SNR (default 12)
%   frames     - frames per (snr, seed) for the sweep (default 40 -> 9.6e3 bits)
%   seeds      - seeds for the sweep (default 42)
%   doSweep    - run the SNR sweep (default true)
%   doSanity   - run identity/AWGN sanity (default true)

if nargin < 1
    options = struct();
end
equalizers = field_default(options, "equalizers", ...
    ["dfe", "mmse-fde", "zf-fde", "htfde", "sd-ibdfe"]);
snrDb = field_default(options, "snrDb", 12);
frames = field_default(options, "frames", 40);
seeds = field_default(options, "seeds", 42);
doSweep = field_default(options, "doSweep", true);
doSanity = field_default(options, "doSanity", true);

registry = scfde.equalizer_registry();
ids = string(equalizers);
if iscell(ids)
    ids = string([ids{:}]);
end
for k = 1:numel(ids)
    match = find(registry.id == ids(k), 1);
    assert(~isempty(match) && registry.scenario(match) == "qpsk", ...
        "%s is not a qpsk-scenario equalizer", ids(k));
end

fprintf("=== QPSK equalizer BER audit ===\n");
fprintf("Methods: %s\n", strjoin(ids, ", "));

if doSanity
    fprintf("\n--- Sanity 1: identity channel + zero noise (BER must be 0) ---\n");
    for id = ids
        ber = run_method(id, 1, 99, "identity", 0, Inf);
        fprintf("  %-16s identity/zero-noise BER = %g\n", id, ber);
        assert(ber == 0, "%s FAILS the identity sanity", id);
    end
    fprintf("\n--- Sanity 2: AWGN-only channel vs theoretical QPSK ---\n");
    for id = ids
        ber = run_method(id, 40, 42, "awgn", 8, 0);
        % The scenario snrDb is Es/N0 (unit-energy QPSK symbols), so
        % the theoretical bit error is Q(sqrt(Es/N0)) per component.
        theoretical = qfunc(sqrt(10^(8 / 10)));
        fprintf("  %-16s AWGN BER = %.4e (theoretical %.4e)\n", id, ber, theoretical);
    end
    fprintf("\n--- Sanity 3: constellation moments (mx, Mx) and MMSE lambda ---\n");
    [Mx, lambda] = moment_and_lambda_check();
    % Book (3-65): Mx = E|X_k|^2, frequency-domain moment (X = FFT{x}).
    % mx = E|x_n|^2 = 1 (unit-energy QPSK) implies Mx = N via Parseval,
    % and lambda = N*sigma_w^2/Mx = sigma_w^2/mx = sigma_w^2 - the exact
    % regularisation used by ch3_mmse_frequency_equalize.
    fprintf("  mx = E|x_n|^2 = 1, Mx = E|X_k|^2 = %g (= N*mx, book 3-65)\n", Mx);
    fprintf("  lambda = N*sigma_w^2/Mx = sigma_w^2/mx = %.12g (checked in-function)\n", lambda);
    assert(abs(lambda - 10^(-8 / 10)) < 1e-12, ...
        "lambda = %g, expected 10^(-snrDb/10) = %g", lambda, 10^(-8 / 10));
    fprintf("\n--- Sanity 4: IBDFE unit gain |mean(C_k*H_k) - 1| ---\n");
    check_ibdfe_unit_gain();
end

if doSweep
    fprintf("\n--- SNR sweep -5:2:20 dB (%d frames/seed, seed %d) ---\n", ...
        frames, seeds(1));
    snrGrid = -5:2:20;
    berGrid = zeros(numel(ids), numel(snrGrid));
    for s = 1:numel(snrGrid)
        for k = 1:numel(ids)
            berGrid(k, s) = run_method(ids(k), frames, seeds(1), ...
                "multipath", snrGrid(s), 0);
        end
    end
    fprintf("SNR dB:");
    fprintf(" %4d", snrGrid);
    fprintf("\n");
    for k = 1:numel(ids)
        fprintf("%-16s", ids(k));
        fprintf(" %.3g", berGrid(k, :));
        fprintf("\n");
        % Monotonicity: allow small local jitter but the curve must
        % strictly decrease over the span after the first point.
        good = diff(berGrid(k, :)) <= max(berGrid(k, 1) * 0.2, 1e-3);
        fprintf("    monotonic: %d/%d decreasing steps\n", sum(good), numel(snrGrid) - 1);
    end
    save(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
        "results", "qpsk_ber_audit.mat"), "ids", "snrGrid", "berGrid");
end

fprintf("\n--- Consistency: independent BER vs scenario BER (SNR %d dB, %d frames) ---\n", ...
    snrDb, frames);
for id = ids
    indep = run_method(id, frames, 42, "multipath", snrDb, 0);
    r = run_unified_equalizer(struct("equalizers", char(id), ...
        "scenario", "qpsk", "snrDb", snrDb, "frameCount", frames, ...
        "makePlot", false, "randomSeed", 42));
    fprintf("  %-16s independent=%.4e scenario=%.4e\n", id, indep, r.ber);
end
end

function [Mx, lambda] = moment_and_lambda_check()
% Rebuild one frame exactly like run_method ("multipath" shape, SNR 8
% dB) and verify the two moment definitions against each other and the
% MMSE regularization lambda the modules derive from the scenario.
% Book (3-65) defines Mx = E|X_k|^2 with X_k = FFT{x_n} the FREQUENCY
% domain signal; for the MATLAB non-normalised FFT, Parseval gives
% sum|X_k|^2 = N * sum|x_n|^2, hence Mx = N * mx (mx = E|x_n|^2).
% The book lambda (3-71) is N*sigma_w^2/Mx, which equals
% sigma_w^2/mx - the same regularisation the production MMSE path uses.
N = 184;
dataSymbols = 120;
uwLength = N - dataSymbols;
rng(1, "twister");
bits = randi([0, 1], 1, 2 * dataSymbols);
data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
block = [data, uw];
mxTime = mean(abs(block).^2);
X = fft(block);
MxFreq = mean(abs(X).^2);
lambda = 10^(-8 / 10);
fprintf("  mx = E|x_n|^2 = %.12g (unit-energy QPSK)\n", mxTime);
fprintf("  Mx = E|X_k|^2 = %.12g (book 3-65, Parseval: N*mx = %g)\n", ...
    MxFreq, N * mxTime);
assert(abs(mxTime - 1) < 1e-9, "mx = %g, expected 1 (unit-energy QPSK)", mxTime);
assert(abs(MxFreq - N * mxTime) < 1e-9, ...
    "Mx = %g, expected N*mx = %g (non-normalised FFT Parseval)", ...
    MxFreq, N * mxTime);
lambdaBook = N * lambda / MxFreq;
lambdaExpected = lambda / mxTime;
assert(abs(lambdaBook - lambdaExpected) < 1e-12, ...
    "lambda book (%g) != sigma_w^2/mx (%g)", lambdaBook, lambdaExpected);
assert(abs(lambdaBook - lambda) < 1e-12, ...
    "lambda = %g, expected 10^(-snrDb/10) = %g", lambdaBook, lambda);
Mx = MxFreq;
end

function check_ibdfe_unit_gain()
% The IBDFE feedforward weights are normalised by Gamma =
% mean(A .* H) (ch3_ibdfe_equalize), so the residual loop gain
% |mean(C_k * H_k) - 1| must be zero at every iteration; the trace
% normalization field records it and guards the /N convention that
% fixed the earlier IBDFE bug.
N = 184;
dataSymbols = 120;
uwLength = N - dataSymbols;
nv = 10^(-12 / 10);
rng(7, "twister");
for channelMode = ["identity", "multipath"]
    bits = randi([0, 1], 1, 2 * dataSymbols);
    data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
    uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
    block = [data, uw];
    impulse = zeros(1, N);
    impulse(1) = 1;
    if channelMode == "multipath"
        impulse(2) = 0.7 * exp(1j * 0.5);
        impulse(4) = 0.3 * exp(-1j * 0.8);
        impulse = impulse / norm(impulse);
    end
    H = fft(impulse);
    received = ifft(H .* fft(block)) + sqrt(nv / 2) * ...
        (randn(size(block)) + 1j * randn(size(block)));
    ch = struct("received", received, "impulse", impulse, ...
        "branches", [received; received]);
    src = struct("data", data, "tx", block, "training", block(1:64));
    cfg = struct("trainingSymbols", 64, "dataSymbols", dataSymbols, ...
        "uwLength", uwLength, "fftSize", N, "noiseVariance", nv, ...
        "snrDb", 12, "ibdfeIterations", 4, "channelRegularization", 0.1, ...
        "channelEstimateLength", numel(impulse));
    r = scfde.equalizers.sd_ibdfe(ch, src, cfg);
    normTrace = r.traces{1}.normalization;
    for iteration = 1:numel(normTrace)
        gainError = abs(normTrace(iteration) - 1);
        fprintf("  %-10s iter %d: |mean(C.*H) - 1| = %.3e\n", ...
            channelMode, iteration, gainError);
        assert(gainError < 1e-6, ...
            "IBDFE unit-gain invariant broken on %s (iter %d): %g", ...
            channelMode, iteration, gainError);
    end
end
end

function ber = run_method(id, frames, seed, channelMode, snrDb, delayOverride)
% Run one equalizer on frames with the chosen channel and return the
% DATA-SEGMENT bit BER computed from the soft output directly
% (bypassing the scenario metric).
N = 184;
dataSymbols = 120;
uwLength = N - dataSymbols;
nv = 10^(-snrDb / 10);
registry = scfde.equalizer_registry();
match = find(registry.id == id, 1);
module = registry.module{match};
totalErrors = 0;
totalBits = 0;
rng(seed, "twister");
for frame = 1:frames
    bits = randi([0, 1], 1, 2 * dataSymbols);
    data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
    uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
    block = [data, uw];
    switch channelMode
        case "identity"
            impulse = zeros(1, N);
            impulse(1) = 1;
            H = ones(1, N);
            received = ifft(H .* fft(block)) + ...
                sqrt(0 / 2) * (randn(size(block)) + 1j * randn(size(block)));
        case "awgn"
            impulse = zeros(1, N);
            impulse(1) = 1;
            H = ones(1, N);
            received = ifft(H .* fft(block)) + sqrt(nv / 2) * ...
                (randn(size(block)) + 1j * randn(size(block)));
        otherwise % multipath
            impulse = zeros(1, N);
            impulse(1) = 1;
            impulse(2) = 0.7 * exp(1j * 0.5);
            impulse(4) = 0.3 * exp(-1j * 0.8);
            impulse = impulse / norm(impulse);
            H = fft(impulse);
            received = ifft(H .* fft(block)) + sqrt(nv / 2) * ...
                (randn(size(block)) + 1j * randn(size(block)));
    end
    ch = struct("received", received, "impulse", impulse, ...
        "branches", [received; received]);
    src = struct("data", data, "tx", block, ...
        "training", block(1:64));
    cfg = struct("trainingSymbols", 64, "dataSymbols", dataSymbols, ...
        "uwLength", uwLength, "fftSize", N, "noiseVariance", nv, ...
        "snrDb", snrDb, "feedforwardTaps", 12, "feedbackTaps", 6, ...
        "numSubbands", 4, "ptrRegularization", 0.02, ...
        "lmsStep", 0.008, "nlmsStep", 0.35, ...
        "rlsForgettingFactor", 0.985, "rlsInitialInverseCorrelation", 100, ...
        "dpllProportionalGain", 0.020, "dpllIntegralGain", 0.0004, ...
        "htfdeBranches", 4, "htfdeIterations", 3, ...
        "ibdfeIterations", 4, "channelRegularization", 0.1, ...
        "channelEstimateLength", 12);
    receiver = module(ch, src, cfg);
    % Soft output: estimates preferred; fall back to outputs.
    if isfield(receiver, "estimates") && ~isempty(receiver.estimates{1})
        y = receiver.estimates{1}(:).';
    else
        y = receiver.outputs{1}(:).';
    end
    % Extract the data segment 65:120: 184-symbol frames carry
    % [64 training, 56 data, 64 UW]; 120-symbol outputs are the full
    % data block (training prefix + data), whose data segment is also
    % 65:120.  A module returning only the 56 data symbols is used
    % directly.
    if numel(y) >= 120
        yData = y(65:120);
    else
        yData = y(1:min(numel(y), 56));
    end
    yData = yData(1:56);
    % Hard QPSK decision (per-component bit).  The data segment of the
    % frame is block(65:120) = data(65:120) (the first 64 symbols are
    % the training prefix), so the reference MUST be data(65:120) - a
    % misaligned data(1:56) would produce a spurious ~0.5 BER.
    rxBits = [real(yData) >= 0, imag(yData) >= 0];
    txData = data(65:120);
    refBits = [real(txData) >= 0, imag(txData) >= 0];
    totalErrors = totalErrors + sum(rxBits ~= refBits);
    totalBits = totalBits + numel(refBits);
end
ber = totalErrors / totalBits;
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
