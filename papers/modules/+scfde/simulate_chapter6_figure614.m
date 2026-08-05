function result = simulate_chapter6_figure614(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE614 Simulate Fig. 6-14 BER under user loading.
%   A frame uses 255-chip binary spreading, a sparse multipath channel,
%   repeated acquisition, and joint LMMSE-PIC with soft repetition decoding.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrDb = -2:1:6;
defaults.userCounts = [8, 12, 16];
defaults.referenceUserCount = 8;
defaults.codeLength = 255;
defaults.codeFlipCount = 100;
defaults.loadPowerExponent = 0.80;
defaults.syncLoadPowerExponent = 0.65;
defaults.symbolsPerFrame = 180;
defaults.frameCount = 500;
defaults.repetitionFactor = 3;
defaults.outerIterations = 2;
defaults.channelDelays = [0, 11, 27, 59];
defaults.channelGains = [1.00, 0.37 * exp(1j * 0.44), ...
    0.25 * exp(-1j * 0.83), 0.16 * exp(1j * 1.37)];
defaults.syncRepeatCount = 9;
defaults.syncConsensusRatio = 2 / 3;
defaults.syncAmplitude = 2.85;
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
root = m_sequence255();
channel = sparse_channel(cfg);
loadCount = numel(cfg.userCounts);
snrCount = numel(cfg.snrDb);
ber = zeros(loadCount, snrCount);
errorCount = zeros(loadCount, snrCount);
bitCount = zeros(loadCount, snrCount);
systems = cell(loadCount, 1);

for loadIndex = 1:loadCount
    users = cfg.userCounts(loadIndex);
    codes = loaded_codebook(root, users, cfg.codeLength, cfg.codeFlipCount);
    systems{loadIndex} = matched_filter_system(codes, channel, users, cfg);
    for snrIndex = 1:snrCount
        noiseVariance = 10^(-cfg.snrDb(snrIndex) / 10);
        errors = 0;
        total = 0;
        for frameIndex = 1:cfg.frameCount
            frame = loaded_frame(root, channel, systems{loadIndex}, ...
                noiseVariance, cfg);
            errors = errors + frame.errors;
            total = total + frame.totalBits;
        end
        errorCount(loadIndex, snrIndex) = errors;
        bitCount(loadIndex, snrIndex) = total;
        ber(loadIndex, snrIndex) = errors / total;
    end
end

result.config = cfg;
result.model = "255-chip multiuser spreading; total-power constrained loading; repeated PN acquisition; correlated matched-filter noise; joint LMMSE-PIC and repetition soft decoding";
result.rootSequence = root;
result.channel = channel;
result.systems = systems;
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
result.matPath = fullfile(cfg.outputDir, "fig6_14_user_loading_ber.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_14_user_loading_ber.csv");
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
assert(cfg.codeLength == 255, "SCFDE:Figure614CodeLength", ...
    "Fig. 6-14 uses 255-chip spreading.");
assert(isequal(cfg.userCounts, [8, 12, 16]), "SCFDE:Figure614Users", ...
    "Fig. 6-14 compares 8, 12, and 16 users.");
assert(mod(cfg.symbolsPerFrame, cfg.repetitionFactor) == 0, ...
    "SCFDE:Figure614Repetition", "symbolsPerFrame must divide repetitionFactor.");
assert(numel(cfg.channelDelays) == numel(cfg.channelGains), ...
    "SCFDE:Figure614Channel", "channelDelays and channelGains must have the same length.");
assert(all(cfg.channelDelays >= 0) && all(cfg.channelDelays < cfg.codeLength), ...
    "SCFDE:Figure614Delays", "All channel delays must be less than codeLength.");
assert(cfg.syncRepeatCount >= 1 && cfg.syncConsensusRatio > 0 && cfg.syncConsensusRatio <= 1, ...
    "SCFDE:Figure614Sync", "The synchronization consensus parameters are invalid.");
assert(cfg.loadPowerExponent > 0 && cfg.loadPowerExponent <= 1 && ...
    cfg.syncLoadPowerExponent > 0 && cfg.syncLoadPowerExponent <= 1, ...
    "SCFDE:Figure614Power", "The load power exponents must be in (0, 1].");
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
channel.gains = cfg.channelGains;
end

function book = loaded_codebook(root, userCount, codeLength, flipCount)
book = zeros(codeLength, userCount);
for user = 1:userCount
    code = root;
    if user > 1
        savedState = rng;
        rng(61400 + user, "twister");
        locations = randperm(codeLength, flipCount);
        rng(savedState);
        code(locations) = -code(locations);
    end
    book(:, user) = code.';
end
book = book / sqrt(codeLength);
end

function system = matched_filter_system(codes, channel, users, cfg)
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
powerScale = (cfg.referenceUserCount / users)^(cfg.loadPowerExponent / 2);
system.userCount = users;
system.codebook = codes;
system.current = powerScale * current;
system.previous = powerScale * previous;
system.noiseCorrelation = codes' * codes;
system.powerScale = powerScale;
system.syncPowerScale = (cfg.referenceUserCount / users)^(cfg.syncLoadPowerExponent / 2);
system.conditionNumber = cond(system.current);
end

function frame = loaded_frame(root, channel, system, noiseVariance, cfg)
users = system.userCount;
symbolCount = cfg.symbolsPerFrame;
informationCount = symbolCount / cfg.repetitionFactor;
information = 2 * randi([0, 1], informationCount, users) - 1;
if ~synchronization_success(root, channel, noiseVariance, system.syncPowerScale, cfg)
    decision = 2 * randi([0, 1], informationCount, users) - 1;
    frame.errors = sum(decision(:) ~= information(:));
    frame.totalBits = numel(information);
    return;
end

transmitted = zeros(symbolCount, users);
permutations = cell(1, users);
for user = 1:users
    encoded = repelem(information(:, user), cfg.repetitionFactor);
    permutations{user} = randperm(symbolCount);
    transmitted(permutations{user}, user) = encoded;
end

factor = chol(system.noiseCorrelation + 1e-10 * eye(users), "lower");
noise = sqrt(noiseVariance / 2) * (randn(symbolCount, users) + ...
    1j * randn(symbolCount, users)) * factor.';
received = (system.current * transmitted.').';
received(2:end, :) = received(2:end, :) + ...
    (system.previous * transmitted(1:end - 1, :).').';
received = received + noise;

prior = zeros(symbolCount, users);
for iteration = 1:cfg.outerIterations
    llr = joint_lmmse_pic(received, system, noiseVariance, prior);
    prior = repetition_feedback(llr, permutations, cfg.repetitionFactor);
end
decision = repetition_decode(llr, permutations, cfg.repetitionFactor);
frame.errors = sum(decision(:) ~= information(:));
frame.totalBits = numel(information);
end

function isSynchronized = synchronization_success(root, channel, noiseVariance, powerScale, cfg)
reference = root / sqrt(numel(root));
signal = cfg.syncAmplitude * powerScale * conv(reference, channel.impulseResponse);
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

function llr = joint_lmmse_pic(received, system, noiseVariance, prior)
symbolCount = size(received, 1);
users = system.userCount;
soft = tanh(prior / 2);
previousSoft = [zeros(1, users); soft(1:end - 1, :)];
covariance = noiseVariance * system.noiseCorrelation + ...
    system.previous * system.previous';
filter = (system.current' * (covariance \ system.current) + eye(users)) \ ...
    (system.current' / covariance);
gain = diag(filter * system.current);
postVariance = real(diag(filter * covariance * filter'));
llr = zeros(symbolCount, users);
for time = 1:symbolCount
    residual = received(time, :).'- system.previous * previousSoft(time, :).';
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
figurePath = fullfile(cfg.outputDir, "fig6_14_user_loading_ber.png");
figureHandle = figure("Color", "w", "Position", [260, 70, 850, 900], "Visible", "off");
axisHandle = axes(figureHandle);
hold(axisHandle, "on");
axisHandle.Position = [0.14, 0.20, 0.78, 0.73];
colours = [0.84, 0.25, 0.19; 0.20, 0.47, 0.74; 0.18, 0.62, 0.35];
markers = [">", "s", "d"];
for index = 1:numel(cfg.userCounts)
    curve = result.ber(index, :);
    curve(curve == 0) = result.zeroErrorUpperBound(index, curve == 0);
    semilogy(axisHandle, result.snrDb, curve, "Color", colours(index, :), ...
        "LineWidth", 1.55, "Marker", markers(index), "MarkerFaceColor", "w", ...
        "MarkerSize", 8, "DisplayName", string(cfg.userCounts(index)) + "个用户");
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
    "String", "图 6-14  不同用户的误码率", "HorizontalAlignment", "center", ...
    "VerticalAlignment", "middle", "EdgeColor", "none", ...
    "FontName", "Microsoft YaHei", "FontSize", 17);
exportgraphics(figureHandle, figurePath, "Resolution", 240);
close(figureHandle);
end
