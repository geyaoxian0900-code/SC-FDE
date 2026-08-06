function results = simulate_chapter2_single_carrier_tde(options)
%SIMULATE_CHAPTER2_SINGLE_CARRIER_TDE Modular single-carrier TDE suite.
%   Set OPTIONS.modules.source, channel, receiverBank, metric, or plot to a
%   compatible function handle to replace that stage without editing this
%   experiment.

if nargin < 1
    options = struct();
end
ensure_module_path();

defaults.snrDb = 12;
defaults.berSnrDb = 0:2:14;
defaults.berSweepFrames = 1;
defaults.dopplerHz = 1.5;
defaults.symbolRate = 4000;
defaults.trainingSymbols = 256;
defaults.dataSymbols = 1200;
defaults.feedforwardTaps = 24;
defaults.feedbackTaps = 12;
defaults.randomSeed = 20260724;
defaults.makePlot = true;
defaults.numSubbands = 4;
defaults.ptrRegularization = 0.02;
defaults.methods = "all";
defaults.lmsStep = 0.008;
defaults.nlmsStep = 0.35;
defaults.rlsForgettingFactor = 0.985;
defaults.rlsInitialInverseCorrelation = 100;
defaults.dpllProportionalGain = 0.020;
defaults.dpllIntegralGain = 0.0004;
defaults.pathDelays = [0, 2, 5, 8];
defaults.pathGains = [1, 0.72 * exp(1j * 0.5), ...
    0.48 * exp(-1j * 1.0), 0.30 * exp(1j * 1.7)];
defaults.outputDir = fullfile(fileparts(mfilename("fullpath")), "results");
defaults.modules = struct();
% This entry uses a BPSK training+data linear-convolution frame, which is
% compatible with the Chapter 2 TDE equalizers only. Frequency-domain
% equalizers (Chapter 3) require the QPSK data+UW cyclic frame and are
% selected through run_unified_equalizer instead.
defaults.equalizers = ["dfe", "lms-dfe", "nlms-dfe", "rls-dfe", ...
    "dpll-dfe", "mc-lms-dfe", "mc-nlms-dfe", "mc-rls-dfe", ...
    "ptr-dfe", "subband-ptr-dfe"];
cfg = scfde.merge_struct(defaults, options);

assert(numel(cfg.pathDelays) == numel(cfg.pathGains), ...
    "Path configuration mismatch.");
assert(~isempty(cfg.berSnrDb) && all(isfinite(cfg.berSnrDb)), ...
    "berSnrDb must contain finite SNR values.");
assert(isscalar(cfg.berSweepFrames) && cfg.berSweepFrames >= 1 && ...
    cfg.berSweepFrames == floor(cfg.berSweepFrames), ...
    "berSweepFrames must be a positive integer.");
rng(cfg.randomSeed, "twister");
modules = scfde.default_modules(cfg.modules);
pipeline = scfde.run_pipeline(cfg, modules);

results = pipeline;
results.names = pipeline.receiver.names;
results.receiverIds = pipeline.receiver.ids;
results.ber = pipeline.metrics.ber;
results.tx = pipeline.source.tx;
results.channelImpulse = pipeline.channel.impulse;
results.received = pipeline.channel.received;
results.receivers = pipeline.receiver.outputs;
results.learningMse = pipeline.receiver.learningMse;
berSweep = run_ber_sweep(cfg, modules, pipeline.receiver.ids);
results.berSnrDb = berSweep.snrDb;
results.berBySnr = berSweep.ber;
results.berSweepFrames = berSweep.frameCount;
if isfield(pipeline.receiver, "estimates")
    results.equalizerEstimates = pipeline.receiver.estimates;
else
    results.equalizerEstimates = pipeline.receiver.outputs;
end
if isfield(pipeline.receiver, "traces")
    results.equalizerTraces = pipeline.receiver.traces;
else
    results.equalizerTraces = {};
end

fprintf("\n===== Chapter 2 modular single-carrier TDE simulation =====\n");
fprintf("SNR=%.1f dB, Doppler=%.2f Hz, data=%d symbols\n", ...
    cfg.snrDb, cfg.dopplerHz, cfg.dataSymbols);
fprintf("BER-SNR scan: %d points, %d frame(s) per point\n", ...
    numel(results.berSnrDb), results.berSweepFrames);
for receiverIndex = 1:numel(results.names)
    fprintf("%-28s BER=%.5g\n", ...
        results.names(receiverIndex), results.ber(receiverIndex));
end

results.outputPath = "";
results.figurePaths = strings(0, 1);
if cfg.makePlot
    if isempty(modules.plot)
        if isequal(string(results.receiverIds), ["dfe", "nlms-dfe", ...
                "dpll-dfe", "mc-nlms-dfe", "ptr-dfe", "subband-ptr-dfe"])
            results.figurePaths = visualize_sc_tde_stages(results);
        else
            results.figurePaths = plot_selected_methods(results);
        end
        results.outputPath = results.figurePaths(1);
    else
        results.outputPath = modules.plot(results);
        results.figurePaths = string(results.outputPath(:));
    end
end
end

function sweep = run_ber_sweep(cfg, modules, expectedReceiverIds)
snrDb = reshape(double(cfg.berSnrDb), 1, []);
frameCount = cfg.berSweepFrames;
receiverIds = expectedReceiverIds(:);
ber = zeros(numel(receiverIds), numel(snrDb));
frameBer = zeros(numel(receiverIds), frameCount);
for snrIndex = 1:numel(snrDb)
    frameBer(:) = 0;
    for frameIndex = 1:frameCount
        sweepCfg = cfg;
        sweepCfg.snrDb = snrDb(snrIndex);
        sweepCfg.makePlot = false;
        rng(cfg.randomSeed + frameIndex - 1, "twister");
        pipeline = scfde.run_pipeline(sweepCfg, modules);
        assert(isequal(pipeline.receiver.ids(:), receiverIds), ...
            "SCFDE:InconsistentReceiverSweep", ...
            "Receiver selection changed during the BER-SNR sweep.");
        frameBer(:, frameIndex) = pipeline.metrics.ber(:);
    end
    ber(:, snrIndex) = mean(frameBer, 2);
end
sweep.snrDb = snrDb;
sweep.ber = ber;
sweep.frameCount = frameCount;
sweep.receiverIds = receiverIds;
end

function paths = plot_selected_methods(results)
path = fullfile(results.config.outputDir, "sc_tde_selected_methods.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [80, 80, 1200, 520], ...
    "Visible", "off");
tiledlayout(1, 2, "TileSpacing", "compact", "Padding", "compact");
labels = selected_method_labels(results.receiverIds, results.names);
berFloor = 0.5 / (results.config.dataSymbols * results.berSweepFrames);
nexttile; hold on;
colors = lines(numel(results.names));
for methodIndex = 1:numel(results.names)
    semilogy(results.berSnrDb, max(results.berBySnr(methodIndex, :), berFloor), ...
        "-o", "Color", colors(methodIndex, :), "LineWidth", 1.2, ...
        "MarkerSize", 5, "DisplayName", labels(methodIndex));
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("误码率 BER");
ylim([berFloor / 2, 1]);
title("第二章 SC-TDE 均衡算法 BER-SNR 对比");
legend("Location", "southwest", "NumColumns", 2);
nexttile; hold on;
payload = results.config.trainingSymbols + (1:results.config.dataSymbols);
showCount = min(180, numel(payload));
for methodIndex = 1:numel(results.names)
    plot(real(results.equalizerEstimates{methodIndex}( ...
        payload(1:showCount))), "Color", colors(methodIndex, :), ...
        "DisplayName", labels(methodIndex));
end
grid on; xlabel("数据码元索引"); ylabel("均衡器输出实部");
title(sprintf("诊断输出：SNR = %.1f dB", results.config.snrDb));
legend("Location", "best", "NumColumns", 2);
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
paths = string(path);
end

function labels = selected_method_labels(ids, fallback)
canonicalIds = ["dfe", "lms-dfe", "nlms-dfe", "rls-dfe", "dpll-dfe", ...
    "mc-lms-dfe", "mc-nlms-dfe", "mc-rls-dfe", "ptr-dfe", "subband-ptr-dfe"];
canonicalNames = ["传统 DFE", "LMS 自适应 DFE", "NLMS 自适应 DFE", ...
    "RLS 自适应 DFE", "DPLL-DFE", "多通道 LMS DFE", ...
    "多通道 NLMS DFE", "多通道 RLS DFE", "被动时反 DFE", ...
    "子带被动时反 DFE"];
labels = string(fallback);
for methodIndex = 1:numel(ids)
    match = find(strcmpi(ids(methodIndex), canonicalIds), 1);
    if ~isempty(match)
        labels(methodIndex) = canonicalNames(match);
    end
end
end

function ensure_module_path()
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.default_modules"))
    addpath(moduleDir);
end
end
