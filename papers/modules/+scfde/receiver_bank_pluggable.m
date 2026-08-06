function receiver = receiver_bank_pluggable(channel, source, cfg)
%RECEIVER_BANK_PLUGGABLE Run a bank of pluggable equalizer modules.
%
% The set of equalizers is taken from cfg.equalizers, which accepts:
%   - "all"                        (default) run every built-in module
%   - string array of module IDs   built-ins from equalizer_registry
%   - function handle              one custom module
%   - cell array                   mix of IDs and function handles
%
% Every module follows the contract
%   receiver = equalizer(channel, source, cfg)
% and must return receiver.outputs{1} (symbol estimates), receiver.ids,
% receiver.names and optionally receiver.traces/receiver.learningMse.
% Custom modules can therefore be plugged in without touching built-ins.

if isfield(cfg, "equalizers")
    requested = cfg.equalizers;
else
    requested = "all";
end
modules = resolve_equalizer_modules(requested);

registry = scfde.equalizer_registry();
receiver.names = strings(1, numel(modules));
receiver.ids = strings(1, numel(modules));
receiver.outputs = cell(1, numel(modules));
receiver.learningMse = cell(1, numel(modules));
receiver.estimates = cell(1, numel(modules));
receiver.traces = cell(1, numel(modules));
receiver.requestedMethods = strings(1, numel(modules));

for moduleIndex = 1:numel(modules)
    module = modules{moduleIndex};
    if isa(module, "function_handle")
        single = module(channel, source, cfg);
        assert(isfield(single, "outputs") && numel(single.outputs) == 1, ...
            "SCFDE:InvalidEqualizer", ...
            "Equalizer module must return receiver.outputs{1}.");
        receiver.names(moduleIndex) = single.names;
        receiver.ids(moduleIndex) = single.ids;
        receiver.outputs{moduleIndex} = single.outputs{1};
        receiver.learningMse{moduleIndex} = unpack_cell(single, "learningMse");
        receiver.estimates{moduleIndex} = unpack_cell(single, "estimates");
        receiver.traces{moduleIndex} = unpack_cell(single, "traces");
        receiver.requestedMethods(moduleIndex) = single.ids;
    else
        id = string(module);
        match = find(strcmpi(registry.id, id), 1);
        assert(~isempty(match), "SCFDE:UnknownEqualizer", ...
            "Unknown equalizer ID: %s. Available: %s", id, ...
            strjoin(registry.id, ", "));
        builtin = registry.module{match}(channel, source, cfg);
        receiver.names(moduleIndex) = builtin.names;
        receiver.ids(moduleIndex) = registry.id(match);
        receiver.outputs{moduleIndex} = builtin.outputs{1};
        receiver.learningMse{moduleIndex} = unpack_cell(builtin, "learningMse");
        receiver.estimates{moduleIndex} = unpack_cell(builtin, "estimates");
        receiver.traces{moduleIndex} = unpack_cell(builtin, "traces");
        receiver.requestedMethods(moduleIndex) = registry.id(match);
    end
end
end

function modules = resolve_equalizer_modules(requested)
if isa(requested, "function_handle")
    modules = {requested};
    return;
end
if iscell(requested)
    modules = requested;
    return;
end
requested = string(requested);
if isscalar(requested) && requested == "all"
    % "all" runs the symbol-aligned equalizers (ch2 TDE + ch3 FDE) that
    % share the same frame structure. Chapter 4/5/6 equalizers use their
    % own frame formats and must be selected explicitly by ID.
    modules = {@scfde.equalizers.conventional_dfe, ...
        @scfde.equalizers.lms_dfe, @scfde.equalizers.nlms_dfe, ...
        @scfde.equalizers.rls_dfe, @scfde.equalizers.dpll_dfe, ...
        @scfde.equalizers.mc_lms_dfe, @scfde.equalizers.mc_nlms_dfe, ...
        @scfde.equalizers.mc_rls_dfe, @scfde.equalizers.ptr_dfe, ...
        @scfde.equalizers.subband_ptr_dfe, ...
        @scfde.equalizers.mmse_fde, @scfde.equalizers.zf_fde, ...
        @scfde.equalizers.htfde, @scfde.equalizers.sd_ibdfe, ...
        @scfde.equalizers.hd_ibdfe, @scfde.equalizers.ice_sd_ibdfe, ...
        @scfde.equalizers.ice_hd_ibdfe};
    return;
end
if isstring(requested) && ~isscalar(requested)
    modules = num2cell(requested);
    return;
end
if isstring(requested) && isscalar(requested) && startsWith(requested, "@")
    modules = {str2func(char(requested))};
    return;
end
if isstring(requested) && isscalar(requested)
    modules = {requested};
    return;
end
error("SCFDE:InvalidEqualizers", ...
    "cfg.equalizers must be 'all', an ID string, a function handle, or a cell array.");
end

function value = unpack_cell(s, name)
if isfield(s, name) && ~isempty(s.(name)) && iscell(s.(name))
    value = s.(name){1};
elseif isfield(s, name)
    value = s.(name);
else
    value = [];
end
end
