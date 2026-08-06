function modules = default_modules(overrides)
%DEFAULT_MODULES Default replaceable modules for the SC-TDE link.
%
% The receiverBank module is a bank dispatcher. Its set of equalizers is
% configured through cfg.equalizers (see receiver_bank_pluggable):
%   - "all"                        every built-in equalizer
%   - string array of module IDs   built-ins from equalizer_registry
%   - function handle              a single custom equalizer module
%   - cell array                   mix of IDs and custom function handles
% Every equalizer module follows the contract
%   receiver = equalizer(channel, source, cfg)
% so arbitrary equalizers can be plugged in without touching built-ins.

modules.source = @scfde.source_bpsk;
modules.channel = @scfde.channel_two_branch_multipath;
modules.receiverBank = @scfde.receiver_bank_pluggable;
modules.metric = @scfde.metric_ber;
modules.plot = [];

if nargin >= 1 && ~isempty(overrides)
    modules = scfde.merge_struct(modules, overrides);
end

required = ["source", "channel", "receiverBank", "metric"];
for name = required
    assert(isfield(modules, name) && isa(modules.(name), "function_handle"), ...
        "SCFDE:InvalidModule", "Module '%s' must be a function handle.", name);
end
if ~isempty(modules.plot)
    assert(isa(modules.plot, "function_handle"), ...
        "SCFDE:InvalidModule", "Module 'plot' must be empty or a function handle.");
end
end
