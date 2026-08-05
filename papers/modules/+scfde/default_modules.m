function modules = default_modules(overrides)
%DEFAULT_MODULES Default replaceable modules for the SC-TDE link.

modules.source = @scfde.source_bpsk;
modules.channel = @scfde.channel_two_branch_multipath;
modules.receiverBank = @scfde.receiver_bank_tde;
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
