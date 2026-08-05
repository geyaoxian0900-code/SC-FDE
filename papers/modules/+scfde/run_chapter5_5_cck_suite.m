function results = run_chapter5_5_cck_suite(options, simulationDir)
%RUN_CHAPTER5_5_CCK_SUITE Modular reproductions for Chapter 5.5.

defaults.snrList = 0:3:15;
defaults.snrDb = 8;
defaults.symbols = 24;
defaults.frameCount = 2;
defaults.randomSeed = 20260727;
defaults.groups = "all";
defaults.gcckModes = "all";
defaults.receiverMethods = "all";
defaults.turboMethods = "all";
defaults.smMethods = "all";
defaults.receiverCandidateLimit = 128;
defaults.turboIterations = 3;
defaults.turboOuterCode = "repetition-1/2";
defaults.turboDamping = 0.50;
defaults.turboDiagnosticFrames = 12;
defaults.extendedLengths = [8, 16, 32];
defaults.dynamicAlphas = [1, 0.9995, 0.995];
defaults.smTxAntennas = 4;
defaults.smRxAntennas = 2;
defaults.smIterations = 3;
defaults.smSnrList = -6:3:15;
defaults.smDiagnosticSnrDb = -3;
defaults.smDiagnosticSeed = 20260735;
defaults.awgnDefinition = "EbN0";
defaults.receiverSnrDefinition = "EsN0";
defaults.useCyclicPrefix = false;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "results");
cfg = merge_options(defaults, options);
assert(cfg.symbols > 0 && cfg.frameCount > 0, ...
    "SCFDE:InvalidFrame", "symbols and frameCount must be positive.");
assert(cfg.turboIterations > 0 && cfg.turboDiagnosticFrames > 0 && ...
    cfg.smIterations > 0, "SCFDE:InvalidIterations", ...
    "Turbo and SM iteration counts must be positive.");
assert(all(cfg.extendedLengths >= 8) && all(mod(cfg.extendedLengths, 8) == 0), ...
    "SCFDE:InvalidCCKLength", "extendedLengths must be multiples of eight.");
assert(mod(cfg.smTxAntennas, 1) == 0 && log2(cfg.smTxAntennas) == ...
    round(log2(cfg.smTxAntennas)), "SCFDE:InvalidSmAntennaCount", ...
    "smTxAntennas must be a power of two.");
assert(isvector(cfg.smSnrList) && ~isempty(cfg.smSnrList), ...
    "SCFDE:InvalidSmSnr", "smSnrList must be a nonempty vector.");
assert(isscalar(cfg.smDiagnosticSeed) && cfg.smDiagnosticSeed >= 0 && ...
    mod(cfg.smDiagnosticSeed, 1) == 0, "SCFDE:InvalidSmDiagnosticSeed", ...
    "smDiagnosticSeed must be a nonnegative integer.");
assert(strcmpi(string(cfg.turboOuterCode), "repetition-1/2"), ...
    "SCFDE:InvalidTurboOuterCode", ...
    "Chapter 5.5 currently implements the repetition-1/2 outer code.");

groupNames = ["gcck", "extended", "turbo", "sm"];
groupIndices = select_names(groupNames, cfg.groups, "5.5 experiment group");
rng(cfg.randomSeed, "twister");
results.config = cfg;
results.availableGroups = groupNames;
results.groupNames = groupNames(groupIndices);
results.outputPath = "";
results.figurePaths = strings(0, 1);

if any(groupNames(groupIndices) == "gcck")
    results.gcck = run_gcck_study(cfg);
end
if any(groupNames(groupIndices) == "extended")
    results.extended = run_extended_study(cfg);
end
if any(groupNames(groupIndices) == "turbo")
    results.turbo = run_turbo_study(cfg);
end
if any(groupNames(groupIndices) == "sm")
    results.spatialModulation = run_spatial_modulation_study(cfg);
end

if cfg.makePlot
    if isfield(results, "gcck")
        paths = plot_gcck(results.gcck, cfg);
        results.figurePaths = [results.figurePaths; paths];
    end
    if isfield(results, "extended")
        results.figurePaths = [results.figurePaths; plot_extended(results.extended, cfg)];
    end
    if isfield(results, "turbo")
        results.figurePaths = [results.figurePaths; plot_turbo(results.turbo, cfg)];
    end
    if isfield(results, "spatialModulation")
        results.figurePaths = [results.figurePaths; ...
            plot_spatial_modulation(results.spatialModulation, cfg)];
    end
    if ~isempty(results.figurePaths)
        results.outputPath = results.figurePaths(1);
    end
end
end

function output = run_gcck_study(cfg)
modeNames = ["GCCK-QPSK-4R", "GCCK-QPSK-8R", "GCCK-8PSK-12R"];
modeIndices = select_names(modeNames, cfg.gcckModes, "GCCK mode");
receiverNames = ["Rake", "Rake-DFE", "BiDFE-1", "BiDFE-2", ...
    "TR-Diversity-2R", "MFB"];
receiverIndices = select_names(receiverNames, cfg.receiverMethods, ...
    "GCCK receiver");
if isfield(cfg, "gcckChannel")
    channel = cfg.gcckChannel(:).';
else
    channel = long_uwa_channel();
end
books = cell(1, numel(modeNames));
bitTables = cell(1, numel(modeNames));
for mode = 1:numel(modeNames)
    [books{mode}, bitTables{mode}] = cck_codebook(modeNames(mode), 8, true);
end
awgnBer = zeros(numel(modeNames), numel(cfg.snrList));
unionBound = zeros(numel(modeNames), numel(cfg.snrList));
receiverBer = zeros(numel(modeNames), numel(receiverNames), numel(cfg.snrList));
for snrIndex = 1:numel(cfg.snrList)
    for mode = modeIndices
        awgnErrors = 0;
        awgnTotal = 0;
        receiverErrors = zeros(numel(receiverNames), 1);
        receiverTotal = 0;
        for frame = 1:cfg.frameCount
            [errors, total] = awgn_codebook_ber(books{mode}, bitTables{mode}, ...
                cfg.symbols, cfg.snrList(snrIndex), cfg.awgnDefinition);
            awgnErrors = awgnErrors + errors;
            awgnTotal = awgnTotal + total;
            frameResult = static_receiver_frame(books{mode}, bitTables{mode}, ...
                channel, cfg, cfg.snrList(snrIndex));
            receiverErrors = receiverErrors + frameResult.errors;
            receiverTotal = receiverTotal + frameResult.total;
        end
        awgnBer(mode, snrIndex) = awgnErrors / awgnTotal;
        receiverBer(mode, :, snrIndex) = receiverErrors / receiverTotal;
        unionBound(mode, snrIndex) = nearest_neighbor_bound(books{mode}, ...
            bitTables{mode}, cfg.snrList(snrIndex), cfg.awgnDefinition);
    end
end

referenceMode = find(modeNames == "GCCK-QPSK-8R", 1);
dynamicBer = zeros(numel(cfg.dynamicAlphas), numel(cfg.snrList));
for alphaIndex = 1:numel(cfg.dynamicAlphas)
    for snrIndex = 1:numel(cfg.snrList)
        errors = 0;
        total = 0;
        for frame = 1:cfg.frameCount
            result = dynamic_dfe_frame(books{referenceMode}, bitTables{referenceMode}, ...
                channel, cfg, cfg.snrList(snrIndex), cfg.dynamicAlphas(alphaIndex));
            errors = errors + result.errors;
            total = total + result.total;
        end
        dynamicBer(alphaIndex, snrIndex) = errors / total;
    end
end
output.modeNames = modeNames(modeIndices);
output.modeIndices = modeIndices;
output.awgnBer = awgnBer(modeIndices, :);
output.unionBound = unionBound(modeIndices, :);
output.allAwgnBer = awgnBer;
output.allUnionBound = unionBound;
output.receiverNames = receiverNames(receiverIndices);
output.receiverIndices = receiverIndices;
output.receiverBer = receiverBer(modeIndices, receiverIndices, :);
output.allReceiverBer = receiverBer;
output.channel = channel;
output.dynamicAlphas = cfg.dynamicAlphas;
output.dynamicBer = dynamicBer;
output.snrList = cfg.snrList;
end

function output = run_extended_study(cfg)
lengths = cfg.extendedLengths(:).';
books = cell(1, numel(lengths));
bits = cell(1, numel(lengths));
autoCorrelation = cell(1, numel(lengths));
crossCorrelation95 = zeros(1, numel(lengths));
meanCrossCorrelation = zeros(1, numel(lengths));
maximumCrossCorrelation = zeros(1, numel(lengths));
for index = 1:numel(lengths)
    [books{index}, bits{index}] = cck_codebook("FR-CCK", lengths(index), false);
    autoCorrelation{index} = aperiodic_autocorrelation(books{index}(17, :));
    [meanCrossCorrelation(index), crossCorrelation95(index), ...
        maximumCrossCorrelation(index)] = ...
        cross_correlation_statistics(books{index});
end
awgnBer = zeros(numel(lengths), numel(cfg.snrList));
for snrIndex = 1:numel(cfg.snrList)
    for index = 1:numel(lengths)
        errors = 0;
        total = 0;
        for frame = 1:cfg.frameCount
            [frameErrors, frameTotal] = awgn_codebook_ber(books{index}, ...
                bits{index}, cfg.symbols, cfg.snrList(snrIndex), ...
                cfg.awgnDefinition);
            errors = errors + frameErrors;
            total = total + frameTotal;
        end
        awgnBer(index, snrIndex) = errors / total;
    end
end

methodNames = ["CCK-Rake", "CCK-TE-1", "CCK-TE-2", "CCK-TE-3", ...
    "DSSS-4", "DSSS-8"];
dynamicBer = zeros(numel(methodNames), numel(cfg.dynamicAlphas));
baseBook = books{1};
baseBits = bits{1};
channel = long_uwa_channel();
for alphaIndex = 1:numel(cfg.dynamicAlphas)
    errors = zeros(numel(methodNames), 1);
    totals = zeros(numel(methodNames), 1);
    for frame = 1:cfg.frameCount
        cckFrame = dynamic_cck_frame(baseBook, channel, cfg, cfg.snrDb, ...
            cfg.dynamicAlphas(alphaIndex));
        rake = rake_detect(cckFrame.received, baseBook, channel);
        [~, history] = fde_cck_detect(cckFrame.received, baseBook, channel, ...
            cckFrame.noiseVariance, cfg.turboIterations);
        errors(1) = errors(1) + bit_errors(rake, cckFrame.indices, baseBits);
        for iteration = 1:cfg.turboIterations
            errors(iteration + 1) = errors(iteration + 1) + ...
                bit_errors(history(iteration, :), cckFrame.indices, baseBits);
        end
        totals(1:4) = totals(1:4) + numel(baseBits(cckFrame.indices, :));
        for spreadingIndex = 1:2
            [dsssErrors, dsssTotal] = dsss_fde_frame(cfg, channel, cfg.snrDb, ...
                4 * spreadingIndex, cfg.dynamicAlphas(alphaIndex));
            errors(4 + spreadingIndex) = errors(4 + spreadingIndex) + dsssErrors;
            totals(4 + spreadingIndex) = totals(4 + spreadingIndex) + dsssTotal;
        end
    end
    dynamicBer(:, alphaIndex) = errors ./ totals;
end
output.lengths = lengths;
output.autoCorrelation = autoCorrelation;
output.crossCorrelation95 = crossCorrelation95;
output.meanCrossCorrelation = meanCrossCorrelation;
output.maximumCrossCorrelation = maximumCrossCorrelation;
output.awgnBer = awgnBer;
output.methodNames = methodNames;
output.dynamicBer = dynamicBer;
output.dynamicAlphas = cfg.dynamicAlphas;
output.snrList = cfg.snrList;
end

function output = run_turbo_study(cfg)
[book, bits] = cck_codebook("FR-CCK", 8, true);
methodNames = ["CCK-Rake", "CCK-FDE", "CCK-TE-2", "CCK-TE-3", ...
    "DSSS-4", "DSSS-8"];
methodIndices = select_names(methodNames, cfg.turboMethods, "CCK Turbo method");
allBer = zeros(numel(methodNames), numel(cfg.snrList));
channel = short_turbo_channel();
for snrIndex = 1:numel(cfg.snrList)
    errors = zeros(numel(methodNames), 1);
    totals = zeros(numel(methodNames), 1);
    for frame = 1:cfg.frameCount
        txFrame = turbo_cck_frame(book, bits, channel, cfg, cfg.snrList(snrIndex));
        rake = rake_detect(txFrame.received, book, channel);
        [informationHistory, ~] = fde_cck_turbo_detect(txFrame, book, bits, ...
            channel, cfg.turboIterations, cfg.turboDamping);
        rakeBits = reshape(bits(rake, :).', 1, []);
        rakeInformation = decode_repetition_bits(rakeBits, txFrame);
        errors(1) = errors(1) + sum(rakeInformation ~= txFrame.informationBits);
        errors(2) = errors(2) + sum(informationHistory(1, :) ~= txFrame.informationBits);
        errors(3) = errors(3) + sum(informationHistory(min(2, cfg.turboIterations), :) ...
            ~= txFrame.informationBits);
        errors(4) = errors(4) + sum(informationHistory(end, :) ~= txFrame.informationBits);
        totals(1:4) = totals(1:4) + numel(txFrame.informationBits);
        for spreadingIndex = 1:2
            [dsssErrors, dsssTotal] = dsss_fde_frame(cfg, channel, ...
                cfg.snrList(snrIndex), 4 * spreadingIndex, 1);
            errors(4 + spreadingIndex) = errors(4 + spreadingIndex) + dsssErrors;
            totals(4 + spreadingIndex) = totals(4 + spreadingIndex) + dsssTotal;
        end
    end
    allBer(:, snrIndex) = errors ./ totals;
end
iterationErrors = zeros(1, cfg.turboIterations);
residualEnergy = zeros(1, cfg.turboIterations);
iterationTotal = 0;
for frame = 1:cfg.turboDiagnosticFrames
    example = turbo_cck_frame(book, bits, channel, cfg, cfg.snrDb);
    [informationHistory, frameResidual] = fde_cck_turbo_detect(example, book, bits, ...
        channel, cfg.turboIterations, cfg.turboDamping);
    for iteration = 1:cfg.turboIterations
        iterationErrors(iteration) = iterationErrors(iteration) + ...
            sum(informationHistory(iteration, :) ~= example.informationBits);
    end
    residualEnergy = residualEnergy + frameResidual;
    iterationTotal = iterationTotal + numel(example.informationBits);
end
iterationBer = iterationErrors / iterationTotal;
residualEnergy = residualEnergy / cfg.turboDiagnosticFrames;
output.methodNames = methodNames(methodIndices);
output.methodIndices = methodIndices;
output.ber = allBer(methodIndices, :);
output.allBer = allBer;
output.iterationBer = iterationBer;
output.iterationResidual = residualEnergy;
output.channel = channel;
output.snrList = cfg.snrList;
end

function output = run_spatial_modulation_study(cfg)
methodNames = ["QPSK-SM-MMSE", "CCK-SM-MMSE", "CCK-SM-IBDFE-2", ...
    "CCK-SM-IBDFE-3"];
methodIndices = select_names(methodNames, cfg.smMethods, "CCK-SM method");
[qpskBook, qpskBits] = qpsk_word_book();
[cckBook, cckBits] = cck_codebook("FR-CCK", 8, true);
snrList = cfg.smSnrList;
allBer = zeros(numel(methodNames), numel(snrList));
allIndexBer = zeros(numel(methodNames), numel(snrList));
for snrIndex = 1:numel(snrList)
    errors = zeros(numel(methodNames), 1);
    indexErrors = zeros(numel(methodNames), 1);
    totals = zeros(numel(methodNames), 1);
    indexTotals = zeros(numel(methodNames), 1);
    for frame = 1:cfg.frameCount
        qpsk = sm_ibdfe_frame(qpskBook, qpskBits, cfg, snrList(snrIndex), 1);
        cck = sm_ibdfe_frame(cckBook, cckBits, cfg, snrList(snrIndex), ...
            cfg.smIterations);
        errors(1) = errors(1) + qpsk.bitErrors(1) + qpsk.indexErrors(1);
        indexErrors(1) = indexErrors(1) + qpsk.indexErrors(1);
        totals(1) = totals(1) + qpsk.totalBits;
        indexTotals(1) = indexTotals(1) + qpsk.totalIndexBits;
        for iteration = 1:3
            selected = min(iteration, cfg.smIterations);
            errors(iteration + 1) = errors(iteration + 1) + ...
                cck.bitErrors(selected) + cck.indexErrors(selected);
            indexErrors(iteration + 1) = indexErrors(iteration + 1) + ...
                cck.indexErrors(selected);
            totals(iteration + 1) = totals(iteration + 1) + cck.totalBits;
            indexTotals(iteration + 1) = indexTotals(iteration + 1) + ...
                cck.totalIndexBits;
        end
    end
    allBer(:, snrIndex) = errors ./ totals;
    allIndexBer(:, snrIndex) = indexErrors ./ indexTotals;
end
randomState = rng;
rng(cfg.smDiagnosticSeed, "twister");
example = sm_ibdfe_frame(cckBook, cckBits, cfg, cfg.smDiagnosticSnrDb, ...
    cfg.smIterations);
rng(randomState);
output.methodNames = methodNames(methodIndices);
output.methodIndices = methodIndices;
output.ber = allBer(methodIndices, :);
output.indexBer = allIndexBer(methodIndices, :);
output.allBer = allBer;
output.allIndexBer = allIndexBer;
output.exampleBitBer = example.bitErrors / example.totalBits;
output.exampleIndexBer = example.indexErrors / example.totalIndexBits;
output.snrList = snrList;
output.diagnosticSnrDb = cfg.smDiagnosticSnrDb;
end

function [book, bits] = cck_codebook(name, wordLength, unitEnergy)
name = string(name);
switch name
    case {"FR-CCK", "GCCK-QPSK-8R"}
        bitCount = 8;
    case {"HR-CCK", "GCCK-QPSK-4R"}
        bitCount = 4;
    case "GCCK-8PSK-12R"
        bitCount = 12;
    otherwise
        error("SCFDE:UnknownCCK", "Unknown CCK mode: %s", name);
end
M = 2^bitCount;
bits = zeros(M, bitCount);
book = complex(zeros(M, wordLength));
for index = 0:M - 1
    rowBits = bitget(index, 1:bitCount);
    bits(index + 1, :) = rowBits;
    phase = cck_phases(name, rowBits);
    word = cck_word(phase);
    if wordLength > 8
        word = extend_cck_word(word, wordLength, rowBits);
    end
    if unitEnergy
        word = word / sqrt(wordLength);
    else
        word = word / sqrt(8);
    end
    book(index + 1, :) = word;
end
end

function phase = cck_phases(name, bits)
qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
switch name
    case {"FR-CCK", "GCCK-QPSK-8R"}
        phase = [qpsk(bits(1:2)), qpsk(bits(3:4)), ...
            qpsk(bits(5:6)), qpsk(bits(7:8))];
    case {"HR-CCK", "GCCK-QPSK-4R"}
        phase = [qpsk(bits(1:2)), pi * bits(3) + 0.5 * pi, 0, ...
            pi * bits(4)];
    case "GCCK-8PSK-12R"
        psk8 = @(triple) pi / 4 * ...
            (triple(1) + 2 * triple(2) + 4 * triple(3));
        phase = [psk8(bits(1:3)), psk8(bits(4:6)), ...
            psk8(bits(7:9)), psk8(bits(10:12))];
end
end

function word = cck_word(phase)
phi1 = phase(1); phi2 = phase(2); phi3 = phase(3); phi4 = phase(4);
word = exp(1j * [phi1 + phi2 + phi3 + phi4, phi1 + phi3 + phi4, ...
    phi1 + phi2 + phi4, phi1 + phi4, phi1 + phi2 + phi3, phi1 + phi3, ...
    phi1 + phi2, phi1]);
word([4, 7]) = -word([4, 7]);
end

function word = extend_cck_word(baseWord, wordLength, bits)
% 书 (5-8)(5-9): Golay 互补对递推构造 [A_k B_k] = [A_{k-1} B_{k-1}; B_{k-1} -A_{k-1}]
% 种子 A_1=[1 1], B_1=[1 -1]；CCK-16 取 A_2/B_2，CCK-32 取 A_3/B_3
blocks = wordLength / 8;
levels = log2(blocks) - 1;
[A, B] = golay_complementary_pair(levels);
if blocks == 2
    if bits(3) == 0, signs = A; else, signs = B; end
else
    patternIndex = 1 + bits(3) + 2 * bits(4);
    if patternIndex == 1, signs = A; else, signs = B; end
end
word = repmat(baseWord, 1, blocks);
word = word .* repelem(signs, 8);
end

function [A, B] = golay_complementary_pair(levels)
% 书 (5-8): A_k=[A_{k-1} B_{k-1}], B_k=[A_{k-1} -B_{k-1}]
% 种子 (5-9): A_1=[1 1], B_1=[1 -1]。levels=1 得 A_2=[1 1 1 -1]（4 位）
A = [1, 1];
B = [1, -1];
for level = 1:levels
    nextA = [A, B];
    nextB = [A, -B];
    A = nextA;
    B = nextB;
end
end

function channel = long_uwa_channel()
delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
power = exp(-delays / 5.5);
phase = [0, .5, -1.0, .8, -2.1, .25, -1.5, 1.4, -.8, .9, -2.6];
channel = zeros(1, delays(end) + 1);
channel(delays + 1) = sqrt(power) .* exp(1j * phase);
channel = channel / norm(channel);
end

function channel = short_turbo_channel()
channel = [1, .70 * exp(1j * .4), .50 * exp(-1j * .8), ...
    .28 * exp(1j * 1.4), .15 * exp(-1j * 2.1)];
channel = channel / norm(channel);
end

function [errors, total] = awgn_codebook_ber(book, bits, count, snrDb, definition)
indices = randi(size(book, 1), 1, count);
if nargin < 5 || strcmpi(string(definition), "EsN0")
    noiseVariance = 10^(-snrDb / 10);
else
    bitsPerWord = size(bits, 2);
    noiseVariance = 10^(-snrDb / 10) / bitsPerWord;
end
received = book(indices, :) + sqrt(noiseVariance / 2) * ...
    (randn(count, size(book, 2)) + 1j * randn(count, size(book, 2)));
detected = nearest_book(received, book);
errors = bit_errors(detected, indices, bits);
total = numel(bits(indices, :));
end

function value = nearest_neighbor_bound(book, bits, snrDb, definition)
M = size(book, 1);
probe = unique(round(linspace(1, M, min(32, M))));
if nargin < 4 || strcmpi(string(definition), "EsN0")
    noiseVariance = 10^(-snrDb / 10);
else
    noiseVariance = 10^(-snrDb / 10) / size(bits, 2);
end
sumBound = 0;
for index = probe
    distances = sum(abs(book - book(index, :)).^2, 2);
    distances(index) = inf;
    [sorted, order] = sort(distances, "ascend");
    count = min(12, M - 1);
    hamming = sum(bits(order(1:count), :) ~= bits(index, :), 2);
    argument = sqrt(sorted(1:count) / (2 * noiseVariance));
    sumBound = sumBound + sum(hamming .* q_function(argument)) / size(bits, 2);
end
value = min(0.5, sumBound / numel(probe));
end

function value = q_function(argument)
value = 0.5 * erfc(argument / sqrt(2));
end

function frame = static_cck_frame(book, channel, cfg, snrDb)
frame.indices = randi(size(book, 1), 1, cfg.symbols);
frame.chips = reshape(book(frame.indices, :).', 1, []);
frame.noiseVariance = 10^(-snrDb / 10);
if isfield(cfg, "receiverSnrDefinition") && ...
        strcmpi(string(cfg.receiverSnrDefinition), "EbN0")
    frame.noiseVariance = frame.noiseVariance / log2(size(book, 1));
end
memory = numel(channel) - 1;
if isfield(cfg, "useCyclicPrefix") && cfg.useCyclicPrefix
    transmitted = [frame.chips(end - memory + 1:end), frame.chips];
    channelOutput = filter(channel, 1, transmitted);
    channelOutput = channelOutput(memory + 1:memory + numel(frame.chips));
    channelTail = zeros(1, memory);
else
    channelOutput = filter(channel, 1, [frame.chips, zeros(1, memory)]);
    channelTail = zeros(1, 0);
end
receivedLength = numel(channelOutput) + numel(channelTail);
frame.received = [channelOutput channelTail] + ...
    sqrt(frame.noiseVariance / 2) * ...
    (randn(1, receivedLength) + 1j * randn(1, receivedLength));
end

function frame = turbo_cck_frame(book, bits, channel, cfg, snrDb)
bitCount = size(bits, 2);
codedLength = cfg.symbols * bitCount;
assert(mod(codedLength, 2) == 0, "SCFDE:InvalidTurboFrame", ...
    "symbols times bits per CCK word must be even for repetition-1/2.");
informationLength = codedLength / 2;
frame.informationBits = randi([0, 1], 1, informationLength);
positions = randperm(codedLength);
frame.firstCopy = positions(1:informationLength);
secondCopy = positions(informationLength + 1:end);
interleaver = randperm(informationLength);
frame.codedBits = zeros(1, codedLength);
frame.codedBits(frame.firstCopy) = frame.informationBits;
frame.codedBits(secondCopy) = frame.informationBits(interleaver);
inverseInterleaver = zeros(1, informationLength);
inverseInterleaver(interleaver) = 1:informationLength;
frame.pairedPosition = zeros(1, codedLength);
frame.pairedPosition(frame.firstCopy) = secondCopy(inverseInterleaver);
frame.pairedPosition(secondCopy) = frame.firstCopy(interleaver);
wordBits = reshape(frame.codedBits, bitCount, []).';
frame.indices = (1 + wordBits * (2 .^ (0:bitCount - 1)).').';
frame.chips = reshape(book(frame.indices, :).', 1, []);
frame.noiseVariance = 10^(-snrDb / 10);
memory = numel(channel) - 1;
frame.received = filter(channel, 1, [frame.chips, zeros(1, memory)]) + ...
    sqrt(frame.noiseVariance / 2) * ...
    (randn(1, numel(frame.chips) + memory) + ...
    1j * randn(1, numel(frame.chips) + memory));
end

function [informationHistory, residualEnergy] = fde_cck_turbo_detect( ...
        frame, book, bits, channel, iterations, damping)
wordLength = size(book, 2);
bitCount = size(bits, 2);
blockCount = numel(frame.indices);
lengthFrame = blockCount * wordLength;
received = frame.received(1:lengthFrame);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
soft = zeros(1, lengthFrame);
prior = zeros(1, blockCount * bitCount);
informationHistory = false(iterations, numel(frame.informationBits));
residualEnergy = zeros(1, iterations);
for iteration = 1:iterations
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    C = conj(H) ./ (frame.noiseVariance + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    priorWords = reshape(prior, bitCount, []).';
    [~, softWord, posteriorLlr] = soft_book_detect_with_prior( ...
        blocks, book, bits, frame.noiseVariance, priorWords);
    channelExtrinsic = reshape(posteriorLlr.', 1, []) - prior;
    informationLlr = channelExtrinsic(frame.firstCopy) + ...
        channelExtrinsic(frame.pairedPosition(frame.firstCopy));
    informationHistory(iteration, :) = informationLlr < 0;
    prior = damping * channelExtrinsic(frame.pairedPosition);
    candidateSoft = reshape(softWord.', 1, []);
    soft = 0.65 * soft + 0.35 * candidateSoft;
    reconstructed = filter(channel, 1, soft);
    residualEnergy(iteration) = mean(abs(received - reconstructed).^2);
end
end

function [detected, softWord, posteriorLlr] = soft_book_detect_with_prior( ...
        observations, book, bits, noiseVariance, priorWords)
blockCount = size(observations, 1);
bitCount = size(bits, 2);
detected = zeros(1, blockCount);
softWord = complex(zeros(size(observations)));
posteriorLlr = zeros(blockCount, bitCount);
for block = 1:blockCount
    distance = sum(abs(book - observations(block, :)).^2, 2);
    metric = -distance / max(noiseVariance, 1e-8) + ...
        0.5 * ((1 - 2 * bits) * priorWords(block, :).');
    [maximum, detected(block)] = max(metric);
    weights = exp(metric - maximum);
    weights = weights / sum(weights);
    softWord(block, :) = weights.' * book;
    for bit = 1:bitCount
        posteriorLlr(block, bit) = log_sum_exp(metric(bits(:, bit) == 0)) - ...
            log_sum_exp(metric(bits(:, bit) == 1));
    end
end
end

function informationBits = decode_repetition_bits(codedBits, frame)
informationBits = codedBits(frame.firstCopy);
pairedBits = codedBits(frame.pairedPosition(frame.firstCopy));
agreement = informationBits == pairedBits;
informationBits(agreement) = pairedBits(agreement);
end

function value = log_sum_exp(values)
maximum = max(values);
value = maximum + log(sum(exp(values - maximum)));
end

function frame = dynamic_cck_frame(book, channel, cfg, snrDb, alpha)
frame.indices = randi(size(book, 1), 1, cfg.symbols);
wordLength = size(book, 2);
memory = numel(channel) - 1;
state = zeros(1, memory);
channelState = channel;
received = complex(zeros(1, cfg.symbols * wordLength));
profile = sqrt(abs(channel) .^ 2 + 1e-8);
for block = 1:cfg.symbols
    innovation = profile .* (randn(size(channel)) + 1j * randn(size(channel))) / sqrt(2);
    channelState = alpha * channelState + sqrt(max(0, 1 - alpha^2)) * innovation;
    word = book(frame.indices(block), :);
    received((block - 1) * wordLength + (1:wordLength)) = ...
        expected_block(state, word, channelState);
    state = append_channel_state(state, word, memory);
end
frame.chips = reshape(book(frame.indices, :).', 1, []);
frame.noiseVariance = 10^(-snrDb / 10);
received = [received, zeros(1, memory)];
frame.received = received + sqrt(frame.noiseVariance / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
end

function output = static_receiver_frame(book, bits, channel, cfg, snrDb)
frame = static_cck_frame(book, channel, cfg, snrDb);
rake = rake_detect(frame.received, book, channel);
rakeDfe = dfe_detect(frame.received, book, channel, frame.noiseVariance, ...
    cfg.receiverCandidateLimit);
[forward, forwardScores] = dfe_detect(frame.received, book, channel, ...
    frame.noiseVariance, cfg.receiverCandidateLimit);
[~, backwardScores] = backward_dfe_detect(frame.received, book, channel, ...
    frame.noiseVariance, cfg.receiverCandidateLimit);
bi1 = fuse_scores(forwardScores, backwardScores);
bi2 = bidirectional_refine(frame.received, book, channel, bi1, ...
    frame.noiseVariance, cfg.receiverCandidateLimit);
tr = tr_diversity_detect(frame.received, book, channel, frame.noiseVariance);
mfb = matched_filter_detect(frame.received, book, channel);
decisions = [rake; rakeDfe; bi1; bi2; tr; mfb];
output.errors = zeros(6, 1);
for method = 1:6
    output.errors(method) = bit_errors(decisions(method, :), frame.indices, bits);
end
output.total = numel(bits(frame.indices, :));
if isempty(forward)
    error("SCFDE:ReceiverFailure", "GCCK receiver did not produce a decision.");
end
end

function output = dynamic_dfe_frame(book, bits, channel, cfg, snrDb, alpha)
frame = dynamic_cck_frame(book, channel, cfg, snrDb, alpha);
detected = dfe_detect(frame.received, book, channel, frame.noiseVariance, ...
    cfg.receiverCandidateLimit);
output.errors = bit_errors(detected, frame.indices, bits);
output.total = numel(bits(frame.indices, :));
end

function detected = rake_detect(received, book, channel)
wordLength = size(book, 2);
blockCount = floor((numel(received) - numel(channel) + 1) / wordLength);
padded = [received, zeros(1, numel(channel))];
combined = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    start = (block - 1) * wordLength + 1;
    for tap = 1:numel(channel)
        combined(block, :) = combined(block, :) + conj(channel(tap)) * ...
            padded(start + tap - 1:start + tap + wordLength - 2);
    end
end
detected = nearest_book(combined / max(sum(abs(channel).^2), 1e-8), book);
end

function [detected, scores] = dfe_detect(received, book, channel, noiseVariance, limit)
wordLength = size(book, 2);
blockCount = floor((numel(received) - numel(channel) + 1) / wordLength);
memory = numel(channel) - 1;
state = zeros(1, memory);
detected = zeros(1, blockCount);
scores = -inf(blockCount, size(book, 1));
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = candidate_list(observation, book, min(limit, size(book, 1)));
    local = candidate_scores(observation, state, book(active, :), channel, noiseVariance);
    scores(block, active) = local;
    [~, best] = max(local);
    detected(block) = active(best);
    state = append_channel_state(state, book(detected(block), :), memory);
end
end

function [detected, scores] = backward_dfe_detect(received, book, channel, noiseVariance, limit)
reverseReceived = conj(fliplr(received));
reverseBook = conj(fliplr(book));
reverseChannel = conj(fliplr(channel));
[reverseDetected, reverseScores] = dfe_detect(reverseReceived, reverseBook, ...
    reverseChannel, noiseVariance, limit);
detected = fliplr(reverseDetected);
scores = flipud(reverseScores);
end

function scores = candidate_scores(observation, state, candidates, channel, noiseVariance)
scores = zeros(1, size(candidates, 1));
for index = 1:size(candidates, 1)
    predicted = expected_block(state, candidates(index, :), channel);
    scores(index) = -sum(abs(observation - predicted).^2) / max(noiseVariance, 1e-8);
end
end

function active = candidate_list(observation, book, count)
distance = sum(abs(book - observation).^2, 2);
[~, order] = sort(distance, "ascend");
active = order(1:count).';
end

function output = expected_block(state, word, channel)
memory = numel(channel) - 1;
convolution = conv([state, word], channel);
output = convolution(memory + 1:memory + numel(word));
end

function state = append_channel_state(state, samples, memory)
combined = [state, samples];
state = combined(end - memory + 1:end);
end

function detected = fuse_scores(forwardScores, backwardScores)
combined = forwardScores - max(forwardScores, [], 2) + ...
    backwardScores - max(backwardScores, [], 2);
[~, detected] = max(combined, [], 2);
detected = detected.';
end

function detected = bidirectional_refine(received, book, channel, initial, noiseVariance, limit)
wordLength = size(book, 2);
memory = numel(channel) - 1;
forwardScores = -inf(numel(initial), size(book, 1));
state = zeros(1, memory);
for block = 1:numel(initial)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = candidate_list(observation, book, min(limit, size(book, 1)));
    forwardScores(block, active) = candidate_scores(observation, state, ...
        book(active, :), channel, noiseVariance);
    state = append_channel_state(state, book(initial(block), :), memory);
end
reverseScores = feedback_scores(conj(fliplr(received)), conj(fliplr(book)), ...
    conj(fliplr(channel)), fliplr(initial), noiseVariance, limit);
detected = fuse_scores(forwardScores, flipud(reverseScores));
end

function scores = feedback_scores(received, book, channel, decisions, noiseVariance, limit)
wordLength = size(book, 2);
memory = numel(channel) - 1;
scores = -inf(numel(decisions), size(book, 1));
state = zeros(1, memory);
for block = 1:numel(decisions)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = candidate_list(observation, book, min(limit, size(book, 1)));
    scores(block, active) = candidate_scores(observation, state, ...
        book(active, :), channel, noiseVariance);
    state = append_channel_state(state, book(decisions(block), :), memory);
end
end

function detected = tr_diversity_detect(received, book, channel, noiseVariance)
wordLength = size(book, 2);
memory = numel(channel) - 1;
channels = [channel; conj(fliplr(channel))];
combined = zeros(1, numel(received));
for branch = 1:2
    focused = filter(conj(fliplr(channels(branch, :))), 1, received);
    delay = numel(channel) - 1;
    alignedLength = numel(received) - delay;
    combined(1:alignedLength) = combined(1:alignedLength) + ...
        focused(delay + (1:alignedLength)) / ...
        sum(abs(channels(branch, :)).^2);
end
usable = floor((numel(received) - memory) / wordLength) * wordLength;
combined = combined(1:usable);
blocks = reshape(combined / 2, wordLength, []).';
detected = nearest_book(blocks, book);
end

function detected = matched_filter_detect(received, book, channel)
memory = numel(channel) - 1;
focused = filter(conj(fliplr(channel)), 1, received);
aligned = focused(memory + (1:(numel(received) - memory)));
blockCount = floor(numel(aligned) / size(book, 2));
blocks = reshape(aligned(1:blockCount * size(book, 2)), size(book, 2), []).';
detected = nearest_book(blocks, book);
end

function detected = genie_dfe_detect(received, chips, book, channel, noiseVariance, limit)
wordLength = size(book, 2);
blockCount = floor(numel(chips) / wordLength);
memory = numel(channel) - 1;
state = zeros(1, memory);
detected = zeros(1, blockCount);
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = candidate_list(observation, book, min(limit, size(book, 1)));
    score = candidate_scores(observation, state, book(active, :), channel, noiseVariance);
    [~, best] = max(score);
    detected(block) = active(best);
    known = chips((block - 1) * wordLength + (1:wordLength));
    state = append_channel_state(state, known, memory);
end
end

function [detected, history] = fde_cck_detect(received, book, channel, noiseVariance, iterations)
wordLength = size(book, 2);
blockCount = floor((numel(received) - numel(channel) + 1) / wordLength);
lengthFrame = blockCount * wordLength;
received = received(1:lengthFrame);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
soft = zeros(1, lengthFrame);
history = zeros(iterations, blockCount);
residualEnergy = inf(1, iterations);
for iteration = 1:iterations
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    C = conj(H) ./ (noiseVariance + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    [detected, softWord] = soft_book_detect(blocks, book, noiseVariance);
    candidateSoft = 0.65 * soft + 0.35 * reshape(softWord.', 1, []);
    reconstructed = filter(channel, 1, candidateSoft);
    residualEnergy(iteration) = mean(abs(received - reconstructed).^2);
    if iteration > 1 && residualEnergy(iteration) > residualEnergy(iteration - 1)
        residualEnergy(iteration) = residualEnergy(iteration - 1);
        history(iteration, :) = history(iteration - 1, :);
    else
        history(iteration, :) = detected;
        soft = candidateSoft;
    end
end
end

function [detected, softWord] = soft_book_detect(observations, book, noiseVariance)
detected = zeros(1, size(observations, 1));
softWord = complex(zeros(size(observations)));
for index = 1:size(observations, 1)
    distance = sum(abs(book - observations(index, :)).^2, 2);
    [minimum, detected(index)] = min(distance);
    weights = exp(-(distance - minimum) / max(noiseVariance, 1e-8));
    weights = weights / sum(weights);
    softWord(index, :) = weights.' * book;
end
end

function [errors, total] = dsss_fde_frame(cfg, channel, snrDb, spreading, alpha)
symbols = cfg.symbols;
bits = randi([0, 1], symbols, 2);
qpsk = (1 - 2 * bits(:, 1) + 1j * (1 - 2 * bits(:, 2))) / sqrt(2);
pn = sign(sin((1:spreading) * 1.71));
chips = reshape((qpsk * pn) / sqrt(spreading), 1, []);
noiseVariance = 10^(-snrDb / 10);
if alpha < 1
    dynamic = dynamic_filter(chips, channel, spreading, alpha);
else
    dynamic = filter(channel, 1, chips);
end
lengthFrame = numel(chips);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
received = dynamic + sqrt(noiseVariance / 2) * ...
    (randn(size(dynamic)) + 1j * randn(size(dynamic)));
equalized = ifft(conj(H) ./ (abs(H).^2 + noiseVariance) .* fft(received));
estimate = reshape(equalized, spreading, []).' * pn.' / sqrt(spreading);
detectedBits = [real(estimate) < 0, imag(estimate) < 0];
errors = sum(detectedBits ~= bits, "all");
total = numel(bits);
end

function output = dynamic_filter(chips, channel, blockLength, alpha)
memory = numel(channel) - 1;
blockCount = floor(numel(chips) / blockLength);
state = zeros(1, memory);
output = complex(zeros(1, numel(chips)));
current = channel;
profile = sqrt(abs(channel).^2 + 1e-8);
for block = 1:blockCount
    innovation = profile .* (randn(size(channel)) + 1j * randn(size(channel))) / sqrt(2);
    current = alpha * current + sqrt(max(0, 1 - alpha^2)) * innovation;
    positions = (block - 1) * blockLength + (1:blockLength);
    output(positions) = expected_block(state, chips(positions), current);
    state = append_channel_state(state, chips(positions), memory);
end
end

function [book, bits] = qpsk_word_book()
bits = [0, 0; 1, 0; 0, 1; 1, 1];
symbols = (1 - 2 * bits(:, 1) + 1j * (1 - 2 * bits(:, 2))) / sqrt(2);
book = repmat(symbols, 1, 8) / sqrt(8);
end

function output = sm_ibdfe_frame(book, bits, cfg, snrDb, iterations)
txCount = cfg.smTxAntennas;
rxCount = cfg.smRxAntennas;
book = book * sqrt(size(bits, 2) + log2(txCount));
wordLength = size(book, 2);
blockCount = cfg.symbols;
lengthFrame = blockCount * wordLength;
indices = randi(size(book, 1), 1, blockCount);
activeAntenna = randi(txCount, 1, blockCount);
transmitted = zeros(txCount, lengthFrame);
for block = 1:blockCount
    positions = (block - 1) * wordLength + (1:wordLength);
    transmitted(activeAntenna(block), positions) = book(indices(block), :);
end
channel = mimo_channel(rxCount, txCount);
received = zeros(rxCount, lengthFrame);
for receive = 1:rxCount
    for transmit = 1:txCount
        received(receive, :) = received(receive, :) + ...
            filter(squeeze(channel(receive, transmit, :)).', 1, transmitted(transmit, :));
    end
end
noiseVariance = 10^(-snrDb / 10);
received = received + sqrt(noiseVariance / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
H = mimo_frequency_response(channel, lengthFrame);
Y = fft(received, [], 2);
soft = zeros(txCount, lengthFrame);
output.bitErrors = zeros(1, iterations);
output.indexErrors = zeros(1, iterations);
for iteration = 1:iterations
    Xbar = fft(soft, [], 2);
    equalized = zeros(txCount, lengthFrame);
    for bin = 1:lengthFrame
        h = H(:, :, bin);
        c = (h' * h + noiseVariance * eye(txCount)) \ h';
        b = c * h - eye(txCount);
        equalized(:, bin) = c * Y(:, bin) - b * Xbar(:, bin);
    end
    estimates = ifft(equalized, [], 2);
    detectedIndex = zeros(1, blockCount);
    detectedAntenna = zeros(1, blockCount);
    newSoft = complex(zeros(txCount, lengthFrame));
    for block = 1:blockCount
        positions = (block - 1) * wordLength + (1:wordLength);
        [detectedAntenna(block), detectedIndex(block), softBlock] = ...
            spatial_codeword_detect(estimates(:, positions), book, noiseVariance);
        newSoft(:, positions) = softBlock;
    end
    soft = 0.65 * soft + 0.35 * newSoft;
    output.bitErrors(iteration) = bit_errors(detectedIndex, indices, bits);
    output.indexErrors(iteration) = antenna_bit_errors(detectedAntenna, activeAntenna, txCount);
end
output.totalBits = numel(bits(indices, :)) + blockCount * log2(txCount);
output.totalIndexBits = blockCount * log2(txCount);
end

function channel = mimo_channel(rxCount, txCount)
tapCount = 6;
power = [1, .65, .42, .30, .20, .12];
channel = complex(zeros(rxCount, txCount, tapCount));
for receive = 1:rxCount
    for transmit = 1:txCount
        channel(receive, transmit, :) = sqrt(power / (2 * txCount)) .* ...
            (randn(1, tapCount) + 1j * randn(1, tapCount));
    end
end
end

function response = mimo_frequency_response(channel, lengthFrame)
[rxCount, txCount, tapCount] = size(channel);
response = complex(zeros(rxCount, txCount, lengthFrame));
for receive = 1:rxCount
    for transmit = 1:txCount
        impulse = [squeeze(channel(receive, transmit, :)).', ...
            zeros(1, lengthFrame - tapCount)];
        response(receive, transmit, :) = fft(impulse);
    end
end
end

function [antenna, index, softEstimate] = spatial_codeword_detect( ...
        observation, book, noiseVariance)
candidateCount = size(observation, 1) * size(book, 1);
metric = zeros(1, candidateCount);
antennaList = zeros(1, candidateCount);
indexList = zeros(1, candidateCount);
candidate = 0;
for antennaCandidate = 1:size(observation, 1)
    for indexCandidate = 1:size(book, 1)
        prediction = zeros(size(observation));
        prediction(antennaCandidate, :) = book(indexCandidate, :);
        candidate = candidate + 1;
        metric(candidate) = -sum(abs(observation - prediction).^2, "all") / ...
            max(noiseVariance, 1e-8);
        antennaList(candidate) = antennaCandidate;
        indexList(candidate) = indexCandidate;
    end
end
[maximum, best] = max(metric);
antenna = antennaList(best);
index = indexList(best);
weights = exp(metric - maximum);
weights = weights / sum(weights);
softEstimate = complex(zeros(size(observation)));
for candidate = 1:candidateCount
    softEstimate(antennaList(candidate), :) = ...
        softEstimate(antennaList(candidate), :) + ...
        weights(candidate) * book(indexList(candidate), :);
end
end

function errors = antenna_bit_errors(detected, transmitted, antennaCount)
bitCount = log2(antennaCount);
detectedBits = zeros(numel(detected), bitCount);
transmittedBits = zeros(numel(transmitted), bitCount);
for bit = 1:bitCount
    detectedBits(:, bit) = bitget(detected(:) - 1, bit);
    transmittedBits(:, bit) = bitget(transmitted(:) - 1, bit);
end
errors = sum(detectedBits ~= transmittedBits, "all");
end

function errors = bit_errors(detected, transmitted, bits)
errors = sum(bits(detected, :) ~= bits(transmitted, :), "all");
end

function detected = nearest_book(observations, book)
[~, detected] = min(sum(abs(observations).^2, 2) + sum(abs(book).^2, 2).' - ...
    2 * real(observations * book'), [], 2);
detected = detected.';
end

function correlation = aperiodic_autocorrelation(word)
lengthWord = numel(word);
correlation = zeros(1, 2 * lengthWord - 1);
for lag = -(lengthWord - 1):(lengthWord - 1)
    if lag >= 0
        value = sum(word(1:lengthWord - lag) .* conj(word(1 + lag:end)));
    else
        value = sum(word(1 - lag:end) .* conj(word(1:lengthWord + lag)));
    end
    correlation(lag + lengthWord) = abs(value) / sum(abs(word).^2);
end
end

function [meanValue, percentile95, maximum] = cross_correlation_statistics(book)
canonical = book .* conj(book(:, end));
canonical = canonical ./ sqrt(sum(abs(canonical).^2, 2));
key = [round(real(canonical) * 1e10), round(imag(canonical) * 1e10)];
[~, representatives] = unique(key, "rows");
canonical = canonical(representatives, :);
correlation = abs(canonical * canonical');
correlation(1:size(canonical, 1) + 1:end) = 0;
upperTriangle = correlation(triu(true(size(correlation)), 1));
meanValue = mean(upperTriangle);
percentile95 = quantile(upperTriangle, 0.95);
maximum = max(upperTriangle);
end

function paths = plot_gcck(result, cfg)
paths = [plot_gcck_awgn(result, cfg); plot_gcck_receivers(result, cfg)];
end

function path = plot_gcck_awgn(result, cfg)
path = output_path(cfg, "chapter5_5_gcck_awgn.png");
fig = figure("Color", "w", "Position", [90, 90, 1250, 520], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
legendLabels = strings(2 * numel(result.modeNames), 1);
for index = 1:numel(result.modeNames)
    semilogy(result.snrList, max(result.awgnBer(index, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
    legendLabels(2 * index - 1) = result.modeNames(index) + " 仿真";
    semilogy(result.snrList, max(result.unionBound(index, :), 1e-6), ...
        "--", "LineWidth", 1.0);
    legendLabels(2 * index) = result.modeNames(index) + " 近邻联合界";
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("图5-14 GCCK 在 AWGN 信道中的性能");
legend(legendLabels, "Location", "southwest");
nexttile; stem(0:numel(result.channel) - 1, abs(result.channel), "filled");
grid on; xlabel("码片时延索引"); ylabel("归一化路径幅度");
title("图5-15 3 km 稀疏多径水声信道");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_gcck_receivers(result, cfg)
path = output_path(cfg, "chapter5_5_gcck_receivers.png");
fig = figure("Color", "w", "Position", [70, 70, 1450, 850], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
for mode = 1:numel(result.modeNames)
    nexttile; hold on;
    for method = 1:numel(result.receiverNames)
        semilogy(result.snrList, max(squeeze(result.receiverBer(mode, method, :)).', 1e-6), ...
            "LineWidth", 1.1);
    end
    grid on; xlabel("信噪比 SNR (dB)"); ylabel("BER");
    title("3 km " + result.modeNames(mode) + " 接收机比较");
    legend(result.receiverNames, "Location", "southwest");
end
nexttile; hold on;
for alphaIndex = 1:numel(result.dynamicAlphas)
    semilogy(result.snrList, max(result.dynamicBer(alphaIndex, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("BER");
title("图5-19 时变信道对 GCCK-QPSK-8R 的影响");
legend("相关系数 a=" + string(result.dynamicAlphas), "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_extended(result, cfg)
path = output_path(cfg, "chapter5_5_extended_cck.png");
fig = figure("Color", "w", "Position", [70, 70, 1450, 850], "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for index = 1:numel(result.lengths)
    values = result.autoCorrelation{index};
    lags = -(numel(values) - 1) / 2:(numel(values) - 1) / 2;
    stem(lags, values, "LineWidth", 0.8);
end
grid on; xlabel("码片时延"); ylabel("归一化自相关");
title("图5-22 CCK-8、CCK-16 与 CCK-32 的自相关");
legend("CCK-" + string(result.lengths), "Location", "northeast");
nexttile; hold on;
for index = 1:numel(result.lengths)
    semilogy(result.snrList, max(result.awgnBer(index, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER");
title("图5-23 不同码长扩展 CCK 的 AWGN 性能");
legend("CCK-" + string(result.lengths), "Location", "southwest");
nexttile;
bar(1:numel(result.lengths), result.meanCrossCorrelation);
xticks(1:numel(result.lengths));
xticklabels("CCK-" + string(result.lengths));
grid on; ylabel("平均互相关");
title("扩展 CCK 去等效相位后的平均互相关");
nexttile; hold on;
for method = 1:numel(result.methodNames)
    semilogy(result.dynamicAlphas, max(result.dynamicBer(method, :), 1e-6), ...
        "o-", "LineWidth", 1.1);
end
grid on; xlabel("路径时间相关系数 a"); ylabel("BER");
title("图5-24 时变信道下 CCK、Turbo 与 DSSS 对比");
legend(result.methodNames, "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_turbo(result, cfg)
path = output_path(cfg, "chapter5_5_cck_turbo.png");
fig = figure("Color", "w", "Position", [100, 100, 1200, 500], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for method = 1:numel(result.methodNames)
    semilogy(result.snrList, max(result.ber(method, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("BER");
title("图5-27/5-28 CCK Turbo 与 DSSS 接收机比较");
legend(result.methodNames, "Location", "southwest");
nexttile;
yyaxis left;
plot(1:numel(result.iterationBer), result.iterationBer, "o-", "LineWidth", 1.3);
ylabel("外码信息 BER");
yyaxis right;
plot(1:numel(result.iterationResidual), ...
    result.iterationResidual / result.iterationResidual(1), "s--", "LineWidth", 1.2);
ylabel("归一化残差能量");
grid on; xlabel("CCK Turbo 迭代次数");
title("图5-31 CCK Turbo-IBDFE 外码信息迭代");
legend("外码信息 BER", "归一化残差", "Location", "northeast");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_spatial_modulation(result, cfg)
path = output_path(cfg, "chapter5_5_cck_sm.png");
fig = figure("Color", "w", "Position", [100, 100, 1200, 500], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; hold on;
for method = 1:numel(result.methodNames)
    semilogy(result.snrList, max(result.ber(method, :), 1e-6), ...
        "o-", "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("总比特 BER");
title("图5-30 CCK-SM 与 QPSK-SM 的 MIMO 接收性能");
legend(result.methodNames, "Location", "southwest");
nexttile; hold on;
plot(1:numel(result.exampleBitBer), result.exampleBitBer, "o-", "LineWidth", 1.3);
plot(1:numel(result.exampleIndexBer), result.exampleIndexBer, "s-", "LineWidth", 1.3);
grid on; xlabel("IBDFE 迭代次数"); ylabel("BER");
title("CCK-SM 低信噪比收敛 (SNR=" + ...
    string(result.diagnosticSnrDb) + " dB)");
legend("CCK 码字比特", "空间索引比特", "Location", "northeast");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = output_path(cfg, filename)
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
path = fullfile(cfg.outputDir, filename);
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
