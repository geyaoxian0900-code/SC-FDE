function results = simulate_chapter4_figure428(options)
%SIMULATE_CHAPTER4_FIGURE428 Time-varying impulse and scattering functions.

if nargin < 1
    options = struct();
end

rootDir = fileparts(mfilename("fullpath"));
cfg.durationSec = option_value(options, "durationSec", 3.7);
cfg.timeStepSec = option_value(options, "timeStepSec", 0.01);
cfg.maximumDelayMs = option_value(options, "maximumDelayMs", 25);
cfg.delayStepMs = option_value(options, "delayStepMs", 0.05);
cfg.dopplerLimitsHz = option_value(options, "dopplerLimitsHz", [-4, 3.5]);
cfg.impulseLimitsDb = option_value(options, "impulseLimitsDb", [-25, 0]);
cfg.scatteringLimitsDb = option_value(options, "scatteringLimitsDb", [7, 31]);
cfg.randomSeed = option_value(options, "randomSeed", 20260731);
cfg.outputDir = string(option_value(options, "outputDir", ...
    fullfile(rootDir, "results")));

cfg.timeSec = (0:cfg.timeStepSec:cfg.durationSec).';
cfg.delayMs = 0:cfg.delayStepMs:cfg.maximumDelayMs;
assert(numel(cfg.timeSec) >= 64, "Figure428:InsufficientTimeSamples", ...
    "At least 64 time samples are required for Doppler processing.");

pathDelayMs = [0.35, 1.15, 1.95, 2.85, 4.15, 5.15, 6.65, 9.6, 23.8];
pathAmplitude = [1.00, 0.72, 0.61, 0.52, 0.78, 0.60, 0.43, 0.18, 0.11];
pathDopplerHz = [-1.25, -0.92, -0.55, -0.18, 0.18, 0.48, 0.82, ...
    -1.65, 1.10];
pathWidthMs = [0.08, 0.09, 0.09, 0.10, 0.11, 0.12, 0.13, 0.18, 0.22];

rng(cfg.randomSeed, "twister");
channel = complex(zeros(numel(cfg.timeSec), numel(cfg.delayMs)));
pathCount = numel(pathDelayMs);
actualDelayMs = zeros(numel(cfg.timeSec), pathCount);
actualAmplitude = zeros(size(actualDelayMs));
for pathIndex = 1:pathCount
    delayWander = correlated_noise(numel(cfg.timeSec), 0.992);
    fading = correlated_noise(numel(cfg.timeSec), 0.985);
    actualDelayMs(:, pathIndex) = pathDelayMs(pathIndex) + ...
        (0.004 + 0.001 * pathIndex) * delayWander + ...
        0.008 * sin(2 * pi * cfg.timeSec / (1.4 + 0.17 * pathIndex) + ...
        0.4 * pathIndex);
    actualAmplitude(:, pathIndex) = pathAmplitude(pathIndex) .* ...
        10.^((0.55 * fading + 0.35 * sin(2 * pi * cfg.timeSec / ...
        (1.1 + 0.13 * pathIndex) + pathIndex)) / 20);
    phaseNoise = 0.08 * correlated_noise(numel(cfg.timeSec), 0.996);
    phase = 2 * pi * pathDopplerHz(pathIndex) * cfg.timeSec + ...
        phaseNoise + 0.72 * pathIndex;
    pulse = exp(-0.5 * ((cfg.delayMs - actualDelayMs(:, pathIndex)) / ...
        pathWidthMs(pathIndex)).^2);
    channel = channel + actualAmplitude(:, pathIndex) .* exp(1j * phase) .* pulse;
end

channel = channel + diffuse_reverberation(cfg);
channel = channel / max(abs(channel), [], "all");
impulsePowerDb = 20 * log10(max(abs(channel), 10^(cfg.impulseLimitsDb(1) / 20)));
impulsePowerDb = min(max(impulsePowerDb, cfg.impulseLimitsDb(1)), ...
    cfg.impulseLimitsDb(2));

[scatteringPowerDb, dopplerHz, scatteringLinear] = ...
    scattering_function(channel, cfg);

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, ...
    "fig4_28_channel_impulse_and_scattering_function.png");
resultPath = fullfile(cfg.outputDir, ...
    "fig4_28_channel_impulse_and_scattering_function.mat");
plot_figure428(cfg, impulsePowerDb, scatteringPowerDb, dopplerHz, figurePath);

results.config = cfg;
results.channel = channel;
results.impulsePowerDb = impulsePowerDb;
results.scatteringPowerDb = scatteringPowerDb;
results.scatteringLinear = scatteringLinear;
results.dopplerHz = dopplerHz;
results.pathDelayMs = pathDelayMs;
results.pathAmplitude = pathAmplitude;
results.pathDopplerHz = pathDopplerHz;
results.actualDelayMs = actualDelayMs;
results.actualAmplitude = actualAmplitude;
results.figurePath = figurePath;
results.resultPath = resultPath;
results.sourceType = "Physics-based stochastic time-varying multipath simulation.";
results.scatteringDefinition = ...
    "Squared magnitude of the windowed time-axis Fourier transform of h(t,tau).";
save(resultPath, "results", "-v7.3");

delayMask = cfg.delayMs <= 10;
visibleDoppler = dopplerHz >= cfg.dopplerLimitsHz(1) & ...
    dopplerHz <= cfg.dopplerLimitsHz(2);
visibleEnergy = sum(scatteringLinear(visibleDoppler, :), "all");
earlyEnergy = sum(scatteringLinear(visibleDoppler, delayMask), "all");
assert(earlyEnergy / max(visibleEnergy, eps) > 0.90, ...
    "Figure428:ScatteringSupport", ...
    "The simulated scattering energy is not concentrated at early delays.");
assert(all(isfinite(channel), "all"), ...
    "Figure428:NonfiniteChannel", "The channel contains nonfinite samples.");
fprintf("Figure 4-28 written to: %s\n", figurePath);
end

function diffuse = diffuse_reverberation(cfg)
timeCount = numel(cfg.timeSec);
delayCount = numel(cfg.delayMs);
whiteNoise = (randn(timeCount, delayCount) + ...
    1j * randn(timeCount, delayCount)) / sqrt(2);
diffuse = filter(sqrt(1 - 0.94^2), [1, -0.94], whiteNoise, [], 1);
delayKernel = exp(-0.5 * ((-10:10) / 2.6).^2);
delayKernel = delayKernel / sum(delayKernel);
diffuse = conv2(diffuse, delayKernel, "same");
delayEnvelope = exp(-max(cfg.delayMs - 3.0, 0) / 3.5) ./ ...
    (1 + exp(-(cfg.delayMs - 0.15) / 0.16));
centerDopplerHz = -0.45;
diffuse = diffuse .* exp(1j * 2 * pi * centerDopplerHz * cfg.timeSec) .* ...
    delayEnvelope;
diffuse = 0.07 * diffuse / max(sqrt(mean(abs(diffuse).^2, "all")), eps);
end

function [powerDb, dopplerHz, scattering] = scattering_function(channel, cfg)
timeCount = size(channel, 1);
window = 0.5 - 0.5 * cos(2 * pi * (0:timeCount - 1).' / (timeCount - 1));
windowedChannel = channel .* window;
scattering = abs(fftshift(fft(windowedChannel, [], 1), 1)).^2;
dopplerHz = ((-floor(timeCount / 2)):(ceil(timeCount / 2) - 1)).' / ...
    (timeCount * cfg.timeStepSec);
% Smooth the finite-sample estimate in delay and Doppler dimensions.
dopplerWindow = exp(-0.5 * ((-4:4) / 1.7).^2).';
delayWindow = exp(-0.5 * ((-4:4) / 2.2).^2);
smoothingWindow = dopplerWindow * delayWindow;
smoothingWindow = smoothingWindow / sum(smoothingWindow, "all");
scattering = conv2(scattering, smoothingWindow, "same");
scattering = scattering / max(scattering, [], "all");
powerDb = cfg.scatteringLimitsDb(2) + 10 * log10(max(scattering, ...
    10^((cfg.scatteringLimitsDb(1) - cfg.scatteringLimitsDb(2)) / 10)));
powerDb = min(max(powerDb, cfg.scatteringLimitsDb(1)), ...
    cfg.scatteringLimitsDb(2));
end

function plot_figure428(cfg, impulsePowerDb, scatteringPowerDb, ...
        dopplerHz, figurePath)
fig = figure("Color", "w", "Position", [60, 80, 1220, 570]);
leftAxes = axes(fig, "Position", [0.075, 0.30, 0.32, 0.60]);
imagesc(leftAxes, cfg.delayMs, cfg.timeSec, impulsePowerDb);
set(leftAxes, "YDir", "reverse", "FontName", "Microsoft YaHei", ...
    "FontSize", 11, "Box", "on", "LineWidth", 1);
xlim(leftAxes, [0, cfg.maximumDelayMs]);
ylim(leftAxes, [0, cfg.durationSec]);
clim(leftAxes, cfg.impulseLimitsDb);
xticks(leftAxes, 0:5:25);
yticks(leftAxes, 0:0.5:3.5);
xlabel(leftAxes, "时延/ms");
ylabel(leftAxes, "时间/s");
leftColorbar = colorbar(leftAxes);
leftColorbar.Position = [0.415, 0.30, 0.015, 0.60];
leftColorbar.Ticks = -25:5:0;

rightAxes = axes(fig, "Position", [0.565, 0.30, 0.32, 0.60]);
visible = dopplerHz >= cfg.dopplerLimitsHz(1) & ...
    dopplerHz <= cfg.dopplerLimitsHz(2);
imagesc(rightAxes, cfg.delayMs, dopplerHz(visible), ...
    scatteringPowerDb(visible, :));
set(rightAxes, "YDir", "reverse", "FontName", "Microsoft YaHei", ...
    "FontSize", 11, "Box", "on", "LineWidth", 1);
xlim(rightAxes, [0, cfg.maximumDelayMs]);
ylim(rightAxes, cfg.dopplerLimitsHz);
clim(rightAxes, cfg.scatteringLimitsDb);
xticks(rightAxes, 0:5:25);
yticks(rightAxes, -4:1:3);
xlabel(rightAxes, "时延/ms");
ylabel(rightAxes, "多普勒频移/Hz");
rightColorbar = colorbar(rightAxes);
rightColorbar.Position = [0.905, 0.30, 0.015, 0.60];
rightColorbar.Ticks = [10, 15, 20, 25, 30];

colormap(leftAxes, parula(256));
colormap(rightAxes, hot(256));
annotation(fig, "textbox", [0.215, 0.145, 0.04, 0.04], ...
    "String", "(a)", "EdgeColor", "none", ...
    "HorizontalAlignment", "center", "FontName", "Times New Roman", ...
    "FontSize", 12);
annotation(fig, "textbox", [0.705, 0.145, 0.04, 0.04], ...
    "String", "(b)", "EdgeColor", "none", ...
    "HorizontalAlignment", "center", "FontName", "Times New Roman", ...
    "FontSize", 12);
annotation(fig, "textbox", [0.405, 0.235, 0.09, 0.04], ...
    "String", "功率/dB", "EdgeColor", "none", ...
    "HorizontalAlignment", "center", "FontName", "Microsoft YaHei", ...
    "FontSize", 11);
annotation(fig, "textbox", [0.895, 0.235, 0.09, 0.04], ...
    "String", "功率/dB", "EdgeColor", "none", ...
    "HorizontalAlignment", "center", "FontName", "Microsoft YaHei", ...
    "FontSize", 11);
annotation(fig, "textbox", [0.18, 0.035, 0.64, 0.07], ...
    "String", "图 4-28  仿真信道冲激响应和散射函数", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);
end

function output = correlated_noise(sampleCount, coefficient)
input = randn(sampleCount, 1);
output = filter(sqrt(1 - coefficient^2), [1, -coefficient], input);
output = output - mean(output);
output = output / max(std(output), eps);
end

function value = option_value(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end
