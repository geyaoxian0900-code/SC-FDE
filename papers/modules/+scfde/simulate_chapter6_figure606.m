function result = simulate_chapter6_figure606(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE606 Simulate Fig. 6-6 array-diversity BER curves.
%   Four spread-spectrum users transmit BPSK symbols through a correlated,
%   frame-varying multipath array channel. The receiver uses the channel
%   matrix of every array element in a joint linear MMSE detector.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrDb = -15:1:10;
defaults.userCount = 4;
defaults.arrayCounts = [1, 2, 4, 8];
defaults.codeLength = 63;
defaults.chipRateHz = 2000;
defaults.symbolsPerFrame = 48;
defaults.frameCount = 500;
defaults.spatialCorrelation = 0.20;
defaults.pathCommonFraction = 0.82;
defaults.channelEstimationNmse = 0;
defaults.syncPreambleChips = 63;
defaults.syncSearchBins = 16;
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
powerDelayProfile = reference_power_delay_profile(cfg, simulationDir);
spreadingCodes = m_sequence_codebook(cfg.codeLength, cfg.userCount);
ber = zeros(numel(cfg.arrayCounts), numel(cfg.snrDb));
errorCount = zeros(size(ber));
bitCount = zeros(size(ber));

for countIndex = 1:numel(cfg.arrayCounts)
    arrayCount = cfg.arrayCounts(countIndex);
    for snrIndex = 1:numel(cfg.snrDb)
        % The horizontal axis is in-band SNR. With U users and L chips,
        % the chip-domain noise variance is U/L times the linear SNR.
        noiseVariance = cfg.userCount / cfg.codeLength * 10^(-cfg.snrDb(snrIndex) / 10);
        for frameIndex = 1:cfg.frameCount
            channel = array_multipath_channel(cfg, arrayCount, powerDelayProfile);
            [frameErrors, frameBits] = multiuser_lmmse_frame( ...
                spreadingCodes, channel, noiseVariance, cfg);
            errorCount(countIndex, snrIndex) = errorCount(countIndex, snrIndex) + frameErrors;
            bitCount(countIndex, snrIndex) = bitCount(countIndex, snrIndex) + frameBits;
        end
        ber(countIndex, snrIndex) = errorCount(countIndex, snrIndex) / bitCount(countIndex, snrIndex);
    end
end

result.config = cfg;
result.powerDelayProfile = powerDelayProfile;
result.spreadingCodes = spreadingCodes;
result.ber = ber;
result.errorCount = errorCount;
result.bitCount = bitCount;
result.figurePath = "";
result.matPath = "";
result.csvPath = "";
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
if cfg.makePlot
    result.figurePath = plot_figure(result);
end
result.matPath = fullfile(cfg.outputDir, "fig6_6_four_user_array_diversity.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_6_four_user_array_diversity.csv");
writematrix([cfg.snrDb(:), ber.'], result.csvPath);
save(result.matPath, "result");
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end

function validate_config(cfg)
assert(isscalar(cfg.userCount) && cfg.userCount == 4, ...
    "SCFDE:Figure606Users", "Fig. 6-6 is defined for four active users.");
assert(isscalar(cfg.codeLength) && cfg.codeLength == 63, ...
    "SCFDE:Figure606CodeLength", "Fig. 6-6 uses the 63-chip m-sequence codebook.");
assert(all(ismember(cfg.arrayCounts, [1, 2, 4, 8])), ...
    "SCFDE:Figure606Arrays", "arrayCounts must be selected from [1 2 4 8].");
assert(isscalar(cfg.spatialCorrelation) && cfg.spatialCorrelation >= 0 && cfg.spatialCorrelation < 1, ...
    "SCFDE:Figure606Correlation", "spatialCorrelation must be in [0, 1).");
assert(isscalar(cfg.pathCommonFraction) && cfg.pathCommonFraction >= 0 && cfg.pathCommonFraction <= 1, ...
    "SCFDE:Figure606PathMix", "pathCommonFraction must be in [0, 1].");
assert(isscalar(cfg.channelEstimationNmse) && cfg.channelEstimationNmse >= 0 && cfg.channelEstimationNmse < 1, ...
    "SCFDE:Figure606ChannelError", "channelEstimationNmse must be in [0, 1).");
assert(isscalar(cfg.syncPreambleChips) && cfg.syncPreambleChips >= 2, ...
    "SCFDE:Figure606Preamble", "syncPreambleChips must be at least 2.");
assert(isscalar(cfg.syncSearchBins) && cfg.syncSearchBins >= 2, ...
    "SCFDE:Figure606Search", "syncSearchBins must be at least 2.");
end

function profile = reference_power_delay_profile(cfg, simulationDir)
referencePath = fullfile(cfg.outputDir, "fig6_5_single_user_four_element_cir.mat");
if isfile(referencePath)
    data = load(referencePath, "result");
    reference = data.result;
else
    reference = scfde.simulate_chapter6_figure605( ...
        struct("makePlot", false, "outputDir", cfg.outputDir), simulationDir);
end
referenceSampleRate = reference.config.sampleRateHz;
samplesPerChip = referenceSampleRate / cfg.chipRateHz;
assert(abs(samplesPerChip - round(samplesPerChip)) < eps, ...
    "SCFDE:Figure606Rate", "The reference sample rate must be divisible by chipRateHz.");
samplePower = mean(abs(reference.impulseResponses).^2, 1);
chipIndex = floor((0:numel(samplePower) - 1) / round(samplesPerChip)) + 1;
profile = accumarray(chipIndex(:), samplePower(:));
profile = profile(:).' / sum(profile);
end

function codebook = m_sequence_codebook(codeLength, userCount)
state = ones(1, 6);
sequence = zeros(1, codeLength);
for chipIndex = 1:codeLength
    sequence(chipIndex) = state(end);
    feedback = xor(state(6), state(1));
    state = [feedback, state(1:5)];
end
root = 1 - 2 * sequence;
shifts = [0, 9, 21, 37];
codebook = zeros(codeLength, userCount);
for userIndex = 1:userCount
    codebook(:, userIndex) = circshift(root, -shifts(userIndex)).' / sqrt(codeLength);
end
end

function channel = array_multipath_channel(cfg, arrayCount, profile)
pathCount = numel(profile);
userCount = cfg.userCount;
channel = complex(zeros(arrayCount, userCount, pathCount));
commonFading = (randn(1, userCount) + 1j * randn(1, userCount)) / sqrt(2);
for arrayIndex = 1:arrayCount
    independentFading = (randn(1, userCount) + 1j * randn(1, userCount)) / sqrt(2);
    branchFading = sqrt(cfg.spatialCorrelation) * commonFading + ...
        sqrt(1 - cfg.spatialCorrelation) * independentFading;
    pathJitter = (randn(userCount, pathCount) + 1j * randn(userCount, pathCount)) / sqrt(2);
    for userIndex = 1:userCount
        pathGain = sqrt(cfg.pathCommonFraction) * branchFading(userIndex) + ...
            sqrt(1 - cfg.pathCommonFraction) * pathJitter(userIndex, :);
        channel(arrayIndex, userIndex, :) = sqrt(profile) .* pathGain;
    end
end
end

function [errors, totalBits] = multiuser_lmmse_frame(codebook, channel, noiseVariance, cfg)
userCount = cfg.userCount;
symbolCount = cfg.symbolsPerFrame;
sampleCount = size(codebook, 1) + size(channel, 3) - 1;
bits = 2 * randi([0, 1], userCount, symbolCount) - 1;
totalBits = numel(bits);
if ~synchronize_array_frame(channel, noiseVariance, cfg)
    randomDecisions = 2 * randi([0, 1], userCount, symbolCount) - 1;
    errors = sum(randomDecisions(:) ~= bits(:));
    return;
end
gramMatrix = zeros(userCount, userCount);
matchedOutput = zeros(userCount, symbolCount);
for arrayIndex = 1:size(channel, 1)
    dictionary = complex(zeros(sampleCount, userCount));
    estimatedDictionary = dictionary;
    for userIndex = 1:userCount
        impulseResponse = reshape(channel(arrayIndex, userIndex, :), 1, []);
        dictionary(:, userIndex) = conv(codebook(:, userIndex), impulseResponse).';
        if cfg.channelEstimationNmse == 0
            estimatedDictionary(:, userIndex) = dictionary(:, userIndex);
        else
            estimateNoise = (randn(sampleCount, 1) + 1j * randn(sampleCount, 1)) / sqrt(2);
            estimateNoise = estimateNoise / max(norm(estimateNoise), eps) * norm(dictionary(:, userIndex));
            estimatedDictionary(:, userIndex) = sqrt(1 - cfg.channelEstimationNmse) * ...
                dictionary(:, userIndex) + sqrt(cfg.channelEstimationNmse) * estimateNoise;
        end
    end
    received = dictionary * bits + sqrt(noiseVariance / 2) * ...
        (randn(sampleCount, symbolCount) + 1j * randn(sampleCount, symbolCount));
    gramMatrix = gramMatrix + real(estimatedDictionary' * estimatedDictionary);
    matchedOutput = matchedOutput + real(estimatedDictionary' * received);
end
estimatedSymbols = (gramMatrix + noiseVariance * eye(userCount)) \ matchedOutput;
decisions = 2 * (estimatedSymbols >= 0) - 1;
errors = sum(decisions(:) ~= bits(:));
end

function isSynchronized = synchronize_array_frame(channel, noiseVariance, cfg)
% Noncoherent PN acquisition across all receive elements. The true timing
% bin contains the channel energy; the remaining bins model timing aliases.
elementEnergy = squeeze(sum(abs(channel(:, 1, :)).^2, 3));
preambleEnergy = cfg.syncPreambleChips / cfg.codeLength;
trueCorrelation = sqrt(preambleEnergy * elementEnergy) + ...
    sqrt(noiseVariance / 2) * (randn(size(elementEnergy)) + 1j * randn(size(elementEnergy)));
falseCorrelation = sqrt(noiseVariance / 2) * ...
    (randn(numel(elementEnergy), cfg.syncSearchBins - 1) + ...
    1j * randn(numel(elementEnergy), cfg.syncSearchBins - 1));
trueMetric = sum(abs(trueCorrelation).^2);
falseMetric = max(sum(abs(falseCorrelation).^2, 1));
isSynchronized = trueMetric > falseMetric;
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_6_four_user_array_diversity.png");
figureHandle = figure("Color", "w", "Position", [220, 80, 760, 700], "Visible", "off");
axisHandle = axes(figureHandle); hold(axisHandle, "on");
axisHandle.Position = [0.15, 0.18, 0.73, 0.74];
markers = ["none", "s", "o", "d"];
lineStyles = ["-", "-", "-", "-"];
for countIndex = 1:numel(cfg.arrayCounts)
    curve = result.ber(countIndex, :);
    curve(curve == 0) = NaN;
    semilogy(axisHandle, cfg.snrDb, curve, "Color", [0.30, 0.30, 0.30], ...
        "LineStyle", lineStyles(countIndex), "Marker", markers(countIndex), ...
        "LineWidth", 1.25, "MarkerSize", 5, ...
        "DisplayName", "M = " + string(cfg.arrayCounts(countIndex)));
end
grid(axisHandle, "on");
axisHandle.YScale = "log";
axisHandle.XMinorGrid = "on";
axisHandle.YMinorGrid = "on";
axisHandle.GridLineStyle = "--";
axisHandle.MinorGridLineStyle = "--";
axisHandle.GridAlpha = 0.42;
axisHandle.MinorGridAlpha = 0.30;
xlim(axisHandle, [-15, 10]);
ylim(axisHandle, [1e-4, 1]);
xlabel(axisHandle, "带内信噪比/dB");
ylabel(axisHandle, "误码率");
legend(axisHandle, "Location", "northeast", "Box", "on");
set(axisHandle, "FontName", "Microsoft YaHei", "FontSize", 13, "Box", "on", "TickDir", "in");
annotation(figureHandle, "textbox", [0.11, 0.008, 0.78, 0.05], ...
    "String", "图 6-6  四用户通信时误码率随接收阵元个数变化曲线", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "EdgeColor", "none", "FontName", "Microsoft YaHei", "FontSize", 16);
exportgraphics(figureHandle, figurePath, "Resolution", 220);
close(figureHandle);
end
