function results = simulate_chapter4_figure49(options)
%SIMULATE_CHAPTER4_FIGURE49 Simulate four time-varying channel responses.

if nargin < 1
    options = struct();
end

rootDir = fileparts(mfilename("fullpath"));
cfg.durationSec = option_value(options, "durationSec", 50);
cfg.timeStepSec = option_value(options, "timeStepSec", 0.2);
cfg.maximumDelayMs = option_value(options, "maximumDelayMs", 33);
cfg.delayStepMs = option_value(options, "delayStepMs", 0.1);
cfg.powerLimitsDb = option_value(options, "powerLimitsDb", [37, 57]);
cfg.randomSeed = option_value(options, "randomSeed", 20260730);
cfg.outputDir = string(option_value(options, "outputDir", ...
    fullfile(rootDir, "results")));
cfg.timeSec = (0:cfg.timeStepSec:cfg.durationSec).';
cfg.delayMs = 0:cfg.delayStepMs:cfg.maximumDelayMs;

channelProfiles(1) = struct( ...
    "delayMs", [2.8, 4.8, 6.2, 7.5, 9.1, 10.8, 12.4, 14.1], ...
    "amplitude", [0.22, 0.52, 0.78, 0.64, 1.00, 0.72, 0.86, 0.42], ...
    "diffuseOnsetMs", 12.2, "diffuseStrength", 0.12);
channelProfiles(2) = struct( ...
    "delayMs", [3.1, 4.9, 6.4, 7.8, 9.2, 10.5, 11.8, 13.0], ...
    "amplitude", [0.20, 0.48, 0.70, 0.88, 1.00, 0.82, 0.92, 0.58], ...
    "diffuseOnsetMs", 12.6, "diffuseStrength", 0.13);
channelProfiles(3) = struct( ...
    "delayMs", [4.1, 5.8, 7.1, 8.6, 9.8, 11.0, 12.4, 14.0], ...
    "amplitude", [0.25, 0.52, 0.73, 0.90, 1.00, 0.88, 0.79, 0.48], ...
    "diffuseOnsetMs", 13.4, "diffuseStrength", 0.14);
channelProfiles(4) = struct( ...
    "delayMs", [4.7, 6.3, 7.7, 9.1, 10.4, 11.8, 13.2, 14.8], ...
    "amplitude", [0.20, 0.45, 0.67, 0.80, 1.00, 0.85, 0.74, 0.46], ...
    "diffuseOnsetMs", 14.0, "diffuseStrength", 0.13);

rng(cfg.randomSeed, "twister");
channelCount = numel(channelProfiles);
complexResponse = complex(zeros(numel(cfg.timeSec), ...
    numel(cfg.delayMs), channelCount));
powerDb = zeros(size(complexResponse));
pathDelayMs = cell(channelCount, 1);
pathAmplitude = cell(channelCount, 1);
for channelIndex = 1:channelCount
    [complexResponse(:, :, channelIndex), powerDb(:, :, channelIndex), ...
        pathDelayMs{channelIndex}, pathAmplitude{channelIndex}] = ...
        simulate_channel(cfg, channelProfiles(channelIndex), channelIndex);
end

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, ...
    "fig4_9_time_varying_channel_impulse_response.png");
resultPath = fullfile(cfg.outputDir, ...
    "fig4_9_time_varying_channel_impulse_response.mat");
fig = figure("Color", "w", "Position", [80, 60, 1180, 900]);
layout = tiledlayout(fig, 2, 2, "TileSpacing", "compact", ...
    "Padding", "compact");
for channelIndex = 1:channelCount
    axesHandle = nexttile(layout);
    imagesc(axesHandle, cfg.delayMs, cfg.timeSec, ...
        powerDb(:, :, channelIndex));
    set(axesHandle, "YDir", "normal", "FontName", ...
        "Microsoft YaHei", "FontSize", 11);
    axis(axesHandle, "tight");
    xlim(axesHandle, [0, cfg.maximumDelayMs]);
    ylim(axesHandle, [0, cfg.durationSec]);
    clim(axesHandle, cfg.powerLimitsDb);
    xticks(axesHandle, 5:5:30);
    yticks(axesHandle, 10:10:50);
    xlabel(axesHandle, "时延/ms");
    ylabel(axesHandle, "时间/s");
    title(axesHandle, compose("通道 %d", channelIndex), ...
        "FontWeight", "normal");
    colorbarHandle = colorbar(axesHandle);
    colorbarHandle.Ticks = 38:2:56;
    colorbarHandle.Label.String = "功率/dB";
end
colormap(fig, jet(256));
title(layout, "图 4-9 仿真使用的时变信道冲激响应", ...
    "FontName", "Microsoft YaHei", "FontSize", 15, ...
    "FontWeight", "bold");
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);

results.config = cfg;
results.channelProfiles = channelProfiles;
results.complexResponse = complexResponse;
results.powerDb = powerDb;
results.pathDelayMs = pathDelayMs;
results.pathAmplitude = pathAmplitude;
results.figurePath = figurePath;
results.resultPath = resultPath;
results.model = ["Time-varying specular paths", ...
    "correlated fading", "delay-diffuse reverberation"];
results.sourceType = "Physics-based stochastic channel simulation.";
results.isDigitizedPaperImage = false;
save(resultPath, "results", "-v7.3");

assert(all(size(powerDb) == [numel(cfg.timeSec), ...
    numel(cfg.delayMs), 4]), "The Figure 4.9 response cube is incomplete.");
assert(all(powerDb(:) >= cfg.powerLimitsDb(1)) && ...
    all(powerDb(:) <= cfg.powerLimitsDb(2)), ...
    "The response power lies outside the requested display range.");
fprintf("Figure 4.9 simulation written to: %s\n", figurePath);
end

function [response, displayedPowerDb, pathDelays, pathAmplitudes] = ...
        simulate_channel(cfg, profile, channelIndex)
time = cfg.timeSec;
delay = cfg.delayMs;
timeCount = numel(time);
pathCount = numel(profile.delayMs);
response = complex(zeros(timeCount, numel(delay)));
pathDelays = zeros(timeCount, pathCount);
pathAmplitudes = zeros(timeCount, pathCount);

for pathIndex = 1:pathCount
    delayNoise = correlated_noise(timeCount, 0.975);
    amplitudeNoise = correlated_noise(timeCount, 0.955);
    delayPeriod = 17 + 2.3 * pathIndex + 0.8 * channelIndex;
    delayPhase = 0.7 * pathIndex + 0.5 * channelIndex;
    pathDelays(:, pathIndex) = profile.delayMs(pathIndex) + ...
        (0.08 + 0.018 * pathIndex) * ...
        sin(2 * pi * time / delayPeriod + delayPhase) + ...
        0.045 * delayNoise;
    fadingDb = 0.75 * sin(2 * pi * time / ...
        (11 + 1.7 * pathIndex) + 0.4 * pathIndex) + ...
        0.42 * amplitudeNoise;
    pathAmplitudes(:, pathIndex) = profile.amplitude(pathIndex) * ...
        10.^(fadingDb / 20);
    pathPhase = 2 * pi * (0.008 + 0.0015 * pathIndex) * time + ...
        0.6 * correlated_noise(timeCount, 0.985) + 0.9 * pathIndex;
    pathWidthMs = 0.16 + 0.025 * mod(pathIndex + channelIndex, 4);
    pulse = exp(-0.5 * ((delay - pathDelays(:, pathIndex)) / ...
        pathWidthMs).^2);
    response = response + pathAmplitudes(:, pathIndex) .* ...
        exp(1j * pathPhase) .* pulse;
end

diffuse = (randn(size(response)) + 1j * randn(size(response))) / sqrt(2);
diffuse = filter(1, [1, -0.94], diffuse, [], 1);
delayKernel = exp(-0.5 * ((-8:8) / 2.2).^2);
delayKernel = delayKernel / sum(delayKernel);
diffuse = conv2(diffuse, delayKernel, "same");
diffuse = diffuse / max(sqrt(mean(abs(diffuse).^2, "all")), eps);
diffuseOnset = 1 ./ (1 + exp(-(delay - profile.diffuseOnsetMs) / 0.55));
diffuseDecay = exp(-max(delay - profile.diffuseOnsetMs, 0) / 7.2);
response = response + profile.diffuseStrength * diffuse .* ...
    (diffuseOnset .* diffuseDecay);

response = response / max(abs(response), [], "all");
noiseFloor = 10^((cfg.powerLimitsDb(1) - cfg.powerLimitsDb(2)) / 20);
measurementNoise = noiseFloor / sqrt(2) * ...
    (randn(size(response)) + 1j * randn(size(response)));
response = response + measurementNoise;
displayedPowerDb = cfg.powerLimitsDb(2) + 20 * log10(max(abs(response), eps));
displayedPowerDb = min(max(displayedPowerDb, cfg.powerLimitsDb(1)), ...
    cfg.powerLimitsDb(2));
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
