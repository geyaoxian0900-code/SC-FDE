function results = run_chapter5_cck_suite(options, simulationDir)
%RUN_CHAPTER5_CCK_SUITE Modular simulations for Chapter 5 Sections 5.1-5.3.
%   Supports configurable CCK, ISI receiver, and CCK Turbo detector studies.

if nargin < 1
    options = struct();
end
if strcmp(getenv("SCFDE_USE_LEGACY_CCK_SUITE"), "1")
defaults.snrList = 0:3:15;
defaults.snrDb = 9;
defaults.symbols = 48;
defaults.frameCount = 3;
defaults.randomSeed = 20260724;
defaults.turboIterations = 4;
defaults.mapStateList = 32;
defaults.reducedStateList = 8;
defaults.modulationMethods = "all";
defaults.isiMethods = "all";
defaults.turboMethods = "all";
defaults.makePlot = true;
defaults.isiChannel = [1, 0.62 * exp(1j * 0.5), ...
    0.30 * exp(-1j * 1.0)];
defaults.outputDir = fullfile(simulationDir, "results");
cfg = merge_options(defaults, options);
cfg.isiChannel = cfg.isiChannel(:).' / norm(cfg.isiChannel);

modulationNames = ["FR-CCK", "HR-CCK", "GCCK-QPSK-4R", ...
    "GCCK-QPSK-8R", "GCCK-8PSK-12R", "Extended-CCK"];
isiNames = ["MLD", "Rake", "DFE", "BiDFE-1", "BiDFE-2", "TR-Rake"];
turboNames = ["MAP-CCK-TE", "RSSE-CCK-TE"];
modulationIndices = select_indices(modulationNames, cfg.modulationMethods, ...
    "CCK modulation");
isiIndices = select_indices(isiNames, cfg.isiMethods, "ISI receiver");
turboIndices = select_indices(turboNames, cfg.turboMethods, "CCK Turbo detector");
assert(cfg.symbols > 0 && cfg.frameCount > 0, ...
    "SCFDE:InvalidFrameConfig", "symbols and frameCount must be positive.");
assert(cfg.mapStateList >= cfg.reducedStateList && cfg.reducedStateList > 0, ...
    "SCFDE:InvalidStateList", ...
    "mapStateList must be no smaller than reducedStateList.");

rng(cfg.randomSeed, "twister");
books = cell(1, numel(modulationNames));
bitTables = cell(1, numel(modulationNames));
codeInfo = repmat(struct("name", "", "bitsPerWord", 0, ...
    "chipsPerWord", 0, "phaseOrder", 0), 1, numel(modulationNames));
for index = 1:numel(modulationNames)
    [books{index}, bitTables{index}, codeInfo(index)] = ...
        make_cck_codebook(modulationNames(index));
end
baseIndex = find(strcmp(modulationNames, "FR-CCK"), 1);
baseBook = books{baseIndex};
baseBits = bitTables{baseIndex};

allAwgnBer = zeros(numel(modulationNames), numel(cfg.snrList));
allIsiBer = zeros(numel(isiNames), numel(cfg.snrList));
allTurboBer = zeros(numel(turboNames), numel(cfg.snrList));
for snrIndex = 1:numel(cfg.snrList)
    awgnErrors = zeros(numel(modulationNames), 1);
    awgnTotals = zeros(numel(modulationNames), 1);
    isiErrors = zeros(numel(isiNames), 1);
    turboErrors = zeros(numel(turboNames), 1);
    isiTotal = 0;
    turboTotal = 0;
    for frameIndex = 1:cfg.frameCount
        for modulationIndex = 1:numel(modulationNames)
            [errors, total] = simulate_awgn(books{modulationIndex}, ...
                bitTables{modulationIndex}, cfg.symbols, cfg.snrList(snrIndex));
            awgnErrors(modulationIndex) = awgnErrors(modulationIndex) + errors;
            awgnTotals(modulationIndex) = awgnTotals(modulationIndex) + total;
        end
        [errors, total] = simulate_isi_receivers(baseBook, baseBits, cfg, ...
            cfg.snrList(snrIndex));
        isiErrors = isiErrors + errors;
        isiTotal = isiTotal + total;
        [errors, total] = simulate_turbo_detectors(baseBook, baseBits, cfg, ...
            cfg.snrList(snrIndex));
        turboErrors = turboErrors + errors;
        turboTotal = turboTotal + total;
    end
    allAwgnBer(:, snrIndex) = awgnErrors ./ awgnTotals;
    allIsiBer(:, snrIndex) = isiErrors / isiTotal;
    allTurboBer(:, snrIndex) = turboErrors / turboTotal;
end

diagnostics = diagnostic_frame(baseBook, baseBits, cfg);
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
results.availableTurboMethods = turboNames;
results.turboIndices = turboIndices;
results.turboMethodNames = turboNames(turboIndices);
results.turboBer = allTurboBer(turboIndices, :);
results.allTurboBer = allTurboBer;
results.snrList = cfg.snrList;
results.codeInfo = codeInfo(modulationIndices);
results.frBook = baseBook;
results.frBits = baseBits;
results.diagnostics = diagnostics;
results.smBer = nan(size(cfg.snrList));
results.outputPath = "";
results.figurePaths = strings(0, 1);

fprintf("\n===== Chapter 5 CCK Sections 5.1-5.3 =====\n");
for index = modulationIndices
    fprintf("%-22s AWGN BER@%.1f dB=%.5g\n", modulationNames(index), ...
        cfg.snrDb, value_at_snr(cfg.snrList, allAwgnBer(index, :), cfg.snrDb));
end
for index = isiIndices
    fprintf("%-22s ISI BER@%.1f dB=%.5g\n", isiNames(index), ...
        cfg.snrDb, value_at_snr(cfg.snrList, allIsiBer(index, :), cfg.snrDb));
end
for index = turboIndices
    fprintf("%-22s BER@%.1f dB=%.5g\n", turboNames(index), ...
        cfg.snrDb, value_at_snr(cfg.snrList, allTurboBer(index, :), cfg.snrDb));
end
if cfg.makePlot
    results.outputPath = plot_sections(results);
    results.figurePaths = [string(results.outputPath); plot_isi_detail(results)];
end
else
    results = scfde.run_chapter5_cck_suite_impl(options, simulationDir);
end
end

function [book, bits, info] = make_cck_codebook(name)
switch string(name)
    case "FR-CCK"
        bitCount = 8; phaseOrder = 4; phaseCount = 4; wordLength = 8;
    case "HR-CCK"
        bitCount = 4; phaseOrder = 4; phaseCount = 2; wordLength = 8;
    case "GCCK-QPSK-4R"
        bitCount = 4; phaseOrder = 4; phaseCount = 2; wordLength = 8;
    case "GCCK-QPSK-8R"
        bitCount = 8; phaseOrder = 4; phaseCount = 4; wordLength = 8;
    case "GCCK-8PSK-12R"
        bitCount = 12; phaseOrder = 8; phaseCount = 4; wordLength = 8;
    case "Extended-CCK"
        bitCount = 8; phaseOrder = 4; phaseCount = 4; wordLength = 16;
    otherwise
        error("SCFDE:UnknownCCK", "Unknown CCK modulation: %s", name);
end
M = 2^bitCount;
bits = zeros(M, bitCount);
book = complex(zeros(M, wordLength));
bitsPerPhase = log2(phaseOrder);
for index = 0:M - 1
    rowBits = bitget(index, 1:bitCount);
    bits(index + 1, :) = rowBits;
    phaseIndex = zeros(1, 4);
    for phase = 1:phaseCount
        positions = (phase - 1) * bitsPerPhase + (1:bitsPerPhase);
        phaseIndex(phase) = sum(rowBits(positions) .* 2.^(0:bitsPerPhase - 1));
    end
    if string(name) == "HR-CCK"
        phaseIndex(3:4) = [mod(phaseIndex(1) + 1, phaseOrder), ...
            mod(phaseIndex(2) + 2, phaseOrder)];
    end
    word = cck_word(2 * pi * phaseIndex / phaseOrder);
    if wordLength == 16
        extension = [ones(1, 8), 1, -1, 1, -1, -1, 1, -1, 1];
        word = [word, word] .* extension;
    end
    book(index + 1, :) = word / sqrt(wordLength);
end
info.name = string(name);
info.bitsPerWord = bitCount;
info.chipsPerWord = wordLength;
info.phaseOrder = phaseOrder;
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

function [errors, total] = simulate_isi_receivers(book, bits, cfg, snrDb)
[indices, received, noiseVariance] = isi_frame(book, cfg, snrDb);
mld = block_mld(received, book);
rake = rake_detect(received, book, cfg.isiChannel);
[dfe, forwardScores] = dfe_detect(received, book, cfg.isiChannel, noiseVariance);
reverseBook = fliplr(book);
[~, reverseScores] = dfe_detect(fliplr(received), reverseBook, ...
    fliplr(conj(cfg.isiChannel)), noiseVariance);
backwardScores = flipud(reverseScores);
[~, biDfe1] = max(forwardScores + backwardScores, [], 2);
biDfe2 = bidirectional_refine(received, book, cfg.isiChannel, biDfe1, ...
    backwardScores, noiseVariance);
trRake = time_reversal_rake(received, book, cfg.isiChannel);
decisions = [mld; rake; dfe; biDfe1.'; biDfe2; trRake];
errors = zeros(6, 1);
for method = 1:6
    errors(method) = sum(bits(decisions(method, :), :) ~= bits(indices, :), "all");
end
total = numel(bits(indices, :));
end

function [indices, received, noiseVariance] = isi_frame(book, cfg, snrDb)
indices = randi(size(book, 1), 1, cfg.symbols);
chips = reshape(book(indices, :).', 1, []);
noiseVariance = 10^(-snrDb / 10);
received = filter(cfg.isiChannel, 1, chips) + sqrt(noiseVariance / 2) * ...
    (randn(size(chips)) + 1j * randn(size(chips)));
end

function detected = block_mld(received, book)
lengthWord = size(book, 2);
blockCount = floor(numel(received) / lengthWord);
blocks = reshape(received(1:blockCount * lengthWord), lengthWord, []).';
detected = nearest_book(blocks, book);
end

function detected = rake_detect(received, book, channel)
lengthWord = size(book, 2);
blockCount = floor(numel(received) / lengthWord);
padded = [received, zeros(1, numel(channel))];
combined = complex(zeros(blockCount, lengthWord));
for block = 1:blockCount
    start = (block - 1) * lengthWord + 1;
    for tap = 1:numel(channel)
        combined(block, :) = combined(block, :) + conj(channel(tap)) * ...
            padded(start + tap - 1:start + tap + lengthWord - 2);
    end
end
detected = nearest_book(combined / sum(abs(channel).^2), book);
end

function [detected, scores] = dfe_detect(received, book, channel, noiseVariance)
lengthWord = size(book, 2);
blockCount = floor(numel(received) / lengthWord);
state = complex(zeros(1, numel(channel) - 1));
detected = zeros(1, blockCount);
scores = zeros(blockCount, size(book, 1));
for block = 1:blockCount
    observation = received((block - 1) * lengthWord + (1:lengthWord));
    for candidate = 1:size(book, 1)
        predicted = expected_block(state, book(candidate, :), channel);
        scores(block, candidate) = -sum(abs(observation - predicted).^2) / ...
            max(noiseVariance, 1e-6);
    end
    [~, detected(block)] = max(scores(block, :));
    state = book(detected(block), end - numel(channel) + 2:end);
end
end

function detected = bidirectional_refine(received, book, channel, initial, ...
        backwardScores, noiseVariance)
lengthWord = size(book, 2);
blockCount = numel(initial);
detected = zeros(1, blockCount);
for block = 1:blockCount
    observation = received((block - 1) * lengthWord + (1:lengthWord));
    if block == 1
        state = zeros(1, numel(channel) - 1);
    else
        state = book(initial(block - 1), end - numel(channel) + 2:end);
    end
    metric = zeros(1, size(book, 1));
    for candidate = 1:size(book, 1)
        predicted = expected_block(state, book(candidate, :), channel);
        metric(candidate) = -sum(abs(observation - predicted).^2) / ...
            max(noiseVariance, 1e-6) + backwardScores(block, candidate);
    end
    [~, detected(block)] = max(metric);
end
end

function detected = time_reversal_rake(received, book, channel)
filtered = filter(conj(fliplr(channel)), 1, received);
detected = block_mld(filtered, book);
end

function output = expected_block(previousState, word, channel)
memory = numel(channel) - 1;
convolution = conv([previousState, word], channel);
output = convolution(memory + 1:memory + numel(word));
end

function [errors, total] = simulate_turbo_detectors(book, bits, cfg, snrDb)
[indices, received, noiseVariance] = isi_frame(book, cfg, snrDb);
[mapDecision, ~] = cck_state_turbo(received, book, cfg.isiChannel, ...
    noiseVariance, cfg.turboIterations, min(cfg.mapStateList, size(book, 1)), indices);
[rsseDecision, ~] = cck_state_turbo(received, book, cfg.isiChannel, ...
    noiseVariance, cfg.turboIterations, ...
    min(cfg.reducedStateList, size(book, 1)), indices);
errors = [sum(bits(mapDecision, :) ~= bits(indices, :), "all"); ...
    sum(bits(rsseDecision, :) ~= bits(indices, :), "all")];
total = numel(bits(indices, :));
end

function [decision, curve] = cck_state_turbo(received, book, channel, ...
        noiseVariance, iterations, stateCount, truth)
lengthWord = size(book, 2);
blockCount = floor(numel(received) / lengthWord);
active = cell(1, blockCount);
baseMetric = cell(1, blockCount);
for block = 1:blockCount
    observation = received((block - 1) * lengthWord + (1:lengthWord));
    distance = sum(abs(book - observation).^2, 2);
    [sorted, order] = sort(distance);
    active{block} = order(1:stateCount).';
    baseMetric{block} = -sorted(1:stateCount).' / max(noiseVariance, 1e-6);
end
prior = cellfun(@zeros_like, active, "UniformOutput", false);
curve = zeros(1, iterations);
for iteration = 1:iterations
    [alpha, beta] = state_forward_backward(received, book, channel, ...
        noiseVariance, active, baseMetric, prior);
    decision = zeros(1, blockCount);
    nextPrior = cell(1, blockCount);
    for block = 1:blockCount
        posterior = alpha{block} + beta{block};
        posterior = posterior - logsumexp(posterior);
        [~, local] = max(posterior);
        decision(block) = active{block}(local);
        nextPrior{block} = posterior;
    end
    curve(iteration) = mean(decision ~= truth);
    prior = nextPrior;
end
end

function [alpha, beta] = state_forward_backward(received, book, channel, ...
        noiseVariance, active, baseMetric, prior)
blockCount = numel(active);
lengthWord = size(book, 2);
alpha = cell(1, blockCount);
beta = cell(1, blockCount);
for block = 1:blockCount
    current = active{block};
    alpha{block} = -inf(1, numel(current));
    observation = received((block - 1) * lengthWord + (1:lengthWord));
    for currentIndex = 1:numel(current)
        if block == 1
            metric = -sum(abs(observation - ...
                expected_block(zeros(1, numel(channel) - 1), ...
                book(current(currentIndex), :), channel)).^2) / max(noiseVariance, 1e-6);
            alpha{block}(currentIndex) = metric + 0.25 * prior{block}(currentIndex);
        else
            previous = active{block - 1};
            values = -inf(1, numel(previous));
            for previousIndex = 1:numel(previous)
                expected = expected_block(book(previous(previousIndex), ...
                    end - numel(channel) + 2:end), book(current(currentIndex), :), channel);
                values(previousIndex) = alpha{block - 1}(previousIndex) - ...
                    sum(abs(observation - expected).^2) / max(noiseVariance, 1e-6);
            end
            alpha{block}(currentIndex) = logsumexp(values) + ...
                baseMetric{block}(currentIndex) + 0.25 * prior{block}(currentIndex);
        end
    end
    alpha{block} = alpha{block} - max(alpha{block});
end
beta{blockCount} = zeros(1, numel(active{blockCount}));
for block = blockCount - 1:-1:1
    current = active{block};
    next = active{block + 1};
    observation = received(block * lengthWord + (1:lengthWord));
    beta{block} = -inf(1, numel(current));
    for currentIndex = 1:numel(current)
        values = -inf(1, numel(next));
        state = book(current(currentIndex), end - numel(channel) + 2:end);
        for nextIndex = 1:numel(next)
            expected = expected_block(state, book(next(nextIndex), :), channel);
            values(nextIndex) = -sum(abs(observation - expected).^2) / ...
                max(noiseVariance, 1e-6) + beta{block + 1}(nextIndex);
        end
        beta{block}(currentIndex) = logsumexp(values);
    end
    beta{block} = beta{block} - max(beta{block});
end
end

function value = zeros_like(vector)
value = zeros(1, numel(vector));
end

function value = logsumexp(values)
maximum = max(values);
if isinf(maximum)
    value = maximum;
else
    value = maximum + log(sum(exp(values - maximum)));
end
end

function diagnostic = diagnostic_frame(book, bits, cfg)
[indices, received, noiseVariance] = isi_frame(book, cfg, cfg.snrDb);
[mapDecision, mapCurve] = cck_state_turbo(received, book, cfg.isiChannel, ...
    noiseVariance, cfg.turboIterations, min(cfg.mapStateList, size(book, 1)), indices);
[rsseDecision, rsseCurve] = cck_state_turbo(received, book, cfg.isiChannel, ...
    noiseVariance, cfg.turboIterations, ...
    min(cfg.reducedStateList, size(book, 1)), indices);
correlation = abs(book * book');
correlation(1:size(book, 1) + 1:end) = 0;
diagnostic.mapCurve = mapCurve;
diagnostic.rsseCurve = rsseCurve;
diagnostic.mapErrors = sum(bits(mapDecision, :) ~= bits(indices, :), "all");
diagnostic.rsseErrors = sum(bits(rsseDecision, :) ~= bits(indices, :), "all");
diagnostic.txIndices = indices;
diagnostic.received = received;
diagnostic.crossCorrelation = max(correlation, [], 2);
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
title("5.1 CCK 码字与速率模式的 AWGN 性能"); legend(result.names, "Location", "southwest");

nexttile;
bar(categorical([result.codeInfo.name]), [result.codeInfo.bitsPerWord]);
grid on; ylabel("每个 CCK 码字的信息比特数"); title("5.1 CCK 速率映射");

nexttile; plot(result.diagnostics.crossCorrelation, "LineWidth", 1.0);
grid on; xlabel("FR-CCK 码字索引"); ylabel("最大互相关"); title("5.1 FR-CCK 码本互相关");

nexttile; hold on;
for index = 1:numel(result.isiMethodNames)
    semilogy(result.snrList, max(result.isiBer(index, :), floorValue), ...
        markers(index), "LineWidth", 1.1);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("5.2 含 ISI 的 CCK 接收机"); legend(result.isiMethodNames, "Location", "southwest");

nexttile; hold on;
for index = 1:numel(result.turboMethodNames)
    semilogy(result.snrList, max(result.turboBer(index, :), floorValue), ...
        markers(index), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("5.3 MAP-CCK-TE 与 RSSE-CCK-TE"); legend(result.turboMethodNames, "Location", "southwest");

nexttile; hold on;
plot(1:numel(result.diagnostics.mapCurve), result.diagnostics.mapCurve, "o-", "LineWidth", 1.2);
plot(1:numel(result.diagnostics.rsseCurve), result.diagnostics.rsseCurve, "s-", "LineWidth", 1.2);
grid on; xlabel("CCK Turbo 迭代次数"); ylabel("码字判决错误率");
title("5.3 状态检测迭代收敛"); legend("MAP-CCK-TE", "RSSE-CCK-TE", "Location", "best");
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
grid on; xlabel("多径抽头索引"); ylabel("归一化幅度"); title("5.2 CCK 码片级 ISI 信道");
nexttile; hold on;
for index = 1:numel(result.isiMethodNames)
    semilogy(result.snrList, max(result.isiBer(index, :), 1e-5), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("比特误码率 BER");
title("MLD、Rake、DFE 与双向 DFE 对比"); legend(result.isiMethodNames, "Location", "southwest");
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

function value = value_at_snr(snrList, values, snrDb)
value = interp1(snrList, values, snrDb, "linear", "extrap");
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
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
