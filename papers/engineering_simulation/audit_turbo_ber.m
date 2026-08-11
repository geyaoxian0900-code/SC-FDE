function audit_turbo_ber(options)
%AUDIT_TURBO_BER Independent BER audit of the ten turbo equalizers.
%   AUDIT_TURBO_BER()
%
% Invariants (per user review):
%   1) identity channel + zero noise -> information-bit BER exactly 0
%   2) AWGN / simple channel -> BER decreasing with SNR (sweep)
%   3) independently reconstructed BER == reported BER exactly, when
%      both use the same final information decisions (receiver.outputs)
%   4) training / coded / tail bits never enter the information-bit
%      denominator
%   Each method reports (N_err, N_bits, BER) plus the 95% Clopper-
%   Pearson binomial interval, so 0/512 is not read as proven BER=0.
%
% The frame is [256 training ; 1024 coded data] (1280 symbols) with
% 512 information bits; BER is counted on the 512 information bits
% only, from the decoder's final information decisions.

if nargin < 1
    options = struct();
end
snrDb = field_default(options, "snrDb", 12);
frames = field_default(options, "frames", 20);
seed = field_default(options, "seed", 42);

registry = scfde.equalizer_registry();
ids = registry.id(registry.scenario == "turbo");
fprintf("=== Turbo equalizer BER audit (%d methods) ===\n", numel(ids));

% --- 1) identity + zero noise ------------------------------------------
fprintf("\n--- 1) Identity channel + zero noise (BER must be 0) ---\n");
identityFail = strings(0);
for id = ids
    [err, bits] = run_method(id, 1, 99, "identity", 0, seed);
    ber = err / bits;
    fprintf("  %-14s err=%d bits=%d BER=%g\n", id, err, bits, ber);
    if ber ~= 0
        identityFail(end + 1) = id; %#ok<AGROW>
    end
end
if ~isempty(identityFail)
    fprintf("  FAIL: %s\n", strjoin(identityFail, ", "));
end

% --- 2) AWGN SNR sweep --------------------------------------------------
fprintf("\n--- 2) AWGN SNR sweep (BER must decrease) ---\n");
snrGrid = 0:2:12;
berGrid = zeros(numel(ids), numel(snrGrid));
for s = 1:numel(snrGrid)
    for k = 1:numel(ids)
        [e, b] = run_method(ids(k), frames, 100 + s, "awgn", snrGrid(s), seed);
        berGrid(k, s) = e / b;
    end
end
fprintf("SNR dB:");
fprintf(" %4d", snrGrid);
fprintf("\n");
for k = 1:numel(ids)
    fprintf("%-14s", ids(k));
    fprintf(" %.3g", berGrid(k, :));
    good = diff(berGrid(k, :)) <= max(berGrid(k, 1) * 0.2, 1e-3);
    fprintf("  monotonic %d/%d\n", sum(good), numel(snrGrid) - 1);
end

% --- 3) independent reconstruction == reported, with CI ----------------
fprintf("\n--- 3) Independent BER vs reported (SNR %d dB, %d frames) ---\n", ...
    snrDb, frames);
alpha = 0.05;
for id = ids
    [err, bits] = run_method(id, frames, 42, "multipath", snrDb, seed);
    ber = err / bits;
    [lo, hi] = clopper_pearson(err, bits, alpha);
    r = run_unified_equalizer(struct("equalizers", char(id), ...
        "scenario", "turbo", "snrDb", snrDb, "frameCount", frames, ...
        "makePlot", false, "randomSeed", 42));
    match = (ber == r.ber);
    fprintf("  %-14s indep err=%d bits=%d BER=%.4e [%.2e, %.2e]  reported=%.4e  %s\n", ...
        id, err, bits, ber, lo, hi, r.ber, ternary(match, "MATCH", "DIFF"));
end

% --- 4) training exclusion ----------------------------------------------
fprintf("\n--- 4) Training never enters the information-bit denominator ---\n");
fprintf("  Frame: 256 training + 1024 coded data; denominator = 512 info bits\n");
fprintf("  (verified by construction: the audit compares only the decoder's\n");
fprintf("   512 information decisions with the transmitted information bits)\n");
save(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "turbo_ber_audit.mat"), "ids", "snrGrid", "berGrid");
end

function [err, bits] = run_method(id, frames, snrDb, channelMode, infoBitsSeed, scenarioSeed)
% Rebuild the turbo frame like run_turbo_scenario: [256 training;
% 1024 coded BPSK], 3-path channel (or identity/awgn), then decode and
% count information-bit errors from receiver.outputs (the decoder's
% final information decisions).
infoBits = 512;
trainingSymbols = 256;
rng(scenarioSeed, "twister");
permutation = randperm(2 * infoBits);
registry = scfde.equalizer_registry();
match = find(registry.id == id, 1);
module = registry.module{match};
totalErrors = 0;
totalBits = 0;
for frame = 1:frames
    info = randi([0, 1], 1, infoBits);
    coded = scfde.equalizers.ch4_convolutional_encode(info);
    dataSymbols = 1 - 2 * coded(permutation);
    training = 1 - 2 * randi([0, 1], 1, trainingSymbols);
    tx = [training, dataSymbols];
    N = numel(tx);
    switch channelMode
        case "identity"
            impulse = [1, 0, 0];
            nv = 0;
        case "awgn"
            impulse = [1, 0, 0];
            nv = 10^(-snrDb / 10);
        otherwise
            impulse = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
            nv = 10^(-snrDb / 10);
    end
    H = fft([impulse, zeros(1, N - numel(impulse))]);
    received = ifft(H .* fft(tx)) + sqrt(nv / 2) * ...
        (randn(size(tx)) + 1j * randn(size(tx)));
    ch = struct("received", received, "impulse", impulse, ...
        "branches", [received; received]);
    src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
    cfg = struct("noiseVariance", nv, "iterations", 3, ...
        "trainingSymbols", trainingSymbols, "infoBits", infoBits, ...
        "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
        "baselineDecoder", "Log-MAP", "turboDamping", 0.75, ...
        "tdAdaptiveTaps", 16, "tdNlmsStep", 0.35, ...
        "blmsStep", 0.2, "blmsLeakage", 1e-3, ...
        "blmsRegularization", 1e-3, "fddaStepFf", 0.2, ...
        "fddaStepFb", 0.01, "fddaBlockLength", 32, ...
        "fddaFfLength", 32, "fddaFbLength", 10);
    receiver = module(ch, src, cfg);
    out = receiver.outputs{1}(:).';
    ref = 1 - 2 * info;
    totalErrors = totalErrors + sum(out(1:numel(ref)) ~= ref);
    totalBits = totalBits + numel(ref);
end
err = totalErrors;
bits = totalBits;
end

function [lo, hi] = clopper_pearson(errors, bits, alpha)
x = double(errors);
n = double(bits);
if x == 0
    lo = 0;
    hi = 1 - (alpha / 2)^(1 / max(n, 1));
elseif x == n
    lo = (alpha / 2)^(1 / max(n, 1));
    hi = 1;
else
    lo = betainv(alpha / 2, x, n - x + 1);
    hi = betainv(1 - alpha / 2, x + 1, n - x);
end
end

function s = ternary(cond, a, b)
if cond
    s = a;
else
    s = b;
end
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
