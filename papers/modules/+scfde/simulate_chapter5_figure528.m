function result = simulate_chapter5_figure528(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE528 Compare CCK receiver frame error rates over UWA.
%   FER is measured directly: one simulated CCK or TE-CCK frame is counted
%   as erroneous when at least one recovered information bit differs.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

baseOptions = options;
if ~isfield(baseOptions, "frontEndWords")
    baseOptions.frontEndWords = 24;
end
if ~isfield(baseOptions, "frontEndFrameCount")
    baseOptions.frontEndFrameCount = 24;
end
if ~isfield(baseOptions, "teFrameWords")
    % FER compares packets of equal CCK-codeword length across receivers.
    baseOptions.teFrameWords = baseOptions.frontEndWords;
end
if ~isfield(baseOptions, "teFrameCount")
    baseOptions.teFrameCount = baseOptions.frontEndFrameCount;
end
base = scfde.simulate_chapter5_figure527(baseOptions, simulationDir);
frontEndIndices = [1, 2, 4, 5, 6, 7];
methodCount = numel(base.methodLabels);
snrCount = numel(base.snrList);
frameErrors = zeros(methodCount, snrCount);
frameTotals = zeros(methodCount, snrCount);

frameErrors(1:6, :) = base.frontEnd.allIsiFrameErrorCounts(frontEndIndices, :);
frameTotals(1:6, :) = repmat(base.frontEnd.isiFrameTotals, 6, 1);
frameErrors(7, :) = base.rsse.frameErrorCounts;
frameTotals(7, :) = base.rsse.frameTotals;
frameErrors(8:12, :) = base.te.frameErrorCounts(2:6, :);
frameTotals(8:12, :) = base.te.frameTotals(2:6, :);

fer = frameErrors ./ frameTotals;
displayFer = fer;
displayFer(frameErrors == 0) = 0.5 ./ frameTotals(frameErrors == 0);

result.config = base.config;
result.methodLabels = base.methodLabels;
result.snrList = base.snrList;
result.fer = fer;
result.displayFer = displayFer;
result.frameErrorCounts = frameErrors;
result.frameTotals = frameTotals;
result.zeroErrorDisplayConvention = "0.5 / frameTotal";
result.baseBerResult = base;
result.figurePath = fullfile(base.config.outputDir, "fig5_28_uwa_cck_receiver_fer.png");
result.matPath = fullfile(base.config.outputDir, "fig5_28_uwa_cck_receiver_fer.mat");
result.csvPath = fullfile(base.config.outputDir, "fig5_28_uwa_cck_receiver_fer.csv");

write_figure(result);
write_table(result);
cfg = result.config;
save(result.matPath, "result", "cfg");
end

function write_figure(result)
fig = figure("Color", "w", "Position", [120, 55, 980, 850], "Visible", "off");
ax = axes(fig, "Position", [0.16, 0.22, 0.73, 0.70]);
hold(ax, "on");
styles = {"-o", "-s", "--*", ":o", ":^", ":*", "-", ...
    "-s", "->", "-o", "-*", "-d"};
colors = [0.87, 0.18, 0.14; 0.35, 0.65, 0.24; 0.15, 0.34, 0.66; ...
    0.15, 0.34, 0.66; 0.64, 0.34, 0.62; 0.64, 0.34, 0.62; ...
    0.88, 0.18, 0.14; 0.04, 0.04, 0.04; 0.04, 0.04, 0.04; ...
    0.04, 0.04, 0.04; 0.04, 0.04, 0.04; 0.04, 0.04, 0.04];
for methodIndex = 1:numel(result.methodLabels)
    markerFace = "none";
    if ismember(methodIndex, [2, 4, 6, 10])
        markerFace = colors(methodIndex, :);
    end
    semilogy(ax, result.snrList, result.displayFer(methodIndex, :), ...
        styles{methodIndex}, "Color", colors(methodIndex, :), ...
        "LineWidth", 1.35, "MarkerSize", 8, ...
        "MarkerFaceColor", markerFace, ...
        "DisplayName", result.methodLabels(methodIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.30;
ax.MinorGridAlpha = 0.20;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 10.2;
ax.LineWidth = 1;
ax.YScale = "log";
xlim(ax, [-5, 10]);
ylim(ax, [1e-4, 1]);
xticks(ax, -5:5:10);
yticks(ax, 10 .^ (-4:0));
yticklabels(ax, {"10^{-4}", "10^{-3}", "10^{-2}", "10^{-1}", "10^{0}"});
xlabel(ax, "SNR/dB");
ylabel(ax, "FER");
legend(ax, "Location", "southwest", "FontSize", 9.1, "NumColumns", 1);
annotation(fig, "textbox", [0.13, 0.055, 0.76, 0.055], "String", ...
    "图 5-28  水声信道下多种 CCK 接收机的 FER 性能比较", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);
exportgraphics(fig, result.figurePath, "Resolution", 220);
close(fig);
end

function write_table(result)
methodColumn = strings(0, 1);
snrColumn = zeros(0, 1);
ferColumn = zeros(0, 1);
displayColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
totalColumn = zeros(0, 1);
for methodIndex = 1:numel(result.methodLabels)
    count = numel(result.snrList);
    methodColumn = [methodColumn; repmat(result.methodLabels(methodIndex), count, 1)];
    snrColumn = [snrColumn; result.snrList(:)];
    ferColumn = [ferColumn; result.fer(methodIndex, :).'];
    displayColumn = [displayColumn; result.displayFer(methodIndex, :).'];
    errorColumn = [errorColumn; result.frameErrorCounts(methodIndex, :).'];
    totalColumn = [totalColumn; result.frameTotals(methodIndex, :).'];
end
writetable(table(methodColumn, snrColumn, ferColumn, displayColumn, errorColumn, ...
    totalColumn, 'VariableNames', {'Method', 'SNR_dB', 'FER', 'DisplayFER', ...
    'FrameErrorCount', 'FrameTotal'}), result.csvPath);
end
