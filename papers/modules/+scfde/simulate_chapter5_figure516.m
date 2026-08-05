function result = simulate_chapter5_figure516(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE516 Reproduce the GCCK-QPSK-4R receiver comparison.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
defaults.snrList = 0:1:10;
defaults.snrDb = 8;
defaults.symbols = 64;
defaults.frameCount = 5;
defaults.randomSeed = 20260802;
defaults.groups = "gcck";
defaults.gcckModes = "GCCK-QPSK-4R";
defaults.receiverMethods = "all";
defaults.dynamicAlphas = 1;
defaults.gcckChannel = [0.76 0 0 0.55 0 0 0 0 0 0 0.38];
defaults.receiverSnrDefinition = "EbN0";
defaults.makePlot = false;
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
result = scfde.run_chapter5_5_cck_suite(cfg, simulationDir);

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_16_gcck_qpsk_4r_receivers.png");
matPath = fullfile(cfg.outputDir, "fig5_16_gcck_qpsk_4r_receivers.mat");
csvPath = fullfile(cfg.outputDir, "fig5_16_gcck_qpsk_4r_receivers.csv");

fig = figure("Color", "w", "Position", [120 80 760 560], "Visible", "off");
ax = axes(fig); hold(ax, "on");
styles = {"o-", "s-", "^-", "d-", "x-", "+-"};
for index = 1:numel(result.gcck.receiverNames)
    values = squeeze(result.gcck.receiverBer(1, index, :)).';
    semilogy(ax, result.gcck.snrList, max(values, 1e-6), styles{index}, ...
        "LineWidth", 1.15, "MarkerSize", 5, ...
        "DisplayName", result.gcck.receiverNames(index));
end
grid(ax, "on"); ax.GridAlpha = 0.25; ax.YScale = "log";
xlim(ax, [0 10]); ylim(ax, [1e-6 1]);
xlabel(ax, "信噪比 SNR (dB)"); ylabel(ax, "误码率 BER");
title(ax, "图5-16 GCCK-QPSK-4R 在 3 km 水声信道中的接收机性能比较");
legend(ax, "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);

snrValues = result.gcck.snrList(:);
berValues = squeeze(result.gcck.receiverBer(1, :, :)).';
writematrix([snrValues berValues], csvPath);
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
