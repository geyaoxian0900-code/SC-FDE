function results = run_chapter6_spread_spectrum_suite(options, simulationDir)
%RUN_CHAPTER6_SPREAD_SPECTRUM_SUITE Modular Chapter 6 CSK spread-spectrum studies.

defaults.snrDb = -6:2:10;
defaults.frameCount = 2;
defaults.symbolsPerFrame = 32;
defaults.codeLength = 32;
defaults.modulationOrders = [2, 4, 8, 16];
defaults.cskOrder = 16;
defaults.conventionalUsers = 4;
defaults.multiUserCounts = [2, 4, 6];
defaults.idmaUsers = 8;
defaults.idmaUserCounts = [8, 12, 16];
defaults.comparisonUserCounts = [8, 10];
defaults.innerIterations = 3;
defaults.outerIterations = 3;
defaults.diagnosticSnrDb = 2;
defaults.randomSeed = 20260729;
defaults.measuredChannelFile = "";
defaults.cskRootFamily = "m-sequence";
defaults.enablePtr = true;
defaults.eseDamping = 0.58;
defaults.groups = "all";
defaults.sequenceFamilies = "all";
defaults.sequenceLength = 63;
defaults.sequenceCodeCount = 8;
defaults.sequenceUsers = 4;
defaults.sequenceFrameCount = 20;
defaults.sequenceSymbolsPerFrame = 64;
defaults.makePlot = true;
defaults.exportData = true;
defaults.outputDir = fullfile(simulationDir, "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

groupNames = ["principles", "conventional", "idma"];
groupIndices = select_names(groupNames, cfg.groups, "Chapter 6 experiment group");
rng(cfg.randomSeed, "twister");
[channel, channelInfo] = load_channel(cfg.measuredChannelFile, cfg.codeLength);
root = csk_root_sequence(cfg.codeLength, cfg.cskRootFamily);
[cskBook, cskBits] = csk_codebook(root, cfg.cskOrder);

results.config = cfg;
results.availableGroups = groupNames;
results.groupNames = groupNames(groupIndices);
results.channel = channel;
results.channelInfo = channelInfo;
results.rootSequence = root;
results.cskBook = cskBook;
results.cskBits = cskBits;
results.formulaCoverage = ["(6-1) PN/m序列与直接扩频", ...
    "(6-4)-(6-12) CSK循环移位与相关捕获", ...
    "(6-13)-(6-18) 多用户CSK-CDMA多径叠加和匹配滤波", ...
    "(6-21)-(6-35) ESE均值、方差与软PIC", ...
    "(6-37)-(6-40) 用户特定PTR预处理", ...
    "(6-45)-(6-64) CSK-IDMA外信息与重复码迭代"];
results.figurePaths = strings(0, 1);
results.dataPaths = strings(0, 1);
results.outputPath = "";

if any(groupNames(groupIndices) == "principles")
    results.principles = run_principles(cfg, root, cskBook, cskBits);
end
if any(groupNames(groupIndices) == "conventional")
    results.conventional = run_conventional(cfg, channel, root);
end
if any(groupNames(groupIndices) == "idma")
    results.idma = run_idma(cfg, channel, root);
end

if cfg.makePlot
    if isfield(results, "principles")
        results.figurePaths(end + 1, 1) = plot_principles(results, cfg);
        results.figurePaths(end + 1, 1) = plot_sequence_families(results, cfg);
    end
    if isfield(results, "conventional")
        results.figurePaths(end + 1, 1) = plot_conventional(results, cfg);
    end
    if isfield(results, "idma")
        paths = plot_idma(results, cfg);
        results.figurePaths = [results.figurePaths; paths];
        results.figurePaths(end + 1, 1) = plot_idma_ptr_trace(results, cfg);
    end
    if ~isempty(results.figurePaths)
        results.outputPath = results.figurePaths(1);
    end
end
if cfg.exportData
    results.dataPaths = export_result_data(results, cfg);
end
end

function output = run_principles(cfg, root, cskBook, cskBits)
orthBook = orthogonal_codebook(cfg.cskOrder, cfg.codeLength);
methodNames = ["DS-BPSK", "M 元正交扩频", "CSK"];
ber = zeros(numel(methodNames), numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    errors = zeros(numel(methodNames), 1);
    totals = zeros(numel(methodNames), 1);
    for frame = 1:cfg.frameCount
        [frameErrors, frameTotal] = awgn_bpsk(root, cfg.symbolsPerFrame, ...
            cfg.snrDb(snrIndex));
        errors(1) = errors(1) + frameErrors;
        totals(1) = totals(1) + frameTotal;
        [frameErrors, frameTotal] = awgn_codebook(orthBook, cskBits, ...
            cfg.symbolsPerFrame, cfg.snrDb(snrIndex));
        errors(2) = errors(2) + frameErrors;
        totals(2) = totals(2) + frameTotal;
        [frameErrors, frameTotal] = awgn_codebook(cskBook, cskBits, ...
            cfg.symbolsPerFrame, cfg.snrDb(snrIndex));
        errors(3) = errors(3) + frameErrors;
        totals(3) = totals(3) + frameTotal;
    end
    ber(:, snrIndex) = errors ./ totals;
end

correlation = abs(cskBook * cskBook');
correlation(1:size(correlation, 1) + 1:end) = 0;
acquisitionShift = mod(round(0.41 * cfg.codeLength), cfg.codeLength);
noiseVariance = 1 / (log2(cfg.cskOrder) * 10^(cfg.diagnosticSnrDb / 10));
received = circshift(root, acquisitionShift) + sqrt(noiseVariance / 2) * ...
    (randn(size(root)) + 1j * randn(size(root)));
acquisition = abs(ifft(fft(received) .* conj(fft(root))));

hopLength = 24;
hopping = zeros(3, hopLength);
for user = 1:size(hopping, 1)
    hopping(user, :) = mod((0:hopLength - 1) * (2 * user + 1) + ...
        user^2, cfg.codeLength) + 1;
end
output.methodNames = methodNames;
output.ber = ber;
output.snrDb = cfg.snrDb;
output.crossCorrelation = correlation;
output.acquisition = acquisition / max(acquisition);
output.acquisitionShift = acquisitionShift;
output.hopping = hopping;
output.sequenceStudy = run_sequence_study(cfg);
end

function output = run_conventional(cfg, channel, root)
orders = cfg.modulationOrders(:).';
mfBer = zeros(numel(orders), numel(cfg.snrDb));
picBer = zeros(numel(orders), numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    mfErrors = zeros(numel(orders), 1);
    picErrors = zeros(numel(orders), 1);
    totals = zeros(numel(orders), 1);
    for frame = 1:cfg.frameCount
        for orderIndex = 1:numel(orders)
            [book, bits] = csk_codebook(root, orders(orderIndex));
            frameResult = csk_multiuser_frame(book, bits, channel, ...
                cfg.conventionalUsers, cfg.symbolsPerFrame, cfg.snrDb(snrIndex), ...
                cfg.innerIterations);
            mfErrors(orderIndex) = mfErrors(orderIndex) + frameResult.mfErrors;
            picErrors(orderIndex) = picErrors(orderIndex) + frameResult.picErrors(end);
            totals(orderIndex) = totals(orderIndex) + frameResult.totalBits;
        end
    end
    mfBer(:, snrIndex) = mfErrors ./ totals;
    picBer(:, snrIndex) = picErrors ./ totals;
end

[book, bits] = csk_codebook(root, cfg.cskOrder);
loadMfBer = zeros(numel(cfg.multiUserCounts), numel(cfg.snrDb));
loadPicBer = zeros(numel(cfg.multiUserCounts), numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    mfErrors = zeros(numel(cfg.multiUserCounts), 1);
    picErrors = zeros(numel(cfg.multiUserCounts), 1);
    totals = zeros(numel(cfg.multiUserCounts), 1);
    for frame = 1:cfg.frameCount
        for loadIndex = 1:numel(cfg.multiUserCounts)
            frameResult = csk_multiuser_frame(book, bits, channel, ...
                cfg.multiUserCounts(loadIndex), cfg.symbolsPerFrame, ...
                cfg.snrDb(snrIndex), cfg.innerIterations);
            mfErrors(loadIndex) = mfErrors(loadIndex) + frameResult.mfErrors;
            picErrors(loadIndex) = picErrors(loadIndex) + frameResult.picErrors(end);
            totals(loadIndex) = totals(loadIndex) + frameResult.totalBits;
        end
    end
    loadMfBer(:, snrIndex) = mfErrors ./ totals;
    loadPicBer(:, snrIndex) = picErrors ./ totals;
end

diagnostic = csk_multiuser_frame(book, bits, channel, cfg.conventionalUsers, ...
    cfg.symbolsPerFrame, cfg.diagnosticSnrDb, cfg.innerIterations);
output.orders = orders;
output.mfBer = mfBer;
output.picBer = picBer;
output.loadMfBer = loadMfBer;
output.loadPicBer = loadPicBer;
output.userCounts = cfg.multiUserCounts;
output.userChannels = diagnostic.userChannels;
output.diagnostic = diagnostic;
output.snrDb = cfg.snrDb;
end

function output = run_idma(cfg, channel, root)
[cskBook, bits] = csk_codebook(root, cfg.cskOrder);
dsssBook = dsss_symbol_codebook(cfg.cskOrder, cfg.codeLength);
innerErrors = zeros(cfg.innerIterations, numel(cfg.snrDb));
outerErrors = zeros(cfg.outerIterations, numel(cfg.snrDb));
innerMse = zeros(cfg.innerIterations, numel(cfg.snrDb));
outerMse = zeros(cfg.outerIterations, numel(cfg.snrDb));
totals = zeros(1, numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    for frame = 1:cfg.frameCount
        frameResult = csk_idma_frame(cskBook, bits, channel, cfg.idmaUsers, ...
            cfg.symbolsPerFrame, cfg.snrDb(snrIndex), cfg.innerIterations, ...
            cfg.outerIterations, cfg.enablePtr, cfg.eseDamping);
        innerErrors(:, snrIndex) = innerErrors(:, snrIndex) + ...
            frameResult.innerErrors(:);
        outerErrors(:, snrIndex) = outerErrors(:, snrIndex) + ...
            frameResult.outerErrors(:);
        innerMse(:, snrIndex) = innerMse(:, snrIndex) + frameResult.innerMse(:);
        outerMse(:, snrIndex) = outerMse(:, snrIndex) + frameResult.outerMse(:);
        totals(snrIndex) = totals(snrIndex) + frameResult.totalBits;
    end
end
innerBer = innerErrors ./ totals;
outerBer = outerErrors ./ totals;
innerMse = innerMse / cfg.frameCount;
outerMse = outerMse / cfg.frameCount;

loadingBer = zeros(numel(cfg.idmaUserCounts), numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    loadingErrors = zeros(numel(cfg.idmaUserCounts), 1);
    loadingTotals = zeros(numel(cfg.idmaUserCounts), 1);
    for frame = 1:cfg.frameCount
        for loadIndex = 1:numel(cfg.idmaUserCounts)
            frameResult = csk_idma_frame(cskBook, bits, channel, ...
                cfg.idmaUserCounts(loadIndex), cfg.symbolsPerFrame, ...
                cfg.snrDb(snrIndex), cfg.innerIterations, cfg.outerIterations, ...
                cfg.enablePtr, cfg.eseDamping);
            loadingErrors(loadIndex) = loadingErrors(loadIndex) + ...
                frameResult.outerErrors(end);
            loadingTotals(loadIndex) = loadingTotals(loadIndex) + ...
                frameResult.totalBits;
        end
    end
    loadingBer(:, snrIndex) = loadingErrors ./ loadingTotals;
end

comparisonBer = zeros(2, numel(cfg.comparisonUserCounts), numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    comparisonErrors = zeros(2, numel(cfg.comparisonUserCounts));
    comparisonTotals = zeros(1, numel(cfg.comparisonUserCounts));
    for frame = 1:cfg.frameCount
        for userIndex = 1:numel(cfg.comparisonUserCounts)
            users = cfg.comparisonUserCounts(userIndex);
            dsssResult = csk_idma_frame(dsssBook, bits, channel, users, ...
                cfg.symbolsPerFrame, cfg.snrDb(snrIndex), cfg.innerIterations, ...
                cfg.outerIterations, cfg.enablePtr, cfg.eseDamping);
            cskResult = csk_idma_frame(cskBook, bits, channel, users, ...
                cfg.symbolsPerFrame, cfg.snrDb(snrIndex), cfg.innerIterations, ...
                cfg.outerIterations, cfg.enablePtr, cfg.eseDamping);
            comparisonErrors(1, userIndex) = comparisonErrors(1, userIndex) + ...
                dsssResult.outerErrors(end);
            comparisonErrors(2, userIndex) = comparisonErrors(2, userIndex) + ...
                cskResult.outerErrors(end);
            comparisonTotals(userIndex) = comparisonTotals(userIndex) + ...
                cskResult.totalBits;
        end
    end
    comparisonBer(:, :, snrIndex) = comparisonErrors ./ comparisonTotals;
end

diagnostic = csk_idma_frame(cskBook, bits, channel, cfg.idmaUsers, ...
    cfg.symbolsPerFrame, cfg.diagnosticSnrDb, cfg.innerIterations, ...
    cfg.outerIterations, cfg.enablePtr, cfg.eseDamping);
output.innerBer = innerBer;
output.outerBer = outerBer;
output.innerMse = innerMse;
output.outerMse = outerMse;
output.loadingBer = loadingBer;
output.comparisonBer = comparisonBer;
output.idmaUserCounts = cfg.idmaUserCounts;
output.comparisonUserCounts = cfg.comparisonUserCounts;
output.snrDb = cfg.snrDb;
output.diagnostic = diagnostic;
output.ptrTrace = diagnostic.ptrTrace;
end

function frame = csk_multiuser_frame(book, bits, channel, users, symbols, snrDb, iterations)
dicts = conventional_dictionaries(book, channel, users);
[received, indices, transmitted, noiseVariance] = multiuser_observation( ...
    dicts, symbols, snrDb, size(bits, 2));
[mfDecision, ~] = matched_filter_detect(received, dicts);
[picDecision, picMse] = soft_sic_detect(received, dicts, noiseVariance, ...
    iterations, transmitted, []);
frame.mfErrors = bit_errors(mfDecision, indices, bits);
frame.picErrors = zeros(iterations, 1);
for iteration = 1:iterations
    frame.picErrors(iteration) = bit_errors(picDecision(iteration, :, :), ...
        indices, bits);
end
frame.picMse = picMse;
frame.totalBits = numel(bits(indices, :));
frame.userChannels = dictionary_channels(channel, users, size(book, 2));
end

function frame = csk_idma_frame(book, bits, channel, users, symbols, snrDb, ...
        innerIterations, outerIterations, enablePtr, eseDamping)
if nargin < 9
    enablePtr = true;
end
if nargin < 10
    eseDamping = 0.58;
end
assert(mod(symbols, 2) == 0, "SCFDE:InvalidIdmaSymbols", ...
    "symbolsPerFrame must be even for the repetition outer code.");
[dicts, userChannels] = idma_dictionaries(book, channel, users);
pair = repeated_symbol_indices(size(book, 1), symbols, users);
[received, indices, transmitted, noiseVariance] = multiuser_observation( ...
    dicts, symbols, snrDb, size(bits, 2), pair.indices);
[innerDecision, outerDecision, innerMse, outerMse, directDecision, ptrTrace] = ...
    csk_idma_detect(received, dicts, userChannels, noiseVariance, pair, ...
    innerIterations, outerIterations, transmitted, enablePtr, eseDamping);
frame.innerErrors = zeros(innerIterations, 1);
for iteration = 1:innerIterations
    frame.innerErrors(iteration) = bit_errors(innerDecision(iteration, :, :), ...
        pair.information, bits);
end
frame.outerErrors = zeros(outerIterations, 1);
for iteration = 1:outerIterations
    frame.outerErrors(iteration) = bit_errors(outerDecision(iteration, :, :), ...
        pair.information, bits);
end
frame.innerMse = innerMse;
frame.outerMse = outerMse;
frame.totalBits = numel(bits(pair.information, :));
frame.indices = indices;
frame.information = pair.information;
frame.innerDecision = innerDecision;
frame.outerDecision = outerDecision;
frame.secondPosition = pair.secondPosition;
frame.directDecision = directDecision;
frame.ptrTrace = ptrTrace;
frame.received = received;
frame.userChannels = userChannels;
end

function [received, indices, transmitted, noiseVariance] = multiuser_observation( ...
        dicts, symbols, snrDb, bitsPerSymbol, requestedIndices)
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(dicts{1}, 2);
if nargin < 5 || isempty(requestedIndices)
    indices = randi(M, symbols, users);
else
    indices = requestedIndices;
end
transmitted = complex(zeros(users, symbols, lengthCode));
received = complex(zeros(symbols, lengthCode));
for user = 1:users
    for symbol = 1:symbols
        transmitted(user, symbol, :) = dicts{user}(indices(symbol, user), :);
        received(symbol, :) = received(symbol, :) + dicts{user}(indices(symbol, user), :);
    end
end
noiseVariance = 1 / (bitsPerSymbol * 10^(snrDb / 10));
received = received + sqrt(noiseVariance / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
end

function [decision, expected] = matched_filter_detect(received, dicts)
symbols = size(received, 1);
users = numel(dicts);
decision = zeros(symbols, users);
expected = complex(zeros(users, symbols, size(received, 2)));
for symbol = 1:symbols
    for user = 1:users
        [decision(symbol, user), expected(user, symbol, :)] = ...
            hard_dictionary_detect(received(symbol, :), dicts{user});
    end
end
end

function [decisionHistory, mseHistory] = soft_sic_detect( ...
        received, dicts, noiseVariance, iterations, transmitted, logPriors)
symbols = size(received, 1);
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(received, 2);
if isempty(logPriors)
    logPriors = zeros(symbols, M, users);
end
soft = complex(zeros(users, symbols, lengthCode));
decisionHistory = zeros(iterations, symbols, users);
mseHistory = zeros(iterations, 1);
for iteration = 1:iterations
    updated = soft;
    for symbol = 1:symbols
        for user = 1:users
            otherUsers = [1:user - 1, user + 1:users];
            interference = reshape(sum(soft(otherUsers, symbol, :), 1), 1, []);
            residual = received(symbol, :) - interference;
            interferenceVariance = noiseVariance * ones(1, lengthCode);
            for source = otherUsers
                sourceEnergy = mean(abs(dicts{source}).^2, 1);
                sourceMean = reshape(soft(source, symbol, :), 1, []);
                interferenceVariance = interferenceVariance + ...
                    max(0, sourceEnergy - abs(sourceMean).^2);
            end
            [decision, expected] = soft_dictionary_detect(residual, dicts{user}, ...
                interferenceVariance, reshape(logPriors(symbol, :, user), 1, []));
            decisionHistory(iteration, symbol, user) = decision;
            updated(user, symbol, :) = expected;
        end
    end
    soft = 0.45 * soft + 0.55 * updated;
    mseHistory(iteration) = mean(abs(soft(:) - transmitted(:)).^2);
end
end

function [innerDecision, outerDecision, innerMse, outerMse, directDecision, trace] = ...
        csk_idma_detect(received, dicts, userChannels, noiseVariance, pair, ...
        innerIterations, outerIterations, transmitted, enablePtr, damping)
% Equation (6-21) is evaluated in the PTR domain.  The ESE computes the
% codeword mean and chip-wise variance in (6-22)-(6-31), then transfers the
% resulting symbol likelihood to the interleaved repetition decoder.
symbols = size(received, 1);
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(received, 2);
context = ptr_context(received, dicts, userChannels, noiseVariance, enablePtr);
posterior = ones(symbols, M, users) / M;
logPrior = zeros(symbols, M, users);
innerDecision = zeros(innerIterations, size(pair.information, 1), users);
outerDecision = zeros(outerIterations, size(pair.information, 1), users);
innerMse = zeros(innerIterations, 1);
outerMse = zeros(outerIterations, 1);
directDecision = zeros(symbols, users);
lastVariance = noiseVariance * ones(1, lengthCode);
for outer = 1:outerIterations
    likelihood = zeros(symbols, M, users);
    for inner = 1:innerIterations
        updatedPosterior = posterior;
        for symbol = 1:symbols
            for user = 1:users
                [residual, interferenceVariance] = ese_residual(symbol, user, ...
                    posterior, context);
                [directDecision(symbol, user), ~, metric, probability] = ...
                    soft_dictionary_detect(residual, context.dictionaries{user, user}, ...
                    interferenceVariance, reshape(logPrior(symbol, :, user), 1, []));
                likelihood(symbol, :, user) = metric;
                updatedPosterior(symbol, :, user) = probability;
                if symbol == 1 && user == 1
                    lastVariance = interferenceVariance;
                end
            end
        end
        posterior = (1 - damping) * posterior + damping * updatedPosterior;
        decoded = repeated_symbol_decode(likelihood, pair);
        if outer == 1
            innerDecision(inner, :, :) = decoded;
            soft = posterior_signal_estimate(posterior, dicts);
            innerMse(inner) = mean(abs(soft(:) - transmitted(:)).^2);
        end
    end
    decoded = repeated_symbol_decode(likelihood, pair);
    outerDecision(outer, :, :) = decoded;
    soft = posterior_signal_estimate(posterior, dicts);
    outerMse(outer) = mean(abs(soft(:) - transmitted(:)).^2);
    logPrior = repeated_symbol_priors(likelihood, pair);
end
trace.ptrEnabled = enablePtr;
trace.ptrReceivedUser1 = context.observation(:, :, 1);
trace.ptrEquivalentChannelUser1 = context.equivalentChannels(1, :);
trace.effectiveNoiseVariance = context.noiseVariances;
trace.eseVarianceUser1Symbol1 = lastVariance;
trace.finalPosteriorUser1 = squeeze(posterior(:, :, 1));
end

function context = ptr_context(received, dictionaries, userChannels, noiseVariance, enablePtr)
symbols = size(received, 1);
lengthCode = size(received, 2);
users = numel(dictionaries);
context.observation = complex(zeros(symbols, lengthCode, users));
context.dictionaries = cell(users, users);
context.noiseVariances = zeros(1, users);
context.equivalentChannels = complex(zeros(users, lengthCode));
receivedSpectrum = fft(received, [], 2);
for target = 1:users
    if enablePtr
        channelSpectrum = fft(userChannels(target, :), lengthCode);
        gain = max(sum(abs(userChannels(target, :)).^2), eps);
        matchedSpectrum = conj(channelSpectrum) / gain;
        context.observation(:, :, target) = ifft(receivedSpectrum .* ...
            repmat(matchedSpectrum, symbols, 1), [], 2);
        context.noiseVariances(target) = noiseVariance / gain;
        context.equivalentChannels(target, :) = ifft(abs(channelSpectrum).^2 / gain);
        for source = 1:users
            context.dictionaries{target, source} = ifft( ...
                fft(dictionaries{source}, [], 2) .* ...
                repmat(matchedSpectrum, size(dictionaries{source}, 1), 1), [], 2);
        end
    else
        context.observation(:, :, target) = received;
        context.noiseVariances(target) = noiseVariance;
        context.equivalentChannels(target, 1) = 1;
        for source = 1:users
            context.dictionaries{target, source} = dictionaries{source};
        end
    end
end
end

function [residual, variance] = ese_residual(symbol, target, posterior, context)
users = size(posterior, 3);
lengthCode = size(context.observation, 2);
residual = context.observation(symbol, :, target);
variance = context.noiseVariances(target) * ones(1, lengthCode);
for source = 1:users
    if source == target
        continue;
    end
    probability = reshape(posterior(symbol, :, source), 1, []);
    dictionary = context.dictionaries{target, source};
    meanWord = probability * dictionary;
    secondMoment = probability * abs(dictionary).^2;
    residual = residual - meanWord;
    variance = variance + max(0, secondMoment - abs(meanWord).^2);
end
end

function soft = posterior_signal_estimate(posterior, dictionaries)
symbols = size(posterior, 1);
users = size(posterior, 3);
lengthCode = size(dictionaries{1}, 2);
soft = complex(zeros(users, symbols, lengthCode));
for user = 1:users
    for symbol = 1:symbols
        probability = reshape(posterior(symbol, :, user), 1, []);
        soft(user, symbol, :) = probability * dictionaries{user};
    end
end
end

function [decision, expected, metric, posterior] = soft_dictionary_detect( ...
        observation, dictionary, variance, logPrior)
if isscalar(variance)
    variance = repmat(variance, 1, size(dictionary, 2));
end
variance = max(real(variance(:).'), 1e-10);
distance = sum(abs(dictionary - observation).^2 ./ variance, 2);
metric = -distance + logPrior(:);
metric = normalize_log(metric);
[~, decision] = max(metric);
posterior = exp(metric);
posterior = posterior / sum(posterior);
expected = posterior.' * dictionary;
end

function [decision, expected] = hard_dictionary_detect(observation, dictionary)
distance = sum(abs(dictionary - observation).^2, 2);
[~, decision] = min(distance);
expected = dictionary(decision, :);
end

function pair = repeated_symbol_indices(M, symbols, users)
informationSymbols = symbols / 2;
pair.information = randi(M, informationSymbols, users);
pair.indices = zeros(symbols, users);
pair.secondPosition = zeros(informationSymbols, users);
pair.indices(1:informationSymbols, :) = pair.information;
for user = 1:users
    interleaver = randperm(informationSymbols);
    pair.indices(informationSymbols + 1:end, user) = ...
        pair.information(interleaver, user);
    inverseInterleaver = zeros(1, informationSymbols);
    inverseInterleaver(interleaver) = 1:informationSymbols;
    pair.secondPosition(:, user) = informationSymbols + inverseInterleaver(:);
end
end

function decoded = repeated_symbol_decode(likelihood, pair)
informationSymbols = size(pair.information, 1);
users = size(pair.information, 2);
decoded = zeros(informationSymbols, users);
for user = 1:users
    for symbol = 1:informationSymbols
        second = pair.secondPosition(symbol, user);
        metric = likelihood(symbol, :, user) + likelihood(second, :, user);
        [~, decoded(symbol, user)] = max(metric);
    end
end
end

function prior = repeated_symbol_priors(likelihood, pair)
prior = zeros(size(likelihood));
informationSymbols = size(pair.information, 1);
users = size(pair.information, 2);
for user = 1:users
    for symbol = 1:informationSymbols
        second = pair.secondPosition(symbol, user);
        prior(symbol, :, user) = normalize_log(likelihood(second, :, user));
        prior(second, :, user) = normalize_log(likelihood(symbol, :, user));
    end
end
end

function dictionaries = conventional_dictionaries(book, channel, users)
lengthCode = size(book, 2);
channels = dictionary_channels(channel, users, lengthCode);
dictionaries = cell(1, users);
for user = 1:users
    scramble = exp(1j * 2 * pi * (user - 1) * (0:lengthCode - 1) / lengthCode);
    userBook = circshift(book .* scramble, [0, mod(3 * user - 2, lengthCode)]);
    dictionaries{user} = apply_circular_channel(userBook, channels(user, :));
end
end

function [dictionaries, channels] = idma_dictionaries(book, channel, users)
lengthCode = size(book, 2);
channels = dictionary_channels(channel, users, lengthCode);
dictionaries = cell(1, users);
for user = 1:users
    permutation = randperm(lengthCode);
    dictionaries{user} = apply_circular_channel(book(:, permutation), channels(user, :));
end
end

function channels = dictionary_channels(channel, users, lengthCode)
base = zeros(1, lengthCode);
base(1:min(numel(channel), lengthCode)) = channel(1:min(numel(channel), lengthCode));
channels = complex(zeros(users, lengthCode));
for user = 1:users
    delay = mod(2 * user - 2, max(1, floor(lengthCode / 4)));
    gain = 0.85 + 0.15 * cos(0.7 * user);
    phase = exp(1j * 0.35 * (user - 1));
    channels(user, :) = gain * phase * circshift(base, delay);
    channels(user, :) = channels(user, :) / max(norm(channels(user, :)), eps);
end
end

function output = apply_circular_channel(book, channel)
lengthCode = size(book, 2);
response = ifft(fft(book, [], 2) .* fft(channel, lengthCode), [], 2);
scale = sqrt(mean(sum(abs(response).^2, 2)));
output = response / max(scale, eps);
end

function [book, bits] = csk_codebook(root, M)
bitCount = round(log2(M));
bits = bit_table(M, bitCount);
book = complex(zeros(M, numel(root)));
for index = 0:M - 1
    book(index + 1, :) = circshift(root, index);
end
end

function book = orthogonal_codebook(M, lengthCode)
hadamard = sylvester_hadamard(lengthCode) / sqrt(lengthCode);
book = hadamard(1:M, :);
end

function book = dsss_symbol_codebook(M, lengthCode)
bitCount = round(log2(M));
bits = bit_table(M, bitCount);
repetitions = lengthCode / bitCount;
book = zeros(M, lengthCode);
for index = 1:M
    book(index, :) = reshape(repmat(1 - 2 * bits(index, :).', ...
        repetitions, 1), 1, []);
end
book = book / sqrt(lengthCode);
end

function bits = bit_table(M, bitCount)
bits = zeros(M, bitCount);
for index = 0:M - 1
    bits(index + 1, :) = bitget(index, 1:bitCount);
end
end

function root = select_csk_root(lengthCode)
bestScore = inf;
root = ones(1, lengthCode);
for trial = 1:600
    candidate = 2 * randi([0, 1], 1, lengthCode) - 1;
    if abs(sum(candidate)) > 2
        continue;
    end
    correlation = abs(ifft(abs(fft(candidate)).^2)) / lengthCode;
    score = max(correlation(2:end));
    if score < bestScore
        bestScore = score;
        root = candidate;
    end
end
root = root / norm(root);
end

function root = csk_root_sequence(lengthCode, family)
switch lower(string(family))
    case "m-sequence"
        % The degree-6 recurrence in (6-1) provides the PN root; longer
        % spreading factors repeat its complete 63-chip period.
        period = m_sequence63(1);
        root = period(mod(0:lengthCode - 1, numel(period)) + 1);
    case "optimized-pn"
        root = select_csk_root(lengthCode);
    otherwise
        error("SCFDE:UnknownCskRoot", ...
            "cskRootFamily must be m-sequence or optimized-pn.");
end
root = root / norm(root);
end

function output = run_sequence_study(cfg)
familyIds = ["m-sequence", "gold", "kasami", "walsh", "zadoff-chu", "chaotic"];
familyNames = ["m 序列", "Gold 序列", "Kasami 序列", "Walsh 序列组", ...
    "Zadoff-Chu 序列", "混沌序列"];
selected = select_names(familyIds, cfg.sequenceFamilies, "spreading sequence family");
sampleCount = cfg.sequenceFrameCount * cfg.sequenceSymbolsPerFrame;
familyCount = numel(selected);
singleUserBer = zeros(familyCount, numel(cfg.snrDb));
multiUserBer = zeros(familyCount, numel(cfg.snrDb));
meanCrossCorrelation = zeros(familyCount, 1);
maxCrossCorrelation = zeros(familyCount, 1);
codeLengths = zeros(familyCount, 1);
autoCorrelation = cell(familyCount, 1);
autoCorrelationLags = cell(familyCount, 1);
codebooks = cell(familyCount, 1);

for snrIndex = 1:numel(cfg.snrDb)
    [singleErrors, singleTotal] = matched_bpsk_awgn(sampleCount, cfg.snrDb(snrIndex));
    singleUserBer(:, snrIndex) = singleErrors / singleTotal;
end

for familyIndex = 1:familyCount
    book = spreading_sequence_codebook(familyIds(selected(familyIndex)), ...
        cfg.sequenceLength, cfg.sequenceCodeCount);
    reference = book(1, :);
    correlation = real(fftshift(ifft(fft(reference) .* conj(fft(reference)))));
    correlation = correlation / max(abs(correlation));
    lengthCode = size(book, 2);
    lags = -floor(lengthCode / 2):ceil(lengthCode / 2) - 1;
    crossCorrelation = abs(book * book');
    crossCorrelation(1:size(crossCorrelation, 1) + 1:end) = 0;

    codebooks{familyIndex} = book;
    codeLengths(familyIndex) = lengthCode;
    autoCorrelation{familyIndex} = correlation;
    autoCorrelationLags{familyIndex} = lags;
    meanCrossCorrelation(familyIndex) = sum(crossCorrelation, "all") / ...
        (size(book, 1) * (size(book, 1) - 1));
    maxCrossCorrelation(familyIndex) = max(crossCorrelation, [], "all");
    for snrIndex = 1:numel(cfg.snrDb)
        [multiErrors, multiTotal] = multiuser_spread_bpsk(book, cfg.sequenceUsers, ...
            sampleCount, cfg.snrDb(snrIndex));
        multiUserBer(familyIndex, snrIndex) = multiErrors / multiTotal;
    end
end

output.availableFamilyIds = familyIds;
output.familyIds = familyIds(selected);
output.familyNames = familyNames(selected);
output.codeLengths = codeLengths;
output.codebooks = codebooks;
output.autoCorrelation = autoCorrelation;
output.autoCorrelationLags = autoCorrelationLags;
output.meanCrossCorrelation = meanCrossCorrelation;
output.maxCrossCorrelation = maxCrossCorrelation;
output.singleUserBer = singleUserBer;
output.multiUserBer = multiUserBer;
output.snrDb = cfg.snrDb;
output.userCount = cfg.sequenceUsers;
end

function book = spreading_sequence_codebook(familyId, sequenceLength, codeCount)
switch string(familyId)
    case "m-sequence"
        root = m_sequence63(1);
        book = shifted_codebook(root, codeCount);
    case "gold"
        first = m_sequence63(1);
        second = m_sequence63([5, 2, 1]);
        book = zeros(codeCount, sequenceLength);
        for codeIndex = 1:codeCount
            shifted = circshift(second, codeIndex - 1);
            book(codeIndex, :) = 1 - 2 * xor(first > 0, shifted > 0);
        end
    case "kasami"
        first = m_sequence63(1);
        decimation = 2^(6 / 2) + 1;
        second = first(mod((0:sequenceLength - 1) * decimation, sequenceLength) + 1);
        book = zeros(codeCount, sequenceLength);
        book(1, :) = first;
        for codeIndex = 2:codeCount
            shifted = circshift(second, codeIndex - 2);
            book(codeIndex, :) = 1 - 2 * xor(first > 0, shifted > 0);
        end
    case "walsh"
        walshLength = 2^ceil(log2(sequenceLength));
        book = sylvester_hadamard(walshLength);
        book = book(2:codeCount + 1, :);
    case "zadoff-chu"
        index = 0:sequenceLength - 1;
        root = exp(-1j * pi * 5 * index .* (index + 1) / sequenceLength);
        book = shifted_codebook(root, codeCount);
    case "chaotic"
        root = chaotic_sequence(sequenceLength);
        book = shifted_codebook(root, codeCount);
    otherwise
        error("SCFDE:UnknownSequenceFamily", "Unknown sequence family: %s", familyId);
end
book = book ./ sqrt(sum(abs(book).^2, 2));
end

function sequence = m_sequence63(exponents)
sequenceLength = 63;
order = 6;
bits = ones(1, sequenceLength);
for index = 1:sequenceLength - order
    bits(index + order) = mod(sum(bits(index + [0, exponents])), 2);
end
sequence = 1 - 2 * bits;
end

function book = shifted_codebook(root, codeCount)
lengthCode = numel(root);
book = zeros(codeCount, lengthCode, "like", root);
shifts = round((0:codeCount - 1) * lengthCode / codeCount);
for codeIndex = 1:codeCount
    book(codeIndex, :) = circshift(root, shifts(codeIndex));
end
end

function sequence = chaotic_sequence(lengthCode)
state = 0.173;
for index = 1:128
    state = 4 * state * (1 - state);
end
sequence = zeros(1, lengthCode);
for index = 1:lengthCode
    state = 4 * state * (1 - state);
    sequence(index) = 2 * state - 1;
end
sequence = sequence - mean(sequence);
end

function [errors, total] = multiuser_spread_bpsk(book, userCount, symbolCount, snrDb)
activeBook = book(1:userCount, :);
truth = randi([0, 1], symbolCount, userCount);
transmitted = (1 - 2 * truth) * activeBook;
noiseVariance = 10^(-snrDb / 10);
received = transmitted + sqrt(noiseVariance / 2) * ...
    (randn(size(transmitted)) + 1j * randn(size(transmitted)));
decision = real(received * activeBook') < 0;
errors = sum(decision ~= truth, "all");
total = numel(truth);
end

function [errors, total] = matched_bpsk_awgn(symbolCount, snrDb)
truth = randi([0, 1], symbolCount, 1);
noiseVariance = 10^(-snrDb / 10);
received = 1 - 2 * truth + sqrt(noiseVariance / 2) * randn(symbolCount, 1);
decision = received < 0;
errors = sum(decision ~= truth);
total = numel(truth);
end

function [errors, total] = awgn_bpsk(root, count, snrDb)
bits = randi([0, 1], count, 1);
transmitted = (1 - 2 * bits) .* root;
noiseVariance = 10^(-snrDb / 10);
received = transmitted + sqrt(noiseVariance / 2) * ...
    (randn(size(transmitted)) + 1j * randn(size(transmitted)));
decision = real(received * root') < 0;
errors = sum(decision ~= bits);
total = count;
end

function [errors, total] = awgn_codebook(book, bits, count, snrDb)
M = size(book, 1);
bitCount = size(bits, 2);
indices = randi(M, count, 1);
noiseVariance = 1 / (bitCount * 10^(snrDb / 10));
received = book(indices, :) + sqrt(noiseVariance / 2) * ...
    (randn(count, size(book, 2)) + 1j * randn(count, size(book, 2)));
[decision, ~] = hard_dictionary_detect_batch(received, book);
errors = bit_errors(decision, indices, bits);
total = count * bitCount;
end

function [decision, distance] = hard_dictionary_detect_batch(received, book)
decision = zeros(size(received, 1), 1);
distance = zeros(size(received, 1), 1);
for symbol = 1:size(received, 1)
    values = sum(abs(book - received(symbol, :)).^2, 2);
    [distance(symbol), decision(symbol)] = min(values);
end
end

function errors = bit_errors(decision, truth, bits)
decision = reshape(decision, size(truth));
errors = sum(bits(decision(:), :) ~= bits(truth(:), :), "all");
end

function output = normalize_log(values)
maximum = max(values(:));
if isfinite(maximum)
    output = values - maximum;
else
    output = values;
end
end

function H = sylvester_hadamard(lengthCode)
stageCount = round(log2(lengthCode));
H = zeros(lengthCode);
for row = 0:lengthCode - 1
    for column = 0:lengthCode - 1
        parity = 0;
        overlap = bitand(row, column);
        for stage = 1:stageCount
            parity = parity + bitget(overlap, stage);
        end
        H(row + 1, column + 1) = (-1)^parity;
    end
end
end

function [channel, info] = load_channel(fileName, maxLength)
if strlength(string(fileName)) > 0
    assert(isfile(fileName), "SCFDE:MissingMeasuredChannel", ...
        "Measured channel file not found: %s", fileName);
    data = load(fileName);
    names = ["h", "ir", "impulseResponse"];
    channel = [];
    for name = names
        if isfield(data, name)
            channel = data.(name);
            break;
        end
    end
    assert(~isempty(channel), "SCFDE:MissingChannelVariable", ...
        "MAT file must contain h, ir, or impulseResponse.");
    info.source = "测量 CIR 文件";
    info.file = string(fileName);
else
    channel = zeros(1, min(maxLength, 16));
    tapPosition = [1, 3, 7, 11];
    tapPosition = tapPosition(tapPosition <= numel(channel));
    tapValue = [1, 0.52 * exp(1j * 0.80), 0.29 * exp(-1j * 1.10), ...
        0.16 * exp(1j * 2.25)];
    channel(tapPosition) = tapValue(1:numel(tapPosition));
    info.source = "参数化参考多径";
    info.file = "";
end
channel = channel(:).';
channel = channel(1:min(numel(channel), maxLength));
channel = channel / max(norm(channel), eps);
info.pathCount = sum(abs(channel) > max(abs(channel)) * 1e-3);
end

function path = plot_principles(results, cfg)
path = output_path(cfg, "chapter6_spreading_principles.png");
figure("Color", "w", "Position", [60, 60, 1420, 820], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for method = 1:numel(results.principles.methodNames)
    semilogy(results.principles.snrDb, max(results.principles.ber(method, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title("图6-1 扩频体制的 AWGN 性能");
legend(results.principles.methodNames, "Location", "southwest");
nexttile;
imagesc(results.principles.crossCorrelation); axis image; colorbar;
xlabel("CSK 码字索引"); ylabel("CSK 码字索引");
title("循环移位码字互相关矩阵");
nexttile;
stem(0:numel(results.principles.acquisition) - 1, ...
    results.principles.acquisition, "filled", "LineWidth", 1.1);
grid on; xlabel("候选循环移位"); ylabel("归一化相关峰");
title("CSK 捕获：真实移位=" + string(results.principles.acquisitionShift));
nexttile;
stairs(0:size(results.principles.hopping, 2) - 1, results.principles.hopping.', ...
    "LineWidth", 1.1);
grid on; xlabel("跳频时隙"); ylabel("频点索引");
title("多用户跳频序列示例");
legend("用户1", "用户2", "用户3", "Location", "northwest");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function path = plot_sequence_families(results, cfg)
study = results.principles.sequenceStudy;
path = output_path(cfg, "chapter6_spreading_sequence_families.png");
figure("Color", "w", "Position", [70, 70, 1460, 860], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for familyIndex = 1:numel(study.familyNames)
    plot(study.autoCorrelationLags{familyIndex}, study.autoCorrelation{familyIndex}, ...
        "LineWidth", 1.15);
end
grid on; xlabel("循环时延（码片）"); ylabel("归一化周期自相关");
title("图6-2 各扩频序列的周期自相关");
legend(study.familyNames, "Location", "southwest");
nexttile;
bar([study.meanCrossCorrelation, study.maxCrossCorrelation]);
grid on; ylabel("绝对互相关");
title("图6-3 码组零时延互相关");
set(gca, "XTick", 1:numel(study.familyNames), "XTickLabel", study.familyNames);
xtickangle(18);
legend("平均值", "最大值", "Location", "northwest");
nexttile; hold on;
semilogy(study.snrDb, max(study.singleUserBer(1, :), 1e-6), ...
    "o-", "LineWidth", 1.2);
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title("图6-4 单用户 DS-BPSK：单位能量归一化");
legend("六类序列的匹配滤波等效 AWGN", "Location", "southwest");
nexttile; hold on;
for familyIndex = 1:numel(study.familyNames)
    semilogy(study.snrDb, max(study.multiUserBer(familyIndex, :), 1e-6), ...
        "s-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title(string(study.userCount) + " 用户同步 DS-CDMA 匹配滤波检测");
legend(study.familyNames, "Location", "southwest");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function path = plot_conventional(results, cfg)
path = output_path(cfg, "chapter6_conventional_multiuser.png");
figure("Color", "w", "Position", [60, 60, 1450, 850], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for user = 1:size(results.conventional.userChannels, 1)
    stem(0:size(results.conventional.userChannels, 2) - 1, ...
        abs(results.conventional.userChannels(user, :)), "LineWidth", 0.9);
end
grid on; xlabel("码片时延"); ylabel("归一化路径幅度");
title("图6-5 多用户参数化信道冲激响应");
legend("用户" + string(1:size(results.conventional.userChannels, 1)), ...
    "Location", "northeast");
nexttile; hold on;
legendLabels = strings(2 * numel(results.conventional.orders), 1);
for orderIndex = 1:numel(results.conventional.orders)
    semilogy(results.conventional.snrDb, ...
        max(results.conventional.mfBer(orderIndex, :), 1e-6), "--o", ...
        "LineWidth", 1.0);
    legendLabels(2 * orderIndex - 1) = "M=" + ...
        string(results.conventional.orders(orderIndex)) + " 匹配滤波";
    semilogy(results.conventional.snrDb, ...
        max(results.conventional.picBer(orderIndex, :), 1e-6), "-s", ...
        "LineWidth", 1.2);
    legendLabels(2 * orderIndex) = "M=" + ...
        string(results.conventional.orders(orderIndex)) + " 软 PIC";
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title("图6-6 四用户 M 元 CSK 性能");
legend(legendLabels, "Location", "southwest");
nexttile; hold on;
for userIndex = 1:numel(results.conventional.userCounts)
    semilogy(results.conventional.snrDb, ...
        max(results.conventional.loadMfBer(userIndex, :), 1e-6), "--o", ...
        "LineWidth", 1.0);
    semilogy(results.conventional.snrDb, ...
        max(results.conventional.loadPicBer(userIndex, :), 1e-6), "-s", ...
        "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title("多用户负载下的 CSK 检测");
legend(user_receiver_labels(results.conventional.userCounts), "Location", "southwest");
nexttile;
semilogy(1:numel(results.conventional.diagnostic.picErrors), ...
    max(results.conventional.diagnostic.picErrors / ...
    results.conventional.diagnostic.totalBits, 1e-6), "o-", "LineWidth", 1.3);
grid on; xlabel("软 PIC 迭代次数"); ylabel("BER");
title("接收机软干扰抵消收敛");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function paths = plot_idma(results, cfg)
paths = [plot_idma_iterations(results, cfg); plot_idma_loading(results, cfg)];
end

function path = plot_idma_iterations(results, cfg)
path = output_path(cfg, "chapter6_csk_idma_iterations.png");
figure("Color", "w", "Position", [70, 70, 1450, 850], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for iteration = 1:size(results.idma.innerBer, 1)
    semilogy(results.idma.snrDb, max(results.idma.innerBer(iteration, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-12(a) 内迭代次数的影响");
legend("内迭代" + string(1:size(results.idma.innerBer, 1)) + "次", ...
    "Location", "southwest");
nexttile; hold on;
for iteration = 1:size(results.idma.outerBer, 1)
    semilogy(results.idma.snrDb, max(results.idma.outerBer(iteration, :), 1e-6), ...
        "s-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-12(b) 外迭代次数的影响");
legend("外迭代" + string(1:size(results.idma.outerBer, 1)) + "次", ...
    "Location", "southwest");
nexttile; hold on;
for iteration = 1:size(results.idma.innerMse, 1)
    plot(results.idma.snrDb, results.idma.innerMse(iteration, :), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("码字软估计 MSE");
title("图6-13(a) 内迭代的软估计误差");
legend("内迭代" + string(1:size(results.idma.innerMse, 1)) + "次", ...
    "Location", "northeast");
nexttile; hold on;
for iteration = 1:size(results.idma.outerMse, 1)
    plot(results.idma.snrDb, results.idma.outerMse(iteration, :), ...
        "s-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("码字软估计 MSE");
title("图6-13(b) 外迭代的软估计误差");
legend("外迭代" + string(1:size(results.idma.outerMse, 1)) + "次", ...
    "Location", "northeast");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function path = plot_idma_loading(results, cfg)
path = output_path(cfg, "chapter6_csk_idma_loading.png");
figure("Color", "w", "Position", [90, 90, 1250, 540], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for userIndex = 1:numel(results.idma.idmaUserCounts)
    semilogy(results.idma.snrDb, max(results.idma.loadingBer(userIndex, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-14 不同用户数的 CSK-IDMA 性能");
legend(string(results.idma.idmaUserCounts) + " 个用户", "Location", "southwest");
nexttile; hold on;
legendLabels = strings(2 * numel(results.idma.comparisonUserCounts), 1);
for userIndex = 1:numel(results.idma.comparisonUserCounts)
    semilogy(results.idma.snrDb, ...
        max(squeeze(results.idma.comparisonBer(1, userIndex, :)).', 1e-6), ...
        "--o", "LineWidth", 1.1);
    legendLabels(2 * userIndex - 1) = "DSSS-IDMA, " + ...
        string(results.idma.comparisonUserCounts(userIndex)) + " 用户";
    semilogy(results.idma.snrDb, ...
        max(squeeze(results.idma.comparisonBer(2, userIndex, :)).', 1e-6), ...
        "-s", "LineWidth", 1.2);
    legendLabels(2 * userIndex) = "CSK-IDMA, " + ...
        string(results.idma.comparisonUserCounts(userIndex)) + " 用户";
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("信息 BER");
title("图6-15 DSSS-IDMA 与 CSK-IDMA 对比");
legend(legendLabels, "Location", "southwest");
set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function path = plot_idma_ptr_trace(results, cfg)
% Plot one independently generated received frame.  This is a diagnostic
% view of the actual PTR-ESE quantities, separate from the BER aggregates.
trace = results.idma.diagnostic.ptrTrace;
received = results.idma.diagnostic.received(1, :);
ptrReceived = trace.ptrReceivedUser1(1, :);
equivalentChannel = trace.ptrEquivalentChannelUser1;
eseVariance = real(trace.eseVarianceUser1Symbol1);
posterior = trace.finalPosteriorUser1;
path = output_path(cfg, "chapter6_csk_idma_ptr_ese_trace.png");

figure("Color", "w", "Position", [90, 90, 1460, 850], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
plot(0:numel(received) - 1, real(received), "LineWidth", 1.05); hold on;
plot(0:numel(received) - 1, imag(received), "LineWidth", 1.05);
grid on; xlabel("码片索引"); ylabel("幅度");
title("第6章 CSK-IDMA：多用户接收码片（第1个符号）");
legend("实部", "虚部", "Location", "northeast");

nexttile;
plot(0:numel(ptrReceived) - 1, real(ptrReceived), "LineWidth", 1.05); hold on;
plot(0:numel(ptrReceived) - 1, imag(ptrReceived), "LineWidth", 1.05);
grid on; xlabel("码片索引"); ylabel("幅度");
if trace.ptrEnabled
    title("用户1 PTR 输出：匹配信道后的等效观测");
else
    title("用户1观测：未启用 PTR");
end
legend("实部", "虚部", "Location", "northeast");

nexttile;
yyaxis left;
stem(0:numel(equivalentChannel) - 1, abs(equivalentChannel), ...
    "filled", "LineWidth", 0.9);
ylabel("等效信道幅度");
yyaxis right;
plot(0:numel(eseVariance) - 1, eseVariance, "LineWidth", 1.1);
grid on; xlabel("码片索引"); ylabel("ESE 残余方差");
title("PTR 等效信道与 ESE 残余干扰方差");

nexttile;
imagesc(0:size(posterior, 1) - 1, 0:size(posterior, 2) - 1, posterior.');
axis xy; colorbar; ylabel("CSK 符号索引");
xlabel("接收符号索引");
title("ESE 输出的最终 CSK 后验概率（用户1）");

set(findall(gcf, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(gcf, path, "Resolution", 180);
close(gcf);
end

function labels = user_receiver_labels(userCounts)
labels = strings(2 * numel(userCounts), 1);
for index = 1:numel(userCounts)
    labels(2 * index - 1) = string(userCounts(index)) + "用户 匹配滤波";
    labels(2 * index) = string(userCounts(index)) + "用户 软PIC";
end
end

function path = output_path(cfg, filename)
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
path = fullfile(cfg.outputDir, filename);
end

function paths = export_result_data(results, cfg)
matPath = output_path(cfg, "chapter6_formula_results.mat");
save(matPath, "results", "-v7");
paths = string(matPath);

berTable = collect_ber_table(results);
if ~isempty(berTable)
    csvPath = output_path(cfg, "chapter6_formula_ber.csv");
    writetable(berTable, csvPath, 'Encoding', 'UTF-8');
    paths(end + 1, 1) = string(csvPath);
end
end

function berTable = collect_ber_table(results)
berTable = table('Size', [0, 4], ...
    'VariableTypes', {'string', 'string', 'double', 'double'}, ...
    'VariableNames', {'组别', '曲线', 'EbN0_dB', 'BER'});
if isfield(results, "principles")
    berTable = [berTable; ber_rows("6.1 扩频原理", ...
        results.principles.methodNames, results.principles.snrDb, ...
        results.principles.ber)];
end
if isfield(results, "conventional")
    orders = string(results.conventional.orders(:));
    berTable = [berTable; ber_rows("6.2 常规多用户CSK", ...
        "M=" + orders + " 匹配滤波", results.conventional.snrDb, ...
        results.conventional.mfBer)];
    berTable = [berTable; ber_rows("6.2 常规多用户CSK", ...
        "M=" + orders + " 软PIC", results.conventional.snrDb, ...
        results.conventional.picBer)];
    users = string(results.conventional.userCounts(:));
    berTable = [berTable; ber_rows("6.2 用户负载", ...
        users + "用户 匹配滤波", results.conventional.snrDb, ...
        results.conventional.loadMfBer)];
    berTable = [berTable; ber_rows("6.2 用户负载", ...
        users + "用户 软PIC", results.conventional.snrDb, ...
        results.conventional.loadPicBer)];
end
if isfield(results, "idma")
    inner = "内迭代" + string((1:size(results.idma.innerBer, 1)).');
    outer = "外迭代" + string((1:size(results.idma.outerBer, 1)).');
    berTable = [berTable; ber_rows("6.3 CSK-IDMA", inner, ...
        results.idma.snrDb, results.idma.innerBer)];
    berTable = [berTable; ber_rows("6.3 CSK-IDMA", outer, ...
        results.idma.snrDb, results.idma.outerBer)];
    users = string(results.idma.idmaUserCounts(:));
    berTable = [berTable; ber_rows("6.3 用户负载", users + "用户 CSK-IDMA", ...
        results.idma.snrDb, results.idma.loadingBer)];
    for userIndex = 1:numel(results.idma.comparisonUserCounts)
        userCount = string(results.idma.comparisonUserCounts(userIndex));
        berTable = [berTable; ber_rows("6.3 IDMA体制比较", ...
            "DSSS-IDMA " + userCount + "用户", results.idma.snrDb, ...
            squeeze(results.idma.comparisonBer(1, userIndex, :)).')];
        berTable = [berTable; ber_rows("6.3 IDMA体制比较", ...
            "CSK-IDMA " + userCount + "用户", results.idma.snrDb, ...
            squeeze(results.idma.comparisonBer(2, userIndex, :)).')];
    end
end
end

function rows = ber_rows(groupName, curveNames, snrDb, values)
curveNames = string(curveNames(:));
assert(size(values, 1) == numel(curveNames), ...
    "SCFDE:InvalidBerExport", "Number of BER curves and labels must match.");
assert(size(values, 2) == numel(snrDb), ...
    "SCFDE:InvalidBerExport", "BER curve length must match snrDb.");
snr = repmat(snrDb(:).', size(values, 1), 1);
names = repmat(curveNames, 1, numel(snrDb));
rows = table(repmat(string(groupName), numel(values), 1), names(:), ...
    snr(:), values(:), 'VariableNames', {'组别', '曲线', 'EbN0_dB', 'BER'});
end

function validate_config(cfg)
assert(cfg.frameCount > 0 && cfg.symbolsPerFrame > 1, ...
    "SCFDE:InvalidFrame", "frameCount and symbolsPerFrame must be positive.");
assert(mod(cfg.symbolsPerFrame, 2) == 0, "SCFDE:InvalidSymbols", ...
    "symbolsPerFrame must be even for the Chapter 6 outer code.");
assert(2^round(log2(cfg.codeLength)) == cfg.codeLength, ...
    "SCFDE:InvalidCodeLength", "codeLength must be a power of two.");
assert(all(cfg.modulationOrders <= cfg.codeLength) && ...
    all(2.^round(log2(cfg.modulationOrders)) == cfg.modulationOrders), ...
    "SCFDE:InvalidModulationOrder", ...
    "modulationOrders must be powers of two no larger than codeLength.");
assert(cfg.cskOrder <= cfg.codeLength && ...
    2^round(log2(cfg.cskOrder)) == cfg.cskOrder, ...
    "SCFDE:InvalidCskOrder", "cskOrder must be a power of two no larger than codeLength.");
assert(mod(cfg.codeLength, log2(cfg.cskOrder)) == 0, ...
    "SCFDE:InvalidDsssIdmaRate", ...
    "codeLength must be divisible by log2(cskOrder) for the DSSS-IDMA baseline.");
assert(cfg.innerIterations > 0 && cfg.outerIterations > 0, ...
    "SCFDE:InvalidIterations", "innerIterations and outerIterations must be positive.");
assert(all(cfg.idmaUserCounts > 0) && all(cfg.comparisonUserCounts > 0), ...
    "SCFDE:InvalidUserCount", "All user counts must be positive.");
assert(cfg.sequenceLength == 63, "SCFDE:InvalidSequenceLength", ...
    "The common m/Gold/Kasami sequence period must be 63 chips.");
assert(cfg.sequenceCodeCount >= 2 && cfg.sequenceCodeCount <= 8 && ...
    cfg.sequenceUsers >= 1 && cfg.sequenceUsers <= cfg.sequenceCodeCount, ...
    "SCFDE:InvalidSequenceUsers", ...
    "sequenceCodeCount must be 2 to 8 and sequenceUsers must not exceed it.");
assert(cfg.sequenceFrameCount > 0 && cfg.sequenceSymbolsPerFrame > 0, ...
    "SCFDE:InvalidSequenceSamples", ...
    "sequenceFrameCount and sequenceSymbolsPerFrame must be positive.");
assert(any(strcmpi(string(cfg.cskRootFamily), ["m-sequence", "optimized-pn"])), ...
    "SCFDE:InvalidCskRoot", ...
    "cskRootFamily must be m-sequence or optimized-pn.");
assert(cfg.eseDamping > 0 && cfg.eseDamping <= 1, ...
    "SCFDE:InvalidEseDamping", "eseDamping must be in (0, 1].");
end

function selected = select_names(available, requested, label)
requested = string(requested);
if isscalar(requested) && strcmpi(requested, "all")
    selected = 1:numel(available);
    return;
end
selected = zeros(1, numel(requested));
for index = 1:numel(requested)
    match = find(strcmpi(requested(index), available), 1);
    assert(~isempty(match), "SCFDE:UnknownMethod", ...
        "Unknown %s: %s. Available: %s", label, requested(index), ...
        strjoin(available, ", "));
    selected(index) = match;
end
assert(numel(unique(selected)) == numel(selected), ...
    "SCFDE:DuplicateMethod", "A %s was selected twice.", label);
end

function output = merge_options(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
