function results = run_chapter5_cck_suite_impl(options, simulationDir)
%RUN_CHAPTER5_CCK_SUITE_IMPL CCK simulations for Chapter 5 Sections 5.1-5.3.

defaults.snrList = 0:3:15;
defaults.snrDb = 9;
defaults.symbols = 48;
defaults.frameCount = 3;
defaults.randomSeed = 20260724;
defaults.turboIterations = 4;
defaults.mapStateList = 256;
defaults.reducedStateList = 32;
defaults.rsseTrellisStates = 4;
defaults.turboOuterCode = "repetition-1/2";
defaults.turboDamping = 0.75;
defaults.modulationMethods = "all";
defaults.isiMethods = "all";
defaults.isiModulation = "FR-CCK";
defaults.turboMethods = "all";
defaults.makePlot = true;
defaults.runAwgn = true;
defaults.runIsi = true;
defaults.runTurbo = true;
defaults.normalizeIsiChannel = true;
defaults.receiverSnrDefinition = "EsN0";
defaults.isiReceiverProfile = "generic";
defaults.receiverBranchCount = 1;
defaults.receiverChannel = [];
defaults.fastSingleDfe = false;
defaults.fastTrDiversity2 = false;
defaults.timeVaryingCorrelation = 1;
defaults.timeVaryingInnovationScale = 1;
defaults.isiChannel = [1, 0.62 * exp(1j * 0.5), ...
    0.30 * exp(-1j * 1.0)];
defaults.outputDir = fullfile(simulationDir, "results");
cfg = merge_options(defaults, options);
cfg.isiChannel = cfg.isiChannel(:).';
if cfg.normalizeIsiChannel
    cfg.isiChannel = cfg.isiChannel / norm(cfg.isiChannel);
end
if isempty(cfg.receiverChannel)
    cfg.receiverChannel = cfg.isiChannel;
else
    cfg.receiverChannel = cfg.receiverChannel(:).';
end

modulationNames = ["FR-CCK", "HR-CCK", "GCCK-QPSK-4R", ...
    "GCCK-QPSK-8R", "GCCK-8PSK-12R", "Extended-CCK"];
if strcmpi(string(cfg.isiReceiverProfile), "gcckFigure517")
    isiNames = ["Rake", "Rake-DFE", "BiDFE-1", ...
        "BiDFE-2 (1 iteration)", "BiDFE-2 (2 iterations)", ...
        "TR-Diversity (1 iteration)", "TR-Diversity (2 iterations)", ...
        "MFB", "BPSK-MMSE"];
elseif strcmpi(string(cfg.isiReceiverProfile), "gcckFigure518")
    isiNames = ["Rake", "Rake-DFE", "BiDFE-1", "BiDFE-2", ...
        "TR-Diversity-2R", "MFB"];
else
    isiNames = ["MLD", "Rake", "DFE", "BiDFE-1", "BiDFE-2", "TR-Rake"];
end
turboNames = ["MAP-CCK-TE", "RSSE-CCK-TE"];
modulationIndices = select_indices(modulationNames, cfg.modulationMethods, ...
    "CCK modulation");
isiIndices = select_indices(isiNames, cfg.isiMethods, "ISI receiver");
turboIndices = select_indices(turboNames, cfg.turboMethods, "CCK Turbo detector");
assert(cfg.symbols > 0 && cfg.frameCount > 0, ...
    "SCFDE:InvalidFrameConfig", "symbols and frameCount must be positive.");
assert(cfg.turboIterations > 0 && cfg.mapStateList > 0 && ...
    cfg.reducedStateList > 0 && cfg.rsseTrellisStates > 0, ...
    "SCFDE:InvalidTurboConfig", "Turbo parameters must be positive.");
assert(any(strcmpi(string(cfg.turboOuterCode), ["none", "repetition-1/2"])), ...
    "SCFDE:InvalidTurboOuterCode", ...
    "turboOuterCode must be none or repetition-1/2.");

rng(cfg.randomSeed, "twister");
books = cell(1, numel(modulationNames));
bitTables = cell(1, numel(modulationNames));
codeInfo = repmat(struct("name", "", "bitsPerWord", 0, ...
    "chipsPerWord", 0, "phaseOrder", 0, "standard", false), ...
    1, numel(modulationNames));
for index = 1:numel(modulationNames)
    [books{index}, bitTables{index}, codeInfo(index)] = ...
        make_cck_codebook(modulationNames(index));
end
baseIndex = find(modulationNames == "FR-CCK", 1);
baseBook = books{baseIndex};
baseBits = bitTables{baseIndex};
isiIndex = find(modulationNames == string(cfg.isiModulation), 1);
assert(~isempty(isiIndex), "SCFDE:UnknownIsiModulation", ...
    "Unknown ISI modulation: %s", string(cfg.isiModulation));
isiBook = books{isiIndex};
isiBits = bitTables{isiIndex};
trellis = make_trellis(isiBook, cfg.receiverChannel);

allAwgnBer = nan(numel(modulationNames), numel(cfg.snrList));
allIsiBer = nan(numel(isiNames), numel(cfg.snrList));
allTurboBer = nan(numel(turboNames), numel(cfg.snrList));
allIsiErrorCounts = zeros(numel(isiNames), numel(cfg.snrList));
allIsiBitTotals = zeros(1, numel(cfg.snrList));
allIsiFrameErrorCounts = zeros(numel(isiNames), numel(cfg.snrList));
allIsiFrameTotals = zeros(1, numel(cfg.snrList));
for snrIndex = 1:numel(cfg.snrList)
    awgnErrors = zeros(numel(modulationNames), 1);
    awgnTotals = zeros(numel(modulationNames), 1);
    isiErrors = zeros(numel(isiNames), 1);
    isiFrameErrors = zeros(numel(isiNames), 1);
    turboErrors = zeros(numel(turboNames), 1);
    isiTotal = 0;
    isiFrameTotal = 0;
    turboTotal = 0;
    for frameIndex = 1:cfg.frameCount
        if cfg.runAwgn
            for modulationIndex = 1:numel(modulationNames)
                [errors, total] = simulate_awgn(books{modulationIndex}, ...
                    bitTables{modulationIndex}, cfg.symbols, cfg.snrList(snrIndex));
                awgnErrors(modulationIndex) = awgnErrors(modulationIndex) + errors;
                awgnTotals(modulationIndex) = awgnTotals(modulationIndex) + total;
            end
        end
        if cfg.runIsi
            [errors, total] = simulate_isi(isiBook, isiBits, trellis, cfg, ...
                cfg.snrList(snrIndex));
            if cfg.fastSingleDfe || cfg.fastTrDiversity2
                isiErrors(isiIndices) = isiErrors(isiIndices) + errors;
                isiFrameErrors(isiIndices) = isiFrameErrors(isiIndices) + (errors > 0);
            else
                isiErrors = isiErrors + errors;
                isiFrameErrors = isiFrameErrors + (errors > 0);
            end
            isiTotal = isiTotal + total;
            isiFrameTotal = isiFrameTotal + 1;
        end
        if cfg.runTurbo
            [errors, total] = simulate_turbo(baseBook, baseBits, trellis, cfg, ...
                cfg.snrList(snrIndex));
            turboErrors = turboErrors + errors;
            turboTotal = turboTotal + total;
        end
    end
    if cfg.runAwgn
        allAwgnBer(:, snrIndex) = awgnErrors ./ awgnTotals;
    end
    if cfg.runIsi
        allIsiBer(:, snrIndex) = isiErrors / isiTotal;
        allIsiErrorCounts(:, snrIndex) = isiErrors;
        allIsiBitTotals(snrIndex) = isiTotal;
        allIsiFrameErrorCounts(:, snrIndex) = isiFrameErrors;
        allIsiFrameTotals(snrIndex) = isiFrameTotal;
    end
    if cfg.runTurbo
        allTurboBer(:, snrIndex) = turboErrors / turboTotal;
    end
end

if isfield(cfg, "skipDiagnostics") && cfg.skipDiagnostics
    diagnostics = struct();
else
    diagnostics = diagnostic_frame(baseBook, baseBits, trellis, cfg);
end
results.config = cfg;
results.availableModulationMethods = modulationNames;
results.modulationIndices = modulationIndices;
results.names = modulationNames(modulationIndices);
results.awgnBer = allAwgnBer(modulationIndices, :);
results.allAwgnBer = allAwgnBer;
results.availableIsiMethods = isiNames;
results.isiIndices = isiIndices;
results.isiMethodNames = isiNames(isiIndices);
results.isiBer = allIsiBer(isiIndices, :);
results.allIsiBer = allIsiBer;
results.isiErrorCounts = allIsiErrorCounts(isiIndices, :);
results.allIsiErrorCounts = allIsiErrorCounts;
results.isiBitTotals = allIsiBitTotals;
results.isiFrameErrorCounts = allIsiFrameErrorCounts(isiIndices, :);
results.allIsiFrameErrorCounts = allIsiFrameErrorCounts;
results.isiFrameTotals = allIsiFrameTotals;
results.availableTurboMethods = turboNames;
results.turboIndices = turboIndices;
results.turboMethodNames = turboNames(turboIndices);
results.turboBer = allTurboBer(turboIndices, :);
results.allTurboBer = allTurboBer;
results.snrList = cfg.snrList;
results.codeInfo = codeInfo(modulationIndices);
results.frBook = baseBook;
results.frBits = baseBits;
results.isiModulation = string(cfg.isiModulation);
results.isiBook = isiBook;
results.isiBits = isiBits;
results.trellis = trellis;
results.diagnostics = diagnostics;
results.smBer = nan(size(cfg.snrList));
results.outputPath = "";
results.figurePaths = strings(0, 1);
if cfg.makePlot
    results.outputPath = plot_sections(results);
    results.figurePaths = [string(results.outputPath); plot_isi_detail(results)];
end
end

function [book, bits, info] = make_cck_codebook(name)
name = string(name);
switch name
    case "FR-CCK"
        bitCount = 8; phaseOrder = 4; wordLength = 8; standard = true;
    case "HR-CCK"
        bitCount = 4; phaseOrder = 4; wordLength = 8; standard = true;
    case "GCCK-QPSK-4R"
        bitCount = 4; phaseOrder = 4; wordLength = 8; standard = false;
    case "GCCK-QPSK-8R"
        bitCount = 8; phaseOrder = 4; wordLength = 8; standard = false;
    case "GCCK-8PSK-12R"
        bitCount = 12; phaseOrder = 8; wordLength = 8; standard = false;
    case "Extended-CCK"
        bitCount = 8; phaseOrder = 4; wordLength = 16; standard = false;
    otherwise
        error("SCFDE:UnknownCCK", "Unknown CCK mode: %s", name);
end
M = 2^bitCount;
bits = zeros(M, bitCount);
book = complex(zeros(M, wordLength));
for index = 0:M - 1
    rowBits = bitget(index, 1:bitCount);
    bits(index + 1, :) = rowBits;
    word = cck_word(cck_phases(name, rowBits));
    if wordLength == 16
        [A, ~] = golay_complementary_pair(2);
        extension = [A, -A];
        word = [word, word] .* extension;
    end
    book(index + 1, :) = word / sqrt(wordLength);
end
info = struct("name", name, "bitsPerWord", bitCount, ...
    "chipsPerWord", wordLength, "phaseOrder", phaseOrder, "standard", standard);
end

function phase = cck_phases(name, bits)
qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
switch string(name)
    case {"FR-CCK", "GCCK-QPSK-8R", "Extended-CCK"}
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

function [A, B] = golay_complementary_pair(levels)
% 书 (5-8)(5-9): Golay 互补对递推 A_k=[A_{k-1} B_{k-1}], B_k=[A_{k-1} -B_{k-1}]
% 种子 A_1=[1 1], B_1=[1 -1]
A = [1, 1];
B = [1, -1];
for level = 1:levels
    nextA = [A, B];
    nextB = [A, -B];
    A = nextA;
    B = nextB;
end
end

function word = cck_word(phase)
phi1 = phase(1); phi2 = phase(2); phi3 = phase(3); phi4 = phase(4);
word = exp(1j * [phi1 + phi2 + phi3 + phi4, phi1 + phi3 + phi4, ...
    phi1 + phi2 + phi4, phi1 + phi4, phi1 + phi2 + phi3, phi1 + phi3, ...
    phi1 + phi2, phi1]);
word([4, 7]) = -word([4, 7]);
end

function [errors, total] = simulate_awgn(book, bits, count, snrDb)
indices = randi(size(book, 1), 1, count);
transmitted = book(indices, :);
noiseVariance = 10^(-snrDb / 10);
received = transmitted + sqrt(noiseVariance / 2) * ...
    (randn(size(transmitted)) + 1j * randn(size(transmitted)));
detected = nearest_book(received, book);
errors = sum(bits(detected, :) ~= bits(indices, :), "all");
total = numel(bits(indices, :));
end

function [errors, total] = simulate_isi(book, bits, trellis, cfg, snrDb)
[indices, received, noiseVariance] = raw_isi_frame(book, bits, cfg, snrDb);
primaryReceived = received(1, :);
if cfg.fastSingleDfe
    assert(isscalar(cfg.isiMethods) && strcmpi(string(cfg.isiMethods), "DFE"), ...
        "SCFDE:FastDfeSelection", ...
        "fastSingleDfe requires isiMethods to be the single method DFE.");
    dfe = dfe_detect(primaryReceived, book, cfg.receiverChannel, noiseVariance);
    errors = sum(bits(dfe, :) ~= bits(indices, :), "all");
    total = numel(bits(indices, :));
    return;
end
if cfg.fastTrDiversity2
    assert(strcmpi(string(cfg.isiReceiverProfile), "gcckFigure517") && ...
        isscalar(cfg.isiMethods) && ...
        strcmpi(string(cfg.isiMethods), "TR-Diversity (2 iterations)"), ...
        "SCFDE:FastTrDiversitySelection", ...
        "fastTrDiversity2 requires the Figure 5-17 profile and TR-Diversity (2 iterations).");
    initial = tr_diversity_detect(received, book, cfg.receiverChannel);
    firstPass = diversity_bidirectional_refine(received, book, ...
        cfg.receiverChannel, initial, noiseVariance);
    secondPass = diversity_bidirectional_refine(received, book, ...
        cfg.receiverChannel, firstPass, noiseVariance);
    errors = sum(bits(secondPass, :) ~= bits(indices, :), "all");
    total = numel(bits(indices, :));
    return;
end
rake = rake_detect(primaryReceived, book, cfg.receiverChannel);
[dfe, forwardScores] = dfe_detect(primaryReceived, book, cfg.receiverChannel, noiseVariance);
[~, backwardScores] = backward_dfe_detect(primaryReceived, book, ...
    cfg.receiverChannel, noiseVariance);
biDfe1 = fuse_scores(forwardScores, backwardScores);
biDfe2 = bidirectional_refine(primaryReceived, book, cfg.receiverChannel, ...
    biDfe1, noiseVariance);
if strcmpi(string(cfg.isiReceiverProfile), "gcckFigure517")
    biDfe2Second = bidirectional_refine(primaryReceived, book, cfg.receiverChannel, ...
        biDfe2, noiseVariance);
    trDiversityInitial = tr_diversity_detect(received, book, cfg.receiverChannel);
    trDiversityFirst = diversity_bidirectional_refine(received, book, ...
        cfg.receiverChannel, trDiversityInitial, noiseVariance);
    trDiversitySecond = diversity_bidirectional_refine(received, book, ...
        cfg.receiverChannel, trDiversityFirst, noiseVariance);
    mfb = mfb_detect(indices, book, cfg.receiverChannel, noiseVariance, size(received, 1));
    [bpskErrors, bpskTotal] = bpsk_mmse_frame(cfg, snrDb, size(bits, 2));
    decisions = [rake; dfe; biDfe1; biDfe2; biDfe2Second; ...
        trDiversityFirst; trDiversitySecond; mfb];
    errors = zeros(9, 1);
    for method = 1:size(decisions, 1)
        errors(method) = sum(bits(decisions(method, :), :) ~= bits(indices, :), "all");
    end
    errors(9) = bpskErrors;
    total = numel(bits(indices, :));
    assert(total == bpskTotal, "SCFDE:BpskRateMismatch", ...
        "The BPSK-MMSE baseline must carry the same number of information bits.");
    return;
elseif strcmpi(string(cfg.isiReceiverProfile), "gcckFigure518")
    trDiversity = tr_diversity_detect(received, book, cfg.receiverChannel);
    mfb = mfb_detect(indices, book, cfg.receiverChannel, noiseVariance, 1);
    decisions = [rake; dfe; biDfe1; biDfe2; trDiversity; mfb];
else
    mld = dfe;
    if isfield(trellis, "supportsMld") && trellis.supportsMld
        mld = viterbi_mld(primaryReceived, book, trellis, noiseVariance);
    end
    trRake = time_reversal_rake(primaryReceived, book, cfg.receiverChannel);
    decisions = [mld; rake; dfe; biDfe1; biDfe2; trRake];
end
errors = zeros(size(decisions, 1), 1);
for method = 1:size(decisions, 1)
    errors(method) = sum(bits(decisions(method, :), :) ~= bits(indices, :), "all");
end
total = numel(bits(indices, :));
end

function [indices, received, noiseVariance] = raw_isi_frame(book, bits, cfg, snrDb)
indices = randi(size(book, 1), 1, cfg.symbols);
chips = reshape(book(indices, :).', 1, []);
noiseVariance = receiver_noise_variance(book, bits, cfg, snrDb);
memory = numel(cfg.isiChannel) - 1;
branchCount = max(1, round(cfg.receiverBranchCount));
if cfg.timeVaryingCorrelation < 1
    clean = time_varying_filter(chips, cfg.isiChannel, ...
        cfg.timeVaryingCorrelation, cfg.timeVaryingInnovationScale);
else
    clean = filter(cfg.isiChannel, 1, [chips, zeros(1, memory)]);
end
received = repmat(clean, branchCount, 1) + sqrt(noiseVariance / 2) * ...
    (randn(branchCount, numel(clean)) + 1j * randn(branchCount, numel(clean)));
end

function output = time_varying_filter(chips, referenceChannel, correlation, innovationScale)
memory = numel(referenceChannel) - 1;
input = [chips, zeros(1, memory)];
output = complex(zeros(size(input)));
channel = referenceChannel;
active = abs(referenceChannel) > 0;
for sample = 1:numel(input)
    innovation = complex(zeros(size(referenceChannel)));
    innovation(active) = innovationScale * abs(referenceChannel(active)) .* ...
        (randn(1, sum(active)) + 1j * randn(1, sum(active))) / sqrt(2);
    channel = correlation * channel + sqrt(1 - correlation^2) * innovation;
    firstTap = max(1, sample - memory);
    taps = 0:sample - firstTap;
    output(sample) = sum(channel(taps + 1) .* input(sample - taps));
end
end

function noiseVariance = receiver_noise_variance(book, bits, cfg, snrDb)
wordEnergy = mean(sum(abs(book).^2, 2));
switch lower(string(cfg.receiverSnrDefinition))
    case "ebn0"
        referenceEnergy = wordEnergy / size(bits, 2);
    case "esn0"
        referenceEnergy = wordEnergy;
    case "chipsnr"
        referenceEnergy = wordEnergy / size(book, 2);
    otherwise
        error("SCFDE:UnknownSnrDefinition", ...
            "receiverSnrDefinition must be EbN0, EsN0, or ChipSNR.");
end
noiseVariance = referenceEnergy * 10^(-snrDb / 10);
end

function trellis = make_trellis(book, channel)
memory = numel(channel) - 1;
trellis.supportsMld = memory < size(book, 2);
if ~trellis.supportsMld
    trellis.channel = channel;
    trellis.memory = memory;
    trellis.tailStates = zeros(0, memory);
    trellis.codeState = zeros(1, size(book, 1));
    return;
end
tails = book(:, end - memory + 1:end);
key = [round(real(tails) * 1e10), round(imag(tails) * 1e10)];
[~, representative, codeState] = unique(key, "rows");
trellis.channel = channel;
trellis.memory = memory;
trellis.tailStates = tails(representative, :);
trellis.codeState = codeState.';
end

function detected = viterbi_mld(received, book, trellis, noiseVariance)
wordLength = size(book, 2);
blockCount = receiver_block_count(received, wordLength, trellis.memory);
stateCount = size(trellis.tailStates, 1);
pathMetric = inf(1, stateCount);
predecessor = zeros(blockCount, stateCount);
survivor = zeros(blockCount, stateCount);
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    nextMetric = inf(1, stateCount);
    for candidate = 1:size(book, 1)
        nextState = trellis.codeState(candidate);
        if block == 1
            predicted = expected_block(zeros(1, trellis.memory), ...
                book(candidate, :), trellis.channel);
            metric = squared_distance(observation, predicted) / noiseVariance;
            if metric < nextMetric(nextState)
                nextMetric(nextState) = metric;
                survivor(block, nextState) = candidate;
            end
        else
            for previousState = 1:stateCount
                predicted = expected_block(trellis.tailStates(previousState, :), ...
                    book(candidate, :), trellis.channel);
                metric = pathMetric(previousState) + ...
                    squared_distance(observation, predicted) / noiseVariance;
                if metric < nextMetric(nextState)
                    nextMetric(nextState) = metric;
                    predecessor(block, nextState) = previousState;
                    survivor(block, nextState) = candidate;
                end
            end
        end
    end
    pathMetric = nextMetric;
end
[~, state] = min(pathMetric);
detected = zeros(1, blockCount);
for block = blockCount:-1:1
    detected(block) = survivor(block, state);
    if block > 1
        state = predecessor(block, state);
    end
end
end

function detected = rake_detect(received, book, channel)
wordLength = size(book, 2);
blockCount = receiver_block_count(received, wordLength, numel(channel) - 1);
padded = [received, zeros(1, numel(channel))];
combined = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    start = (block - 1) * wordLength + 1;
    for tap = 1:numel(channel)
        combined(block, :) = combined(block, :) + conj(channel(tap)) * ...
            padded(start + tap - 1:start + tap + wordLength - 2);
    end
end
detected = nearest_book(combined / sum(abs(channel).^2), book);
end

function [detected, scores] = dfe_detect(received, book, channel, noiseVariance)
wordLength = size(book, 2);
memory = numel(channel) - 1;
blockCount = receiver_block_count(received, wordLength, memory);
state = complex(zeros(1, numel(channel) - 1));
detected = zeros(1, blockCount);
scores = zeros(blockCount, size(book, 1));
wordResponse = filter(channel, 1, book, [], 2);
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    scores(block, :) = candidate_scores_from_response(observation, state, ...
        wordResponse, channel, noiseVariance);
    [~, detected(block)] = max(scores(block, :));
    state = append_feedback_state(state, book(detected(block), :), memory);
end
end

function [detected, scores] = backward_dfe_detect(received, book, channel, noiseVariance)
reverseReceived = conj(fliplr(received));
reverseBook = conj(fliplr(book));
reverseChannel = conj(fliplr(channel));
[reverseDetected, reverseScores] = dfe_detect(reverseReceived, reverseBook, ...
    reverseChannel, noiseVariance);
detected = fliplr(reverseDetected);
scores = flipud(reverseScores);
end

function scores = candidate_scores(observation, state, book, channel, noiseVariance)
wordResponse = filter(channel, 1, book, [], 2);
scores = candidate_scores_from_response(observation, state, wordResponse, ...
    channel, noiseVariance);
end

function scores = candidate_scores_from_response(observation, state, wordResponse, channel, noiseVariance)
memory = numel(channel) - 1;
wordLength = size(wordResponse, 2);
stateResponse = filter(channel, 1, [state, zeros(1, wordLength)]);
stateResponse = stateResponse(memory + 1:memory + wordLength);
residual = wordResponse + stateResponse - observation;
scores = -sum(abs(residual).^2, 2).' / max(noiseVariance, 1e-12);
end

function detected = fuse_scores(forwardScores, backwardScores)
combined = forwardScores - max(forwardScores, [], 2) + ...
    backwardScores - max(backwardScores, [], 2);
[~, detected] = max(combined, [], 2);
detected = detected.';
end

function detected = bidirectional_refine(received, book, channel, initial, noiseVariance)
wordLength = size(book, 2);
blockCount = numel(initial);
memory = numel(channel) - 1;
forwardScores = zeros(blockCount, size(book, 1));
state = complex(zeros(1, memory));
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    forwardScores(block, :) = candidate_scores(observation, state, book, ...
        channel, noiseVariance);
    state = append_feedback_state(state, book(initial(block), :), memory);
end
reverseScores = feedback_scores(conj(fliplr(received)), conj(fliplr(book)), ...
    conj(fliplr(channel)), fliplr(initial), noiseVariance);
detected = fuse_scores(forwardScores, flipud(reverseScores));
end

function scores = feedback_scores(received, book, channel, decisions, noiseVariance)
wordLength = size(book, 2);
scores = zeros(numel(decisions), size(book, 1));
memory = numel(channel) - 1;
state = complex(zeros(1, memory));
wordResponse = filter(channel, 1, book, [], 2);
for block = 1:numel(decisions)
    observation = received((block - 1) * wordLength + (1:wordLength));
    scores(block, :) = candidate_scores_from_response(observation, state, ...
        wordResponse, channel, noiseVariance);
    state = append_feedback_state(state, book(decisions(block), :), memory);
end
end

function detected = diversity_bidirectional_refine(received, book, channel, initial, noiseVariance)
if isvector(received)
    received = received(:).';
end
forwardScores = diversity_feedback_scores(received, book, channel, initial, ...
    noiseVariance);
reverseScores = diversity_feedback_scores(conj(fliplr(received)), ...
    conj(fliplr(book)), conj(fliplr(channel)), fliplr(initial), noiseVariance);
detected = fuse_scores(forwardScores, flipud(reverseScores));
end

function scores = diversity_feedback_scores(received, book, channel, decisions, noiseVariance)
scores = zeros(numel(decisions), size(book, 1));
for branch = 1:size(received, 1)
    scores = scores + feedback_scores(received(branch, :), book, channel, ...
        decisions, noiseVariance);
end
end

function detected = time_reversal_rake(received, book, channel)
wordLength = size(book, 2);
blockCount = receiver_block_count(received, wordLength, numel(channel) - 1);
focused = filter(conj(fliplr(channel)), 1, received);
delay = numel(channel) - 1;
blocks = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    positions = delay + (block - 1) * wordLength + (1:wordLength);
    blocks(block, :) = focused(positions);
end
detected = nearest_book(blocks / sum(abs(channel).^2), book);
end

function detected = tr_diversity_detect(received, book, channel)
if isvector(received)
    received = received(:).';
end
wordLength = size(book, 2);
memory = numel(channel) - 1;
blockCount = receiver_block_count(received(1, :), wordLength, memory);
branchCount = size(received, 1);
combined = complex(zeros(blockCount, wordLength));
for branch = 1:branchCount
    focused = filter(conj(fliplr(channel)), 1, received(branch, :));
    for block = 1:blockCount
        positions = memory + (block - 1) * wordLength + (1:wordLength);
        combined(block, :) = combined(block, :) + focused(positions) / ...
            sum(abs(channel).^2);
    end
end
detected = nearest_book(combined / branchCount, book);
end

function detected = mfb_detect(indices, book, channel, noiseVariance, branchCount)
channelEnergy = sum(abs(channel).^2);
effectiveNoiseVariance = noiseVariance / (branchCount * channelEnergy);
idealObservations = book(indices, :) + sqrt(effectiveNoiseVariance / 2) * ...
    (randn(numel(indices), size(book, 2)) + ...
    1j * randn(numel(indices), size(book, 2)));
detected = nearest_book(idealObservations, book);
end

function detected = genie_dfe_detect(received, indices, book, channel, noiseVariance)
if isvector(received)
    received = received(:).';
end
wordLength = size(book, 2);
memory = numel(channel) - 1;
blockCount = receiver_block_count(received(1, :), wordLength, memory);
state = complex(zeros(1, memory));
detected = zeros(1, blockCount);
for block = 1:blockCount
    positions = (block - 1) * wordLength + (1:wordLength);
    scores = diversity_candidate_scores(received(:, positions), state, book, ...
        channel, noiseVariance);
    [~, detected(block)] = max(scores);
    state = append_feedback_state(state, book(indices(block), :), memory);
end
end

function scores = diversity_candidate_scores(observations, state, book, channel, noiseVariance)
scores = zeros(1, size(book, 1));
for branch = 1:size(observations, 1)
    scores = scores + candidate_scores(observations(branch, :), state, book, ...
        channel, noiseVariance);
end
end

function [errors, total] = bpsk_mmse_frame(cfg, snrDb, bitsPerCckWord)
total = cfg.symbols * bitsPerCckWord;
transmittedBits = randi([0, 1], 1, total);
transmittedSymbols = 2 * transmittedBits - 1;
channel = cfg.isiChannel;
channelMemory = numel(channel) - 1;
noiseVariance = 10^(-snrDb / 10);
received = filter(channel, 1, [transmittedSymbols, zeros(1, channelMemory)]) + ...
    sqrt(noiseVariance / 2) * ...
    (randn(1, total + channelMemory) + 1j * randn(1, total + channelMemory));
equalizer = bpsk_mmse_equalizer(channel, noiseVariance, 21, channelMemory);
estimatedSymbols = zeros(1, total);
for bitIndex = 1:total
    observationIndex = bitIndex + channelMemory;
    sampleIndices = observationIndex - (0:numel(equalizer) - 1);
    observation = complex(zeros(numel(equalizer), 1));
    valid = sampleIndices >= 1;
    observation(valid) = received(sampleIndices(valid)).';
    estimatedSymbols(bitIndex) = real(equalizer' * observation);
end
detectedBits = estimatedSymbols >= 0;
errors = sum(detectedBits ~= transmittedBits);
end

function equalizer = bpsk_mmse_equalizer(channel, noiseVariance, equalizerLength, delay)
channelLength = numel(channel);
channelMatrix = complex(zeros(equalizerLength, equalizerLength + channelLength - 1));
for outputIndex = 1:equalizerLength
    channelMatrix(outputIndex, outputIndex + (0:channelLength - 1)) = channel;
end
crossCorrelation = channelMatrix(:, delay + 1);
covariance = channelMatrix * channelMatrix' + noiseVariance * eye(equalizerLength);
equalizer = covariance \ crossCorrelation;
end

function output = expected_block(previousState, word, channel)
memory = numel(channel) - 1;
convolution = conv([previousState, word], channel);
output = convolution(memory + 1:memory + numel(word));
end

function state = append_feedback_state(state, word, memory)
samples = [state, word];
state = samples(end - memory + 1:end);
end

function blockCount = receiver_block_count(received, wordLength, memory)
payloadLength = numel(received) - memory;
assert(payloadLength >= wordLength && mod(payloadLength, wordLength) == 0, ...
    "SCFDE:InvalidReceivedFrame", ...
    "The received frame must contain an integer number of codewords and the channel tail.");
blockCount = payloadLength / wordLength;
end

function value = squared_distance(first, second)
value = sum(abs(first - second).^2);
end

function [errors, total] = simulate_turbo(book, bits, trellis, cfg, snrDb)
frame = turbo_frame(book, bits, cfg, snrDb);
[mapBits, ~] = cck_turbo_equalize(frame, book, bits, trellis, cfg, ...
    min(cfg.mapStateList, size(book, 1)), size(trellis.tailStates, 1));
[rsseBits, ~] = cck_turbo_equalize(frame, book, bits, trellis, cfg, ...
    min(cfg.reducedStateList, size(book, 1)), cfg.rsseTrellisStates);
errors = [sum(mapBits ~= frame.informationBits); ...
    sum(rsseBits ~= frame.informationBits)];
total = numel(frame.informationBits);
end

function frame = turbo_frame(book, bits, cfg, snrDb)
bitCount = size(bits, 2);
codedLength = cfg.symbols * bitCount;
if strcmpi(string(cfg.turboOuterCode), "repetition-1/2")
    informationLength = codedLength / 2;
    informationBits = randi([0, 1], 1, informationLength);
    positions = randperm(codedLength);
    firstCopy = positions(1:informationLength);
    secondCopy = positions(informationLength + 1:end);
    interleaver = randperm(informationLength);
    codedBits = zeros(1, codedLength);
    codedBits(firstCopy) = informationBits;
    codedBits(secondCopy) = informationBits(interleaver);
    inverse = zeros(1, informationLength);
    inverse(interleaver) = 1:informationLength;
    pairedPosition = zeros(1, codedLength);
    pairedPosition(firstCopy) = secondCopy(inverse);
    pairedPosition(secondCopy) = firstCopy(interleaver);
else
    informationBits = randi([0, 1], 1, codedLength);
    codedBits = informationBits;
    firstCopy = 1:codedLength;
    pairedPosition = 1:codedLength;
end
wordBits = reshape(codedBits, bitCount, []).';
indices = bits_to_indices(wordBits);
chips = reshape(book(indices, :).', 1, []);
informationBitsPerWord = numel(informationBits) / cfg.symbols;
wordEnergy = mean(sum(abs(book).^2, 2));
noiseVariance = wordEnergy / informationBitsPerWord * 10^(-snrDb / 10);
memory = numel(cfg.isiChannel) - 1;
received = filter(cfg.isiChannel, 1, [chips, zeros(1, memory)]) + ...
    sqrt(noiseVariance / 2) * (randn(1, numel(chips) + memory) + ...
    1j * randn(1, numel(chips) + memory));
frame.indices = indices;
frame.received = received;
frame.noiseVariance = noiseVariance;
frame.informationBits = informationBits;
frame.codedBits = codedBits;
frame.firstCopy = firstCopy;
frame.pairedPosition = pairedPosition;
end

function indices = bits_to_indices(wordBits)
indices = 1 + wordBits * (2 .^ (0:size(wordBits, 2) - 1)).';
indices = indices.';
end

function [detectedBits, trace] = cck_turbo_equalize(frame, book, bits, ...
        trellis, cfg, candidateCount, requestedStateCount)
wordLength = size(book, 2);
received = frame.received(1:numel(frame.indices) * wordLength);
candidateSets = select_candidates(received, book, trellis, ...
    frame.noiseVariance, candidateCount);
reduced = reduce_trellis(trellis, requestedStateCount);
metrics = branch_metrics(received, book, reduced, candidateSets, ...
    frame.noiseVariance);
prior = zeros(1, numel(frame.codedBits));
trace.bitErrorRate = zeros(1, cfg.turboIterations);
trace.codewordErrorRate = zeros(1, cfg.turboIterations);
for iteration = 1:cfg.turboIterations
    siso = siso_trellis(metrics, candidateSets, reduced, bits, prior);
    posterior = siso.extrinsicLlr + prior;
    if strcmpi(string(cfg.turboOuterCode), "repetition-1/2")
        prior = cfg.turboDamping * repetition_extrinsic( ...
            siso.extrinsicLlr, frame.pairedPosition);
        informationLlr = posterior(frame.firstCopy);
    else
        informationLlr = posterior;
    end
    detectedBits = informationLlr < 0;
    trace.bitErrorRate(iteration) = mean(detectedBits ~= frame.informationBits);
    trace.codewordErrorRate(iteration) = mean(siso.decision ~= frame.indices);
end
end

function candidateSets = select_candidates(received, book, trellis, noiseVariance, count)
wordLength = size(book, 2);
blockCount = floor(numel(received) / wordLength);
candidateSets = cell(1, blockCount);
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    scores = candidate_scores(observation, zeros(1, trellis.memory), ...
        book, trellis.channel, noiseVariance);
    [~, order] = sort(scores, "descend");
    candidateSets{block} = order(1:count).';
end
end

function reduced = reduce_trellis(trellis, requestedStateCount)
physicalCount = size(trellis.tailStates, 1);
stateCount = min(max(1, round(requestedStateCount)), physicalCount);
if stateCount == physicalCount
    reduced = trellis;
    return;
end
angles = mod(angle(trellis.tailStates(:, end)), 2 * pi);
[~, order] = sort(angles);
group = zeros(1, physicalCount);
for rank = 1:physicalCount
    group(order(rank)) = min(stateCount, ceil(rank * stateCount / physicalCount));
end
representative = zeros(1, stateCount);
for state = 1:stateCount
    representative(state) = find(group == state, 1, "first");
end
reduced.channel = trellis.channel;
reduced.memory = trellis.memory;
reduced.tailStates = trellis.tailStates(representative, :);
reduced.codeState = group(trellis.codeState);
end

function metrics = branch_metrics(received, book, trellis, candidateSets, noiseVariance)
wordLength = size(book, 2);
metrics.conditional = cell(1, numel(candidateSets));
for block = 1:numel(candidateSets)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = candidateSets{block};
    metric = zeros(size(trellis.tailStates, 1), numel(active));
    for state = 1:size(trellis.tailStates, 1)
        for candidateIndex = 1:numel(active)
            predicted = expected_block(trellis.tailStates(state, :), ...
                book(active(candidateIndex), :), trellis.channel);
            metric(state, candidateIndex) = -squared_distance(observation, predicted) / ...
                max(noiseVariance, 1e-8);
        end
    end
    metrics.conditional{block} = metric;
    if block == 1
        metrics.initial = zeros(1, numel(active));
        for candidateIndex = 1:numel(active)
            predicted = expected_block(zeros(1, trellis.memory), ...
                book(active(candidateIndex), :), trellis.channel);
            metrics.initial(candidateIndex) = -squared_distance(observation, predicted) / ...
                max(noiseVariance, 1e-8);
        end
    end
end
end

function siso = siso_trellis(metrics, candidateSets, trellis, bits, prior)
blockCount = numel(candidateSets);
stateCount = size(trellis.tailStates, 1);
bitCount = size(bits, 2);
alpha = cell(1, blockCount);
beta = cell(1, blockCount);
branch = cell(1, blockCount);
logPrior = cell(1, blockCount);
for block = 1:blockCount
    active = candidateSets{block};
    blockPrior = prior((block - 1) * bitCount + (1:bitCount));
    logPrior{block} = 0.5 * ((1 - 2 * bits(active, :)) * blockPrior.');
    branch{block} = metrics.conditional{block} + logPrior{block}.';
end
active = candidateSets{1};
initial = metrics.initial + logPrior{1};
alpha{1} = -inf(1, stateCount);
for candidateIndex = 1:numel(active)
    state = trellis.codeState(active(candidateIndex));
    alpha{1}(state) = logsumexp([alpha{1}(state), initial(candidateIndex)]);
end
alpha{1} = normalize_log(alpha{1});
for block = 2:blockCount
    active = candidateSets{block};
    alpha{block} = -inf(1, stateCount);
    for state = 1:stateCount
        candidates = find(trellis.codeState(active) == state);
        for candidateIndex = reshape(candidates, 1, [])
            values = alpha{block - 1} + branch{block}(:, candidateIndex).';
            alpha{block}(state) = logsumexp([alpha{block}(state), logsumexp(values)]);
        end
    end
    alpha{block} = normalize_log(alpha{block});
end
beta{blockCount} = zeros(1, stateCount);
for block = blockCount - 1:-1:1
    nextActive = candidateSets{block + 1};
    beta{block} = -inf(1, stateCount);
    for state = 1:stateCount
        values = -inf(1, numel(nextActive));
        for candidateIndex = 1:numel(nextActive)
            nextState = trellis.codeState(nextActive(candidateIndex));
            values(candidateIndex) = branch{block + 1}(state, candidateIndex) + ...
                beta{block + 1}(nextState);
        end
        beta{block}(state) = logsumexp(values);
    end
    beta{block} = normalize_log(beta{block});
end
posteriorLlr = zeros(1, blockCount * bitCount);
decision = zeros(1, blockCount);
for block = 1:blockCount
    active = candidateSets{block};
    posterior = -inf(1, numel(active));
    for candidateIndex = 1:numel(active)
        state = trellis.codeState(active(candidateIndex));
        if block == 1
            posterior(candidateIndex) = initial(candidateIndex) + beta{1}(state);
        else
            posterior(candidateIndex) = logsumexp(alpha{block - 1} + ...
                branch{block}(:, candidateIndex).' + beta{block}(state));
        end
    end
    posterior = posterior - logsumexp(posterior);
    [~, best] = max(posterior);
    decision(block) = active(best);
    for bit = 1:bitCount
        posteriorLlr((block - 1) * bitCount + bit) = ...
            logsumexp(posterior(bits(active, bit) == 0)) - ...
            logsumexp(posterior(bits(active, bit) == 1));
    end
end
siso.extrinsicLlr = posteriorLlr - prior;
siso.decision = decision;
end

function output = normalize_log(values)
finiteValues = values(isfinite(values));
if isempty(finiteValues)
    output = values;
else
    output = values - max(finiteValues);
end
end

function extrinsic = repetition_extrinsic(channelExtrinsic, pairedPosition)
extrinsic = channelExtrinsic(pairedPosition);
end

function value = logsumexp(values)
if isempty(values)
    value = -inf;
    return;
end
maximum = max(values);
if isinf(maximum) && maximum < 0
    value = -inf;
else
    value = maximum + log(sum(exp(values - maximum)));
end
end

function diagnostic = diagnostic_frame(book, bits, trellis, cfg)
[indices, received, noiseVariance] = raw_isi_frame(book, bits, cfg, cfg.snrDb);
frame = turbo_frame(book, bits, cfg, cfg.snrDb);
[mapBits, mapTrace] = cck_turbo_equalize(frame, book, bits, trellis, cfg, ...
    min(cfg.mapStateList, size(book, 1)), size(trellis.tailStates, 1));
[rsseBits, rsseTrace] = cck_turbo_equalize(frame, book, bits, trellis, cfg, ...
    min(cfg.reducedStateList, size(book, 1)), cfg.rsseTrellisStates);
canonicalBook = canonical_cck_book(book);
correlation = abs(canonicalBook * canonicalBook');
correlation(1:size(correlation, 1) + 1:end) = 0;
diagnostic.mapCurve = mapTrace.bitErrorRate;
diagnostic.rsseCurve = rsseTrace.bitErrorRate;
diagnostic.mapErrors = sum(mapBits ~= frame.informationBits);
diagnostic.rsseErrors = sum(rsseBits ~= frame.informationBits);
diagnostic.txIndices = indices;
diagnostic.received = received;
diagnostic.noiseVariance = noiseVariance;
diagnostic.canonicalCorrelation = correlation;
diagnostic.canonicalBookSize = size(canonicalBook, 1);
end

function canonicalBook = canonical_cck_book(book)
phaseNormalized = book .* conj(book(:, end)) * sqrt(size(book, 2));
key = [round(real(phaseNormalized) * 1e10), ...
    round(imag(phaseNormalized) * 1e10)];
[~, representatives] = unique(key, "rows");
canonicalBook = phaseNormalized(representatives, :);
canonicalBook = canonicalBook ./ sqrt(sum(abs(canonicalBook).^2, 2));
end

function path = plot_sections(result)
path = fullfile(result.config.outputDir, "chapter5_sections_5_1_5_3.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [70, 70, 1500, 900], "Visible", "off");
tiledlayout(2, 3, "TileSpacing", "compact", "Padding", "compact");
markers = ["o-", "s-", "^-", "d-", "v-", ">-"];
floorValue = 1e-5;
nexttile; hold on;
for index = 1:numel(result.names)
    semilogy(result.snrList, max(result.awgnBer(index, :), floorValue), ...
        markers(index), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("5.1 CCK 码本与速率模式的 AWGN 性能");
legend(result.names, "Location", "southwest");
nexttile;
bar(categorical([result.codeInfo.name]), [result.codeInfo.bitsPerWord]);
grid on; ylabel("每个 CCK 码字的信息比特数"); title("5.1 CCK 速率映射");
nexttile;
imagesc(result.diagnostics.canonicalCorrelation); axis image; colorbar;
xlabel("固定整体相位后的 FR-CCK 码字索引");
ylabel("固定整体相位后的 FR-CCK 码字索引");
title(sprintf("5.1 相位归一化后 %d 个码字的互相关", ...
    result.diagnostics.canonicalBookSize));
nexttile; hold on;
for index = 1:numel(result.isiMethodNames)
    semilogy(result.snrList, max(result.isiBer(index, :), floorValue), ...
        markers(index), "LineWidth", 1.1);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("5.2 含 ISI 的 CCK 接收机");
legend(result.isiMethodNames, "Location", "southwest");
nexttile; hold on;
for index = 1:numel(result.turboMethodNames)
    semilogy(result.snrList, max(result.turboBer(index, :), floorValue), ...
        markers(index), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("信息比特误码率 BER");
title("5.3 MAP-CCK-TE 与 RSSE-CCK-TE");
legend(result.turboMethodNames, "Location", "southwest");
nexttile; hold on;
plot(1:numel(result.diagnostics.mapCurve), result.diagnostics.mapCurve, ...
    "o-", "LineWidth", 1.2);
plot(1:numel(result.diagnostics.rsseCurve), result.diagnostics.rsseCurve, ...
    "s-", "LineWidth", 1.2);
grid on; xlabel("Turbo 迭代次数"); ylabel("信息比特错误率");
title("5.3 外信息交换后的迭代收敛");
legend("MAP-CCK-TE", "RSSE-CCK-TE", "Location", "best");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_isi_detail(result)
path = fullfile(result.config.outputDir, "chapter5_cck_isi_receiver_detail.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [100, 100, 1200, 520], "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile; stem(abs(result.config.isiChannel), "filled");
grid on; xlabel("多径抽头索引"); ylabel("归一化幅度");
title("5.2 CCK 码片级 ISI 信道");
nexttile; hold on;
for index = 1:numel(result.isiMethodNames)
    semilogy(result.snrList, max(result.isiBer(index, :), 1e-5), ...
        "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("MLD、Rake、DFE 与双向 DFE 对比");
legend(result.isiMethodNames, "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function detected = nearest_book(observations, book)
detected = zeros(1, size(observations, 1));
for index = 1:size(observations, 1)
    [~, detected(index)] = min(sum(abs(book - observations(index, :)).^2, 2));
end
end

function selected = select_indices(available, requested, label)
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
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
