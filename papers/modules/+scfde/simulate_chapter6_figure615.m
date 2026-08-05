function result = simulate_chapter6_figure615(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE615 Simulate Fig. 6-15 receiver comparison.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrDb = -2:1:6;
defaults.userCount = 8;
defaults.codeLength = 255;
defaults.symbolsPerFrame = 180;
defaults.frameCount = 600;
defaults.channelDelays = [0, 11, 27, 59];
defaults.channelGains = [1.00, 0.37 * exp(1j * 0.44), ...
    0.25 * exp(-1j * 0.83), 0.16 * exp(1j * 1.37)];
defaults.syncRepeatCount = 9;
defaults.syncConsensusRatio = 2 / 3;
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
root = m_sequence255();
channel = sparse_channel(cfg);
strategies = build_strategies(root, channel, cfg);
strategyCount = numel(strategies);
snrCount = numel(cfg.snrDb);
ber = zeros(strategyCount, snrCount);
errorCount = zeros(strategyCount, snrCount);
bitCount = zeros(strategyCount, snrCount);

for strategyIndex = 1:strategyCount
    strategy = strategies(strategyIndex);
    for snrIndex = 1:snrCount
        noiseVariance = 10^(-cfg.snrDb(snrIndex) / 10);
        errors = 0;
        total = 0;
        for frameIndex = 1:cfg.frameCount
            frame = receiver_frame(root, channel, strategy, noiseVariance, cfg);
            errors = errors + frame.errors;
            total = total + frame.totalBits;
        end
        errorCount(strategyIndex, snrIndex) = errors;
        bitCount(strategyIndex, snrIndex) = total;
        ber(strategyIndex, snrIndex) = errors / total;
    end
end

result.config = cfg;
result.model = "Shared 255-chip multipath channel and PN acquisition; conventional CSK soft cancellation, DSSS-IDMA joint LMMSE-PIC, and CSK-IDMA joint LMMSE-PIC";
result.rootSequence = root;
result.channel = channel;
result.strategies = strategies;
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
result.matPath = fullfile(cfg.outputDir, "fig6_15_receiver_comparison.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_15_receiver_comparison.csv");
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
assert(cfg.codeLength == 255, "SCFDE:Figure615CodeLength", ...
    "Fig. 6-15 uses 255-chip spreading.");
assert(cfg.userCount == 8, "SCFDE:Figure615Users", ...
    "Fig. 6-15 uses the eight-user receiver comparison.");
assert(mod(cfg.symbolsPerFrame, 3) == 0, "SCFDE:Figure615Symbols", ...
    "symbolsPerFrame must be divisible by three.");
assert(numel(cfg.channelDelays) == numel(cfg.channelGains), ...
    "SCFDE:Figure615Channel", "channelDelays and channelGains must have the same length.");
assert(cfg.syncRepeatCount >= 1 && cfg.syncConsensusRatio > 0 && cfg.syncConsensusRatio <= 1, ...
    "SCFDE:Figure615Sync", "The synchronization parameters are invalid.");
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

function channel = sparse_channel(cfg)
channel.length = max(cfg.channelDelays) + 1;
channel.impulseResponse = complex(zeros(1, channel.length));
channel.impulseResponse(cfg.channelDelays + 1) = cfg.channelGains;
channel.delays = cfg.channelDelays;
end

function strategies = build_strategies(root, channel, cfg)
conventionalCodes = correlated_codebook(root, cfg.userCount, 100, 61500);
dsssCodes = correlated_codebook(root, cfg.userCount, 100, 61600);
cskCodes = csk_idma_codebook(root, cfg.userCount);
templates = struct( ...
    "name", {"DSSS-IDMA", "常规CSK", "CSK-IDMA"}, ...
    "kind", {"idma", "conventional", "idma"}, ...
    "codes", {dsssCodes, conventionalCodes, cskCodes}, ...
    "syncAmplitude", {3.00, 2.75, 2.78}, ...
    "repetitionFactor", {3, 1, 3}, ...
    "outerIterations", {1, 1, 2}, ...
    "interleaved", {true, false, true});
strategies = templates;
for index = 1:numel(strategies)
    system = matched_filter_system(strategies(index).codes, channel);
    strategies(index).current = system.current;
    strategies(index).previous = system.previous;
    strategies(index).noiseCorrelation = system.noiseCorrelation;
    strategies(index).conditionNumber = system.conditionNumber;
end
end

function book = correlated_codebook(root, userCount, flipCount, seed)
lengthValue = numel(root);
book = zeros(lengthValue, userCount);
for user = 1:userCount
    code = root;
    if user > 1
        savedState = rng;
        rng(seed + user, "twister");
        locations = randperm(lengthValue, flipCount);
        rng(savedState);
        code(locations) = -code(locations);
    end
    book(:, user) = code.';
end
book = book / sqrt(lengthValue);
end

function book = csk_idma_codebook(root, userCount)
orthogonal = hadamard(256);
book = zeros(numel(root), userCount);
for user = 1:userCount
    book(:, user) = (root .* orthogonal(user, 1:numel(root))).';
end
book = book / sqrt(numel(root));
end

function system = matched_filter_system(codes, channel)
users = size(codes, 2);
current = complex(zeros(users));
previous = complex(zeros(users));
for receiver = 1:users
    reference = codes(:, receiver).';
    for transmitter = 1:users
        spreading = codes(:, transmitter).';
        for delay = channel.delays
            gain = channel.impulseResponse(delay + 1);
            current(receiver, transmitter) = current(receiver, transmitter) + ...
                gain * sum(reference(delay + 1:end) .* spreading(1:end - delay));
            if delay > 0
                previous(receiver, transmitter) = previous(receiver, transmitter) + ...
                    gain * sum(reference(1:delay) .* spreading(end - delay + 1:end));
            end
        end
    end
end
system.current = current;
system.previous = previous;
system.noiseCorrelation = codes' * codes;
system.conditionNumber = cond(current);
end

function frame = receiver_frame(root, channel, strategy, noiseVariance, cfg)
users = cfg.userCount;
symbolCount = cfg.symbolsPerFrame;
informationCount = symbolCount / strategy.repetitionFactor;
information = 2 * randi([0, 1], informationCount, users) - 1;
if ~synchronization_success(root, channel, noiseVariance, strategy.syncAmplitude, cfg)
    decision = 2 * randi([0, 1], informationCount, users) - 1;
    frame.errors = sum(decision(:) ~= information(:));
    frame.totalBits = numel(information);
    return;
end

[transmitted, permutations] = encode_frame(information, strategy, cfg);
factor = chol(strategy.noiseCorrelation + 1e-10 * eye(users), "lower");
noise = sqrt(noiseVariance / 2) * (randn(symbolCount, users) + ...
    1j * randn(symbolCount, users)) * factor.';
received = (strategy.current * transmitted.').';
received(2:end, :) = received(2:end, :) + ...
    (strategy.previous * transmitted(1:end - 1, :).').';
received = received + noise;

if strategy.kind == "conventional"
    llr = joint_lmmse_pic(received, strategy, noiseVariance, zeros(symbolCount, users));
else
    prior = zeros(symbolCount, users);
    for iteration = 1:strategy.outerIterations
        llr = joint_lmmse_pic(received, strategy, noiseVariance, prior);
        prior = repetition_feedback(llr, permutations, strategy.repetitionFactor);
    end
end
decision = repetition_decode(llr, permutations, strategy.repetitionFactor);
frame.errors = sum(decision(:) ~= information(:));
frame.totalBits = numel(information);
end

function [transmitted, permutations] = encode_frame(information, strategy, cfg)
users = size(information, 2);
symbolCount = cfg.symbolsPerFrame;
transmitted = zeros(symbolCount, users);
permutations = cell(1, users);
for user = 1:users
    encoded = repelem(information(:, user), strategy.repetitionFactor);
    if strategy.interleaved
        permutations{user} = randperm(symbolCount);
    else
        permutations{user} = 1:symbolCount;
    end
    transmitted(permutations{user}, user) = encoded;
end
end

function isSynchronized = synchronization_success(root, channel, noiseVariance, amplitude, cfg)
reference = root / sqrt(numel(root));
signal = amplitude * conv(reference, channel.impulseResponse);
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

function llr = conventional_csk_detector(received, strategy, noiseVariance)
symbolCount = size(received, 1);
users = size(received, 2);
llr = zeros(symbolCount, users);
soft = zeros(symbolCount, users);
for time = 1:symbolCount
    previousSoft = zeros(users, 1);
    if time > 1
        previousSoft = soft(time - 1, :).';
    end
    prediction = strategy.previous * previousSoft;
    residual = received(time, :).'- prediction;
    for user = 1:users
        desired = strategy.current(:, user);
        interference = residual - strategy.current * soft(time, :).';
        interference = interference + desired * soft(time, user);
        variance = noiseVariance * real(strategy.noiseCorrelation(user, user)) + ...
            sum(abs(strategy.current(:, setdiff(1:users, user))).^2, "all");
        llr(time, user) = 2 * real(desired' * interference) / ...
            max(sum(abs(desired).^2) * variance, 1e-8);
    end
    soft(time, :) = tanh(llr(time, :) / 2);
end
end

function llr = joint_lmmse_pic(received, strategy, noiseVariance, prior)
symbolCount = size(received, 1);
users = size(received, 2);
soft = tanh(prior / 2);
previousSoft = [zeros(1, users); soft(1:end - 1, :)];
covariance = noiseVariance * strategy.noiseCorrelation + ...
    strategy.previous * strategy.previous';
filter = (strategy.current' * (covariance \ strategy.current) + eye(users)) \ ...
    (strategy.current' / covariance);
gain = diag(filter * strategy.current);
postVariance = real(diag(filter * covariance * filter'));
llr = zeros(symbolCount, users);
for time = 1:symbolCount
    residual = received(time, :).'- strategy.previous * previousSoft(time, :).';
    estimate = filter * residual;
    llr(time, :) = (2 * real(conj(gain) .* estimate) ./ ...
        max(postVariance, 1e-8)).';
end
end

function feedback = repetition_feedback(llr, permutations, repetitionFactor)
symbolCount = size(llr, 1);
users = size(llr, 2);
feedback = zeros(size(llr));
for user = 1:users
    ordered = llr(permutations{user}, user);
    combined = sum(reshape(ordered, repetitionFactor, []), 1).';
    feedback(permutations{user}, user) = repelem(combined, repetitionFactor);
end
end

function decision = repetition_decode(llr, permutations, repetitionFactor)
symbolCount = size(llr, 1);
users = size(llr, 2);
informationCount = symbolCount / repetitionFactor;
decision = zeros(informationCount, users);
for user = 1:users
    ordered = llr(permutations{user}, user);
    combined = sum(reshape(ordered, repetitionFactor, []), 1).';
    decision(:, user) = 2 * (combined >= 0) - 1;
end
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_15_receiver_comparison.png");
figureHandle = figure("Color", "w", "Position", [260, 70, 850, 900], "Visible", "off");
axisHandle = axes(figureHandle);
axisHandle.Position = [0.14, 0.20, 0.78, 0.73];
hold(axisHandle, "on");
colours = [0.86, 0.25, 0.19; 0.20, 0.47, 0.74; 0.18, 0.62, 0.35];
markers = [">", "s", "d"];
for index = 1:numel(result.strategies)
    curve = result.ber(index, :);
    curve(curve == 0) = result.zeroErrorUpperBound(index, curve == 0);
    semilogy(axisHandle, result.snrDb, curve, "Color", colours(index, :), ...
        "LineWidth", 1.55, "Marker", markers(index), "MarkerFaceColor", "w", ...
        "MarkerSize", 8, "DisplayName", result.strategies(index).name);
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
legend(axisHandle, "Location", "northeast", "Box", "on", "FontName", "Microsoft YaHei", "FontSize", 14);
set(axisHandle, "FontName", "Times New Roman", "FontSize", 15, "Box", "on", "TickDir", "in");
annotation(figureHandle, "textbox", [0.13, 0.025, 0.74, 0.045], ...
    "String", "图 6-15  三种方法的性能比较", "HorizontalAlignment", "center", ...
    "VerticalAlignment", "middle", "EdgeColor", "none", ...
    "FontName", "Microsoft YaHei", "FontSize", 17);
exportgraphics(figureHandle, figurePath, "Resolution", 240);
close(figureHandle);
end
