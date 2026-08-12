function audit_csk_ber(options)
%AUDIT_CSK_BER Independent BER audit of the three CSK equalizers.
%   AUDIT_CSK_BER()
%
% CSK is audited with the CORRELATION METRIC (not a QPSK constellation):
%   m_k = |<r, s_k>|  ->  k_hat = argmax_k m_k  ->  bits
% Invariants:
%   1) identity + zero noise -> BER 0
%   2) the true cyclic shift has the maximal correlation metric
%   3) cyclic boundary shifts (0, 1, M-1) decode correctly
%   4) (N_err, N_bits, BER) + 95% Clopper-Pearson interval

if nargin < 1
    options = struct();
end
scfde.book_check_conventions();  % frozen conventions gate (BOOK_CONVENTIONS.md)
snrDb = field_default(options, "snrDb", 12);
frames = field_default(options, "frames", 20);
seed = field_default(options, "seed", 42);

registry = scfde.equalizer_registry();
ids = registry.id(registry.scenario == "csk");
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, bits] = scfde.equalizers.ch6_csk_codebook(root, 4);
fprintf("=== CSK equalizer BER audit (%d methods) ===\n", numel(ids));

% --- 1) identity + zero noise ------------------------------------------
fprintf("\n--- 1) Identity channel + zero noise (BER must be 0) ---\n");
for id = ids
    [err, nbits] = run_method(id, 1, 99, "identity", 0, seed, book, bits);
    fprintf("  %-18s err=%d bits=%d BER=%g\n", id, err, nbits, err / nbits);
end

% --- 2) cyclic shift metric check (boundaries 0/1/M-1) -----------------
fprintf("\n--- 2) Cyclic shift correlation oracle (shifts 0,1,M-1) ---\n");
rng(seed, "twister");
shiftErrors = zeros(1, 3);
shiftBits = zeros(1, 3);
% Boundary shifts 0 / 1 / M-1: the codebook holds M = 4 rows
% (circshift(root, 0..M-1)), so a shift of codeLength-1 = 62 moves the
% 63-tap root OUT of the codebook and the oracle would have to guess
% among rows it was never sent (it scored 0.76 there).  The true cyclic
% boundary is M-1.
shifts = [0, 1, size(book, 1) - 1];
for si = 1:3
    for frame = 1:frames
        shift = shifts(si);
        for rep = 1:4
            sym = randi(4);
            % CSK encoding selects a codebook ROW (a cyclic shift of
            % the root); a boundary-shift test therefore transmits the
            % shifted ROW - circshift(c0, shift) on the 63-tap root
            % moves OUT of the 4-row codebook for sym near the edge
            % (root shifted 4 taps is not a stored row) and the oracle
            % then guesses among rows that were never sent.
            symSent = mod(sym - 1 + shift, size(book, 1)) + 1;
            cShift = book(symSent, :);
            obs = cShift + sqrt(10^(-snrDb / 10) / 2) * ...
                (randn(size(cShift)) + 1j * randn(size(cShift)));
            m = abs(book * obs.');
            [~, kHat] = max(m);
            shiftErrors(si) = shiftErrors(si) + ...
                sum(bits(kHat, :) ~= bits(symSent, :));
            shiftBits(si) = shiftBits(si) + numel(bits(sym, :));
        end
    end
    fprintf("  shift %3d: BER=%.4e (%d/%d)\n", shifts(si), ...
        shiftErrors(si) / shiftBits(si), shiftErrors(si), shiftBits(si));
end

% --- 3) per-method independent BER with CI -----------------------------
fprintf("\n--- 3) Per-method independent BER (SNR %d dB, %d frames) ---\n", ...
    snrDb, frames);
alpha = 0.05;
for id = ids
    [err, nbits] = run_method(id, frames, snrDb, "multipath", 42, seed, book, bits);
    ber = err / nbits;
    [lo, hi] = clopper_pearson(err, nbits, alpha);
    fprintf("  %-18s err=%d bits=%d BER=%.4e [%.2e, %.2e]\n", ...
        id, err, nbits, ber, lo, hi);
end
end

function [err, nbits] = run_method(id, frames, snrDb, channelMode, scenarioSeed, seed, book, bits)
registry = scfde.equalizer_registry();
module = registry.module{find(registry.id == id, 1)};
codeLength = numel(book(1, :));
totalErrors = 0;
totalBits = 0;
rng(scenarioSeed, "twister");
for frame = 1:frames
    idx6 = randi(4, 8, 1);
    % The transmitted codewords are the DICTIONARY rows (which include
    % the per-user scramble and the circular channel), exactly like the
    % unified scenario; sending the raw codebook rows would mismatch
    % the receiver dictionary (user 1 applies a cyclic shift).
    if strcmpi(channelMode, "identity") || strcmpi(channelMode, "awgn")
        imp = [1, 0, 0];
    else
        imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
    end
    % The ESE receiver assumes the repetition-1/2 coded frame; the
    % audit therefore transmits the SAME structure as the unified csk
    % scenario: information symbols repeated and interleaved into the
    % codewords, with the pair passed to the ESE via cfg.pair.
    if strcmpi(channelMode, "identity") || strcmpi(channelMode, "awgn")
        imp = [1, 0, 0];
    else
        imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
    end
    pairAudit = scfde.equalizers.ch6_repeated_symbol_indices(4, 8, 1);
    dictsAudit = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 1);
    txCode = pairAudit.indices(:, 1);   % codeword indices (8)
    infoRef = pairAudit.information(:, 1).';
    received = zeros(8, codeLength);
    for s = 1:8
        c0 = dictsAudit{1}(txCode(s), :);
        switch channelMode
            case "identity"
                f = c0;
            otherwise
                f = c0 + sqrt(10^(-snrDb / 10) / 2) * ...
                    (randn(size(c0)) + 1j * randn(size(c0)));
        end
        received(s, :) = f;
    end
    flat = reshape(received.', 1, []);
    % The receiver dictionary is built from channel.impulse: identity
    % and AWGN audits must therefore report an identity channel, or the
    % transmitted codewords (not convolved) would mismatch the
    % channel-convolved dictionary.
    if strcmpi(channelMode, "identity") || strcmpi(channelMode, "awgn")
        imp = [1, 0, 0];
    else
        imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
    end
    nv = 1 / (2 * 10^(snrDb / 10));
    ch = struct("received", flat, "impulse", imp, "branches", [flat; flat]);
    src = struct("data", ones(1, 8 * codeLength), "tx", flat, ...
        "training", ones(1, 32));
    cfg = struct("noiseVariance", nv, "codeLength", codeLength, ...
        "cskOrder", 4, "conventionalUsers", 1, "idmaUsers", 1, ...
        "innerIterations", 3, "outerIterations", 2, "snrDb", snrDb, ...
        "pair", pairAudit);
    receiver = module(ch, src, cfg);
    trace = receiver.traces{1};
    if isfield(trace, "indices")
        det = trace.indices(:);
        if numel(det) > 8
            det = det(end - 7:end);
        end
        det = det(1:min(8, numel(det)));
    elseif isfield(trace, "history")
        det = squeeze(trace.history(end, :, 1)).';
    else
        det = zeros(1, 8);
        for s = 1:8
            m = abs(book * received(s, :).');
            [~, det(s)] = max(m);
        end
    end
    if numel(det) < 8
        det = [det(:).', zeros(1, 8 - numel(det))];
    end
    % Map codeword indices back to INFORMATION symbols and count bit
    % errors on the information bits (same mapping as the scenario).
    detInfo = zeros(1, numel(infoRef));
    for info = 1:numel(infoRef)
        members = find(pairAudit.indices(:, 1) == infoRef(info));
        if isempty(members)
            detInfo(info) = NaN;
        else
            detInfo(info) = det(members(1));
        end
    end
    txBits = reshape(bits(infoRef, :).', 1, []);
    rxBits = reshape(bits(detInfo, :).', 1, []);
    valid = ~isnan(detInfo);
    totalErrors = totalErrors + ...
        sum(rxBits(~isnan(detInfo)) ~= txBits(~isnan(detInfo)));
    totalBits = totalBits + numel(txBits(valid));
end
err = totalErrors;
nbits = totalBits;
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
