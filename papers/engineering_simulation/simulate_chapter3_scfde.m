function results = simulate_chapter3_scfde(options)
%SIMULATE_CHAPTER3_SCFDE Reproduce the Chapter 3 SC-FDE receiver chain.

if nargin < 1
    options = struct();
end
if isfield(options, "replotResultPath")
    resultPath = string(options.replotResultPath);
    stored = load(resultPath, "results");
    assert(isfield(stored, "results"), ...
        "The MAT file does not contain Chapter 3 results: %s", resultPath);
    results = stored.results;
    [results.figure313, results.figure313Diagnostics] = ...
        figure_313_outputs(results.example, results.diagnostics, ...
        results.config);
    results.outputPath = plot_results(results);
    results.figurePaths = [string(results.outputPath); ...
        plot_estimation_results(results); plot_figure_313(results); ...
        plot_figure_318(results)];
    save(resultPath, "results");
    return;
end
cfg.fftSize = opt(options, "fftSize", 1024);
cfg.uwLength = opt(options, "uwLength", 256);
cfg.dataSymbols = cfg.fftSize - cfg.uwLength;
cfg.bitsPerSymbol = 2;
cfg.symbolRate = opt(options, "symbolRate", 4000);
cfg.snrDb = opt(options, "snrDb", 14);
cfg.cfoHz = opt(options, "cfoHz", 1.0);
cfg.phaseOffset = opt(options, "phaseOffset", 0.55);
cfg.randomSeed = opt(options, "randomSeed", 20260724);
cfg.frameCount = opt(options, "frameCount", 40);
cfg.ibdfeIterations = opt(options, "ibdfeIterations", 5);
cfg.htfdeIterations = opt(options, "htfdeIterations", 2);
cfg.htfdeBranches = opt(options, "htfdeBranches", 4);
cfg.syncPeriod = opt(options, "syncPeriod", 128);
cfg.channelEstimateLength = opt(options, "channelEstimateLength", 32);
cfg.channelTrainingSymbols = opt(options, "channelTrainingSymbols", cfg.fftSize);
cfg.channelRegularization = opt(options, "channelRegularization", 1);
cfg.channelPriorVariance = opt(options, "channelPriorVariance", []);
cfg.outputDir = string(opt(options, "outputDir", fullfile( ...
    fileparts(mfilename("fullpath")), "results", "chapter3_scfde_simulation")));
availableMethods = ["ZF-SC-FDE", "MMSE-SC-FDE", "HTFDE", ...
    "SD-IBDFE", "HD-IBDFE", "ICE-SD-IBDFE", "ICE-HD-IBDFE"];
availableGuardMethods = ["CP-SC", "ZP-SC", "UW-SC"];
availableEstimationMethods = ["Residual-Doppler-PN", "Initial-Phase-PN", ...
    "LS-CE", "MMSE-CE"];
availableChannelEstimators = ["LS-CE", "MMSE-CE"];
cfg.methods = opt(options, "methods", "all");
cfg.guardMethods = opt(options, "guardMethods", "all");
cfg.estimationMethods = opt(options, "estimationMethods", "all");
cfg.channelEstimator = string(opt(options, "channelEstimator", "MMSE-CE"));
cfg.makePlot = opt(options, "makePlot", true);
cfg.channel = opt(options, "channel", ...
    [1, 0.65 * exp(1j * 0.4), 0.35 * exp(-1j * 0.9), ...
    0.18 * exp(1j * 1.4)]);
cfg.channel = cfg.channel(:).' / norm(cfg.channel);
cfg.channelProfile = string(opt(options, "channelProfile", "configured"));
if strcmpi(cfg.channelProfile, "paper-table-3-2")
    cfg.channel = paper_table_32_channel(cfg.symbolRate);
end
cfg.lakeImpulseResponse = opt(options, "lakeImpulseResponse", ...
    [1, 0.82 * exp(1j * 0.2), 0.55 * exp(-1j * 0.8), ...
    0.29 * exp(1j * 1.7), 0.12 * exp(-1j * 0.4)]);
cfg.lakeImpulseResponse = cfg.lakeImpulseResponse(:).' / ...
    norm(cfg.lakeImpulseResponse);

assert(cfg.fftSize > cfg.uwLength, "UW must be shorter than the DFT block.");
assert(cfg.uwLength >= numel(cfg.channel) - 1, ...
    "The guard interval must cover the channel memory.");
assert(mod(cfg.fftSize, cfg.htfdeBranches) == 0, ...
    "The DFT length must be divisible by the HTFDE branch count.");
assert(mod(cfg.fftSize, cfg.syncPeriod) == 0, ...
    "The synchronization period must divide the DFT length.");
assert(cfg.channelEstimateLength <= cfg.uwLength, ...
    "The estimated channel must fit inside the UW guard interval.");
assert(cfg.channelTrainingSymbols > 0 && ...
    cfg.channelTrainingSymbols <= cfg.fftSize, ...
    "channelTrainingSymbols must lie between 1 and fftSize.");
assert(cfg.htfdeIterations > 0 && cfg.ibdfeIterations > 0, ...
    "The HTFDE and IBDFE iteration counts must be positive.");
rng(cfg.randomSeed, "twister");
methodIndices = select_method_indices(availableMethods, cfg.methods, "Chapter 3");
guardIndices = select_method_indices(availableGuardMethods, ...
    cfg.guardMethods, "guard-interval");
estimationIndices = select_method_indices(availableEstimationMethods, ...
    cfg.estimationMethods, "synchronization or channel-estimation");
channelEstimatorIndex = find(strcmpi(cfg.channelEstimator, ...
    availableChannelEstimators), 1);
assert(~isempty(channelEstimatorIndex), "SCFDE:UnknownChannelEstimator", ...
    "channelEstimator must be one of: %s", ...
    strjoin(availableChannelEstimators, ", "));
cfg.channelEstimator = availableChannelEstimators(channelEstimatorIndex);

snrList = opt(options, "snrList", 0:2:20);
allMethodBer = zeros(numel(availableMethods), numel(snrList));
allGuardBer = zeros(numel(availableGuardMethods), numel(snrList));
allEstimationMse = zeros(numel(availableEstimationMethods), numel(snrList));
allMethodErrorCounts = zeros(size(allMethodBer));
allMethodBitCounts = zeros(size(allMethodBer));
allGuardErrorCounts = zeros(size(allGuardBer));
allGuardBitCounts = zeros(size(allGuardBer));
figure318Names = ["MMSE，信道已知", "低复杂度IBDFE，信道已知", ...
    "HD-IBDFE，信道已知", "SD-IBDFE，信道已知", ...
    "MMSE，信道未知", "低复杂度IBDFE，信道未知", ...
    "HD-IBDFE，信道未知", "SD-IBDFE，信道未知"];
figure318ErrorCounts = zeros(numel(figure318Names), numel(snrList));
figure318BitCounts = zeros(size(figure318ErrorCounts));
for snrIndex = 1:numel(snrList)
    [sweep, estimationMse] = ber_sweep(cfg, snrList(snrIndex));
    allMethodBer(:, snrIndex) = sweep.receiver;
    allGuardBer(:, snrIndex) = sweep.guard;
    allMethodErrorCounts(:, snrIndex) = sweep.receiverErrors;
    allMethodBitCounts(:, snrIndex) = sweep.receiverBits;
    allGuardErrorCounts(:, snrIndex) = sweep.guardErrors;
    allGuardBitCounts(:, snrIndex) = sweep.guardBits;
    figure318ErrorCounts(:, snrIndex) = sweep.figure318Errors;
    figure318BitCounts(:, snrIndex) = sweep.figure318Bits;
    allEstimationMse(:, snrIndex) = estimationMse;
end

[example, diagnostics] = one_frame(cfg, cfg.snrDb, cfg.channel);
[figure313, figure313Diagnostics] = figure_313_outputs( ...
    example, diagnostics, cfg);
[lakeImpulse, lakeInfo] = process_lake_style_data(cfg);
results.config = cfg;
results.snrList = snrList;
results.availableMethods = availableMethods;
results.methodIndices = methodIndices;
results.methodNames = availableMethods(methodIndices);
results.methodBer = allMethodBer(methodIndices, :);
results.allMethodBer = allMethodBer;
results.allMethodErrorCounts = allMethodErrorCounts;
results.allMethodBitCounts = allMethodBitCounts;
results.methodErrorCounts = allMethodErrorCounts(methodIndices, :);
results.methodBitCounts = allMethodBitCounts(methodIndices, :);
results.availableGuardMethods = availableGuardMethods;
results.guardMethodIndices = guardIndices;
results.guardMethodNames = availableGuardMethods(guardIndices);
results.guardMethodBer = allGuardBer(guardIndices, :);
results.allGuardBer = allGuardBer;
results.guardErrorCounts = allGuardErrorCounts(guardIndices, :);
results.guardBitCounts = allGuardBitCounts(guardIndices, :);
results.availableEstimationMethods = availableEstimationMethods;
results.estimationIndices = estimationIndices;
results.estimationNames = availableEstimationMethods(estimationIndices);
results.estimationMse = allEstimationMse(estimationIndices, :);
results.allEstimationMse = allEstimationMse;
results.figure318Names = figure318Names;
results.figure318ErrorCounts = figure318ErrorCounts;
results.figure318BitCounts = figure318BitCounts;
results.figure318Ber = figure318ErrorCounts ./ figure318BitCounts;
results.basicBer = allMethodBer(2, :);
results.jointBer = allMethodBer(3, :);
results.htfdeBer = allMethodBer(3, :);
results.ibdfeBer = allMethodBer(6, :);
results.cpBer = allGuardBer(1, :);
results.zpBer = allGuardBer(2, :);
results.uwBer = allGuardBer(3, :);
results.channel = cfg.channel;
results.example = example;
results.diagnostics = diagnostics;
results.figure313 = figure313;
results.figure313Diagnostics = figure313Diagnostics;
results.lakeImpulse = lakeImpulse;
results.lakeInfo = lakeInfo;
results.bandwidthEfficiency = bandwidth_efficiency(cfg.fftSize, ...
    cfg.uwLength);
results.bandwidthEfficiencyExample = bandwidth_efficiency_example();
results.berSource = "Monte Carlo bit-error counting from the simulated SC-FDE receiver chain.";
results.channelSource = "Configured deterministic complex multipath channel.";
results.outputDir = cfg.outputDir;
results.resultPath = fullfile(cfg.outputDir, "chapter3_scfde_simulation.mat");
results.outputPath = "";
results.figurePaths = strings(0, 1);

fprintf("\n===== Chapter 3 SC-FDE simulation =====\n");
fprintf("N=%d, M=%d, UW data=%d, HTFDE branches=%d\n", ...
    cfg.fftSize, cfg.uwLength, cfg.dataSymbols, cfg.htfdeBranches);
fprintf("Bandwidth efficiency (3-27)/(3-28): eta_CP=%.3f, eta_UW=%.3f\n", ...
    results.bandwidthEfficiency.etaCp, results.bandwidthEfficiency.etaUw);
fprintf("Example (3-29) N=1024 M=256 P=96: eta_CP=%.1f%%, eta_UW=%.1f%%\n", ...
    100 * results.bandwidthEfficiencyExample.etaCp, ...
    100 * results.bandwidthEfficiencyExample.etaUw);
fprintf("CFO true/estimated: %.4f / %.4f Hz\n", ...
    cfg.cfoHz, diagnostics.estimatedCfo);
fprintf("Initial phase true/estimated: %.4f / %.4f rad\n", ...
    cfg.phaseOffset, diagnostics.estimatedPhase);
for selectedIndex = methodIndices
    fprintf("%-16s BER@%.1f dB=%.5g\n", availableMethods(selectedIndex), ...
        cfg.snrDb, example.methodBer(selectedIndex));
end
if cfg.makePlot
    results.outputPath = plot_results(results);
    results.figurePaths = [string(results.outputPath); ...
        plot_estimation_results(results); plot_figure_313(results); ...
        plot_figure_318(results)];
end
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
save(results.resultPath, "results");
end

function efficiency = bandwidth_efficiency(N, M)
% 书 (3-27): eta_CP = N/(N+M)；(3-28): eta_UW = (N-M)/N
efficiency.etaCp = N / (N + M);
efficiency.etaUw = (N - M) / N;
end

function example = bandwidth_efficiency_example()
% 书 3.2 节算例: N=1024, M=256, P=96
N = 1024; M = 256; P = 96;
efficiency = bandwidth_efficiency(N, M);
example.etaCp = (N - P) / (N + M);
example.etaUw = efficiency.etaUw;
assert(abs(example.etaCp - 0.725) < 1e-6, ...
    "Example violates (3-29): expected 72.5%%.");
assert(abs(example.etaUw - 0.75) < 1e-6, ...
    "Example violates (3-28): expected 75%%.");
end

function [sweep, estimationMse] = ber_sweep(cfg, snrDb)
receiverErrors = zeros(1, 7);
guardErrors = zeros(1, 3);
receiverBits = 0;
guardBits = zeros(1, 3);
estimationSquaredErrors = zeros(1, 4);
figure318Errors = zeros(1, 8);
for frameIndex = 1:cfg.frameCount
    [frame, diagnostics] = one_frame(cfg, snrDb, cfg.channel);
    receiverErrors = receiverErrors + frame.methodErrors;
    receiverBits = receiverBits + cfg.dataSymbols * cfg.bitsPerSymbol;
    figure318Errors = figure318Errors + frame.figure318Errors;
    estimationSquaredErrors = estimationSquaredErrors + [ ...
        diagnostics.dopplerSquaredError, diagnostics.phaseSquaredError, ...
        diagnostics.lsChannelNmse, diagnostics.mmseChannelNmse];
    guard = guard_interval_frame(cfg, snrDb, cfg.channel);
    guardErrors = guardErrors + guard.errors;
    guardBits = guardBits + guard.bitCounts;
end
sweep.receiver = (receiverErrors / receiverBits).';
sweep.guard = guardErrors ./ guardBits;
sweep.receiverErrors = receiverErrors.';
sweep.receiverBits = repmat(receiverBits, numel(receiverErrors), 1);
sweep.guardErrors = guardErrors.';
sweep.guardBits = guardBits.';
sweep.figure318Errors = figure318Errors.';
sweep.figure318Bits = repmat(receiverBits, numel(figure318Errors), 1);
estimationMse = (estimationSquaredErrors / cfg.frameCount).';
end

function [out, diag] = one_frame(cfg, snrDb, h)
N = cfg.fftSize;
M = cfg.uwLength;
dataBits = randi([0, 1], 1, cfg.dataSymbols * cfg.bitsPerSymbol);
dataSymbols = qpsk_map(dataBits);
uw = zadoff_chu(M, 1);
dataBlock = [dataSymbols, uw];
syncWord = zadoff_chu(cfg.syncPeriod, 1);
syncTraining = repmat(syncWord, 1, N / cfg.syncPeriod);
channelTraining = channel_training_sequence( ...
    N, cfg.channelTrainingSymbols, 3);

channel = [h, zeros(1, N - numel(h))];
H = fft(channel, N);
transmitted = [syncTraining; channelTraining; dataBlock];
clean = complex(zeros(size(transmitted)));
for blockIndex = 1:size(transmitted, 1)
    clean(blockIndex, :) = ifft(fft(transmitted(blockIndex, :)) .* H);
end
sampleIndex = (0:N - 1) + (0:size(clean, 1) - 1).' * N;
carrier = exp(1j * (cfg.phaseOffset + ...
    2 * pi * cfg.cfoHz * sampleIndex / cfg.symbolRate));
noiseVariance = mean(abs(clean).^2, "all") * 10^(-snrDb / 10);
received = clean .* carrier + sqrt(noiseVariance / 2) * ...
    (randn(size(clean)) + 1j * randn(size(clean)));

estimatedCfo = repeated_word_cfo(received(1, :), ...
    cfg.syncPeriod, cfg.symbolRate);
cfoCorrected = received .* exp(-1j * 2 * pi * estimatedCfo * ...
    sampleIndex / cfg.symbolRate);
HphaseReference = estimate_channel_ls(cfoCorrected(2, :), channelTraining, ...
    cfg.channelEstimateLength);
estimatedPhase = initial_phase_from_channel(HphaseReference);
corrected = cfoCorrected .* exp(-1j * estimatedPhase);
Hls = estimate_channel_ls(corrected(2, :), channelTraining, ...
    cfg.channelEstimateLength);
Hmmse = estimate_channel_mmse(corrected(2, :), channelTraining, ...
    cfg.channelEstimateLength, noiseVariance, cfg.channelPriorVariance);
if cfg.channelEstimator == "LS-CE"
    Hinitial = Hls;
else
    Hinitial = Hmmse;
end
receivedData = corrected(3, :);
Y = fft(receivedData);

Xbasic = mmse_frequency_equalize(Y, Hinitial, noiseVariance);
basicSymbols = ifft(Xbasic);
basicBits = qpsk_demap(basicSymbols(1:cfg.dataSymbols));
zfSymbols = ifft(Y ./ (Hinitial + 1e-8));
zfBits = qpsk_demap(zfSymbols(1:cfg.dataSymbols));

residualPhase = cfg.phaseOffset - estimatedPhase;
Hknown = H * exp(1j * residualPhase);
knownMmseSymbols = ifft(mmse_frequency_equalize(Y, Hknown, noiseVariance));
knownMmseBits = qpsk_demap(knownMmseSymbols(1:cfg.dataSymbols));
lowComplexityCfg = cfg;
lowComplexityCfg.ibdfeIterations = 2;
[knownLcSymbols, ~, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hknown, ...
    noiseVariance, uw, lowComplexityCfg, "soft", false);
knownLcBits = qpsk_demap(knownLcSymbols(1:cfg.dataSymbols));
[unknownLcSymbols, ~, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hinitial, ...
    noiseVariance, uw, lowComplexityCfg, "soft", false);
unknownLcBits = qpsk_demap(unknownLcSymbols(1:cfg.dataSymbols));
[knownSdSymbols, ~, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hknown, ...
    noiseVariance, uw, cfg, "soft", false);
knownSdBits = qpsk_demap(knownSdSymbols(1:cfg.dataSymbols));
[knownHdSymbols, ~, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hknown, ...
    noiseVariance, uw, cfg, "hard", false);
knownHdBits = qpsk_demap(knownHdSymbols(1:cfg.dataSymbols));

[htfdeSymbols, htfdeTrace] = htfde_equalize(receivedData, Hinitial, ...
    noiseVariance, uw, cfg);
htfdeBits = qpsk_demap(htfdeSymbols(1:cfg.dataSymbols));

[sdSymbols, sdTrace, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hinitial, ...
    noiseVariance, uw, cfg, "soft", false);
sdBits = qpsk_demap(sdSymbols(1:cfg.dataSymbols));
[hdSymbols, hdTrace, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hinitial, ...
    noiseVariance, uw, cfg, "hard", false);
hdBits = qpsk_demap(hdSymbols(1:cfg.dataSymbols));
[iceSdSymbols, iceSdTrace, Hfinal] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hinitial, ...
    noiseVariance, uw, cfg, "soft", true);
iceSdBits = qpsk_demap(iceSdSymbols(1:cfg.dataSymbols));
[iceHdSymbols, iceHdTrace, ~] = ibdfe_equalize( ...
    receivedData, corrected(2, :), channelTraining, Hinitial, ...
    noiseVariance, uw, cfg, "hard", true);
iceHdBits = qpsk_demap(iceHdSymbols(1:cfg.dataSymbols));

out.methodErrors = [sum(zfBits ~= dataBits), sum(basicBits ~= dataBits), ...
    sum(htfdeBits ~= dataBits), sum(sdBits ~= dataBits), ...
    sum(hdBits ~= dataBits), sum(iceSdBits ~= dataBits), ...
    sum(iceHdBits ~= dataBits)];
out.methodBer = out.methodErrors / numel(dataBits);
out.figure318Errors = [sum(knownMmseBits ~= dataBits), ...
    sum(knownLcBits ~= dataBits), sum(knownHdBits ~= dataBits), ...
    sum(knownSdBits ~= dataBits), sum(basicBits ~= dataBits), ...
    sum(unknownLcBits ~= dataBits), sum(hdBits ~= dataBits), ...
    sum(sdBits ~= dataBits)];
out.basicErrors = out.methodErrors(2);
out.htfdeErrors = out.methodErrors(3);
out.jointErrors = out.htfdeErrors;
out.ibdfeErrors = out.methodErrors(6);
out.basicBer = out.basicErrors / numel(dataBits);
out.htfdeBer = out.htfdeErrors / numel(dataBits);
out.jointBer = out.htfdeBer;
out.ibdfeBer = out.ibdfeErrors / numel(dataBits);
out.methodSymbols = {zfSymbols, basicSymbols, htfdeSymbols, sdSymbols, ...
    hdSymbols, iceSdSymbols, iceHdSymbols};
out.basicSymbols = basicSymbols(1:cfg.dataSymbols);
out.htfdeSymbols = htfdeSymbols(1:cfg.dataSymbols);
out.jointSymbols = out.htfdeSymbols;
out.ibdfeSymbols = iceSdSymbols(1:cfg.dataSymbols);
out.bits = dataBits;
out.received = receivedData;
out.rawReceived = received(3, :);

diag.estimatedCfo = estimatedCfo;
diag.cfoError = estimatedCfo - cfg.cfoHz;
diag.dopplerSquaredError = abs(diag.cfoError)^2;
diag.estimatedPhase = estimatedPhase;
diag.phaseError = wrapped_phase_error(estimatedPhase - cfg.phaseOffset);
diag.phaseSquaredError = diag.phaseError^2;
diag.H = H;
diag.Hls = Hls;
diag.Hmmse = Hmmse;
diag.lsChannelNmse = channel_nmse(Hls, H);
diag.mmseChannelNmse = channel_nmse(Hmmse, H);
diag.Hinitial = Hinitial;
diag.noiseVariance = noiseVariance;
diag.Hjoint = htfdeTrace.effectiveChannel;
diag.Hib = Hfinal;
diag.htfdeCurve = htfdeTrace.errorCurve;
diag.htfdeInitialSymbols = htfdeTrace.initialSymbols;
diag.htfdeIterationSymbols = htfdeTrace.symbolsByIteration;
diag.jointCurve = diag.htfdeCurve;
diag.ibdfeCurve = iceSdTrace.errorCurve;
diag.ibdfeReliability = iceSdTrace.reliability;
diag.ibdfeFeedforward = iceSdTrace.feedforward;
diag.ibdfeFeedback = iceSdTrace.feedback;
diag.ibdfeNormalization = iceSdTrace.normalization;
diag.ibdfeVariants = struct("SD", sdTrace, "HD", hdTrace, ...
    "ICESD", iceSdTrace, "ICEHD", iceHdTrace);
end

function estimatedCfo = repeated_word_cfo(received, period, sampleRate)
% (3-51): Δφ̂ = (1/P)·∠(Σ r*(n)·r(n+P)); (3-53): f̂_d = Δφ̂/(2π·P·T_s)
part1 = received(1:period);
part2 = received(period + (1:period));
phasePerPeriod = angle(sum(conj(part1) .* part2));
estimatedCfo = phasePerPeriod * sampleRate / (2 * pi * period);
end

function H = estimate_channel_ls(receivedTraining, training, channelLength)
N = numel(training);
trainingSpectrum = fft(training);
receivedSpectrum = fft(receivedTraining);
estimate = receivedSpectrum .* conj(trainingSpectrum) ./ ...
    max(abs(trainingSpectrum).^2, eps);
impulse = ifft(estimate);
impulse(channelLength + 1:end) = 0;
H = fft(impulse);
end

function H = estimate_channel_mmse(receivedTraining, training, ...
        channelLength, noiseVariance, priorVariance)
N = numel(training);
trainingSpectrum = fft(training);
receivedSpectrum = fft(receivedTraining);
if isempty(priorVariance)
    Hls = estimate_channel_ls(receivedTraining, training, channelLength);
    priorVariance = max(mean(abs(Hls).^2), eps);
end
estimate = priorVariance * conj(trainingSpectrum) .* receivedSpectrum ./ ...
    (priorVariance * abs(trainingSpectrum).^2 + N * noiseVariance);
impulse = ifft(estimate);
impulse(channelLength + 1:end) = 0;
H = fft(impulse);
end

function phase = initial_phase_from_channel(H)
impulse = ifft(H);
phase = angle(impulse(1));
end

function error = wrapped_phase_error(value)
error = angle(exp(1j * value));
end

function nmse = channel_nmse(estimate, reference)
nmse = sum(abs(estimate - reference).^2) / ...
    max(sum(abs(reference).^2), eps);
end

function X = mmse_frequency_equalize(Y, H, noiseVariance)
X = Y .* conj(H) ./ (abs(H).^2 + noiseVariance);
end

function [symbols, trace] = htfde_equalize(received, H, ...
        noiseVariance, uw, cfg)
N = cfg.fftSize;
segmentLength = N / cfg.htfdeBranches;
symbols = ifft(mmse_frequency_equalize(fft(received), H, noiseVariance));
h = ifft(H);
h(cfg.channelEstimateLength + 1:end) = 0;
trace.errorCurve = zeros(1, cfg.htfdeIterations);
trace.branchPhase = zeros(cfg.htfdeIterations, cfg.htfdeBranches);
trace.initialSymbols = symbols;
trace.symbolsByIteration = complex(zeros(cfg.htfdeIterations, N));

for iteration = 1:cfg.htfdeIterations
    decision = qpsk_map(qpsk_demap(symbols));
    decision(cfg.dataSymbols + 1:end) = uw;
    reliability = symbol_reliability(symbols(1:cfg.dataSymbols), noiseVariance);
    predicted = ifft(H .* fft(decision));
    phaseCorrected = complex(zeros(1, N));
    for branch = 1:cfg.htfdeBranches
        indices = (branch - 1) * segmentLength + (1:segmentLength);
        phase = angle(sum(received(indices) .* conj(predicted(indices))));
        trace.branchPhase(iteration, branch) = phase;
        phaseCorrected(indices) = received(indices) * exp(-1j * phase);
    end
    postcursor = circular_postcursor(decision, h);
    timeEqualized = phaseCorrected - reliability * postcursor;
    effectiveImpulse = h;
    effectiveImpulse(2:end) = (1 - reliability) * effectiveImpulse(2:end);
    effectiveChannel = fft(effectiveImpulse);
    branchSpectrum = complex(zeros(1, N));
    for branch = 1:cfg.htfdeBranches
        indices = (branch - 1) * segmentLength + (1:segmentLength);
        branchSignal = complex(zeros(1, N));
        branchSignal(indices) = timeEqualized(indices);
        branchSpectrum = branchSpectrum + fft(branchSignal);
    end
    symbols = ifft(mmse_frequency_equalize( ...
        branchSpectrum, effectiveChannel, noiseVariance));
    trace.symbolsByIteration(iteration, :) = symbols;
    trace.errorCurve(iteration) = mean(abs(symbols - decision).^2);
end
trace.effectiveChannel = effectiveChannel;
end

function [outputs, diagnostics] = figure_313_outputs(example, frameDiagnostics, cfg)
knownChannel = frameDiagnostics.H;
uw = zadoff_chu(cfg.uwLength, 1);
branchCounts = [1, 2];
equalized = complex(zeros(numel(branchCounts), cfg.fftSize));
errorCurves = zeros(numel(branchCounts), cfg.htfdeIterations);
for index = 1:numel(branchCounts)
    localCfg = cfg;
    localCfg.htfdeBranches = branchCounts(index);
    [symbols, trace] = htfde_equalize(example.received, knownChannel, ...
        frameDiagnostics.noiseVariance, uw, localCfg);
    equalized(index, :) = normalize_constellation_gain(symbols);
    errorCurves(index, :) = trace.errorCurve;
end
preCompensation = ifft(mmse_frequency_equalize( ...
    fft(example.rawReceived), knownChannel, frameDiagnostics.noiseVariance));
outputs.input = preCompensation / ...
    max(sqrt(mean(abs(preCompensation).^2)), eps);
outputs.p1 = equalized(1, :);
outputs.p2 = equalized(2, :);
diagnostics.branchCounts = branchCounts;
diagnostics.errorCurves = errorCurves;
diagnostics.channelKnowledge = "Known simulated channel";
end

function output = normalize_constellation_gain(input)
decisions = qpsk_map(qpsk_demap(input));
gain = sum(decisions .* conj(input)) / max(sum(abs(input).^2), eps);
output = gain * input;
end

function postcursor = circular_postcursor(decisions, impulse)
postcursor = complex(zeros(size(decisions)));
for tap = 2:numel(impulse)
    postcursor = postcursor + impulse(tap) * ...
        circshift(decisions, [0, tap - 1]);
end
end

function [symbols, trace, H] = ibdfe_equalize(receivedData, ...
        receivedTraining, training, H, noiseVariance, uw, cfg, ...
        feedbackMode, updateChannel)
N = cfg.fftSize;
Y = fft(receivedData);
trainingSpectrum = fft(training);
trainingReceivedSpectrum = fft(receivedTraining);
feedbackSpectrum = complex(zeros(1, N));
reliability = 0;
trace.errorCurve = zeros(1, cfg.ibdfeIterations);
trace.reliability = zeros(1, cfg.ibdfeIterations);
trace.feedforward = complex(zeros(cfg.ibdfeIterations, N));
trace.feedback = complex(zeros(cfg.ibdfeIterations, N));
trace.normalization = complex(zeros(1, cfg.ibdfeIterations));
trace.feedbackMode = string(feedbackMode);
trace.updatesChannel = logical(updateChannel);

for iteration = 1:cfg.ibdfeIterations
    symbolVariance = max(1 - reliability, eps);
    A = conj(H) .* symbolVariance ./ ...
        max(abs(H).^2 .* symbolVariance + noiseVariance, eps);
    Gamma = mean(A .* H);
    feedforward = A ./ max(Gamma, eps);
    feedback = feedforward .* H - 1;
    trace.normalization(iteration) = mean(feedforward .* H);
    estimateSpectrum = feedforward .* Y - feedback .* feedbackSpectrum;
    symbols = ifft(estimateSpectrum);

    hardDecision = qpsk_map(qpsk_demap(symbols));
    if feedbackMode == "soft"
        feedbackMean = qpsk_posterior_mean(symbols, noiseVariance);
        reliability = min(0.999, mean(abs( ...
            feedbackMean(1:cfg.dataSymbols)).^2));
    else
        feedbackMean = hardDecision;
        reliability = symbol_reliability( ...
            symbols(1:cfg.dataSymbols), noiseVariance);
    end
    feedbackMean(cfg.dataSymbols + 1:end) = uw;
    feedbackSpectrum = fft(feedbackMean);

    if updateChannel
        regularization = cfg.channelRegularization * N * noiseVariance;
        numerator = conj(trainingSpectrum) .* trainingReceivedSpectrum + ...
            reliability * conj(feedbackSpectrum) .* Y;
        channelDenominator = abs(trainingSpectrum).^2 + ...
            reliability * abs(feedbackSpectrum).^2 + regularization;
        channelEstimate = numerator ./ channelDenominator;
        impulse = ifft(channelEstimate);
        impulse(cfg.channelEstimateLength + 1:end) = 0;
        H = fft(impulse);
    end

    hardDecision(cfg.dataSymbols + 1:end) = uw;
    trace.errorCurve(iteration) = mean(abs(symbols - hardDecision).^2);
    trace.reliability(iteration) = reliability;
    trace.feedforward(iteration, :) = feedforward;
    trace.feedback(iteration, :) = feedback;
end
assert(max(abs(trace.normalization - 1)) < 1e-10, ...
    "IBDFE feedforward coefficients violate the unit-gain constraint.");
end

function meanSymbols = qpsk_posterior_mean(symbols, noiseVariance)
hardSymbols = qpsk_map(qpsk_demap(symbols));
decisionVariance = mean(abs(symbols - hardSymbols).^2);
effectiveVariance = max(noiseVariance, decisionVariance);
scale = sqrt(2) / max(effectiveVariance, 1e-8);
meanSymbols = (tanh(scale * real(symbols)) + ...
    1j * tanh(scale * imag(symbols))) / sqrt(2);
end

function reliability = symbol_reliability(symbols, noiseVariance)
posterior = qpsk_posterior_mean(symbols, noiseVariance);
reliability = min(0.999, mean(abs(posterior).^2));
end

function result = guard_interval_frame(cfg, snrDb, h)
N = cfg.fftSize;
M = cfg.uwLength;
H = fft([h, zeros(1, N - numel(h))]);
noiseRatio = 10^(-snrDb / 10);
equalizer = conj(H) ./ (abs(H).^2 + noiseRatio);

cpBits = randi([0, 1], 1, 2 * N);
cpData = qpsk_map(cpBits);
cpStream = [cpData(end - M + 1:end), cpData];
cpReceived = add_awgn(conv(cpStream, h), snrDb);
cpBlock = cpReceived(M + (1:N));
cpEstimate = ifft(equalizer .* fft(cpBlock));
cpErrors = sum(qpsk_demap(cpEstimate) ~= cpBits);

zpBits = randi([0, 1], 1, 2 * N);
zpData = qpsk_map(zpBits);
zpReceived = add_awgn(conv([zpData, zeros(1, M)], h), snrDb);
zpBlock = zpReceived(1:N + M);
zpFolded = zpBlock(1:N);
zpFolded(1:M) = zpFolded(1:M) + zpBlock(N + (1:M));
zpEstimate = ifft(equalizer .* fft(zpFolded));
zpErrors = sum(qpsk_demap(zpEstimate) ~= zpBits);

uwBits = randi([0, 1], 1, 2 * cfg.dataSymbols);
uwData = qpsk_map(uwBits);
uw = zadoff_chu(M, 1);
uwBlock = [uwData, uw];
uwReceived = add_awgn(conv([uw, uwBlock], h), snrDb);
uwObservation = uwReceived(M + (1:N));
uwEstimate = ifft(equalizer .* fft(uwObservation));
uwErrors = sum(qpsk_demap(uwEstimate(1:cfg.dataSymbols)) ~= uwBits);

result.errors = [cpErrors, zpErrors, uwErrors];
result.bitCounts = [numel(cpBits), numel(zpBits), numel(uwBits)];
end

function symbols = qpsk_map(bits)
bits = logical(bits(:).');
symbols = ((2 * double(bits(1:2:end)) - 1) + ...
    1j * (2 * double(bits(2:2:end)) - 1)) / sqrt(2);
end

function bits = qpsk_demap(symbols)
symbols = symbols(:).';
bits = false(1, 2 * numel(symbols));
bits(1:2:end) = real(symbols) >= 0;
bits(2:2:end) = imag(symbols) >= 0;
bits = double(bits);
end

function sequence = zadoff_chu(lengthValue, root)
assert(gcd(lengthValue, root) == 1, ...
    "The Zadoff-Chu root and length must be coprime.");
index = 0:lengthValue - 1;
if mod(lengthValue, 2) == 0
    sequence = exp(-1j * pi * root * index.^2 / lengthValue);
else
    sequence = exp(-1j * pi * root * index .* (index + 1) / lengthValue);
end
end

function training = channel_training_sequence(blockLength, ...
        trainingSymbols, root)
training = complex(zeros(1, blockLength));
training(1:trainingSymbols) = zadoff_chu(trainingSymbols, root);
end

function channel = paper_table_32_channel(symbolRate)
delayMilliseconds = [0, 9.8, 16.4, 26.0, 31.1];
amplitudes = [0.5791, 0.6929, 0.3370, 0.1938, 0.1831];
phases = [0, 0.45, -0.90, 1.40, -0.50];
delaySymbols = round(delayMilliseconds * 1e-3 * symbolRate);
channel = complex(zeros(1, max(delaySymbols) + 1));
channel(delaySymbols + 1) = amplitudes .* exp(1j * phases);
channel = channel / norm(channel);
end

function output = add_awgn(input, snrDb)
signalPower = mean(abs(input).^2);
noisePower = signalPower * 10^(-snrDb / 10);
output = input + sqrt(noisePower / 2) * ...
    (randn(size(input)) + 1j * randn(size(input)));
end

function [h, info] = process_lake_style_data(cfg)
h = cfg.lakeImpulseResponse;
threshold = 0.05 * max(abs(h));
h(abs(h) < threshold) = 0;
h = h / norm(h);
info.threshold = threshold;
info.delaySpread = find(abs(h) > 0, 1, "last") - ...
    find(abs(h) > 0, 1, "first");
info.source = "synthetic fallback; replace with measured lake response";
end

function path = plot_results(result)
path = fullfile(result.outputDir, "chapter3_scfde_simulation.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [80, 80, 1450, 900], ...
    "Visible", "off");
tiledlayout(2, 3, "TileSpacing", "compact", "Padding", "compact");
nexttile;
plotFloor = 1e-5;
hold on;
markers = ["o-", "s-", "^-", "d-", "v-", ">-", "<-", "p-"];
for methodIndex = 1:numel(result.methodNames)
    semilogy(result.snrList, max(result.methodBer(methodIndex, :), plotFloor), ...
        markers(methodIndex), "LineWidth", 1.2);
end
set(gca, "YScale", "log");
grid on; xlabel("信噪比 SNR（dB）"); ylabel("误码率 BER");
title("第三章已选均衡算法");
legend(result.methodNames, "Location", "southwest");
nexttile;
hold on;
for methodIndex = 1:numel(result.guardMethodNames)
    semilogy(result.snrList, ...
        max(result.guardMethodBer(methodIndex, :), plotFloor), ...
        markers(methodIndex), "LineWidth", 1.2);
end
set(gca, "YScale", "log");
grid on; xlabel("信噪比 SNR（dB）"); ylabel("误码率 BER");
title("保护间隔结构比较");
legend(result.guardMethodNames, "Location", "southwest");
nexttile;
plot(abs(result.diagnostics.H - result.diagnostics.Hinitial), ...
    "LineWidth", 1.0, "DisplayName", "初始");
hold on;
plot(abs(result.diagnostics.H - result.diagnostics.Hib), ...
    "LineWidth", 1.0, "DisplayName", "IBDFE 迭代后");
grid on; title("信道频响估计误差"); xlabel("频率索引"); legend;
nexttile;
plot(real(result.example.received(1:min(300, end))));
grid on; title("接收块实部"); xlabel("码元索引");
nexttile;
hold on;
constellationCount = min(3, numel(result.methodIndices));
for displayIndex = 1:constellationCount
    methodIndex = result.methodIndices(displayIndex);
    symbols = result.example.methodSymbols{methodIndex};
    symbols = symbols(1:result.config.dataSymbols);
    plot(real(symbols), imag(symbols), ".");
end
axis equal; grid on; title("均衡后星座");
legend(result.methodNames(1:constellationCount));
nexttile;
plot(1:numel(result.diagnostics.ibdfeCurve), ...
    result.diagnostics.ibdfeCurve, "o-");
hold on;
plot(1:numel(result.diagnostics.ibdfeReliability), ...
    result.diagnostics.ibdfeReliability, "s-");
grid on; xlabel("迭代次数"); title("IBDFE 迭代状态");
legend("判决均方误差", "可靠度");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_estimation_results(result)
path = fullfile(result.outputDir, "chapter3_scfde_estimation.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [100, 100, 1180, 720], ...
    "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
plotFloor = 1e-12;
for estimationIndex = 1:numel(result.estimationNames)
    nexttile;
    semilogy(result.snrList, ...
        max(result.estimationMse(estimationIndex, :), plotFloor), "o-", ...
        "LineWidth", 1.3, "MarkerSize", 5);
    grid on;
    xlabel("信噪比 SNR (dB)");
    ylabel(estimation_metric_label(result.estimationNames(estimationIndex)));
    title(estimation_title(result.estimationNames(estimationIndex)));
end
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_figure_313(result)
path = fullfile(result.outputDir, "fig3_13_htfde_constellation.png");
fig = figure("Color", "w", "Position", [80, 80, 1500, 520], ...
    "Visible", "off");
tiledlayout(1, 3, "TileSpacing", "compact", "Padding", "compact");
symbolCount = result.config.dataSymbols;
series = {
    result.figure313.input(1:symbolCount)
    result.figure313.p1(1:symbolCount)
    result.figure313.p2(1:symbolCount)
    };
titles = ["(a) 相位补偿前输出", "(b) HTFDE，P = 1", ...
    "(c) HTFDE，P = 2"];
for panelIndex = 1:3
    nexttile;
    plot(real(series{panelIndex}), imag(series{panelIndex}), ".", ...
        "Color", [0.18, 0.18, 0.18], "MarkerSize", 5);
    axis equal; xlim([-2, 2]); ylim([-2, 2]); grid on;
    xlabel("同相分量"); ylabel("正交分量"); title(titles(panelIndex));
end
sgtitle(sprintf("图 3-13  时频域联合均衡器输出信号星座图（SNR = %.0f dB）", ...
    result.config.snrDb), "FontName", "Microsoft YaHei", ...
    "FontSize", 17, "FontWeight", "bold");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei", ...
    "FontSize", 11);
exportgraphics(fig, path, "Resolution", 220);
close(fig);
end

function path = plot_figure_318(result)
path = fullfile(result.outputDir, "fig3_18_equalizer_ber.png");
fig = figure("Color", "w", "Position", [80, 80, 1100, 760], ...
    "Visible", "off");
markers = ["o-", "s-", "^-", "v-", "o--", "s--", "^--", "v--"];
colors = [lines(4); lines(4)];
hold on;
for displayIndex = 1:numel(result.figure318Names)
    bitCounts = result.figure318BitCounts(displayIndex, :);
    plotFloor = 0.5 ./ bitCounts;
    values = max(result.figure318Ber(displayIndex, :), plotFloor);
    semilogy(result.snrList, values, markers(displayIndex), ...
        "Color", colors(displayIndex, :), "LineWidth", 1.35, ...
        "MarkerSize", 7);
end
grid on;
set(gca, "YScale", "log", "YLim", [1e-7, 1], ...
    "FontName", "Microsoft YaHei", "FontSize", 11);
xlabel("信噪比 SNR（dB）"); ylabel("误码率 BER");
title("图 3-18  不同均衡算法误码率性能仿真", ...
    "FontWeight", "bold");
legend(result.figure318Names, "Location", "southwest", ...
    "NumColumns", 2);
exportgraphics(fig, path, "Resolution", 220);
close(fig);
end

function label = estimation_metric_label(name)
switch string(name)
    case "Residual-Doppler-PN"
        label = "频率估计均方误差 (Hz^2)";
    case "Initial-Phase-PN"
        label = "相位估计均方误差 (rad^2)";
    otherwise
        label = "归一化均方误差 NMSE";
end
end

function titleValue = estimation_title(name)
switch string(name)
    case "Residual-Doppler-PN"
        titleValue = "残余多普勒频移估计";
    case "Initial-Phase-PN"
        titleValue = "初始相位旋转估计与补偿";
    case "LS-CE"
        titleValue = "LS 信道估计";
    case "MMSE-CE"
        titleValue = "MMSE 信道估计";
end
end

function value = opt(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function selected = select_method_indices(available, requested, label)
requested = string(requested);
if isscalar(requested) && strcmpi(requested, "all")
    selected = 1:numel(available);
    return;
end
selected = zeros(1, numel(requested));
for index = 1:numel(requested)
    match = find(strcmpi(requested(index), available), 1);
    assert(~isempty(match), "SCFDE:UnknownMethod", ...
        "Unknown %s method: %s. Available: %s", ...
        label, requested(index), strjoin(available, ", "));
    selected(index) = match;
end
assert(numel(unique(selected)) == numel(selected), ...
    "SCFDE:DuplicateMethod", "A %s method was selected twice.", label);
end
