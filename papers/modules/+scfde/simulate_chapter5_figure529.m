function result = simulate_chapter5_figure529(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE529 Compare QPSK and CCK IBDFE receiver modes.
%   The six curves are measured from independent end-to-end Monte Carlo
%   frames.  All modes use the same normalized multipath channel, cyclic
%   prefix length, Eb/N0 definition, and perfect channel response.
%
%   CCK-disjoint denotes a CCK transmitter with chip-independent QPSK soft
%   feedback.  CCK-IBDFE uses the posterior expectation of the complete
%   eight-chip CCK codeword as its feedback signal.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = -4:2:14;
defaults.cckWordsPerFrame = 128;
defaults.frameCount = 64;
defaults.iterations = [1, 5];
defaults.randomSeed = 20260803;
defaults.cpLength = 16;
defaults.channelDelays = 0:4;
defaults.channelPowerDb = 20 * log10([1, .70, .50, .28, .15]);
defaults.channelPhase = [0, .40, -.80, 1.40, -2.10];
defaults.qpskDamping = 0.48;
defaults.disjointDamping = 0.56;
defaults.cckDamping = 0.72;
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
[cckBook, cckBits] = make_cck_book();
channel = make_channel(cfg);
methodLabels = ["QPSK-iter1", "CCK-disjoint-iter1", ...
    "CCK-IBDFE-iter1", "QPSK-iter5", ...
    "CCK-disjoint-iter5", "CCK-IBDFE-iter5"];

snrCount = numel(cfg.snrList);
errorCounts = zeros(6, snrCount);
bitTotals = zeros(6, snrCount);
for snrIndex = 1:snrCount
    snrDb = cfg.snrList(snrIndex);
    errors = zeros(6, 1);
    totals = zeros(6, 1);
    for frameIndex = 1:cfg.frameCount
        qpsk = simulate_qpsk_frame(cfg, channel, snrDb);
        cck = simulate_cck_frame(cfg, channel, snrDb, cckBook, cckBits);
        errors(1) = errors(1) + qpsk.bitErrors(1);
        errors(2) = errors(2) + cck.disjointBitErrors(1);
        errors(3) = errors(3) + cck.ibdfeBitErrors(1);
        errors(4) = errors(4) + qpsk.bitErrors(end);
        errors(5) = errors(5) + cck.disjointBitErrors(end);
        errors(6) = errors(6) + cck.ibdfeBitErrors(end);
        totals([1, 4]) = totals([1, 4]) + qpsk.bitTotal;
        totals([2, 3, 5, 6]) = totals([2, 3, 5, 6]) + cck.bitTotal;
    end
    errorCounts(:, snrIndex) = errors;
    bitTotals(:, snrIndex) = totals;
end

ber = errorCounts ./ bitTotals;
displayBer = ber;
displayBer(errorCounts == 0) = 0.5 ./ bitTotals(errorCounts == 0);

result.config = cfg;
result.channel = channel;
result.cckBook = cckBook;
result.cckBitLabels = cckBits;
result.methodLabels = methodLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.displayBer = displayBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.zeroErrorDisplayConvention = "0.5 / BitTotal";
result.modeDefinitions = struct( ...
    "qpsk", "QPSK symbol mapping, symbol-level soft feedback IBDFE", ...
    "cckDisjoint", "standard 8-chip CCK mapping, chip-wise QPSK soft feedback IBDFE", ...
    "cckIbdfe", "standard 8-chip CCK mapping, full codeword posterior-mean soft IBDFE");
result.assumptions = struct( ...
    "channelKnowledge", "perfect", ...
    "channelUse", "all modes share the same static normalized multipath channel", ...
    "snrDefinition", "Eb/N0, energy per information bit Eb=1", ...
    "coding", "no outer code; gain only from IBDFE soft feedback");

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
result.figurePath = fullfile(cfg.outputDir, "fig5_29_mode_ber.png");
result.matPath = fullfile(cfg.outputDir, "fig5_29_mode_ber.mat");
result.csvPath = fullfile(cfg.outputDir, "fig5_29_mode_ber.csv");
write_figure(result);
write_table(result);
save(result.matPath, "result", "cfg");
end

function validate_config(cfg)
validateattributes(cfg.cckWordsPerFrame, {'numeric'}, ...
    {'scalar', 'integer', '>=', 8});
validateattributes(cfg.frameCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1});
validateattributes(cfg.cpLength, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1});
assert(isequal(cfg.iterations, [1, 5]), "SCFDE:Figure529Iterations", ...
    "Figure 5-29 requires the 1- and 5-iteration receiver outputs.");
assert(numel(cfg.channelDelays) == numel(cfg.channelPowerDb) && ...
    numel(cfg.channelDelays) == numel(cfg.channelPhase), ...
    "SCFDE:Figure529Channel", "Channel delay, power, and phase lengths must match.");
assert(cfg.channelDelays(1) == 0 && all(diff(cfg.channelDelays) > 0) && ...
    cfg.channelDelays(end) <= cfg.cpLength, "SCFDE:Figure529Cp", ...
    "The cyclic prefix must cover the channel delay spread.");
end

function channel = make_channel(cfg)
channel = complex(zeros(1, cfg.channelDelays(end) + 1));
channel(cfg.channelDelays + 1) = 10 .^ (cfg.channelPowerDb / 20) .* ...
    exp(1j * cfg.channelPhase);
channel = channel / norm(channel);
end

function [book, bits] = make_cck_book()
bits = zeros(256, 8);
book = complex(zeros(256, 8));
for value = 0:255
    rowBits = bitget(value, 1:8);
    bits(value + 1, :) = rowBits;
    qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
    phase = [qpsk(rowBits(1:2)), qpsk(rowBits(3:4)), ...
        qpsk(rowBits(5:6)), qpsk(rowBits(7:8))];
    word = exp(1j * [phase(1) + phase(2) + phase(3) + phase(4), ...
        phase(1) + phase(3) + phase(4), ...
        phase(1) + phase(2) + phase(4), ...
        phase(1) + phase(4), ...
        phase(1) + phase(2) + phase(3), ...
        phase(1) + phase(3), phase(1) + phase(2), phase(1)]);
    word([4, 7]) = -word([4, 7]);
    book(value + 1, :) = word;
end
end

function output = simulate_qpsk_frame(cfg, channel, snrDb)
chipCount = cfg.cckWordsPerFrame * 8;
bitPairs = randi([0, 1], chipCount, 2);
% QPSK carries two information bits per chip; scale to Eb=1.
symbols = sqrt(2) * (1 - 2 * bitPairs(:, 1) + 1j * ...
    (1 - 2 * bitPairs(:, 2))) / sqrt(2);
received = transmit_over_cp_channel(symbols.', channel, cfg.cpLength, snrDb);
history = ibdfe_qpsk(received, channel, snrDb, cfg.iterations(end), ...
    cfg.qpskDamping, sqrt(2));
output.bitErrors = zeros(1, numel(cfg.iterations));
for index = 1:numel(cfg.iterations)
    detected = history{cfg.iterations(index)};
    output.bitErrors(index) = sum(detected ~= bitPairs, "all");
end
output.bitTotal = numel(bitPairs);
end

function output = simulate_cck_frame(cfg, channel, snrDb, book, bitTable)
wordCount = cfg.cckWordsPerFrame;
indices = randi(size(book, 1), wordCount, 1);
chips = reshape(book(indices, :).', 1, []);
received = transmit_over_cp_channel(chips, channel, cfg.cpLength, snrDb);
disjointHistory = ibdfe_cck(received, channel, snrDb, book, ...
    cfg.iterations(end), cfg.disjointDamping, "disjoint");
ibdfeHistory = ibdfe_cck(received, channel, snrDb, book, ...
    cfg.iterations(end), cfg.cckDamping, "codeword");
output.disjointBitErrors = zeros(1, numel(cfg.iterations));
output.ibdfeBitErrors = zeros(1, numel(cfg.iterations));
for index = 1:numel(cfg.iterations)
    iteration = cfg.iterations(index);
    output.disjointBitErrors(index) = sum( ...
        bitTable(disjointHistory{iteration}, :) ~= bitTable(indices, :), "all");
    output.ibdfeBitErrors(index) = sum( ...
        bitTable(ibdfeHistory{iteration}, :) ~= bitTable(indices, :), "all");
end
output.bitTotal = numel(bitTable(indices, :));
end

function received = transmit_over_cp_channel(chips, channel, cpLength, snrDb)
tx = [chips(end - cpLength + 1:end), chips];
clean = filter(channel, 1, tx);
noiseVariance = 10^(-snrDb / 10);
noisy = clean + sqrt(noiseVariance / 2) * ...
    (randn(size(clean)) + 1j * randn(size(clean)));
received = noisy(cpLength + (1:numel(chips)));
end

function history = ibdfe_qpsk(received, channel, snrDb, iterations, damping, scale)
lengthFrame = numel(received);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
noiseVariance = 10^(-snrDb / 10);
symbolEnergy = scale^2;
soft = complex(zeros(1, lengthFrame));
history = cell(1, iterations);
for iteration = 1:iterations
    [estimate, effectiveVariance] = ibdfe_step(Y, H, soft, ...
        noiseVariance, symbolEnergy);
    [detected, candidateSoft] = qpsk_detector(estimate, effectiveVariance, scale);
    soft = (1 - damping) * soft + damping * candidateSoft;
    history{iteration} = detected;
end
end

function history = ibdfe_cck(received, channel, snrDb, book, iterations, damping, mode)
wordLength = size(book, 2);
lengthFrame = numel(received);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
noiseVariance = 10^(-snrDb / 10);
soft = complex(zeros(1, lengthFrame));
history = cell(1, iterations);
for iteration = 1:iterations
    [estimate, effectiveVariance, errorSpectrum] = ibdfe_step( ...
        Y, H, soft, noiseVariance, 1);
    blocks = reshape(estimate, wordLength, []).';
    if strcmp(mode, "disjoint")
        [detected, candidateSoft] = disjoint_cck_detector(blocks, book, ...
            effectiveVariance);
    else
        covariance = fde_block_covariance(errorSpectrum, wordLength);
        [detected, candidateSoft] = codeword_cck_detector(blocks, book, covariance);
    end
    soft = (1 - damping) * soft + damping * reshape(candidateSoft.', 1, []);
    history{iteration} = detected;
end
end

function [estimate, effectiveVariance, errorSpectrum] = ibdfe_step(Y, H, feedback, noiseVariance, signalEnergy)
reliability = min(0.985, mean(abs(feedback).^2) / max(signalEnergy, eps));
residualVariance = max(0.015 * signalEnergy, signalEnergy * (1 - reliability));
C = conj(H) ./ (noiseVariance + residualVariance * abs(H).^2);
normalizer = mean(C .* H);
if abs(normalizer) > eps
    C = C / normalizer;
end
B = C .* H - 1;
estimate = ifft(C .* Y - B .* fft(feedback));
errorSpectrum = abs(C).^2 * noiseVariance + abs(B).^2 * residualVariance;
effectiveVariance = max(1e-5, mean(errorSpectrum));
end

function [bits, soft] = qpsk_detector(estimate, variance, scale)
amplitude = scale / sqrt(2);
bits = [real(estimate(:)) < 0, imag(estimate(:)) < 0];
realSoft = amplitude * tanh(2 * amplitude * real(estimate) / variance);
imagSoft = amplitude * tanh(2 * amplitude * imag(estimate) / variance);
soft = realSoft + 1j * imagSoft;
end

function [detected, soft] = disjoint_cck_detector(observations, book, variance)
[~, softVector] = qpsk_detector(observations(:).', variance, 1);
soft = reshape(softVector, size(observations));
distance = squared_distance(soft, book);
[~, detected] = min(distance, [], 2);
end

function [detected, soft] = codeword_cck_detector(observations, book, covariance)
[lower, status] = chol(covariance, 'lower');
if status ~= 0
    lower = chol(covariance + 1e-6 * eye(size(covariance)), 'lower');
end
whitenedObservations = (lower \ observations.').';
whitenedBook = (lower \ book.').';
distance = squared_distance(whitenedObservations, whitenedBook);
[minimum, detected] = min(distance, [], 2);
weights = exp(-(distance - minimum));
weights = weights ./ sum(weights, 2);
soft = weights * book;
end

function covariance = fde_block_covariance(errorSpectrum, wordLength)
autocorrelation = ifft(errorSpectrum);
column = autocorrelation(1:wordLength).';
covariance = toeplitz(column, conj(column));
covariance = (covariance + covariance') / 2;
covariance = covariance + 1e-7 * eye(wordLength);
end

function distance = squared_distance(observations, book)
observationEnergy = sum(abs(observations).^2, 2);
bookEnergy = sum(abs(book).^2, 2).';
distance = observationEnergy + bookEnergy - 2 * real(observations * book');
distance = max(distance, 0);
end

function write_figure(result)
fig = figure("Color", "w", "Position", [105, 55, 980, 820], "Visible", "off");
ax = axes(fig, "Position", [0.14, 0.22, 0.76, 0.70]);
hold(ax, "on");
blue = [0.08, 0.29, 0.58];
black = [0.05, 0.05, 0.05];
red = [0.86, 0.15, 0.12];
styles = {"-s", "-*", "-^", "--s", "--*", "--^"};
colors = [blue; black; red; blue; black; red];
for methodIndex = 1:numel(result.methodLabels)
    semilogy(ax, result.snrList, result.displayBer(methodIndex, :), ...
        styles{methodIndex}, "Color", colors(methodIndex, :), ...
        "LineWidth", 1.8, "MarkerSize", 9, "MarkerFaceColor", "none", ...
        "DisplayName", result.methodLabels(methodIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.30;
ax.MinorGridAlpha = 0.20;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 11;
ax.LineWidth = 1;
ax.YScale = "log";
ax.YDir = "normal";
snrMin = min(result.snrList);
snrMax = max(result.snrList);
if snrMax == snrMin
    snrMin = snrMin - 1;
    snrMax = snrMax + 1;
end
xlim(ax, [snrMin, snrMax]);
ylim(ax, [1e-5, 1]);
xticks(ax, result.snrList);
yticks(ax, 10 .^ (-5:0));
yticklabels(ax, {"10^{-5}", "10^{-4}", "10^{-3}", "10^{-2}", ...
    "10^{-1}", "10^{0}"});
xlabel(ax, "E_b/N_0 / dB");
ylabel(ax, "BER");
legend(ax, "Location", "northeast", "FontSize", 10.5, "NumColumns", 1);
annotation(fig, "textbox", [0.12, 0.055, 0.78, 0.055], "String", ...
    "Fig 5-29: BER performance of each mode", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 15);
exportgraphics(fig, result.figurePath, "Resolution", 220);
close(fig);
end

function write_table(result)
methodColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
displayColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for methodIndex = 1:numel(result.methodLabels)
    count = numel(result.snrList);
    methodColumn = [methodColumn; repmat(result.methodLabels(methodIndex), count, 1)];
    snrColumn = [snrColumn; result.snrList(:)];
    berColumn = [berColumn; result.ber(methodIndex, :).'];
    displayColumn = [displayColumn; result.displayBer(methodIndex, :).'];
    errorColumn = [errorColumn; result.errorCounts(methodIndex, :).'];
    bitColumn = [bitColumn; result.bitTotals(methodIndex, :).'];
end
writetable(table(methodColumn, snrColumn, berColumn, displayColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Method', 'EbN0_dB', 'BER', 'DisplayBER', ...
    'ErrorCount', 'BitTotal'}), result.csvPath);
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
