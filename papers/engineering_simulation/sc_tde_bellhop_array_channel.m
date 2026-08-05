function channel = sc_tde_bellhop_array_channel(options)
%SC_TDE_BELLHOP_ARRAY_CHANNEL Build the paper's eight-element array channel.

if nargin < 1
    options = struct();
end
cfg.source = string(get_option(options, "source", "paper-figure"));
cfg.bellhopRoot = get_option(options, "bellhopRoot", ...
    "D:\MATLAB\atWin10_2020_11_4\atWin10_2020_11_4");
cfg.waterDepth = get_option(options, "waterDepth", 100);
cfg.sourceDepth = get_option(options, "sourceDepth", 50);
cfg.receiverDepths = get_option(options, "receiverDepths", 40:1.5:50.5);
cfg.rangeKm = get_option(options, "rangeKm", 5);
cfg.carrierHz = get_option(options, "carrierHz", 6000);
cfg.symbolRate = get_option(options, "symbolRate", 4000);
cfg.waterSoundSpeedSurface = get_option(options, "waterSoundSpeedSurface", 1500);
cfg.waterSoundSpeedBottom = get_option(options, "waterSoundSpeedBottom", 1490);
cfg.maxDelaySymbols = get_option(options, "maxDelaySymbols", 150);
cfg.maxPathsPerSensor = get_option(options, "maxPathsPerSensor", 40);
cfg.bottomSoundSpeed = get_option(options, "bottomSoundSpeed", 1700);
cfg.bottomDensity = get_option(options, "bottomDensity", 1.8);
cfg.bottomAttenuation = get_option(options, "bottomAttenuation", 0.8);
cfg.outputDir = get_option(options, "outputDir", ...
    fullfile(fileparts(mfilename("fullpath")), "results", ...
    "sc_tde_paper_reproduction", "bellhop"));

if strcmpi(cfg.source, "paper-figure")
    channel = paper_figure_digitized_channel(cfg);
    return;
end
assert(strcmpi(cfg.source, "bellhop"), ...
    "Unknown Chapter 2 channel source: %s", cfg.source);

executable = fullfile(cfg.bellhopRoot, "windows-bin-20201102", "bellhop.exe");
readerDirectory = fullfile(cfg.bellhopRoot, "Matlab", "ReadWrite");
assert(isfile(executable), "Bellhop executable was not found: %s", executable);
assert(isfile(fullfile(readerDirectory, "read_arrivals_asc.m")), ...
    "Bellhop arrival reader was not found: %s", readerDirectory);
assert(numel(cfg.receiverDepths) == 8, "The paper setup requires eight receivers.");
assert(all(cfg.receiverDepths > 0 & cfg.receiverDepths < cfg.waterDepth), ...
    "Receiver depths must lie inside the water column.");

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
rootName = "chapter2_sc_tde_array";
environmentFile = fullfile(cfg.outputDir, rootName + ".env");
write_environment(environmentFile, cfg);

oldDirectory = pwd;
cleanup = onCleanup(@() cd(oldDirectory));
cd(cfg.outputDir);
[status, commandOutput] = system(sprintf('"%s" %s', executable, rootName));
assert(status == 0, "Bellhop failed: %s", commandOutput);

addpath(readerDirectory);
[arrivals, positions] = read_arrivals_asc(rootName + ".arr");
receiverCount = numel(cfg.receiverDepths);
impulses = complex(zeros(receiverCount, cfg.maxDelaySymbols + 1));
arrivalCounts = zeros(1, receiverCount);
absoluteFirstArrival = zeros(1, receiverCount);
retainedPathCounts = zeros(1, receiverCount);
for receiverIndex = 1:receiverCount
    arrival = arrivals(1, receiverIndex, 1);
    arrivalCounts(receiverIndex) = double(arrival.Narr);
    assert(arrivalCounts(receiverIndex) > 0, ...
        "Bellhop returned no arrivals for receiver %d.", receiverIndex);
    delays = real(double(arrival.delay(:).'));
    gains = double(arrival.A(:).');
    absoluteFirstArrival(receiverIndex) = min(delays);
    relativeDelay = delays - min(delays);
    delaySymbols = round(relativeDelay * cfg.symbolRate);
    keep = delaySymbols <= cfg.maxDelaySymbols;
    delaySymbols = delaySymbols(keep);
    gains = gains(keep);
    if numel(gains) > cfg.maxPathsPerSensor
        [~, strongest] = maxk(abs(gains), cfg.maxPathsPerSensor);
        delaySymbols = delaySymbols(strongest);
        gains = gains(strongest);
    end
    for pathIndex = 1:numel(gains)
        impulses(receiverIndex, delaySymbols(pathIndex) + 1) = ...
            impulses(receiverIndex, delaySymbols(pathIndex) + 1) + gains(pathIndex);
    end
    retainedPathCounts(receiverIndex) = nnz(abs(impulses(receiverIndex, :)) > 0);
end

arrayEnergy = sqrt(sum(abs(impulses).^2, "all"));
assert(arrayEnergy > 0, "Bellhop array channel is empty after discretization.");
impulses = impulses / arrayEnergy * sqrt(receiverCount);

channel.config = cfg;
channel.impulses = impulses;
channel.receiverDepths = double(positions.r.z(:).');
channel.rangeKm = double(positions.r.r(1));
channel.frequencyHz = double(positions.freq);
channel.arrivalCounts = arrivalCounts;
channel.retainedPathCounts = retainedPathCounts;
channel.absoluteFirstArrivalSeconds = absoluteFirstArrival;
channel.environmentFile = environmentFile;
channel.arrivalsFile = fullfile(cfg.outputDir, rootName + ".arr");
channel.source = "bellhop";
channel.phaseAssumption = "Bellhop complex arrivals";
end

function channel = paper_figure_digitized_channel(cfg)
delays = {
    [0, 25, 88, 122, 124, 126, 145, 147]
    [0, 25, 88, 120, 122, 124, 127, 139, 143, 146]
    [0, 25, 88, 121, 123, 127, 143, 146, 148]
    [0, 25, 88, 121, 123, 127, 136, 143, 147]
    [0, 25, 90, 122, 124, 126, 128, 145, 148]
    [0, 25, 88, 123, 126, 145]
    [0, 25, 122, 124, 127, 145]
    [0, 25, 122, 124, 127, 140, 145]
    };
amplitudes = {
    [0.15, 0.08, 0.20, 0.52, 0.39, 0.35, 0.18, 0.08]
    [0.10, 0.04, 0.30, 0.18, 0.25, 0.10, 1.00, 0.65, 0.32, 0.03]
    [0.12, 0.05, 0.50, 0.15, 0.10, 1.00, 0.35, 0.15, 0.03]
    [0.16, 0.10, 0.75, 0.25, 0.30, 0.60, 0.55, 0.02, 0.38]
    [0.23, 0.12, 0.65, 0.50, 0.40, 0.35, 1.00, 0.30, 0.10]
    [0.28, 0.17, 0.36, 0.65, 0.50, 0.20]
    [0.35, 0.25, 0.75, 0.50, 1.00, 0.30]
    [0.30, 0.23, 0.85, 0.75, 0.66, 0.75, 0.35]
    };
receiverCount = numel(delays);
impulses = complex(zeros(receiverCount, cfg.maxDelaySymbols + 1));
for receiverIndex = 1:receiverCount
    pathDelays = delays{receiverIndex};
    pathAmplitudes = amplitudes{receiverIndex};
    phaseIndex = 13 * receiverIndex + 19 * (1:numel(pathDelays)) + ...
        7 * pathDelays;
    pathGains = pathAmplitudes .* exp(1j * 2 * pi * mod(phaseIndex, 97) / 97);
    impulses(receiverIndex, pathDelays + 1) = pathGains;
end
arrayEnergy = sqrt(sum(abs(impulses).^2, "all"));
impulses = impulses / arrayEnergy * sqrt(receiverCount);
channel.config = cfg;
channel.impulses = impulses;
channel.receiverDepths = cfg.receiverDepths;
channel.rangeKm = cfg.rangeKm;
channel.frequencyHz = cfg.carrierHz;
channel.arrivalCounts = cellfun(@numel, delays);
channel.retainedPathCounts = channel.arrivalCounts;
channel.absoluteFirstArrivalSeconds = zeros(1, receiverCount);
channel.environmentFile = "";
channel.arrivalsFile = "";
channel.source = "paper-figure";
channel.phaseAssumption = "Deterministic phases; the original figure provides amplitudes only.";
channel.digitizedDelays = delays;
channel.digitizedAmplitudes = amplitudes;
end

function write_environment(fileName, cfg)
fid = fopen(fileName, "w");
assert(fid >= 0, "Cannot create Bellhop environment file: %s", fileName);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "'Chapter 2 SC-TDE eight-element shallow-water array'\n");
fprintf(fid, "%.6f\n", cfg.carrierHz);
fprintf(fid, "1\n'CVW'\n");
fprintf(fid, "101 0.0 %.6f\n", cfg.waterDepth);
fprintf(fid, "0.0 %.6f 0.0 1.0 0.0 /\n", cfg.waterSoundSpeedSurface);
fprintf(fid, "%.6f %.6f /\n", cfg.waterDepth, cfg.waterSoundSpeedBottom);
fprintf(fid, "'A' 0.0\n");
fprintf(fid, "%.6f %.6f 0.0 %.6f %.6f /\n", cfg.waterDepth, ...
    cfg.bottomSoundSpeed, cfg.bottomDensity, cfg.bottomAttenuation);
fprintf(fid, "1\n%.6f /\n", cfg.sourceDepth);
fprintf(fid, "%d\n", numel(cfg.receiverDepths));
fprintf(fid, "%.6f ", cfg.receiverDepths);
fprintf(fid, "/\n");
fprintf(fid, "1\n%.6f /\n", cfg.rangeKm);
fprintf(fid, "'A'\n2000\n-80.0 80.0 /\n");
fprintf(fid, "0.0 %.6f %.6f\n", 1.2 * cfg.waterDepth, cfg.rangeKm + 0.5);
end

function value = get_option(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end
