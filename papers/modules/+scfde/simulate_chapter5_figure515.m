function result = simulate_chapter5_figure515(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE515 Reproduce the 3 km sparse channel impulse response.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.delays = [0 3 10];
defaults.pathAmplitudes = [0.76 0.55 0.38];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
assert(isvector(cfg.delays) && isvector(cfg.pathAmplitudes), ...
    "SCFDE:InvalidChannel", "delays and pathAmplitudes must be vectors.");
assert(numel(cfg.delays) == numel(cfg.pathAmplitudes), ...
    "SCFDE:InvalidChannel", "delays and pathAmplitudes must have equal length.");
assert(all(cfg.delays >= 0) && all(diff(cfg.delays) > 0), ...
    "SCFDE:InvalidChannel", "delays must be strictly increasing and nonnegative.");
assert(all(cfg.pathAmplitudes >= 0), ...
    "SCFDE:InvalidChannel", "pathAmplitudes must be nonnegative.");

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
delays = double(cfg.delays(:).');
pathAmplitudes = double(cfg.pathAmplitudes(:).');
maxDelay = max(delays);
impulseResponse = zeros(1, maxDelay + 1);
impulseResponse(delays + 1) = pathAmplitudes;

figurePath = fullfile(cfg.outputDir, "fig5_15_3km_sparse_channel.png");
matPath = fullfile(cfg.outputDir, "fig5_15_3km_sparse_channel.mat");
csvPath = fullfile(cfg.outputDir, "fig5_15_3km_sparse_channel.csv");
fig = figure("Color", "w", "Position", [120 80 760 560], "Visible", "off");
ax = axes(fig);
stem(ax, delays, pathAmplitudes, "filled", "k", "LineWidth", 1.2, ...
    "MarkerSize", 5);
grid(ax, "on"); ax.GridAlpha = 0.25;
xlim(ax, [0 maxDelay]); ylim(ax, [0 0.85]);
xticks(ax, 0:maxDelay);
xlabel(ax, "码片时延"); ylabel(ax, "归一化路径幅度");
title(ax, "图5-15 3 km 稀疏多径水声信道");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);

channel = struct("distanceKm", 3, "delays", delays, ...
    "pathAmplitudes", pathAmplitudes, "impulseResponse", impulseResponse);
result.config = cfg;
result.channel = channel;
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
writematrix([delays(:), pathAmplitudes(:)], csvPath);
save(matPath, "result", "cfg");
end

function output = merge_options_local(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
