function [dictionaries, channels] = ch6_idma_dictionaries(book, channel, users, cfg)
%CH6_IDMA_DICTIONARIES Per-user chip-interleaved dictionaries.
%   [DICTS, CHANNELS] = CH6_IDMA_DICTIONARIES(BOOK, CHANNEL, USERS, CFG)
%
% The IDMA chip interleaver (book 6.3) must be part of the FRAME
% CONTRACT: the same permutation Pi_u is used by the transmitter and
% the receiver.  The permutation is taken from
% cfg.idmaChipPermutation (1 x codeLength, or users x codeLength);
% with a single user the default is the IDENTITY permutation, so the
% ESE dictionary equals the conventional dictionary and Tx/Rx are the
% same model.  A random randperm inside the receiver would silently
% mismatch the transmitted dictionary (the symptom: MF=0, ESE~0.5).

lengthCode = size(book, 2);
channels = scfde.equalizers.ch6_dictionary_channels(channel, users, lengthCode);
dictionaries = cell(1, users);
if users == 1 && ~(isfield(cfg, "idmaChipPermutation") && ...
        ~isempty(cfg.idmaChipPermutation))
    % Single user without an explicit chip interleaver: the IDMA
    % dictionary must equal the CONVENTIONAL dictionary used by the
    % transmitter (the conventional construction applies the per-user
    % cyclic shift mod(3*u-2, N)); otherwise the ESE hypothesis model
    % mismatches the transmitted codewords by one shift (symptom:
    % MF=0, ESE~0.5).
    dictionaries = scfde.equalizers.ch6_conventional_dictionaries( ...
        book, channel, users);
    return;
end
for user = 1:users
    if isfield(cfg, "idmaChipPermutation") && ~isempty(cfg.idmaChipPermutation)
        if size(cfg.idmaChipPermutation, 1) == users
            permutation = cfg.idmaChipPermutation(user, :);
        else
            permutation = cfg.idmaChipPermutation;
        end
    elseif users == 1
        permutation = 1:lengthCode;
    else
        error("SCFDE:IdmaPermutation", ...
            "Multi-user IDMA requires cfg.idmaChipPermutation (the chip interleaver is part of the frame contract).");
    end
    dictionaries{user} = scfde.equalizers.ch6_apply_circular_channel( ...
        book(:, permutation), channels(user, :));
end
end
