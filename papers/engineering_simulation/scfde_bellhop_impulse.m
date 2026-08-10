function impulse = scfde_bellhop_impulse(bellhopOptions, symbolRateHz, maxTaps)
%SCFDE_BELLHOP_IMPULSE Run Bellhop and sample its arrivals into a
% symbol-rate complex impulse response for the unified equalizer entry.
%   IMPULSE = SCFDE_BELLHOP_IMPULSE(OPTIONS, SYMBOLRATEHZ, MAXTAPS)
%
% The Bellhop arrivals (path delays in ms and complex gains) are
% converted to an integer-tap symbol-rate impulse response:
%     tap = round(delayMs / 1000 * symbolRateHz) + 1
% and normalized to unit energy.  Taps beyond MAXTAPS are discarded
% (documented truncation of the physical spread, not a metric fix).
%
% OPTIONS is passed to scfde_bellhop_channel; defaults (100 m water,
% 20 m source, 30 m receiver, 1 km range, 12 kHz) apply when absent.
% The Bellhop run is cached under papers/results so repeated scenario
% executions reuse the same arrivals.

defaults = struct("bellhopWaterDepth", 100, "bellhopSourceDepth", 20, ...
    "bellhopReceiverDepth", 30, "bellhopRangeKm", 1.0, ...
    "carrierHz", 12000, "txSampleRate", 96000, ...
    "bellhopSediment", "custom", "bellhopSsp", "linear");
if nargin < 1 || isempty(bellhopOptions)
    bellhopOptions = struct();
end
names = fieldnames(defaults);
for k = 1:numel(names)
    if ~isfield(bellhopOptions, names{k})
        bellhopOptions.(names{k}) = defaults.(names{k});
    end
end
cacheFile = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "bellhop_impulse_cache.mat");
sediment = field_default(bellhopOptions, "bellhopSediment", "custom");
ssp = field_default(bellhopOptions, "bellhopSsp", "linear");
cacheKey = sprintf("%.1f_%.1f_%.1f_%.2f_%d_%s_%s", ...
    bellhopOptions.bellhopWaterDepth, bellhopOptions.bellhopSourceDepth, ...
    bellhopOptions.bellhopReceiverDepth, bellhopOptions.bellhopRangeKm, ...
    bellhopOptions.carrierHz, sediment, ssp);
if isfile(cacheFile)
    cache = load(cacheFile);
    if isfield(cache, "cacheKey") && strcmp(cache.cacheKey, cacheKey)
        impulse = cache.impulse;
        return;
    end
end
[pathDelaysMs, pathGains] = scfde_bellhop_channel(bellhopOptions);
maxTap = min(maxTaps, round(max(pathDelaysMs) / 1000 * symbolRateHz) + 1);
impulse = zeros(1, maxTap);
for path = 1:numel(pathDelaysMs)
    tap = round(pathDelaysMs(path) / 1000 * symbolRateHz) + 1;
    if tap >= 1 && tap <= maxTap
        impulse(tap) = impulse(tap) + pathGains(path);
    end
end
if norm(impulse) > 0
    impulse = impulse / norm(impulse);
end
cache = struct("cacheKey", cacheKey, "impulse", impulse, ...
    "timestamp", datetime("now"));
if ~exist(fileparts(cacheFile), "dir")
    mkdir(fileparts(cacheFile));
end
save(cacheFile, "cache");
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
