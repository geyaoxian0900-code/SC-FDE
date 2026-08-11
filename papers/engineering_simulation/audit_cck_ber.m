function audit_cck_ber(options)
%AUDIT_CCK_BER Independent BER audit of the seven CCK equalizers.
%   AUDIT_CCK_BER()
%
% Invariants:
%   1) identity + zero noise -> BER exactly 0
%   2) correlation oracle: for each transmitted codeword the true
%      codeword's correlation is maximal (k_hat = argmin distance to
%      the received chips)
%   3) forward-only / reverse-only / combined oracle BER for the
%      bidirectional methods, with the reverse path checked to align
%      decision(i) <-> tx(i) (NOT tx(N-i+1))
%   4) (N_err, N_bits, BER) with 95% Clopper-Pearson interval

if nargin < 1
    options = struct();
end
snrDb = field_default(options, "snrDb", 12);
frames = field_default(options, "frames", 20);
seed = field_default(options, "seed", 42);

registry = scfde.equalizer_registry();
ids = registry.id(registry.scenario == "cck");
[book, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
fprintf("=== CCK equalizer BER audit (%d methods) ===\n", numel(ids));

% --- 1) identity + zero noise ------------------------------------------
fprintf("\n--- 1) Identity channel + zero noise (BER must be 0) ---\n");
for id = ids
    [err, bits] = run_method(id, 1, 99, "identity", seed, book, bitTable);
    fprintf("  %-16s err=%d bits=%d BER=%g\n", id, err, bits, err / bits);
end

% --- 2) correlation oracle (true codeword must be nearest) -------------
fprintf("\n--- 2) Correlation oracle at SNR %d dB ---\n", snrDb);
oracleErrors = 0;
oracleBits = 0;
rng(seed, "twister");
for frame = 1:frames
    idx = randi(size(book, 1), 1, 8);
    [received, nv] = make_frame(idx, snrDb, "multipath");
    for s = 1:8
        det = nearest_codeword(received((s - 1) * 8 + (1:8)), book);
        if det ~= idx(s)
            oracleErrors = oracleErrors + sum(bitTable(det, :) ~= bitTable(idx(s), :));
        end
        oracleBits = oracleBits + numel(bitTable(idx(s), :));
    end
end
fprintf("  oracle BER = %.4e (%d/%d)\n", oracleErrors / oracleBits, ...
    oracleErrors, oracleBits);

% --- 3) bidirectional structural tests (cck-bidfe, cck-bidfe2) ---------
fprintf("\n--- 3) Bidirectional stage oracles (independent forward/reverse/combined/refined) ---\n");
for id = ["cck-bidfe", "cck-bidfe2"]
    [fErr, fBits] = run_bidi(id, "forward", snrDb, frames, seed, book, bitTable);
    [rErr, rBits] = run_bidi(id, "reverse", snrDb, frames, seed, book, bitTable);
    [cErr, cBits] = run_bidi(id, "combined", snrDb, frames, seed, book, bitTable);
    if id == "cck-bidfe2"
        [nErr, nBits] = run_bidi(id, "refined", snrDb, frames, seed, book, bitTable);
        fprintf("  %-12s forward %.4e (%d/%d) | reverse %.4e (%d/%d) | combined %.4e (%d/%d) | refined %.4e (%d/%d)\n", ...
            id, fErr / fBits, fErr, fBits, rErr / rBits, rErr, rBits, ...
            cErr / cBits, cErr, cBits, nErr / nBits, nErr, nBits);
    else
        fprintf("  %-12s forward %.4e (%d/%d) | reverse %.4e (%d/%d) | combined %.4e (%d/%d)\n", ...
            id, fErr / fBits, fErr, fBits, rErr / rBits, rErr, rBits, ...
            cErr / cBits, cErr, cBits);
    end
end

% --- 4) per-method reported BER with CI --------------------------------
fprintf("\n--- 4) Per-method independent BER (SNR %d dB, %d frames) ---\n", ...
    snrDb, frames);
alpha = 0.05;
for id = ids
    [err, bits] = run_method(id, frames, snrDb, "multipath", 42, book, bitTable);
    ber = err / bits;
    [lo, hi] = clopper_pearson(err, bits, alpha);
    fprintf("  %-16s err=%d bits=%d BER=%.4e [%.2e, %.2e]\n", ...
        id, err, bits, ber, lo, hi);
end
end

function [err, bits] = run_method(id, frames, snrDb, channelMode, scenarioSeed, book, bitTable)
registry = scfde.equalizer_registry();
module = registry.module{find(registry.id == id, 1)};
totalErrors = 0;
totalBits = 0;
rng(scenarioSeed, "twister");
for frame = 1:frames
    idx = randi(size(book, 1), 1, 8);
    [received, nv] = make_frame(idx, snrDb, channelMode);
    % Identity/AWGN audits send the signal through an IDENTITY channel:
    % the module must assume the same channel it actually sees, or the
    % mismatch (5-tap assumed, identity sent) produces spurious errors.
    if strcmpi(channelMode, "identity") || strcmpi(channelMode, "awgn")
        chImpulse = [1, 0, 0];
    else
        chImpulse = scfde.equalizers.ch5_short_turbo_channel();
    end
    ch = struct("received", received, "impulse", chImpulse, ...
        "branches", [received; received]);
    src = struct("data", reshape(book(idx, :).', 1, []), ...
        "tx", received, "training", received(1:32));
    cfg = struct("noiseVariance", nv, "receiverCandidateLimit", 128, ...
        "turboIterations", 3, "snrDb", snrDb);
    receiver = module(ch, src, cfg);
    trace = receiver.traces{1};
    if isfield(trace, "indices")
        det = trace.indices(:);
        det = det(1:min(8, numel(det)));
        if numel(det) < 8
            % A detector that drops blocks is an ERROR: padding with
            % the correlation oracle used to mask block-truncation
            % bugs and still report BER 0.
            error("SCFDE:AuditBlockDrop", ...
                "%s returned %d blocks (expected 8) - block truncation", ...
                id, numel(det));
        end
    else
        % Modules must expose their index trace (cck-fde previously
        % returned only 'history' and silently fell back to the oracle).
        error("SCFDE:AuditNoTrace", "%s trace lacks indices", id);
    end
    txBits = reshape(bitTable(idx, :).', 1, []);
    rxBits = reshape(bitTable(det, :).', 1, []);
    totalErrors = totalErrors + sum(rxBits ~= txBits);
    totalBits = totalBits + numel(txBits);
end
err = totalErrors;
bits = totalBits;
end

function [err, bits] = run_bidi(id, direction, snrDb, frames, seed, book, bitTable)
% Directional oracles run the THREE pipeline stages INDEPENDENTLY
% (plus the BiDFE-2 refinement), NOT the module's combined trace:
%   forward  = ch5_dfe_detect
%   reverse  = ch5_backward_dfe_detect (already in ORIGINAL block
%              order - the module flips back internally, so no post-hoc
%              flip here; a flip would compare tx(i) against tx(N-i+1))
%   combined = ch5_fuse_scores(S_f, S_r)
%   refined  = ch5_bidirectional_refine (BiDFE-2 only)
% A detector that drops blocks is an ERROR (the old oracle fallback
% padded short outputs, masking block-truncation bugs).
totalErrors = 0;
totalBits = 0;
rng(seed, "twister");
for frame = 1:frames
    idx = randi(size(book, 1), 1, 8);
    [received, nv] = make_frame(idx, snrDb, "multipath");
    imp = scfde.equalizers.ch5_short_turbo_channel();
    switch lower(string(direction))
        case "forward"
            det = scfde.equalizers.ch5_dfe_detect(received, book, imp, nv, 128);
        case "reverse"
            det = scfde.equalizers.ch5_backward_dfe_detect(received, book, imp, nv, 128);
        case "combined"
            [~, fwdS] = scfde.equalizers.ch5_dfe_detect(received, book, imp, nv, 128);
            [~, bwS] = scfde.equalizers.ch5_backward_dfe_detect(received, book, imp, nv, 128);
            det = scfde.equalizers.ch5_fuse_scores(fwdS, bwS);
        case "refined"
            [~, fwdS] = scfde.equalizers.ch5_dfe_detect(received, book, imp, nv, 128);
            [~, bwS] = scfde.equalizers.ch5_backward_dfe_detect(received, book, imp, nv, 128);
            bi1 = scfde.equalizers.ch5_fuse_scores(fwdS, bwS);
            det = scfde.equalizers.ch5_bidirectional_refine(received, book, imp, bi1, nv, 128);
        otherwise
            error("SCFDE:AuditBidi", "unknown direction %s", direction);
    end
    det = det(:).';
    assert(numel(det) == 8, ...
        "%s %s returned %d blocks (expected 8) - block truncation", ...
        id, direction, numel(det));
    txBits = reshape(bitTable(idx, :).', 1, []);
    rxBits = reshape(bitTable(det, :).', 1, []);
    totalErrors = totalErrors + sum(rxBits ~= txBits);
    totalBits = totalBits + numel(txBits);
end
err = totalErrors;
bits = totalBits;
end

function [received, nv] = make_frame(idx, snrDb, channelMode)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
chips = reshape(book(idx, :).', 1, []);
imp = scfde.equalizers.ch5_short_turbo_channel();
nv = 10^(-snrDb / 10);
switch channelMode
    case "identity"
        received = chips;
    case "awgn"
        received = chips + sqrt(nv / 2) * ...
            (randn(size(chips)) + 1j * randn(size(chips)));
    otherwise
        received = filter(imp, 1, [chips, zeros(1, numel(imp) - 1)]);
        received = received + sqrt(nv / 2) * ...
            (randn(size(received)) + 1j * randn(size(received)));
end
end

function idxs = oracle_indices(received, book)
idxs = zeros(1, 8);
for s = 1:8
    idxs(s) = nearest_codeword(received((s - 1) * 8 + (1:8)), book);
end
end

function idx = nearest_codeword(chips, book)
% Correlation oracle: k_hat = argmin_k |c - c_k|^2 over the codebook.
distance = sum(abs(book - chips).^2, 2);
[~, idx] = min(distance);
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

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
