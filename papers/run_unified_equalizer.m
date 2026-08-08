function results = run_unified_equalizer(options)
%RUN_UNIFIED_EQUALIZER Unified entry: run any equalizer(s) from all 6 book
% chapters on a shared link, with plug-and-play selection.
%
% Usage:
%   results = run_unified_equalizer                        % default quick
%   results = run_unified_equalizer(struct("equalizers", "all"))
%   results = run_unified_equalizer(struct("equalizers", ...
%       ["htfde", "cck-rake", "csk-ese"], "scenario", "auto"))
%
% Options (struct):
%   equalizers  - "all" | ID string | string array | function handle | cell
%                 (see scfde.receiver_bank_pluggable / equalizer_registry)
%   scenario    - "qpsk"  (ch2+ch3 shared symbol link, default)
%               - "cck"   (Chapter 5 chip link)
%               - "csk"   (Chapter 6 spread-spectrum link)
%               - "auto"  (infer from the requested equalizer IDs)
%   snrDb       - passband/EsN0 SNR in dB (default 18)
%   symbols     - data blocks (default 8)
%   frameCount  - Monte Carlo frames (default 50)
%   makePlot    - draw a BER bar/line figure (default true)
%   randomSeed  - RNG seed (default 42)
%
% Returns results with fields: ids, names, ber, berBySnr, config, figurePath.

rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "modules"));
addpath(fullfile(rootDir, "engineering_simulation"));
addpath(fullfile(rootDir, "examples"));

if nargin < 1
    options = struct();
end
cfg = struct("equalizers", "all", "scenario", "qpsk", ...
    "snrDb", 18, "symbols", 8, "frameCount", 50, ...
    "makePlot", true, "randomSeed", 42);
names = fieldnames(options);
for index = 1:numel(names)
    cfg.(names{index}) = options.(names{index});
end
rng(cfg.randomSeed, "twister");

if strcmpi(cfg.scenario, "auto")
    cfg.scenario = infer_scenario(cfg.equalizers);
end

switch lower(cfg.scenario)
    case "qpsk"
        results = run_qpsk_scenario(cfg);
    case "turbo"
        results = run_turbo_scenario(cfg);
    case "cck"
        results = run_cck_scenario(cfg);
    case "csk"
        results = run_csk_scenario(cfg);
    otherwise
        error("SCFDE:UnknownScenario", ...
            "scenario must be qpsk, turbo, cck, csk, or auto.");
end

% BER statistics metadata: total bits, error bits and the 95%
% Clopper-Pearson interval per equalizer.  A zero-error result is
% reported as an interval, not as an exact BER = 0.
if isfield(results, "totalBits")
    results.errorBits = round(results.ber .* results.totalBits);
    [ciLo, ciHi] = clopper_pearson_95(results.errorBits, results.totalBits);
    results.berLower95 = ciLo;
    results.berUpper95 = ciHi;
    results.totalBits = results.totalBits;
    results.reachedTarget = results.totalBits >= 1;
end
results.gitCommit = git_commit_short();
results.matlabVersion = version;
results.timestamp = datetime("now");
results.rngSeed = rng_seed();

if cfg.makePlot && numel(results.ids) > 1
    results.figurePath = plot_unified(results);
end
end

function [lo95, hi95] = clopper_pearson_95(errors, bits)
% Exact 95% Clopper-Pearson binomial interval (0 when errors = 0).
errors = double(errors(:));
bits = double(bits(:));
alpha = 0.05;
lo95 = zeros(size(errors));
hi95 = zeros(size(errors));
for index = 1:numel(errors)
    x = errors(index);
    n = bits(index);
    if x == 0
        lo95(index) = 0;
        hi95(index) = 1 - (alpha / 2)^(1 / max(n, 1));
    elseif x == n
        lo95(index) = (alpha / 2)^(1 / max(n, 1));
        hi95(index) = 1;
    else
        lo95(index) = betainv(alpha / 2, x, n - x + 1);
        hi95(index) = betainv(1 - alpha / 2, x + 1, n - x);
    end
end
end

function commit = git_commit_short()
commit = "";
try
    [status, out] = system("git -C " + ...
        string(fileparts(fileparts(mfilename("fullpath")))) + ...
        " rev-parse --short HEAD 2>nul");
    if status == 0
        commit = strtrim(string(out));
    end
catch
    commit = "";
end
end

function seed = rng_seed()
state = rng;
if isfield(state, "Seed")
    seed = state.Seed;
else
    seed = [];
end
end

%% Shared QPSK link (Chapters 2 and 3 equalizers)
function results = run_qpsk_scenario(cfg)
N = 184;              % block length
dataSymbols = 120;    % data per block
uwLength = N - dataSymbols;
link = struct("trainingSymbols", 64, "dataSymbols", dataSymbols, ...
    "feedforwardTaps", 12, "feedbackTaps", 6, ...
    "fftSize", N, "uwLength", uwLength, "channelEstimateLength", 12, ...
    "htfdeBranches", 4, "htfdeIterations", 3, ...
    "ibdfeIterations", 4, "channelRegularization", 0.1, ...
    "symbolRate", 4000, "dopplerHz", 0, ...
    "pathDelays", [0, 1, 3], ...
    "pathGains", [1, 0.7 * exp(1j * 0.5), 0.3 * exp(-1j * 0.8)], ...
    "numSubbands", 4, "ptrRegularization", 0.02, ...
    "lmsStep", 0.008, "nlmsStep", 0.35, ...
    "rlsForgettingFactor", 0.985, "rlsInitialInverseCorrelation", 100, ...
    "dpllProportionalGain", 0.020, "dpllIntegralGain", 0.0004, ...
    "snrDb", cfg.snrDb, "noiseVariance", 10^(-cfg.snrDb / 10), ...
    "modulation", "qpsk", ...
    "iterations", 4, "infoBits", 120, ...
    "turboDecoderMode", "Log-MAP", "baselineDecoder", "Log-MAP", ...
    "tdAdaptiveTaps", 16, "tdNlmsStep", 0.35, ...
    "blmsStep", 0.06, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "turboDamping", 0.75);
link.equalizers = cfg.equalizers;
% Build the multipath impulse response honoring the configured delays.
impulse = zeros(1, N);
for path = 1:numel(link.pathGains)
    impulse(link.pathDelays(path) + 1) = link.pathGains(path);
end
impulse = impulse / norm(impulse);
H = fft(impulse);
totalErrors = zeros(1, 0);
totalBits = zeros(1, 0);
for frame = 1:cfg.frameCount
    bits = randi([0, 1], 1, 2 * dataSymbols);
    data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
    uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
    block = [data, uw];
    received = ifft(H .* fft(block));
    received = received + sqrt(link.noiseVariance / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    src = struct("data", data, "tx", block, ...
        "training", block(1:link.trainingSymbols));
    ch = struct("received", received, "impulse", impulse, ...
        "branches", [received; received]);
    recv = scfde.receiver_bank_pluggable(ch, src, link);
    if isempty(totalErrors)
        results.ids = recv.ids;
        results.names = recv.names;
        totalErrors = zeros(1, numel(recv.ids));
        totalBits = zeros(1, numel(recv.ids));
    end
    for eq = 1:numel(recv.ids)
        out = recv.outputs{eq}(:).';
        if numel(out) == N
            % ch2 TDE: full-block output; data = symbols after the training
            % prefix up to dataSymbols (UW tail excluded)
            payload = link.trainingSymbols + 1:dataSymbols;
            ref = block(payload);
        else
            payload = 1:min(numel(out), dataSymbols);
            ref = data(payload);
        end
        % Bit-level comparison for QPSK (real/imag >= 0), so the reported
        % metric is BER, not SER.
        errSym = out(payload);
        refSym = ref;
        errBits = [real(errSym) >= 0, imag(errSym) >= 0];
        refBits = [real(refSym) >= 0, imag(refSym) >= 0];
        totalErrors(eq) = totalErrors(eq) + sum(errBits ~= refBits);
        totalBits(eq) = totalBits(eq) + numel(refBits);
    end
end
results.ber = totalErrors ./ totalBits;
results.totalBits = totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "qpsk";
end

%% Chapter 5 CCK link
function results = run_cck_scenario(cfg)
[book, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
imp = scfde.equalizers.ch5_short_turbo_channel();
nv = 10^(-cfg.snrDb / 10);
link = struct("noiseVariance", nv, "receiverCandidateLimit", 128, ...
    "turboIterations", 3, "snrDb", cfg.snrDb);
totalErrors = [];
totalBits = 0;
for frame = 1:cfg.frameCount
    idx = randi(size(book, 1), 1, cfg.symbols);
    chips = reshape(book(idx, :).', 1, []);
    received = filter(imp, 1, [chips, zeros(1, numel(imp) - 1)]);
    received = received + sqrt(nv / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    ch = struct("received", received, "impulse", imp, ...
        "branches", [received; received]);
    src = struct("data", reshape(book(idx, :).', 1, []), ...
        "tx", chips, "training", chips(1:32));
    link.equalizers = cfg.equalizers;
    recv = scfde.receiver_bank_pluggable(ch, src, link);
    if isempty(totalErrors)
        totalErrors = zeros(1, numel(recv.ids));
        results.ids = recv.ids;
        results.names = recv.names;
    end
    for eq = 1:numel(recv.ids)
        trace = recv.traces{eq};
        if isfield(trace, "indices")
            % CCK receivers expose the detected codeword indices; map
            % them to bits through the bit table (chip distance is not
            % the bit Hamming distance, so this is the true BER).
            detectedIdx = trace.indices(:).';
            detectedIdx = detectedIdx(1:cfg.symbols);
        else
            % Recover indices from the chip-level output by nearest
            % codeword in Euclidean distance.  The output is a row of
            % (symbols * chips) chips; reshape column-major keeps each
            % codeword contiguous per column, then transpose so each row
            % is one codeword.  CCK chips live on the axial QPSK phases
            % {1, j, -1, -j}, so the soft chips are matched directly
            % against the codebook without slicing to the diagonal
            % constellation (hard_qpsk would merge codewords).
            detected = reshape(recv.outputs{eq}(:).', ...
                size(book, 2), []).';
            distance = abs(book - reshape(detected.', 1, ...
                size(book, 2), []));
            distance = squeeze(sum(distance .^ 2, 2));
            [~, detectedIdx] = min(distance, [], 1);
        end
        txBits = reshape(bitTable(idx, :).', 1, []);
        rxBits = reshape(bitTable(detectedIdx, :).', 1, []);
        totalErrors(eq) = totalErrors(eq) + sum(rxBits ~= txBits);
    end
    totalBits = totalBits + numel(txBits);
end
results.ber = totalErrors / totalBits;
results.totalBits = totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "cck";
end

%% Chapter 6 CSK link
function results = run_csk_scenario(cfg)
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, bits] = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
nv = 1 / (size(bits, 2) * 10^(cfg.snrDb / 10));
link = struct("noiseVariance", nv, "codeLength", codeLength, ...
    "cskOrder", 4, "conventionalUsers", 1, "idmaUsers", 1, ...
    "innerIterations", 3, "outerIterations", 2, "snrDb", cfg.snrDb);
channels = scfde.equalizers.ch6_dictionary_channels(imp, 1, codeLength);
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, channels, 1);
totalErrors = 0;
totalBits = 0;
totalErrors = [];
for frame = 1:cfg.frameCount
    idx6 = randi(4, cfg.symbols, 1);
    received = zeros(cfg.symbols, codeLength);
    for s = 1:cfg.symbols
        received(s, :) = dicts{1}(idx6(s), :);
    end
    received = received + sqrt(nv / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    flat = reshape(received.', 1, []);
    ch = struct("received", flat, "impulse", imp, "branches", [flat; flat]);
    src = struct("data", ones(1, cfg.symbols * codeLength), ...
        "tx", flat, "training", ones(1, 32));
    link.equalizers = cfg.equalizers;
    recv = scfde.receiver_bank_pluggable(ch, src, link);
    if isempty(totalErrors)
        totalErrors = zeros(1, numel(recv.ids));
        results.ids = recv.ids;
        results.names = recv.names;
    end
    for eq = 1:numel(recv.ids)
        trace = recv.traces{eq};
        if isfield(trace, "indices")
            det = trace.indices(:);
            if numel(det) == numel(idx6) * 3 || ...
                    (numel(det) > numel(idx6) && mod(numel(det), numel(idx6)) == 0)
                % iterative detectors store (iterations, symbols, users)
                det = det(end - numel(idx6) + 1:end);
            end
        elseif isfield(trace, "history")
            % soft-SIC history: (iterations, symbols, users)
            det = squeeze(trace.history(end, :, 1)).';
        else
            % Column-major reshape keeps each symbol's code-length
            % segment contiguous; transpose so each row is one symbol.
            det = reshape(recv.outputs{eq}(:), codeLength, []).';
            distance = abs(book - reshape(det.', 1, ...
                size(book, 2), []));
            distance = squeeze(sum(distance .^ 2, 2));
            [~, det] = min(distance, [], 1);
            det = det(:);
        end
        % Map detected symbol indices to bits through the bit table and
        % count bit errors (an M-ary symbol error may flip 1 or more
        % bits, so SER is not BER).
        txBits = reshape(bits(idx6, :).', 1, []);
        rxBits = reshape(bits(det, :).', 1, []);
        totalErrors(eq) = totalErrors(eq) + sum(rxBits ~= txBits);
    end
    totalBits = totalBits + numel(txBits);
end
results.ber = totalErrors / totalBits;
results.totalBits = totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "csk";
end

function scenario = infer_scenario(equalizers)
ids = strings(1, 0);
if iscell(equalizers)
    for k = 1:numel(equalizers)
        if ischar(equalizers{k}) || isstring(equalizers{k})
            ids(end + 1) = string(equalizers{k}); %#ok<AGROW>
        end
    end
elseif ischar(equalizers) || isstring(equalizers)
    ids = string(equalizers);
end
if any(contains(ids, "cck-"))
    scenario = "cck";
elseif any(contains(ids, "csk-"))
    scenario = "csk";
elseif any(contains(ids, "turbo") | contains(ids, "teq") | ...
        contains(ids, "fd-dfe"))
    scenario = "turbo";
else
    scenario = "qpsk";
end
end

%% Chapter 4 turbo link (convolutional-coded BPSK frame)
function results = run_turbo_scenario(cfg)
% Chapter-4 coded frame matching the book FDDA-TEQ simulation
% parameters (Fig. 4-29..4-32): convolutional code (7,5) octal, rate
% 1/2, blocks of 256 training + 1024 info symbols, I_inner=2,
% I_outer=3, mu_f=0.2, mu_b=0.01.  The book uses QPSK; this scenario
% transmits BPSK (the implemented turbo equalizers are BPSK LLR
% chains), which is recorded as a modulation deviation in the
% benchmark.
infoBits = 512;                 % 1024 coded bits = 512 info (rate 1/2)
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(-cfg.snrDb / 10);
link = struct("noiseVariance", nv, "iterations", 3, ...
    "infoBits", infoBits, "turboDecoderMode", "Log-MAP", ...
    "baselineDecoder", "Log-MAP", "tdAdaptiveTaps", 16, ...
    "tdNlmsStep", 0.35, "blmsStep", 0.2, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "turboDamping", 0.75, ...
    "fddaStepFf", 0.2, "fddaStepFb", 0.01, ...
    "snrDb", cfg.snrDb);
totalErrors = [];
totalBits = 0;
rng(2024, "twister");
permutation = randperm(2 * infoBits);  % fixed interleaver pattern
for frame = 1:cfg.frameCount
    info = randi([0, 1], 1, infoBits);
    coded = scfde.equalizers.ch4_convolutional_encode(info);
    N = numel(coded);
    tx = 1 - 2 * coded(permutation);
    H = fft([imp, zeros(1, N - numel(imp))]);
    received = ifft(H .* fft(tx));
    received = received + sqrt(nv / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    ch = struct("received", received, "impulse", imp, ...
        "branches", [received; received]);
    src = struct("data", 1 - 2 * info, "tx", tx, ...
        "training", tx(1:trainingSymbols));
    link.equalizers = cfg.equalizers;
    recv = scfde.receiver_bank_pluggable(ch, src, link);
    if isempty(totalErrors)
        totalErrors = zeros(1, numel(recv.ids));
        results.ids = recv.ids;
        results.names = recv.names;
    end
    ref = 1 - 2 * info;
    for eq = 1:numel(recv.ids)
        out = recv.outputs{eq}(:).';
        totalErrors(eq) = totalErrors(eq) + ...
            sum(out(1:numel(ref)) ~= ref);
    end
    totalBits = totalBits + numel(ref);
end
results.ber = totalErrors / totalBits;
results.totalBits = totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "turbo";
end

function path = plot_unified(results)
path = fullfile(tempdir, "unified_equalizer_ber.png");
fig = figure("Color", "w", "Position", [80, 80, 900, 520], "Visible", "off");
bar(1:numel(results.ber), max(results.ber, 1e-6));
set(gca, "YScale", "log", "XTick", 1:numel(results.ber), ...
    "XTickLabel", results.ids);
ylim([1e-4, 1]);
grid on;
xlabel("Equalizer"); ylabel("BER");
title(sprintf("Unified equalizer comparison (%s, SNR=%g dB)", ...
    results.scenario, results.config.snrDb));
exportgraphics(fig, path, "Resolution", 150);
close(fig);
end

function symbol = hard_qpsk(value)
symbol = ((1 - 2 * (real(value) < 0)) + ...
    1j * (1 - 2 * (imag(value) < 0))) / sqrt(2);
end
