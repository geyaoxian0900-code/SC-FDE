function receiver = pack_equalizer(name, id, decisions, mse, estimates, trace)
%PACK_EQUALIZER Wrap a single equalizer result into the receiver contract.
% The DECISIONS argument is the equalizer's output in the metric domain
% of the driving scenario (see receiver_bank_pluggable):
%   qpsk   data-symbol estimates (the metric adapter slices them)
%   turbo  512 information-symbol decisions after BCJR
%   cck/csk chip or spreading-sequence estimates; detected indices are
%          reported through trace.indices
% It is NOT universally aligned with source.tx.
receiver.names = string(name);
receiver.ids = string(id);
receiver.outputs = {decisions};
receiver.learningMse = {mse};
receiver.estimates = {estimates};
receiver.traces = {trace};
receiver.requestedMethods = string(id);
end
