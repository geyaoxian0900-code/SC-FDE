function receiver = pack_equalizer(name, id, decisions, mse, estimates, trace)
%PACK_EQUALIZER Wrap a single equalizer result into the receiver contract.
receiver.names = string(name);
receiver.ids = string(id);
receiver.outputs = {decisions};
receiver.learningMse = {mse};
receiver.estimates = {estimates};
receiver.traces = {trace};
receiver.requestedMethods = string(id);
end
