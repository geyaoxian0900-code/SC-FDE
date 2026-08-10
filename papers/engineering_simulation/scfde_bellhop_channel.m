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

toolboxRoot = char(toolboxRoot);
executable = fullfile(toolboxRoot, "windows-bin-20201102", "bellhop.exe");
readerDirectory = fullfile(toolboxRoot, "Matlab", "ReadWrite");
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
% 'CVW' (N2-linear) accepts depth/sound-speed point pairs; the number
% of points is declared first (Bellhop reads the pairs).
switch lower(ssp)
    case "cvw"
        fprintf(fid, "'CVW'\n");
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
        fprintf(fid, "'CVW'\n");
        fprintf(fid, "%d 0.0 %.6f\n", numel(depth), waterDepth);
        for k = 1:numel(depth)
            if k == 1
                fprintf(fid, "%.6f %.6f 0.0 1.0 /\n", depth(k), speed(k));
            else
                fprintf(fid, "%.6f %.6f /\n", depth(k), speed(k));
            end
        end
    otherwise % "linear": surface->bottom gradient
        fprintf(fid, "'CVW'\n");
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
% Surface option: Gaussian spectrum ('G' with RMS height) when
% requested; the flat default omits the line (Bellhop's built-in
% default surface), matching the project's original environment.
% Surface: this Bellhop build (windows-bin-20201102) reads the source
% depth directly after the bottom halfspace and does NOT accept a
% surface-interface option line ('~'/'G' both fail list-input parsing
% at SourceReceiverPositions).  The flat default is therefore
% implicit; a requested rough sea raises a clear error instead of
% silently ignoring it.  Rough-sea propagation can be approximated by
% a surface-mixed-layer SSP (bellhopSsp="file").
switch lower(surfaceType)
    case "gaussian"
        error("SCFDE:Bellhop", ...
            "This Bellhop build does not support the Gaussian surface option; use bellhopSurface=flat or approximate sea state via a surface-mixed-layer SSP file.");
end
fprintf(fid, "1\n%.6f /\n", sourceDepth);
fprintf(fid, "1\n%.6f /\n", receiverDepth);
fprintf(fid, "1\n%.6f /\n", rangeKm);
fprintf(fid, "'A'\n1000\n-80.0 80.0 /\n");
fprintf(fid, "0.0 %.6f %.6f\n", 1.2 * waterDepth, max(1.1 * rangeKm, rangeKm + 0.1));
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
