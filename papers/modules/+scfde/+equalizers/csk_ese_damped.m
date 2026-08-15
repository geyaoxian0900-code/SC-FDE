function receiver = csk_ese_damped(channel, source, cfg)
%CSK_ESE_DAMPED CSK-IDMA ESE with posterior damping (ENGINEERING).
%   ENGINEERING variant (BOOK_CONVENTIONS.md rule 2): the book defines
%   no posterior damping step, so the book path (csk_ese.m) uses
%   alpha = 1.  This variant applies P_new = (1-alpha)*P_old +
%   alpha*P_update with alpha = cfg.eseDamping (default 0.58, matching
%   run_chapter6_spread_spectrum_suite).
% ESE outputs information-symbol decisions (repetition-1/2 outer code);
% the exported symbol estimates fall back to a matched-filter hard
% decision so the unified BER comparison stays on codeword indices.
codeLength = numel(channel.impulse);
if isfield(cfg, "codeLength"), codeLength = cfg.codeLength; end
M = 4;
if isfield(cfg, "cskOrder"), M = cfg.cskOrder; end
users = 1;
if isfield(cfg, "idmaUsers"), users = cfg.idmaUsers; end
symbols = min(floor(numel(channel.received) / codeLength), ...
    floor(numel(source.data) / codeLength));
innerIterations = 3;
outerIterations = 3;
if isfield(cfg, "innerIterations"), innerIterations = cfg.innerIterations; end
if isfield(cfg, "outerIterations"), outerIterations = cfg.outerIterations; end
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, bits] = scfde.equalizers.ch6_csk_codebook(root, M);
% The dictionary builders derive the per-user channels themselves
% (ch6_idma_dictionaries / ch6_conventional_dictionaries call
% ch6_dictionary_channels internally); passing a pre-built users x
% codeLength channel matrix here would re-derive the users from its
% first row (multi-user channels broken).
[dicts, userChannels] = scfde.equalizers.ch6_idma_dictionaries( ...
    book, channel.impulse, users, cfg);
conventional = scfde.equalizers.ch6_conventional_dictionaries( ...
    book, channel.impulse, users);
% The repetition/interleaver pair comes from the SCENARIO (cfg.pair) so
% the decoder assumes the SAME structure that was transmitted; a local
% random pair would misalign the repetition code.
if isfield(cfg, "pair") && ~isempty(cfg.pair)
    pair = cfg.pair;
else
    pair = scfde.equalizers.ch6_repeated_symbol_indices(M, symbols, users);
end
received = reshape(channel.received(1:symbols * codeLength), codeLength, symbols).';
noiseVariance = cfg.noiseVariance * ones(1, users);
transmitted = zeros(users, symbols, codeLength);
% Damping alpha: P_new = (1-alpha)*P_old + alpha*P_update (engineering).
damping = 0.58;
if isfield(cfg, "eseDamping"), damping = cfg.eseDamping; end
[innerDecision, outerDecision, ~, ~, ~, ~] = scfde.equalizers.ch6_csk_idma_detect( ...
    received, dicts, userChannels, noiseVariance, pair, ...
    innerIterations, outerIterations, transmitted, false, damping);
% The ESE/IDMA decisions ARE the exported codeword indices (repetition
% outer decoding, last outer iteration, user 1).  The previous version
% exported a matched-filter hard decision instead, which made the
% unified BER measure the MF and not the ESE.  outerDecision holds one
% index per INFORMATION symbol (repetition-1/2); pair.indices maps each
% of the symbols transmitted codewords to its information symbol, so
% the exported codeword indices are infoIndices(pair.indices(:,1)).
infoIndices = squeeze(outerDecision(end, :, 1)).';
% Map each transmitted codeword to its INFORMATION symbol: codeword s
% carries the code index pair.indices(s,1), which belongs to the
% information symbol k with pair.information(k,1) == pair.indices(s,1).
infoOf = zeros(1, symbols);
for s = 1:symbols
    infoOf(s) = find(pair.information(:, 1) == pair.indices(s, 1), 1);
end
codeIndices = infoIndices(infoOf).';
decisions = zeros(1, symbols * codeLength);
for symbol = 1:symbols
    decisions((symbol - 1) * codeLength + (1:codeLength)) = ...
        book(codeIndices(symbol), :);
end
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with csk_matched_filter), so the
% constellation shows the soft spreading-chip estimates.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CSK-IDMA-ESE-DAMPED", "csk-ese-damped", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("indices", codeIndices, "infoIndices", infoIndices, ...
    "damping", damping, "formulaStatus", "ENGINEERING"));
end

