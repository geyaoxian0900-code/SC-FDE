function receiver = csk_soft_sic(channel, source, cfg)
%CSK_SOFT_SIC CSK soft successive interference cancellation (book 6.2.2).
codeLength = numel(channel.impulse);
if isfield(cfg, "codeLength"), codeLength = cfg.codeLength; end
M = 4;
if isfield(cfg, "cskOrder"), M = cfg.cskOrder; end
users = 1;
if isfield(cfg, "conventionalUsers"), users = cfg.conventionalUsers; end
symbols = min(floor(numel(channel.received) / codeLength), ...
    floor(numel(source.data) / codeLength));
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, bits] = scfde.equalizers.ch6_csk_codebook(root, M);
channels = scfde.equalizers.ch6_dictionary_channels( ...
    channel.impulse, users, codeLength);
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, channels, users);
iterations = 4;
if isfield(cfg, "innerIterations"), iterations = cfg.innerIterations; end
received = reshape(channel.received(1:symbols * codeLength), codeLength, symbols).';
transmitted = zeros(users, symbols, codeLength);
[decisionHistory, ~] = scfde.equalizers.ch6_soft_sic_detect( ...
    received, dicts, cfg.noiseVariance, iterations, transmitted, []);
detected = decisionHistory(end, :);
decisions = zeros(1, symbols * codeLength);
for symbol = 1:symbols
    decisions((symbol - 1) * codeLength + (1:codeLength)) = ...
        book(detected(symbol), :);
end
receiver = scfde.equalizers.pack_equalizer("CSK-SoftSIC", "csk-soft-sic", ...
    decisions, zeros(size(decisions)), decisions, ...
    struct("history", decisionHistory));
end
