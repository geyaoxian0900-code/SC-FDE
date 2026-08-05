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
    receiverDepth, rangeKm);

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

function write_environment(fileName, frequency, waterDepth, sourceDepth, receiverDepth, rangeKm)
fid = fopen(fileName, "w");
assert(fid >= 0, "Cannot create Bellhop environment file: %s", fileName);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "'SC-FDE generated shallow-water Bellhop arrivals'\n");
fprintf(fid, "%.6f\n", frequency);
fprintf(fid, "1\n'CVW'\n");
fprintf(fid, "101 0.0 %.6f\n", waterDepth);
fprintf(fid, "0.0 1500.0 0.0 1.0 0.0 /\n");
fprintf(fid, "%.6f 1490.0 /\n", waterDepth);
fprintf(fid, "'A' 0.0\n");
fprintf(fid, "%.6f 1700.0 0.0 1.8 0.8 /\n", waterDepth);
fprintf(fid, "1\n%.6f /\n", sourceDepth);
fprintf(fid, "1\n%.6f /\n", receiverDepth);
fprintf(fid, "1\n%.6f /\n", rangeKm);
fprintf(fid, "'A'\n1000\n-80.0 80.0 /\n");
fprintf(fid, "0.0 %.6f %.6f\n", 1.2*waterDepth, max(1.1*rangeKm, rangeKm+0.1));
end

function value = get_field(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end
