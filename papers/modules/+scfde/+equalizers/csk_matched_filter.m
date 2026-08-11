function receiver = csk_matched_filter(channel, source, cfg)
%CSK_MATCHED_FILTER CSK matched-filter / correlation receiver (book 6-7~6-12).
% channel.received is row-major: symbol 1 chips, symbol 2 chips, ...
codeLength = numel(channel.impulse);
if isfield(cfg, "codeLength"), codeLength = cfg.codeLength; end
M = 4;
if isfield(cfg, "cskOrder"), M = cfg.cskOrder; end
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, ~] = scfde.equalizers.ch6_csk_codebook(root, M);
users = 1;
if isfield(cfg, "conventionalUsers"), users = cfg.conventionalUsers; end
dicts = scfde.equalizers.ch6_conventional_dictionaries( ...
    book, channel.impulse, users);
symbolCount = min(floor(numel(channel.received) / codeLength), ...
    floor(numel(source.data) / codeLength));
decisions = zeros(1, symbolCount * codeLength);
detected = zeros(1, symbolCount);
for symbol = 1:symbolCount
    obs = channel.received((symbol - 1) * codeLength + (1:codeLength));
    [detected(symbol), ~] = scfde.equalizers.ch6_hard_dictionary_detect(obs, dicts{1});
    decisions((symbol - 1) * codeLength + (1:codeLength)) = book(detected(symbol), :);
end
% Soft chip output: circular matched filter of the received chips with
% the channel, so the constellation shows the soft spreading-chip
% estimates instead of the hard decisions.
N = numel(channel.received);
softChips = ifft(conj(fft(channel.impulse, N)) .* fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CSK-MF", "csk-matched-filter", ...
    decisions, zeros(size(decisions)), softChips, struct("indices", detected));
end
