function result = simulate_chapter6_figure613(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE613 Simulate Fig. 6-13 sequence-family effects.
%   The receiver works on the exact symbol-rate equivalent obtained after
%   chip-domain spreading, multipath convolution, and matched filtering.
%   The three 255-chip families are reproducible parameterized substitutes
%   because the paper does not publish the construction of its named codes.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrDb = -2:1:6;
defaults.codeLength = 255;
defaults.userCount = 6;
defaults.symbolsPerFrame = 180;
defaults.frameCount = 600;
defaults.repetitionFactor = 3;
defaults.outerIterations = 2;
defaults.channelDelays = [0, 11, 27, 59];
defaults.channelGains = [1.00, 0.37 * exp(1j * 0.44), ...
    0.25 * exp(-1j * 0.83), 0.16 * exp(1j * 1.37)];
defaults.syncRepeatCount = 9;
defaults.syncConsensusRatio = 2 / 3;
defaults.syncAmplitude = 2.7;
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
families = build_sequence_families(cfg);
channel = sparse_channel(cfg);
familyCount = numel(families);
snrCount = numel(cfg.snrDb);
ber = zeros(familyCount, snrCount);
errorCount = zeros(familyCount, snrCount);
bitCount = zeros(familyCount, snrCount);
effectiveChannels = cell(familyCount, 1);

for familyIndex = 1:familyCount
    effectiveChannels{familyIndex} = matched_filter_equivalent( ...
        families(familyIndex).codebook, channel);
    for snrIndex = 1:snrCount
        noiseVariance = 10^(-cfg.snrDb(snrIndex) / 10);
        errors = 0;
        total = 0;
        for frameIndex = 1:cfg.frameCount
            frame = sequence_family_frame(families(familyIndex), ...
                effectiveChannels{familyIndex}, channel, noiseVariance, cfg);
            errors = errors + frame.errors;
            total = total + frame.totalBits;
        end
        errorCount(familyIndex, snrIndex) = errors;
        bitCount(familyIndex, snrIndex) = total;
        ber(familyIndex, snrIndex) = errors / total;
    end
end

result.config = cfg;
result.model = "255-chip parameterized spreading families; chip-domain multipath matched-filter equivalent; multiuser LMMSE-PIC and repetition soft decoding";
result.sequenceDefinitionNote = [ ...
    "The paper only labels mse-ao-sk255, co-msqcc-m255, and lse-ao-m255. ", ...
    "Their generator polynomials and optimization constraints are not published in the supplied material; these are reproducible parameterized families, not the original stored sequences."];
result.channel = channel;
result.families = families;
result.effectiveChannels = effectiveChannels;
result.snrDb = cfg.snrDb;
result.ber = ber;
result.errorCount = errorCount;
result.bitCount = bitCount;
result.zeroErrorUpperBound = 0.5 ./ bitCount;
result.figurePath = "";
result.matPath = "";
result.csvPath = "";

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
if cfg.makePlot
    result.figurePath = plot_figure(result);
end
result.matPath = fullfile(cfg.outputDir, "fig6_13_spreading_sequence_effect.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_13_spreading_sequence_effect.csv");
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
assert(cfg.codeLength == 255, "SCFDE:Figure613CodeLength", ...
    "Fig. 6-13 uses 255-chip sequences.");
assert(mod(cfg.symbolsPerFrame, cfg.repetitionFactor) == 0, ...
    "SCFDE:Figure613Repetition", "symbolsPerFrame must divide repetitionFactor.");
assert(cfg.userCount >= 2 && cfg.userCount <= 12, ...
    "SCFDE:Figure613Users", "userCount must be between 2 and 12.");
assert(numel(cfg.channelDelays) == numel(cfg.channelGains), ...
    "SCFDE:Figure613Channel", "channelDelays and channelGains must have the same length.");
assert(all(cfg.channelDelays >= 0) && all(cfg.channelDelays < cfg.codeLength), ...
    "SCFDE:Figure613Delays", "All channel delays must be less than codeLength.");
assert(cfg.syncRepeatCount >= 1 && cfg.syncConsensusRatio > 0 && cfg.syncConsensusRatio <= 1, ...
    "SCFDE:Figure613Sync", "The synchronization consensus parameters are invalid.");
end

function families = build_sequence_families(cfg)
root = m_sequence255();
coRoot = refine_sidelobes(root, 2400, cfg.randomSeed + 71);
lseRoot = low_sidelobe_root(cfg.codeLength, cfg.randomSeed + 613);
roots = {root, coRoot, lseRoot};
names = ["mse-ao-sk255", "co-msqcc-m255", "lse-ao-m255"];
descriptions = [ ...
    "Reference m-sequence cyclic-shift family", ...
    "Composite phase-constrained m-sequence family", ...
    "Least-sidelobe optimized binary sequence family"];
families = repmat(struct("name", "", "description", "", "root", [], ...
    "codebook", [], "correlation", [], "chipPosition", []), 1, numel(names));
for index = 1:numel(names)
    codebook = sequence_codebook(roots{index}, cfg.userCount, index);
    correlation = normalized_aperiodic_correlation(roots{index});
    families(index).name = names(index);
    families(index).description = descriptions(index);
    families(index).root = roots{index};
    families(index).codebook = codebook;
    families(index).correlation = correlation;
    families(index).chipPosition = 0:numel(correlation) - 1;
end
end

function sequence = m_sequence255()
state = ones(1, 8);
sequence = zeros(1, 255);
for index = 1:255
    sequence(index) = state(end);
    feedback = mod(state(8) + state(6) + state(5) + state(4), 2);
    state = [feedback, state(1:end - 1)];
end
sequence = 1 - 2 * sequence;
end

function sequence = refine_sidelobes(sequence, proposalCount, seed)
rng(seed, "twister");
metric = sidelobe_metric(sequence);
for proposal = 1:proposalCount
    index = randi(numel(sequence));
    candidate = sequence;
    candidate(index) = -candidate(index);
    candidateMetric = sidelobe_metric(candidate);
    if candidateMetric < metric
        sequence = candidate;
        metric = candidateMetric;
    end
end
end

function sequence = low_sidelobe_root(lengthValue, seed)
% Deterministic coordinate descent minimizes the aperiodic sidelobe energy.
rng(seed, "twister");
sequence = 2 * randi([0, 1], 1, lengthValue) - 1;
currentMetric = sidelobe_metric(sequence);
accepted = 0;
for proposal = 1:16000
    index = randi(lengthValue);
    candidate = sequence;
    candidate(index) = -candidate(index);
    candidateMetric = sidelobe_metric(candidate);
    if candidateMetric < currentMetric
        sequence = candidate;
        currentMetric = candidateMetric;
        accepted = accepted + 1;
    elseif proposal < 4500 && rand < exp((currentMetric - candidateMetric) / ...
            max(1, 0.08 * lengthValue * (1 - proposal / 4500)))
        sequence = candidate;
        currentMetric = candidateMetric;
    end
    if accepted >= 220
        break;
    end
end
end

function metric = sidelobe_metric(sequence)
correlation = conv(sequence, fliplr(sequence));
centre = numel(sequence);
sidelobes = correlation([1:centre - 1, centre + 1:end]);
metric = sum(sidelobes.^2) + 10 * max(abs(sidelobes))^2;
end

function book = sequence_codebook(root, userCount, familyIndex)
lengthValue = numel(root);
book = zeros(lengthValue, userCount);
if familyIndex == 1
    for user = 1:userCount
        book(:, user) = perturbed_code(root, 48, user, 4100).';
    end
elseif familyIndex == 2
    for user = 1:userCount
        book(:, user) = perturbed_code(root, 102, user, 5200).';
    end
else
    orthogonal = hadamard(256);
    for user = 1:userCount
        book(:, user) = (root .* orthogonal(user, 1:lengthValue)).';
    end
end
book = book / sqrt(lengthValue);
end

function code = perturbed_code(root, flipCount, user, seed)
code = root;
lengthValue = numel(code);
savedState = rng;
rng(seed + user, "twister");
locations = randperm(lengthValue, flipCount);
rng(savedState);
code(locations) = -code(locations);
end

function correlation = normalized_aperiodic_correlation(sequence)
correlation = abs(conv(sequence, fliplr(sequence)));
correlation = correlation / max(correlation);
end

function channel = sparse_channel(cfg)
channel.length = max(cfg.channelDelays) + 1;
channel.impulseResponse = complex(zeros(1, channel.length));
channel.impulseResponse(cfg.channelDelays + 1) = cfg.channelGains;
channel.delays = cfg.channelDelays;
channel.gains = cfg.channelGains;
channel.energy = sum(abs(channel.impulseResponse).^2);
end

function equivalent = matched_filter_equivalent(codebook, channel)
lengthValue = size(codebook, 1);
userCount = size(codebook, 2);
sameSymbol = complex(zeros(userCount));
previousSymbol = complex(zeros(userCount));
for receiveUser = 1:userCount
    reference = codebook(:, receiveUser).';
    for transmitUser = 1:userCount
        spreading = codebook(:, transmitUser).';
        for delay = channel.delays
            gain = channel.impulseResponse(delay + 1);
            sameSymbol(receiveUser, transmitUser) = ...
                sameSymbol(receiveUser, transmitUser) + gain * ...
                sum(reference(delay + 1:end) .* spreading(1:end - delay));
            if delay > 0
                previousSymbol(receiveUser, transmitUser) = ...
                    previousSymbol(receiveUser, transmitUser) + gain * ...
                    sum(reference(1:delay) .* spreading(end - delay + 1:end));
            end
        end
    end
end
equivalent.current = sameSymbol;
equivalent.previous = previousSymbol;
equivalent.conditionNumber = cond(sameSymbol);
end

function frame = sequence_family_frame(family, equivalent, channel, noiseVariance, cfg)
userCount = cfg.userCount;
symbolCount = cfg.symbolsPerFrame;
informationCount = symbolCount / cfg.repetitionFactor;
information = 2 * randi([0, 1], informationCount, userCount) - 1;
if ~synchronization_success(family.root, channel, noiseVariance, cfg)
    decision = 2 * randi([0, 1], informationCount, userCount) - 1;
    frame.errors = sum(decision(:) ~= information(:));
    frame.totalBits = numel(information);
    return;
end
transmitted = zeros(symbolCount, userCount);
permutations = cell(1, userCount);
for user = 1:userCount
    encoded = repelem(information(:, user), cfg.repetitionFactor);
    permutations{user} = randperm(symbolCount);
    transmitted(permutations{user}, user) = encoded;
end

noise = sqrt(noiseVariance / 2) * (randn(symbolCount, userCount) + ...
    1j * randn(symbolCount, userCount));
received = (equivalent.current * transmitted.').';
received(2:end, :) = received(2:end, :) + ...
    (equivalent.previous * transmitted(1:end - 1, :).').';
received = received + noise;

prior = zeros(symbolCount, userCount);
for iteration = 1:cfg.outerIterations
    llr = parallel_lmmse_pic(received, equivalent, noiseVariance, prior);
    prior = repetition_decoder_feedback(llr, permutations, cfg.repetitionFactor);
end
decision = repetition_decode(llr, permutations, cfg.repetitionFactor);
frame.errors = sum(decision(:) ~= information(:));
frame.totalBits = numel(information);
end

function isSynchronized = synchronization_success(root, channel, noiseVariance, cfg)
reference = root / sqrt(numel(root));
signal = cfg.syncAmplitude * conv(reference, channel.impulseResponse);
correctPosition = numel(root);
successfulAcquisitions = 0;
for repeat = 1:cfg.syncRepeatCount
    noise = sqrt(noiseVariance / 2) * ...
        (randn(size(signal)) + 1j * randn(size(signal)));
    metric = abs(conv(signal + noise, fliplr(reference)));
    correctMetric = metric(correctPosition);
    metric(correctPosition) = 0;
    successfulAcquisitions = successfulAcquisitions + (correctMetric >= max(metric));
end
isSynchronized = successfulAcquisitions >= ceil(cfg.syncConsensusRatio * cfg.syncRepeatCount);
end

function llr = parallel_lmmse_pic(received, equivalent, noiseVariance, prior)
symbolCount = size(received, 1);
userCount = size(received, 2);
soft = tanh(prior / 2);
previousSoft = [zeros(1, userCount); soft(1:end - 1, :)];
llr = zeros(symbolCount, userCount);
current = equivalent.current;
previous = equivalent.previous;
residualVariance = noiseVariance + mean(sum(abs(previous).^2, 2));
filter = (current' * current + residualVariance * eye(userCount)) \ current';
gain = diag(filter * current);
postVariance = residualVariance * sum(abs(filter).^2, 2);
for time = 1:symbolCount
    residual = received(time, :).'- previous * previousSoft(time, :).';
    estimate = filter * residual;
    llr(time, :) = (2 * real(conj(gain) .* estimate) ./ ...
        max(real(postVariance), 1e-8)).';
end
end

function feedback = repetition_decoder_feedback(llr, permutations, repetitionFactor)
symbolCount = size(llr, 1);
userCount = size(llr, 2);
feedback = zeros(size(llr));
for user = 1:userCount
    ordered = llr(permutations{user}, user);
    combined = sum(reshape(ordered, repetitionFactor, []), 1).';
    repeated = repelem(combined, repetitionFactor);
    feedback(permutations{user}, user) = repeated;
end
end

function decision = repetition_decode(llr, permutations, repetitionFactor)
symbolCount = size(llr, 1);
userCount = size(llr, 2);
informationCount = symbolCount / repetitionFactor;
decision = zeros(informationCount, userCount);
for user = 1:userCount
    ordered = llr(permutations{user}, user);
    combined = sum(reshape(ordered, repetitionFactor, []), 1).';
    decision(:, user) = 2 * (combined >= 0) - 1;
end
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_13_spreading_sequence_effect.png");
figureHandle = figure("Color", "w", "Position", [120, 100, 1340, 720], "Visible", "off");
layout = tiledlayout(figureHandle, 2, 2, "TileSpacing", "compact", "Padding", "compact");
leftAxis = nexttile(layout, 1);
rightAxis = nexttile(layout, 2);
plot_correlation(leftAxis, result);
plot_ber(rightAxis, result);
captionAxis = nexttile(layout, 3, [1, 2]);
axis(captionAxis, "off");
text(captionAxis, 0.5, 0.61, "图 6-13  扩频序列的影响", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 19);
text(captionAxis, 0.25, 0.25, "(a) 不同扩频序列的相关结果", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 15);
text(captionAxis, 0.75, 0.25, "(b) 不同扩频序列下的误码率结果", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 15);
exportgraphics(figureHandle, figurePath, "Resolution", 240);
close(figureHandle);
end

function plot_correlation(axisHandle, result)
colours = [0.82, 0.27, 0.22; 0.17, 0.48, 0.71; 0.18, 0.63, 0.35];
markers = [">", "s", "d"];
hold(axisHandle, "on");
for index = 1:numel(result.families)
    family = result.families(index);
    plot(axisHandle, family.chipPosition, family.correlation, ...
        "Color", colours(index, :), "LineWidth", 1.05, ...
        "DisplayName", family.name);
    markerPosition = 1 + round((index + 1) * 255 / 5);
    plot(axisHandle, family.chipPosition(markerPosition), family.correlation(markerPosition), ...
        "LineStyle", "none", "Marker", markers(index), "Color", colours(index, :), ...
        "MarkerFaceColor", "w", "MarkerSize", 7, "HandleVisibility", "off");
end
grid(axisHandle, "on");
xlim(axisHandle, [0, 600]);
ylim(axisHandle, [0, 1]);
xlabel(axisHandle, "码片位数");
ylabel(axisHandle, "归一化相关");
legend(axisHandle, "Location", "northeast", "Box", "on", "FontName", "Microsoft YaHei");
set(axisHandle, "FontName", "Microsoft YaHei", "FontSize", 13, "Box", "on", "TickDir", "in");
end

function plot_ber(axisHandle, result)
colours = [0.82, 0.27, 0.22; 0.17, 0.48, 0.71; 0.18, 0.63, 0.35];
markers = [">", "s", "d"];
hold(axisHandle, "on");
for index = 1:numel(result.families)
    curve = result.ber(index, :);
    curve(curve == 0) = result.zeroErrorUpperBound(index, curve == 0);
    semilogy(axisHandle, result.snrDb, curve, "Color", colours(index, :), ...
        "LineWidth", 1.45, "Marker", markers(index), "MarkerFaceColor", "w", ...
        "MarkerSize", 7, "DisplayName", result.families(index).name);
end
grid(axisHandle, "on");
axisHandle.YScale = "log";
axisHandle.XMinorGrid = "on";
axisHandle.YMinorGrid = "on";
axisHandle.GridLineStyle = "--";
axisHandle.MinorGridLineStyle = ":";
axisHandle.GridAlpha = 0.42;
axisHandle.MinorGridAlpha = 0.32;
xlim(axisHandle, [-2, 6]);
ylim(axisHandle, [1e-5, 1]);
xlabel(axisHandle, "E_b/N_0/dB", "FontName", "Times New Roman");
ylabel(axisHandle, "BER", "FontName", "Times New Roman");
legend(axisHandle, "Location", "northeast", "Box", "on", "FontName", "Microsoft YaHei");
set(axisHandle, "FontName", "Times New Roman", "FontSize", 13, "Box", "on", "TickDir", "in");
end
