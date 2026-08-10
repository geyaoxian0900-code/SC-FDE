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
%
% OUTPUT-DOMAIN CONTRACT (the metric domain of receiver.outputs{1}
% depends on the scenario that drives the module):
%   qpsk    data-symbol estimates; full-frame TDE outputs are sliced by
%           the metric adapter in run_unified_equalizer
%   turbo   512 information-symbol decisions after the (7,5) BCJR
%           (training symbols never enter the decoder)
%   cck     chip estimates plus detected codeword indices in trace
%   csk     spreading-sequence estimates plus detected cyclic-shift
%           indices in trace

if isfield(cfg, "equalizers")
    requested = cfg.equalizers;
else
    requested = "all";
end
modules = resolve_equalizer_modules(requested, cfg);

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

function modules = resolve_equalizer_modules(requested, cfg)
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
    % "all" resolves to every registered equalizer of the CURRENT
    % scenario (cfg.scenario, default qpsk): 17 qpsk, 10 turbo,
    % 7 cck or 3 csk modules.  Each scenario owns its frame format,
    % so mixing scenarios inside one receiver bank is impossible.
    scenario = "qpsk";
    if isfield(cfg, "scenario") && ~isempty(cfg.scenario)
        scenario = string(cfg.scenario);
    end
    registry = scfde.equalizer_registry();
    selected = registry.scenario == scenario;
    modules = registry.module(selected);
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
