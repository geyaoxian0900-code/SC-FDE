function [pathDelaysMs, pathGains, info] = scfde_bellhop_channel(options)
%SCFDE_BELLHOP_CHANNEL Run Bellhop and convert arrivals to a sampled channel.

toolboxRoot = get_field(options, "bellhopRoot", ...
    "D:\MATLAB\atWin10_2020_11_4\atWin10_2020_11_4");
waterDepth = get_field(options, "bellhopWaterDepth", 100);
sourceDepth = get_field(options, "bellhopSourceDepth", 20);
receiverDepth = get_field(options, "bellhopReceiverDepth", 30);
rangeKm = get_field(options, "bellhopRangeKm", 1.0);
maxPaths = get_field(options, "bellhopMaxPaths", 12);
maxSpreadMs = get_field(options, "bellhopMaxSpreadMs", 7.5);
sampleRate = get_field(options, "txSampleRate", 96000);
frequency = get_field(options, "carrierHz", 12000);
% Environment parameterization:
%   bellhopSediment   - bottom type preset: "mud", "clay", "fine-sand",
%                       "coarse-sand", "rock", "silt" or "custom"
%                       (default "custom" keeps the hard-sand halfspace)
%   bellhopSedimentParams - [cp cs rho atten] for "custom" (default
%                       [1700 0 1.8 0.8])
%   bellhopSsp        - "linear" (default, surface->bottom speeds),
%                       "cvw" (constant 1500 m/s) or "file"
%   bellhopSspFile    - two-column text file (depth_m speed_mps) for
%                       bellhopSsp="file"
%   bellhopSurfaceSpeed - surface sound speed (default 1500)
%   bellhopBottomSpeed  - bottom sound speed (default 1490)
%   bellhopSurface    - "flat" (default) or "gaussian"
%   bellhopSurfaceRmsM - Gaussian surface RMS wave height in metres
%                       (default 0.5, used when bellhopSurface="gaussian")
sediment = get_field(options, "bellhopSediment", "custom");
sedimentParams = get_field(options, "bellhopSedimentParams", []);
ssp = get_field(options, "bellhopSsp", "linear");
sspFile = get_field(options, "bellhopSspFile", "");
surfaceSpeed = get_field(options, "bellhopSurfaceSpeed", 1500);
bottomSpeed = get_field(options, "bellhopBottomSpeed", 1490);
surfaceType = get_field(options, "bellhopSurface", "flat");
surfaceRmsM = get_field(options, "bellhopSurfaceRmsM", 0.5);
surfaceCorrelationM = get_field(options, "bellhopSurfaceCorrelationM", 10.0);
surfaceWindSpeed = get_field(options, "bellhopSurfaceWindSpeed", 10.0);

toolboxRoot = char(toolboxRoot);
% Locate the Bellhop executable: legacy layout
% <root>/windows-bin-*/bellhop.exe, modern source layout
% <root>/Bellhop/bellhop.exe, or <root>/bellhop.exe.
executable = find_bellhop_executable(toolboxRoot);
readerDirectory = fullfile(toolboxRoot, "Matlab", "ReadWrite");
if ~isfile(fullfile(readerDirectory, "read_arrivals_asc.m"))
    % Fall back to the legacy toolbox reader when the modern root has
    % no Matlab/ReadWrite directory.
    readerDirectory = fullfile("D:\MATLAB\atWin10_2020_11_4\atWin10_2020_11_4", ...
        "Matlab", "ReadWrite");
end
assert(isfile(executable), "Bellhop executable was not found: %s", executable);
assert(isfile(fullfile(readerDirectory, "read_arrivals_asc.m")), ...
    "Bellhop arrival reader was not found below: %s", toolboxRoot);
assert(sourceDepth > 0 && sourceDepth < waterDepth, ...
    "Bellhop source depth must lie inside the water column.");
assert(receiverDepth > 0 && receiverDepth < waterDepth, ...
    "Bellhop receiver depth must lie inside the water column.");
assert(rangeKm > 0, "Bellhop range must be positive.");

workDirectory = fullfile(fileparts(mfilename("fullpath")), "bellhop", "runtime");
if ~exist(workDirectory, "dir")
    mkdir(workDirectory);
end
rootName = "scfde_runtime";
environmentFile = fullfile(workDirectory, rootName + ".env");
write_environment(environmentFile, frequency, waterDepth, sourceDepth, ...
    receiverDepth, rangeKm, sediment, sedimentParams, ssp, sspFile, ...
    surfaceSpeed, bottomSpeed, surfaceType);
if strcmpi(surfaceType, "gaussian")
    % Rough sea: generate a Pierson-Moskowitz altimetry file (.ati)
    % and write it next to the environment file.
    write_altimetry(fullfile(workDirectory, rootName + ".ati"), ...
        surfaceRmsM, surfaceCorrelationM, surfaceWindSpeed, rangeKm);
end

oldDirectory = pwd;
cleanup = onCleanup(@() cd(oldDirectory)); %#ok<NASGU>
cd(workDirectory);
command = sprintf('"%s" %s', executable, rootName);
[status, commandOutput] = system(command);
assert(status == 0, "Bellhop failed: %s", commandOutput);

addpath(readerDirectory);
[arrivals, positions] = read_arrivals_asc(rootName + ".arr");
arrival = arrivals(1);
assert(double(arrival.Narr) > 0, "Bellhop returned no arrivals.");

absoluteDelay = real(double(arrival.delay(:).'));
amplitude = double(arrival.A(:).');
relativeDelay = absoluteDelay - min(absoluteDelay);
keep = relativeDelay <= maxSpreadMs * 1e-3;
relativeDelay = relativeDelay(keep);
amplitude = amplitude(keep);
assert(~isempty(amplitude), "No Bellhop arrivals remain inside the UW interval.");

if numel(amplitude) > maxPaths
    [~, strongest] = maxk(abs(amplitude), maxPaths);
    relativeDelay = relativeDelay(strongest);
    amplitude = amplitude(strongest);
end

sampleDelay = round(relativeDelay * sampleRate);
uniqueDelay = unique(sampleDelay);
combined = complex(zeros(size(uniqueDelay)));
for index = 1:numel(uniqueDelay)
    combined(index) = sum(amplitude(sampleDelay == uniqueDelay(index)));
end
nonzero = abs(combined) > max(abs(combined)) * 1e-6;
uniqueDelay = uniqueDelay(nonzero);
combined = combined(nonzero);
[uniqueDelay, order] = sort(uniqueDelay);
combined = combined(order);
combined = combined / max(abs(combined));

pathDelaysMs = uniqueDelay / sampleRate * 1000;
pathGains = combined;
info.model = "bellhop";
info.environmentFile = environmentFile;
info.arrivalsFile = fullfile(workDirectory, rootName + ".arr");
info.frequencyHz = positions.freq;
info.absoluteFirstArrivalSeconds = min(absoluteDelay);
info.totalArrivalCount = double(arrival.Narr);
info.retainedRayCount = sum(keep);
info.discretePathCount = numel(pathGains);
info.pathDelaysMs = pathDelaysMs;
info.pathGains = pathGains;
end

function write_environment(fileName, frequency, waterDepth, sourceDepth, ...
        receiverDepth, rangeKm, sediment, sedimentParams, ssp, sspFile, ...
        surfaceSpeed, bottomSpeed, surfaceType)
fid = fopen(fileName, "w");
assert(fid >= 0, "Cannot create Bellhop environment file: %s", fileName);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "'SC-FDE generated shallow-water Bellhop arrivals'\n");
fprintf(fid, "%.6f\n", frequency);
fprintf(fid, "1\n");
% The first line after NMedia is the 6-character TopOpt: position 1 is
% the SSP approximation ('C' = C-linear for the two-point profile),
% positions 3-4 the attenuation units, position 5 '~' selects the
% top-altimetry (rough-sea) file.
if strcmpi(surfaceType, "gaussian")
    topOpt = "'CVW ~'";
else
    topOpt = "'CVW   '";
end
% 'CVW' (N2-linear) accepts depth/sound-speed point pairs; the number
% of points is declared first (Bellhop reads the pairs).
switch lower(ssp)
    case "cvw"
        fprintf(fid, "%s\n", topOpt);
        fprintf(fid, "2 0.0 %.6f\n", waterDepth);
        fprintf(fid, "0.0 %.6f 0.0 1.0 /\n%.6f %.6f /\n", ...
            surfaceSpeed, waterDepth, surfaceSpeed);
    case "file"
        assert(~isempty(sspFile) && isfile(sspFile), ...
            "bellhopSspFile must point to an existing depth-speed file.");
        sspData = load(sspFile);
        assert(size(sspData, 2) >= 2, ...
            "bellhopSspFile must contain two columns: depth speed.");
        depth = sspData(:, 1);
        speed = sspData(:, 2);
        fprintf(fid, "%s\n", topOpt);
        fprintf(fid, "%d 0.0 %.6f\n", numel(depth), waterDepth);
        for k = 1:numel(depth)
            if k == 1
                fprintf(fid, "%.6f %.6f 0.0 1.0 /\n", depth(k), speed(k));
            else
                fprintf(fid, "%.6f %.6f /\n", depth(k), speed(k));
            end
        end
    otherwise % "linear": surface->bottom gradient
        fprintf(fid, "%s\n", topOpt);
        fprintf(fid, "2 0.0 %.6f\n", waterDepth);
        fprintf(fid, "%.6f %.6f 0.0 1.0 /\n", 0.0, surfaceSpeed);
        fprintf(fid, "%.6f %.6f /\n", waterDepth, bottomSpeed);
end
% Bottom halfspace (Bellhop 'A' option): the sediment presets follow
% the Jensen et al. "Computational Ocean Acoustics" table (cp, cs,
% rho, atten dB/lambda); "custom" keeps the project's default.
if isempty(sedimentParams)
    sedimentParams = sediment_table(sediment);
end
fprintf(fid, "'A' 0.0\n");
fprintf(fid, "%.6f %.6f %.6f %.6f %.6f /\n", waterDepth, ...
    sedimentParams(1), sedimentParams(2), sedimentParams(3), sedimentParams(4));
fprintf(fid, "1\n%.6f /\n", sourceDepth);
fprintf(fid, "1\n%.6f /\n", receiverDepth);
fprintf(fid, "1\n%.6f /\n", rangeKm);
fprintf(fid, "'A'\n1000\n-80.0 80.0 /\n");
fprintf(fid, "0.0 %.6f %.6f\n", 1.2 * waterDepth, max(1.1 * rangeKm, rangeKm + 0.1));
end

function write_altimetry(fileName, rmsM, correlationM, windSpeed, rangeKm)
%WRITE_ALTIMETRY Pierson-Moskowitz spectrum sea-surface altimetry file.
%   The .ati file contains: interpolation type, point count and
%   (range_km, depth_m) pairs.  The sea surface height is synthesized
%   as a sum of PM-spectrum cosine components with random phases,
%   scaled so the RMS height equals rmsM (or the PM fetch growth
%   when rmsM is not given explicitly).
alpha = 0.0081;
g = 9.81;
windspeed = max(windSpeed, 1.0);
% PM spectrum peak angular frequency and sample band.
omegaPeak = 0.877 * g / windspeed;
omegaMin = 0.3 * omegaPeak;
omegaMax = 3.0 * omegaPeak;
nComponents = 40;
omega = linspace(omegaMin, omegaMax, nComponents);
dOmega = omega(2) - omega(1);
spectrum = alpha * g^2 ./ omega.^5 .* ...
    exp(-0.74 * (g ./ (windspeed * omega)).^4);
% Target RMS: explicit rmsM wins, otherwise the PM significant
% wave height for the wind speed.
if rmsM > 0
    targetRms = rmsM;
else
    hs = 0.21 * windspeed^2 / g;
    targetRms = hs / 4;
end
amplitudes = sqrt(2 * spectrum .* dOmega);
% Scale to the target RMS.
currentRms = sqrt(0.5 * sum(amplitudes.^2));
if currentRms > 0
    amplitudes = amplitudes * targetRms / currentRms;
end
rng(20260810, "twister");
phases = 2 * pi * rand(1, nComponents);
% Sample every 5 m out to 1.5x the range (km -> m).
rangeMaxM = max(1.5 * rangeKm * 1000, 500);
sampleSpacingM = 5;
rangesM = 0:sampleSpacingM:rangeMaxM;
heights = zeros(size(rangesM));
for k = 1:nComponents
    heights = heights + amplitudes(k) * ...
        cos(2 * pi * rangesM / max(correlationM, 1) * (omega(k) / omegaPeak) + phases(k));
end
fid = fopen(fileName, "w");
assert(fid >= 0, "Cannot create altimetry file: %s", fileName);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
% Shift the surface down so its highest crest sits at depth 0 (the top
% of the SSP); the RMS height is unchanged by the shift.
heights = heights - max(heights);
fprintf(fid, "'L'\n");
fprintf(fid, "%d\n", numel(rangesM));
for k = 1:numel(rangesM)
    fprintf(fid, "%.6f %.6f\n", rangesM(k) / 1000, heights(k));
end
end

function params = sediment_table(sediment)
% Presets [cp(m/s) cs(m/s) rho(g/cm^3) atten(dB/lambda)].
switch lower(string(sediment))
    case "silt"
        params = [1520, 0, 1.2, 0.3];
    case "mud"
        params = [1500, 0, 1.1, 0.2];
    case "clay"
        params = [1550, 0, 1.4, 0.4];
    case "fine-sand"
        params = [1680, 0, 1.8, 0.8];
    case "coarse-sand"
        params = [1750, 0, 1.9, 1.0];
    case "rock"
        params = [3000, 0, 2.5, 0.2];
    case "custom"
        params = [1700, 0, 1.8, 0.8];
    otherwise
        error("SCFDE:Bellhop", ...
            "Unknown sediment preset %s; use mud, silt, clay, fine-sand, coarse-sand, rock or custom.", ...
            string(sediment));
end
end

function value = get_field(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function executable = find_bellhop_executable(root)
candidates = { ...
    fullfile(root, "windows-bin-20201102", "bellhop.exe"), ...
    fullfile(root, "Bellhop", "bellhop.exe"), ...
    fullfile(root, "bellhop.exe")};
executable = "";
for k = 1:numel(candidates)
    if isfile(candidates{k})
        executable = candidates{k};
        return;
    end
end
end
