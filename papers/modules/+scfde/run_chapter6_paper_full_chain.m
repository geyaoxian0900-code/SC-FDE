function results = run_chapter6_paper_full_chain(options, simulationDir)
%RUN_CHAPTER6_PAPER_FULL_CHAIN Chapter 6 chip-level CSK-IDMA receiver.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(mfilename("fullpath")));
end

defaults.snrDb = -2:1:5;
defaults.frameCount = 500;
defaults.symbolsPerFrame = 40;
defaults.codeLength = 256;
defaults.cskOrder = 32;
defaults.idmaUsers = 8;
defaults.idmaUserCounts = [8, 12, 16];
defaults.comparisonUserCounts = [8, 10];
defaults.innerIterations = 3;
defaults.outerIterations = 3;
defaults.chipRate = 2000;
defaults.syncLength = 128;
defaults.syncRepeatCount = 8;
defaults.trainingLength = 256;
defaults.channelLength = 41;
defaults.pathCount = 5;
defaults.delaySpreadChips = 40;
defaults.frameStartOffset = 9;
defaults.syncSearchSpan = 128;
defaults.syncAmplitude = 4;
defaults.trainingAmplitude = 4;
defaults.commonCfoHz = 0.35;
defaults.initialPhase = 0.42;
defaults.channelEstimator = "LS";
defaults.enablePtr = true;
defaults.eseDamping = 0.58;   % consistent with run_chapter6_spread_spectrum_suite
defaults.runLoadStudy = true;
defaults.runComparison = true;
defaults.randomSeed = 20260804;
defaults.diagnosticSnrDb = 2;
defaults.makePlot = true;
defaults.exportData = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_paper_full_chain", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);
rng(cfg.randomSeed, "twister");

root = paper_pn_root(cfg.codeLength);
[cskBook, bitTable] = csk_codebook(root, cfg.cskOrder);
[dsssBook, ~] = dsss_codebook(cfg.codeLength, cfg.cskOrder, bitTable);

results.config = cfg;
results.formulaCoverage = [ ...
    "(6-20)-(6-23) 帧内多径叠加、均值和方差", ...
    "(6-24)-(6-36) ESE 与交织/解交织软信息交换", ...
    "(6-37)-(6-46) 用户特定 PTR 等效信道和 ESE", ...
    "(6-51)-(6-64) CSK 软 MAP 外译码与概率回馈"];
results.signalModel = "帧内准静止、帧间独立的水声多径；同步、频偏与信道估计为显式前端模块。";
results.rootSequence = root;
results.cskBook = cskBook;
results.bitTable = bitTable;
results.figurePaths = strings(0, 1);
results.dataPaths = strings(0, 1);

results.idma = run_sweep(cfg, cskBook, bitTable, cfg.idmaUsers, "CSK", true);
if cfg.runLoadStudy
    results.idma.loadingBer = zeros(numel(cfg.idmaUserCounts), numel(cfg.snrDb));
    for index = 1:numel(cfg.idmaUserCounts)
        loadResult = run_sweep(cfg, cskBook, bitTable, cfg.idmaUserCounts(index), "CSK", false);
        results.idma.loadingBer(index, :) = loadResult.outerBer(end, :);
    end
else
    results.idma.loadingBer = [];
end
results.idma.idmaUserCounts = cfg.idmaUserCounts;

if cfg.runComparison
    comparison = zeros(2, numel(cfg.comparisonUserCounts), numel(cfg.snrDb));
    for index = 1:numel(cfg.comparisonUserCounts)
        dsss = run_sweep(cfg, dsssBook, bitTable, cfg.comparisonUserCounts(index), "DSSS", false);
        csk = run_sweep(cfg, cskBook, bitTable, cfg.comparisonUserCounts(index), "CSK", false);
        comparison(1, index, :) = dsss.outerBer(end, :);
        comparison(2, index, :) = csk.outerBer(end, :);
    end
    results.idma.comparisonBer = comparison;
else
    results.idma.comparisonBer = [];
end
results.idma.comparisonUserCounts = cfg.comparisonUserCounts;

if cfg.makePlot
    results.figurePaths = [ ...
        plot_iterations(results, cfg); ...
        plot_synchronization(results, cfg); ...
        plot_loading_comparison(results, cfg)];
end
if cfg.exportData
    results.dataPaths = export_data(results, cfg);
end
end

function output = run_sweep(cfg, codebook, bitTable, userCount, modulationName, keepDiagnostic)
snrCount = numel(cfg.snrDb);
innerErrors = zeros(cfg.innerIterations, snrCount);
outerErrors = zeros(cfg.outerIterations, snrCount);
innerMse = zeros(cfg.innerIterations, snrCount);
outerMse = zeros(cfg.outerIterations, snrCount);
totalBits = zeros(1, snrCount);
timingSquaredError = zeros(1, snrCount);
cfoSquaredError = zeros(1, snrCount);
channelNmse = zeros(1, snrCount);
diagnostic = struct();

for snrIndex = 1:snrCount
    for frameIndex = 1:cfg.frameCount
        frame = full_chain_frame(cfg, codebook, bitTable, userCount, cfg.snrDb(snrIndex));
        innerErrors(:, snrIndex) = innerErrors(:, snrIndex) + frame.innerErrors;
        outerErrors(:, snrIndex) = outerErrors(:, snrIndex) + frame.outerErrors;
        innerMse(:, snrIndex) = innerMse(:, snrIndex) + frame.innerMse;
        outerMse(:, snrIndex) = outerMse(:, snrIndex) + frame.outerMse;
        totalBits(snrIndex) = totalBits(snrIndex) + frame.totalBits;
        timingSquaredError(snrIndex) = timingSquaredError(snrIndex) + frame.sync.timingError^2;
        cfoSquaredError(snrIndex) = cfoSquaredError(snrIndex) + frame.sync.cfoError^2;
        channelNmse(snrIndex) = channelNmse(snrIndex) + frame.sync.channelNmse;
        if keepDiagnostic && frameIndex == 1 && cfg.snrDb(snrIndex) == cfg.diagnosticSnrDb
            diagnostic = frame;
        end
    end
end
if isempty(fieldnames(diagnostic))
    diagnostic = full_chain_frame(cfg, codebook, bitTable, userCount, cfg.diagnosticSnrDb);
end

output.modulationName = string(modulationName);
output.userCount = userCount;
output.snrDb = cfg.snrDb;
output.innerBer = innerErrors ./ totalBits;
output.outerBer = outerErrors ./ totalBits;
output.innerMse = innerMse / cfg.frameCount;
output.outerMse = outerMse / cfg.frameCount;
output.innerErrors = innerErrors;
output.outerErrors = outerErrors;
output.totalBits = totalBits;
output.sync.timingRmse = sqrt(timingSquaredError / cfg.frameCount);
output.sync.cfoRmseHz = sqrt(cfoSquaredError / cfg.frameCount);
output.sync.channelNmse = channelNmse / cfg.frameCount;
output.diagnostic = diagnostic;
end

function frame = full_chain_frame(cfg, codebook, bitTable, userCount, snrDb)
symbolCount = cfg.symbolsPerFrame;
chipCount = cfg.codeLength;
bitCount = size(bitTable, 2);
dataLength = symbolCount * chipCount;
alphabetSize = size(codebook, 1);
information = randi(alphabetSize, symbolCount, userCount);
transmitted = zeros(userCount, dataLength);
permutations = cell(1, userCount);
for user = 1:userCount
    chips = reshape(codebook(information(:, user), :).', 1, []);
    permutations{user} = randperm(dataLength);
    transmitted(user, permutations{user}) = chips;
end

[trueChannels, channelInfo] = time_varying_uwa_channel(cfg, userCount);
[received, template, noiseVariance] = transmit_frame(cfg, transmitted, trueChannels, snrDb);
[aligned, sync] = synchronize_frame(received, template, cfg);
estimatedChannels = estimate_user_channels(aligned, template, cfg, noiseVariance, userCount);
dataReceived = extract_samples(aligned, template.dataStart, ...
    dataLength + cfg.channelLength - 1);
[ptrObservation, equivalentChannels, ptrNoiseVariance] = ptr_front_end( ...
    dataReceived, estimatedChannels, cfg, noiseVariance);

detector = csk_idma_turbo_detector(ptrObservation, equivalentChannels, ...
    ptrNoiseVariance, permutations, codebook, bitTable, information, transmitted, cfg);
frame.innerErrors = detector.innerErrors;
frame.outerErrors = detector.outerErrors;
frame.innerMse = detector.innerMse;
frame.outerMse = detector.outerMse;
frame.totalBits = symbolCount * userCount * bitCount;
frame.information = information;
frame.transmitted = transmitted;
frame.trueChannels = trueChannels;
frame.estimatedChannels = estimatedChannels;
frame.channelInfo = channelInfo;
frame.ptrObservation = ptrObservation;
frame.equivalentChannels = equivalentChannels;
frame.detector = detector;
frame.sync = sync;
frame.sync.channelNmse = sum(abs(estimatedChannels(:) - trueChannels(:)).^2) / ...
    max(sum(abs(trueChannels(:)).^2), eps);
end

function [channels, info] = time_varying_uwa_channel(cfg, userCount)
channels = complex(zeros(userCount, cfg.channelLength));
delays = zeros(userCount, cfg.pathCount);
for user = 1:userCount
    pathDelays = unique([0, randi([1, cfg.delaySpreadChips], 1, cfg.pathCount - 1)]);
    while numel(pathDelays) < cfg.pathCount
        pathDelays = unique([pathDelays, randi([1, cfg.delaySpreadChips])]);
    end
    pathDelays = sort(pathDelays(1:cfg.pathCount));
    powers = exp(-0.11 * pathDelays);
    gains = sqrt(powers / 2) .* (randn(1, cfg.pathCount) + 1j * randn(1, cfg.pathCount));
    gains(1) = 1.0 * exp(1j * 0.18 * (user - 1));
    channels(user, pathDelays + 1) = gains;
    channels(user, :) = channels(user, :) / max(norm(channels(user, :)), eps);
    delays(user, :) = pathDelays;
end
info.model = "帧内准静止、帧间独立随机多径";
info.pathDelays = delays;
end

function [received, template, noiseVariance] = transmit_frame(cfg, data, channels, snrDb)
userCount = size(data, 1);
sync = synchronization_sequence(cfg.syncLength);
guardLength = cfg.channelLength - 1;
trainingSlotLength = cfg.trainingLength + guardLength;
prefixLength = cfg.syncRepeatCount * cfg.syncLength + guardLength + ...
    userCount * trainingSlotLength;
dataStart = prefixLength + 1;
frameLength = prefixLength + size(data, 2);
transmitted = complex(zeros(userCount, frameLength));
for user = 1:userCount
    for repeat = 0:cfg.syncRepeatCount - 1
        range = repeat * cfg.syncLength + (1:cfg.syncLength);
        transmitted(user, range) = cfg.syncAmplitude * sync / sqrt(userCount);
    end
    pilotStart = cfg.syncRepeatCount * cfg.syncLength + guardLength + ...
        (user - 1) * trainingSlotLength + 1;
    transmitted(user, pilotStart:pilotStart + cfg.trainingLength - 1) = ...
        cfg.trainingAmplitude * paper_pn_root(cfg.trainingLength, user + 3);
    transmitted(user, dataStart:end) = data(user, :);
end

clean = complex(zeros(1, frameLength + cfg.channelLength - 1));
for user = 1:userCount
    clean = clean + conv(transmitted(user, :), channels(user, :));
end
clean = [zeros(1, cfg.frameStartOffset), clean];
bitsPerSymbol = log2(cfg.cskOrder);
noiseVariance = cfg.codeLength / (bitsPerSymbol * 10^(snrDb / 10));
sample = 0:numel(clean) - 1;
carrier = exp(1j * (cfg.initialPhase + 2 * pi * cfg.commonCfoHz * sample / cfg.chipRate));
received = clean .* carrier + sqrt(noiseVariance / 2) * ...
    (randn(size(clean)) + 1j * randn(size(clean)));
template.sync = sync;
template.frameStart = cfg.frameStartOffset + 1;
template.dataStart = dataStart;
template.frameLength = frameLength;
template.trainingSlotLength = trainingSlotLength;
template.guardLength = guardLength;
end

function [aligned, sync] = synchronize_frame(received, template, cfg)
correlation = conv(received, conj(fliplr(template.sync)), "valid");
searchEnd = min(numel(correlation), template.frameStart + ...
    min(cfg.syncSearchSpan, cfg.syncLength - 1));
[~, frameStart] = max(abs(correlation(1:searchEnd)));
aligned = extract_samples(received, frameStart, ...
    template.frameLength + cfg.channelLength - 1);
reference = aligned(1:cfg.syncLength);
phase = zeros(1, cfg.syncRepeatCount);
for repeat = 0:cfg.syncRepeatCount - 1
    range = repeat * cfg.syncLength + (1:cfg.syncLength);
    phase(repeat + 1) = angle(sum(aligned(range) .* conj(reference)));
end
fit = polyfit((0:cfg.syncRepeatCount - 1) * cfg.syncLength, unwrap(phase), 1);
estimatedCfo = fit(1) * cfg.chipRate / (2 * pi);
sample = 0:numel(aligned) - 1;
aligned = aligned .* exp(-1j * 2 * pi * estimatedCfo * sample / cfg.chipRate);
sync.correlation = correlation;
sync.frameStartEstimate = frameStart;
sync.frameStartTrue = template.frameStart;
sync.timingError = frameStart - template.frameStart;
sync.estimatedCfoHz = estimatedCfo;
sync.cfoError = estimatedCfo - cfg.commonCfoHz;
sync.aligned = aligned;
end

function channels = estimate_user_channels(aligned, template, cfg, noiseVariance, userCount)
channels = complex(zeros(userCount, cfg.channelLength));
for user = 1:userCount
    pilotStart = cfg.syncRepeatCount * cfg.syncLength + template.guardLength + ...
        (user - 1) * template.trainingSlotLength + 1;
    pilot = cfg.trainingAmplitude * paper_pn_root(cfg.trainingLength, user + 3);
    observation = extract_samples(aligned, pilotStart, ...
        cfg.trainingLength + cfg.channelLength - 1);
    channels(user, :) = estimate_channel(observation, pilot, cfg, noiseVariance);
end
end

function channel = estimate_channel(observation, pilot, cfg, noiseVariance)
pilotLength = numel(pilot);
matrix = complex(zeros(pilotLength + cfg.channelLength - 1, cfg.channelLength));
for tap = 1:cfg.channelLength
    matrix(tap:tap + pilotLength - 1, tap) = pilot.';
end
if strcmpi(cfg.channelEstimator, "MMSE")
    priorVariance = 1 / cfg.channelLength;
    channel = (matrix' * matrix + noiseVariance / priorVariance * eye(cfg.channelLength)) \ ...
        (matrix' * observation(:));
else
    channel = (matrix' * matrix + 1e-8 * eye(cfg.channelLength)) \ ...
        (matrix' * observation(:));
end
channel = channel(:).';
end

function [observations, equivalent, noiseVariance] = ptr_front_end( ...
        dataReceived, estimatedChannels, cfg, inputNoiseVariance)
userCount = size(estimatedChannels, 1);
dataLength = numel(dataReceived) - cfg.channelLength + 1;
observations = complex(zeros(userCount, dataLength));
equivalent = cell(userCount, userCount);
noiseVariance = zeros(userCount, 1);
for target = 1:userCount
    if cfg.enablePtr
        filter = conj(fliplr(estimatedChannels(target, :)));
        gain = max(sum(abs(estimatedChannels(target, :)).^2), eps);
    else
        filter = 1;
        gain = 1;
    end
    output = conv(dataReceived, filter) / gain;
    centre = cfg.channelLength;
    observations(target, :) = output(centre:centre + dataLength - 1);
    noiseVariance(target) = inputNoiseVariance / gain;
    for source = 1:userCount
        equivalent{target, source} = conv(estimatedChannels(source, :), filter) / gain;
    end
end
end

function output = csk_idma_turbo_detector(observation, equivalent, noiseVariance, ...
        permutations, codebook, bitTable, truth, transmitted, cfg)
userCount = size(observation, 1);
dataLength = size(observation, 2);
centre = cfg.channelLength;
posterior = zeros(userCount, dataLength);
prior = zeros(userCount, dataLength);
innerErrors = zeros(cfg.innerIterations, 1);
outerErrors = zeros(cfg.outerIterations, 1);
innerMse = zeros(cfg.innerIterations, 1);
outerMse = zeros(cfg.outerIterations, 1);
lastEseLlr = zeros(userCount, dataLength);
lastVariance = zeros(userCount, dataLength);

for outer = 1:cfg.outerIterations
    for inner = 1:cfg.innerIterations
        meanValue = tanh(posterior / 2);
        varianceValue = max(0, 1 - meanValue.^2);
        updated = zeros(userCount, dataLength);
        eseLlr = zeros(userCount, dataLength);
        eseVariance = zeros(userCount, dataLength);
        for target = 1:userCount
            expected = zeros(1, dataLength);
            totalVariance = noiseVariance(target) * ones(1, dataLength);
            for source = 1:userCount
                channel = equivalent{target, source};
                expected = expected + centered_filter(meanValue(source, :), channel, centre);
                totalVariance = totalVariance + centered_filter( ...
                    varianceValue(source, :), abs(channel).^2, centre);
            end
            desiredChannel = equivalent{target, target};
            desiredGain = desiredChannel(centre);
            residual = observation(target, :) - ...
                (expected - desiredGain * meanValue(target, :));
            residualVariance = totalVariance - ...
                abs(desiredGain)^2 * varianceValue(target, :);
            residualVariance = max(real(residualVariance), 1e-9);
            eseLlr(target, :) = 2 * real(conj(desiredGain) * residual) ./ residualVariance;
            eseVariance(target, :) = residualVariance;
            updated(target, :) = prior(target, :) + eseLlr(target, :);
        end
        posterior = (1 - cfg.eseDamping) * posterior + cfg.eseDamping * updated;
        decision = decode_frame(posterior, permutations, codebook, bitTable, false);
        innerErrors(inner) = bit_error_count(decision.indices, truth, bitTable);
        innerMse(inner) = mean(abs(tanh(posterior(:) / 2) - transmitted(:)).^2);
        lastEseLlr = eseLlr;
        lastVariance = eseVariance;
    end
    decoded = decode_frame(posterior, permutations, codebook, bitTable, true);
    outerErrors(outer) = bit_error_count(decoded.indices, truth, bitTable);
    outerMse(outer) = mean(abs(tanh(posterior(:) / 2) - transmitted(:)).^2);
    prior = decoded.interleavedExtrinsic;
    posterior = prior;
end

output.innerErrors = innerErrors;
output.outerErrors = outerErrors;
output.innerMse = innerMse;
output.outerMse = outerMse;
output.finalIndices = decoded.indices;
output.finalPosteriorLlr = posterior;
output.eseLlr = lastEseLlr;
output.eseVariance = lastVariance;
end

function decoded = decode_frame(interleavedLlr, permutations, codebook, bitTable, includeExtrinsic)
userCount = size(interleavedLlr, 1);
chipCount = size(codebook, 2);
symbolCount = size(interleavedLlr, 2) / chipCount;
decoded.indices = zeros(symbolCount, userCount);
decoded.interleavedExtrinsic = zeros(size(interleavedLlr));
for user = 1:userCount
    originalLlr = interleavedLlr(user, permutations{user});
    extrinsic = zeros(1, numel(originalLlr));
    for symbol = 1:symbolCount
        range = (symbol - 1) * chipCount + (1:chipCount);
        symbolResult = csk_soft_map(originalLlr(range), codebook);
        decoded.indices(symbol, user) = symbolResult.index;
        if includeExtrinsic
            extrinsic(range) = symbolResult.extrinsic;
        end
    end
    if includeExtrinsic
        decoded.interleavedExtrinsic(user, permutations{user}) = extrinsic;
    end
end
decoded.bitTable = bitTable;
end

function output = csk_soft_map(inputLlr, codebook)
metric = 0.5 * codebook * inputLlr(:);
[~, output.index] = max(metric);
output.posterior = exp(metric - max(metric));
output.posterior = output.posterior / sum(output.posterior);
output.extrinsic = zeros(1, numel(inputLlr));
for chip = 1:numel(inputLlr)
    excluded = metric - 0.5 * codebook(:, chip) * inputLlr(chip);
    output.extrinsic(chip) = logsumexp(excluded(codebook(:, chip) > 0)) - ...
        logsumexp(excluded(codebook(:, chip) < 0));
end
end

function output = centered_filter(input, channel, centre)
full = conv(input, channel);
output = full(centre:centre + numel(input) - 1);
end

function samples = extract_samples(input, startIndex, count)
samples = complex(zeros(1, count));
available = startIndex:min(numel(input), startIndex + count - 1);
if ~isempty(available) && startIndex >= 1
    samples(1:numel(available)) = input(available);
end
end

function [book, bits] = csk_codebook(root, alphabetSize)
bits = bit_table(alphabetSize);
book = zeros(alphabetSize, numel(root));
for index = 0:alphabetSize - 1
    book(index + 1, :) = circshift(root, index);
end
end

function [book, bits] = dsss_codebook(chipCount, alphabetSize, bits)
book = zeros(alphabetSize, chipCount);
for index = 1:alphabetSize
    source = 1 - 2 * bits(index, :);
    book(index, :) = source(mod(0:chipCount - 1, numel(source)) + 1);
end
end

function bits = bit_table(alphabetSize)
bitCount = round(log2(alphabetSize));
bits = zeros(alphabetSize, bitCount);
for index = 0:alphabetSize - 1
    bits(index + 1, :) = bitget(index, 1:bitCount);
end
end

function root = paper_pn_root(lengthValue, shift)
if nargin < 2
    shift = 1;
end
state = ones(1, 8);
sequence = zeros(1, 255);
for index = 1:255
    sequence(index) = state(end);
    feedback = mod(state(8) + state(6) + state(5) + state(4), 2);
    state = [feedback, state(1:end - 1)];
end
sequence = 1 - 2 * sequence;
root = sequence(mod((0:lengthValue - 1) + 17 * shift, numel(sequence)) + 1);
end

function sequence = synchronization_sequence(lengthValue)
index = 0:lengthValue - 1;
root = 5;
if mod(lengthValue, 2) == 0
    sequence = exp(-1j * pi * root * index.^2 / lengthValue);
else
    sequence = exp(-1j * pi * root * index .* (index + 1) / lengthValue);
end
end

function errorCount = bit_error_count(decision, truth, bitTable)
errorCount = sum(bitTable(decision(:), :) ~= bitTable(truth(:), :), "all");
end

function value = logsumexp(input)
maximum = max(input);
value = maximum + log(sum(exp(input - maximum)));
end

function paths = plot_iterations(results, cfg)
path = output_path(cfg, "chapter6_paper_full_idma_iterations.png");
figure("Color", "w", "Position", [70, 70, 1400, 820], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for index = 1:size(results.idma.innerBer, 1)
    semilogy(results.idma.snrDb, max(results.idma.innerBer(index, :), 1e-7), "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-12(a) ESE 内迭代次数的影响");
legend("内迭代" + string(1:size(results.idma.innerBer, 1)) + "次", "Location", "southwest");
nexttile; hold on;
for index = 1:size(results.idma.outerBer, 1)
    semilogy(results.idma.snrDb, max(results.idma.outerBer(index, :), 1e-7), "s-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-12(b) CSK 软 MAP 外迭代次数的影响");
legend("外迭代" + string(1:size(results.idma.outerBer, 1)) + "次", "Location", "southwest");
nexttile; hold on;
for index = 1:size(results.idma.innerMse, 1)
    plot(results.idma.snrDb, results.idma.innerMse(index, :), "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("码片软估计 MSE");
title("图6-13(a) ESE 内迭代软估计误差");
nexttile; hold on;
for index = 1:size(results.idma.outerMse, 1)
    plot(results.idma.snrDb, results.idma.outerMse(index, :), "s-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("码片软估计 MSE");
title("图6-13(b) 外译码反馈后的软估计误差");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180); close(gcf);
paths = string(path);
end

function paths = plot_synchronization(results, cfg)
frame = results.idma.diagnostic;
path = output_path(cfg, "chapter6_paper_full_sync_channel.png");
figure("Color", "w", "Position", [80, 80, 1400, 810], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile;
plot(abs(frame.sync.correlation), "LineWidth", 1.0); grid on;
xlabel("候选帧起点"); ylabel("相关幅度"); title("帧同步：前导 Zadoff-Chu 匹配相关");
nexttile;
stem(0:numel(frame.trueChannels(1, :)) - 1, abs(frame.trueChannels(1, :)), "filled"); hold on;
stem(0:numel(frame.estimatedChannels(1, :)) - 1, abs(frame.estimatedChannels(1, :)), "LineWidth", 1.0);
grid on; xlabel("码片时延"); ylabel("幅度"); title("用户1：真实与训练估计信道");
legend("真实", "估计", "Location", "northeast");
nexttile;
plot(frame.detector.eseLlr(1, 1:min(512, size(frame.detector.eseLlr, 2))), "LineWidth", 0.9); grid on;
xlabel("交织码片索引"); ylabel("ESE 外信息 LLR"); title("PTR-ESE 输出（用户1）");
nexttile;
sampleCount = min(512, numel(frame.sync.aligned));
plot(0:sampleCount - 1, real(frame.sync.aligned(1:sampleCount)), "LineWidth", 0.8); hold on;
plot(0:sampleCount - 1, imag(frame.sync.aligned(1:sampleCount)), "LineWidth", 0.8); grid on;
xlabel("同步后码片索引"); ylabel("复基带幅度"); title("重复 UW 频偏补偿后的接收信号");
legend("实部", "虚部", "Location", "northeast");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180); close(gcf);
paths = string(path);
end

function paths = plot_loading_comparison(results, cfg)
path = output_path(cfg, "chapter6_paper_full_loading_comparison.png");
figure("Color", "w", "Position", [90, 90, 1320, 540], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
if ~isempty(results.idma.loadingBer)
    for index = 1:numel(results.idma.idmaUserCounts)
        semilogy(results.idma.snrDb, max(results.idma.loadingBer(index, :), 1e-7), "o-", "LineWidth", 1.2);
    end
    legend(string(results.idma.idmaUserCounts) + "个用户", "Location", "southwest");
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER"); title("图6-14 不同用户数的 CSK-IDMA 性能");
nexttile; hold on;
if ~isempty(results.idma.comparisonBer)
    labels = strings(2 * numel(results.idma.comparisonUserCounts), 1);
    for index = 1:numel(results.idma.comparisonUserCounts)
        semilogy(results.idma.snrDb, max(squeeze(results.idma.comparisonBer(1, index, :)).', 1e-7), "--o", "LineWidth", 1.1);
        semilogy(results.idma.snrDb, max(squeeze(results.idma.comparisonBer(2, index, :)).', 1e-7), "-s", "LineWidth", 1.2);
        labels(2 * index - 1) = "DSSS-IDMA, " + string(results.idma.comparisonUserCounts(index)) + "用户";
        labels(2 * index) = "CSK-IDMA, " + string(results.idma.comparisonUserCounts(index)) + "用户";
    end
    legend(labels, "Location", "southwest");
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER"); title("图6-15 DSSS-IDMA 与 CSK-IDMA 对比");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180); close(gcf);
paths = string(path);
end

function paths = export_data(results, cfg)
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
matPath = fullfile(cfg.outputDir, "chapter6_paper_full_chain.mat");
save(matPath, "results", "-v7");
rows = [ ...
    result_rows("CSK-IDMA 内迭代", "内迭代", results.idma.snrDb, results.idma.innerBer); ...
    result_rows("CSK-IDMA 外迭代", "外迭代", results.idma.snrDb, results.idma.outerBer)];
if ~isempty(results.idma.loadingBer)
    rows = [rows; result_rows("CSK-IDMA 用户负载", ...
        string(results.idma.idmaUserCounts(:)) + "用户", results.idma.snrDb, results.idma.loadingBer)];
end
csvPath = fullfile(cfg.outputDir, "chapter6_paper_full_chain_ber.csv");
writetable(rows, csvPath, 'Encoding', 'UTF-8');
paths = [string(matPath); string(csvPath)];
end

function output = result_rows(group, names, snrDb, values)
names = string(names(:));
if isscalar(names) && size(values, 1) > 1
    names = names + string((1:size(values, 1)).');
end
assert(numel(names) == size(values, 1), "SCFDE:InvalidExport", ...
    "Each BER curve must have one export label.");
snr = repmat(snrDb(:).', size(values, 1), 1);
labels = repmat(names, 1, numel(snrDb));
output = table(repmat(string(group), numel(values), 1), labels(:), snr(:), values(:), ...
    'VariableNames', {'组别', '曲线', 'EbN0_dB', 'BER'});
end

function path = output_path(cfg, filename)
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
path = fullfile(cfg.outputDir, filename);
end

function validate_config(cfg)
assert(cfg.symbolsPerFrame > 0 && cfg.codeLength > 0, "SCFDE:InvalidFrame", ...
    "symbolsPerFrame and codeLength must be positive.");
assert(cfg.cskOrder <= cfg.codeLength && 2^round(log2(cfg.cskOrder)) == cfg.cskOrder, ...
    "SCFDE:InvalidCskOrder", "cskOrder must be a power of two no larger than codeLength.");
assert(cfg.trainingLength >= cfg.channelLength, "SCFDE:InvalidTraining", ...
    "trainingLength must cover the channel length.");
assert(cfg.pathCount >= 2 && cfg.delaySpreadChips < cfg.channelLength, ...
    "SCFDE:InvalidChannel", "Channel delays must fit inside channelLength.");
assert(cfg.syncSearchSpan > 0 && cfg.syncAmplitude > 0 && cfg.trainingAmplitude > 0, ...
    "SCFDE:InvalidSynchronization", ...
    "syncSearchSpan, syncAmplitude and trainingAmplitude must be positive.");
assert(cfg.syncRepeatCount >= 2 && mod(cfg.syncRepeatCount, 1) == 0, ...
    "SCFDE:InvalidSynchronization", "syncRepeatCount must be an integer of at least two.");
assert(cfg.innerIterations > 0 && cfg.outerIterations > 0, ...
    "SCFDE:InvalidIterations", "Iteration counts must be positive.");
assert(any(strcmpi(string(cfg.channelEstimator), ["LS", "MMSE"])), ...
    "SCFDE:InvalidEstimator", "channelEstimator must be LS or MMSE.");
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
