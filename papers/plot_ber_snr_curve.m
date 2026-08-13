function plot_ber_snr_curve(ids, snrs, frameCount, channelOpts)
%PLOT_BER_SNR_CURVE  Select equalizers interactively (or by ID) and plot
%   BER vs SNR curves directly.  Same-scenario IDs share one figure;
%   multi-scenario selections produce one figure per scenario.
%
%   PLOT_BER_SNR_CURVE()                     interactive menu (multi-select)
%   PLOT_BER_SNR_CURVE("dfe")                one ID, default 6:2:18 dB
%   PLOT_BER_SNR_CURVE(["dfe","htfde"], 6:2:18)
%   PLOT_BER_SNR_CURVE(["dfe","htfde"], 6:2:18, 200)   % more frames per point
%   PLOT_BER_SNR_CURVE(["dfe","htfde"], 6:2:18, 200, ...
%       struct("pathDelays", [0 2 5], "pathGains", [1 0.5 0.25]))  % channel
%
%   Figures are saved to papers/results/ber_snr_curves/ as PNG.

rootDir = fileparts(mfilename("fullpath"));
addpath(rootDir);
addpath(fullfile(rootDir, "modules"));
addpath(fullfile(rootDir, "engineering_simulation"));
addpath(fullfile(rootDir, "examples"));

if nargin < 1 || isempty(ids)
    ids = choose_ids();
end
if nargin < 2 || isempty(snrs)
    snrs = 6:2:18;
end
if nargin < 3 || isempty(frameCount)
    frameCount = 100;
end
if nargin < 4 || isempty(channelOpts)
    channelOpts = struct();
end
if isstring(ids) && numel(ids) == 1 && contains(ids, ",")
    ids = strtrim(strsplit(ids, ","));
end
ids = string(ids(:).');

registry = scfde.equalizer_registry();
ids = intersect(ids, registry.id, "stable");

scenarios = unique(registry.scenario(ismember(registry.id, ids)), "stable");
figurePaths = strings(0);
for s = 1:numel(scenarios)
    sc = scenarios(s);
    scIds = registry.id(ismember(registry.id, ids) & registry.scenario == sc);
    ber = nan(numel(scIds), numel(snrs));
    ciHi = ber;
    for i = 1:numel(snrs)
        r = run_unified_equalizer(struct("equalizers", scIds, ...
            "scenario", sc, "snrDb", snrs(i), "frameCount", frameCount, ...
            "makePlot", false, "pathDelays", field_default(channelOpts, "pathDelays", []), ...
            "pathGains", field_default(channelOpts, "pathGains", []), ...
            "channelMode", field_default(channelOpts, "channelMode", "synthetic")));
        ber(:, i) = r.ber;
        ciHi(:, i) = r.berUpper95;
    end
    f = figure("Color", "w");
    set(f, "DefaultAxesFontSize", 11);
    fprintf("=== %s scenario: BER vs SNR ===\n", sc);
    fprintf("%-18s", "id");
    fprintf("%9.1f dB", snrs);
    fprintf("\n");
    for k = 1:numel(scIds)
        fprintf("%-18s", scIds(k));
        fprintf("%9.2g", ber(k, :));
        fprintf("\n");
    end
    for k = 1:numel(scIds)
        yneg = ber(k, :) - max(ber(k, :), 0);
        ypos = ciHi(k, :) - ber(k, :);
        errorbar(snrs, ber(k, :), yneg, ypos, "o-", "LineWidth", 1.4, ...
            "MarkerSize", 5, "DisplayName", scIds(k));
        hold on;
    end
    hold off;
    set(gca, "YScale", "log", "YLim", [1e-4, 1]);
    grid on;
    legend("Location", "southwest", "Interpreter", "none");
    xlabel("SNR (dB)"); ylabel("BER");
    title(sprintf("%s scenario - BER vs SNR (frameCount=%d, seed=42)", sc, frameCount));
    outDir = fullfile(rootDir, "results", "ber_snr_curves");
    if ~exist(outDir, "dir")
        mkdir(outDir);
    end
    name = sprintf("ber_snr_%s_%s.png", sc, ...
        strrep(strjoin(scIds, "_"), "-", "_"));
    figPath = fullfile(outDir, name);
    exportgraphics(f, figPath, "Resolution", 200);
    figurePaths(end + 1) = figPath; %#ok<AGROW>
    fprintf("saved: %s\n", figPath);
end
end

function ids = choose_ids()
registry = scfde.equalizer_registry();
n = numel(registry.id);
fprintf("=== equalizer selection (37) ===\n");
for k = 1:n
    fprintf("%2d. [ch%d/%s] %s\n", k, registry.chapter(k), ...
        registry.scenario(k), registry.id(k));
end
while true
    text = strtrim(input("选择编号（逗号或空格分隔，如 1,3,17）：", "s"));
    if strcmpi(text, "all")
        ids = registry.id;
        return;
    end
    if isempty(text)
        fprintf("输入无效，请重新输入。\n");
        continue;
    end
    toks = regexp(text, "\d+", "match");
    idx = str2double(toks);
    if isempty(idx) || any(idx < 1 | idx > n)
        fprintf("输入无效，请重新输入。\n");
        continue;
    end
    ids = registry.id(idx);
    return;
end
end

function v = field_default(opts, name, def)
if isfield(opts, name) && ~isempty(opts.(name))
    v = opts.(name);
else
    v = def;
end
end
