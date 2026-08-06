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

if cfg.makePlot && numel(results.ids) > 1
    results.figurePath = plot_unified(results);
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
impulse = [link.pathGains, zeros(1, N - numel(link.pathGains))];
H = fft(impulse);
totalErrors = zeros(1, 0);
totalBits = 0;
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
    ch = struct("received", received, "impulse", link.pathGains, ...
        "branches", [received; received]);
    recv = scfde.receiver_bank_pluggable(ch, src, link);
    if frame == 1
        results.ids = recv.ids;
        results.names = recv.names;
        totalErrors = zeros(1, numel(recv.ids));
    end
    for eq = 1:numel(recv.ids)
        out = recv.outputs{eq}(:).';
        if numel(out) == N
            % ch2 TDE: full-block output; training = first trainingSymbols
            % symbols, data = the rest up to dataSymbols (UW excluded)
            payload = link.trainingSymbols + 1:dataSymbols;
            ref = block(payload);
        else
            payload = 1:min(numel(out), dataSymbols);
            ref = data(payload);
        end
        totalErrors(eq) = totalErrors(eq) + ...
            sum(out(payload) ~= ref);
    end
    totalBits = totalBits + dataSymbols;
end
results.ber = totalErrors / totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "qpsk";
end

%% Chapter 5 CCK link
function results = run_cck_scenario(cfg)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
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
        totalErrors(eq) = totalErrors(eq) + ...
            sum(recv.outputs{eq}(:) ~= src.data(:));
    end
    totalBits = totalBits + numel(src.data);
end
results.ber = totalErrors / totalBits;
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
            totalErrors(eq) = totalErrors(eq) + sum(det ~= idx6);
        elseif isfield(trace, "history")
            % soft-SIC history: (iterations, symbols, users)
            det = squeeze(trace.history(end, :, 1)).';
            totalErrors(eq) = totalErrors(eq) + sum(det ~= idx6);
        else
            totalErrors(eq) = totalErrors(eq) + ...
                sum(recv.outputs{eq}(:) ~= src.data(:));
        end
    end
    totalBits = totalBits + numel(idx6);
end
results.ber = totalErrors / totalBits;
results.traces = recv.traces;
results.config = link;
results.scenario = "csk";
end

function scenario = infer_scenario(equalizers)
ids = string(equalizers);
if iscell(ids)
    ids = string([ids{:}]);
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
infoBits = 120;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(-cfg.snrDb / 10);
link = struct("noiseVariance", nv, "iterations", 4, ...
    "infoBits", infoBits, "turboDecoderMode", "Log-MAP", ...
    "baselineDecoder", "Log-MAP", "tdAdaptiveTaps", 16, ...
    "tdNlmsStep", 0.35, "blmsStep", 0.06, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "turboDamping", 0.75, ...
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
        "training", tx(1:64));
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
