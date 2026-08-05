function result = simulate_chapter5_figure514(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE514 Reproduce the single-panel Fig. 5-14 AWGN plot.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
defaults.snrList = 0:1:12;
defaults.symbols = 256;
defaults.frameCount = 40;
defaults.randomSeed = 20260801;
defaults.makePlot = false;
defaults.groups = "gcck";
defaults.gcckModes = ["GCCK-QPSK-4R", "GCCK-QPSK-8R", "GCCK-8PSK-12R"];
defaults.receiverMethods = "Rake";
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
defaults.awgnDefinition = "EbN0";
cfg = merge_options_local(defaults, options);
result = scfde.run_chapter5_5_cck_suite(cfg, simulationDir);

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_14_gcck_awgn_ber.png");
matPath = fullfile(cfg.outputDir, "fig5_14_gcck_awgn_ber.mat");
csvPath = fullfile(cfg.outputDir, "fig5_14_gcck_awgn_ber.csv");

fig = figure("Color", "w", "Position", [120 80 760 560], "Visible", "off");
ax = axes(fig); hold(ax, "on");
colors = [0.00 0.00 0.00; 0.20 0.35 0.75; 0.75 0.15 0.10];
markers = ["o", "s", "^"];
for index = 1:numel(result.gcck.modeNames)
    semilogy(ax, result.gcck.snrList, max(result.gcck.awgnBer(index, :), 1e-6), ...
        "-", "Color", colors(index, :), "Marker", markers(index), ...
        "LineWidth", 1.25, "MarkerSize", 5, ...
        "DisplayName", result.gcck.modeNames(index) + " 仿真");
    semilogy(ax, result.gcck.snrList, max(result.gcck.unionBound(index, :), 1e-6), ...
        "--", "Color", colors(index, :), "LineWidth", 1.0, ...
        "DisplayName", result.gcck.modeNames(index) + " 理论");
end
grid(ax, "on"); ax.GridAlpha = 0.25;
xlabel(ax, "信噪比 E_b/N_0 (dB)"); ylabel(ax, "误码率 BER");
ax.YScale = "log";
xlim(ax, [0 12]); ylim(ax, [1e-6 1]);
title(ax, "图5-14 GCCK 在 AWGN 信道中的基本性能");
legend(ax, "Location", "southwest", "NumColumns", 2);
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);
data = [result.gcck.snrList(:), result.gcck.awgnBer.', result.gcck.unionBound.'];
writematrix(data, csvPath);
save(matPath, "result", "cfg");
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
end

function output = merge_options_local(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
