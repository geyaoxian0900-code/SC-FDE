function plot_equalizer_outputs(options)
%PLOT_EQUALIZER_OUTPUTS Received constellation vs equalized output
% constellation for every requested equalizer on the SAME frame.
%   PLOT_EQUALIZER_OUTPUTS()                      % all 17 QPSK methods
%   PLOT_EQUALIZER_OUTPUTS(STRUCT("equalizers", {"mmse-fde","zf-fde"}))
%
% The SAME QPSK frame (Chapter 2/3 link: 120 data + 64 UW, 3-path
% channel, fixed seed) is used twice:
%   - LEFT  : the RAW received constellation (downconverted symbols
%             before any equalization) - identical for every method;
%   - RIGHT : the equalizer's soft output constellation (estimates).
%
% Outputs (papers/results/equalizer_outputs/):
%   equalizer_outputs.png - received vs equalized grid
%   equalizer_outputs.mat - received symbols, outputs, ids, ber
%
% OPTIONS:
%   equalizers - IDs (default all 17 qpsk methods)
%   snrDb      - SNR (default 12)
%   randomSeed - seed (default 42)

if nargin < 1
    options = struct();
end
equalizers = field_default(options, "equalizers", []);
if isempty(equalizers)
    registry = scfde.equalizer_registry();
    equalizers = registry.id(registry.scenario == "qpsk");
end
snrDb = field_default(options, "snrDb", 12);
randomSeed = field_default(options, "randomSeed", 42);

result = run_unified_equalizer(struct("equalizers", {equalizers}, ...
    "scenario", "qpsk", "snrDb", snrDb, "frameCount", 1, ...
    "makePlot", false, "randomSeed", randomSeed));

% Rebuild the SAME frame that the scenario transmitted: reproduce the
% qpsk link (N=184, 120 data + 64 UW, training 64, 3-path channel)
% with the same seed, so the received constellation matches the
% equalizer inputs exactly.
N = 184;
dataSymbols = 120;
uwLength = N - dataSymbols;
impulse = zeros(1, N);
impulse(1) = 1;
impulse(2) = 0.7 * exp(1j * 0.5);
impulse(4) = 0.3 * exp(-1j * 0.8);
impulse = impulse / norm(impulse);
H = fft(impulse);
noiseVariance = 10^(-snrDb / 10);
rng(randomSeed, "twister");
bits = randi([0, 1], 1, 2 * dataSymbols);
data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
block = [data, uw];
received = ifft(H .* fft(block));
received = received + sqrt(noiseVariance / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));

nMethods = numel(result.ids);
% Compact grid: the raw received constellation takes the top-left cell
% (merged over 2x2 cells), the 17 equalized constellations fill the
% remaining cells - one screen, roughly square constellation axes.
cols = 4;
gridRows = ceil((nMethods + 1) / cols);
fig = figure("Color", "w", "Position", [40, 40, 1400, 340 * gridRows], "Visible", "off");
% Top-left: the RAW received constellation (before any equalization) -
% the same input for every equalizer.
subplot(gridRows, cols, [1, 2]);
plot(real(received), imag(received), ".", "MarkerSize", 4); hold on;
plot([-1 1 1 -1 -1] / sqrt(2), [-1 -1 1 1 -1] / sqrt(2), "r--", "LineWidth", 1);
grid on; axis equal; axis([-2 2 -2 2]);
title(sprintf("Received (no equalization), SNR %g dB", snrDb), "FontSize", 9);
% Remaining cells: one equalized soft-output constellation per method.
for k = 1:nMethods
    if isfield(result, "estimates") && numel(result.estimates) >= k && ...
            ~isempty(result.estimates{k})
        out = result.estimates{k}(:).';
        if max(abs(out)) < 1e-9
            out = result.outputs{k}(:).';
        end
    else
        out = result.outputs{k}(:).';
    end
    peak = max(abs(out));
    if peak > 0
        out = out / peak;
    end
    subplot(gridRows, cols, k + 1);
    plot(real(out(abs(out) > 1e-3)), imag(out(abs(out) > 1e-3)), ...
        ".", "MarkerSize", 4); hold on;
    plot([-1 1 1 -1 -1] / sqrt(2), [-1 -1 1 1 -1] / sqrt(2), "r--", "LineWidth", 1);
    grid on; axis equal; axis([-2 2 -2 2]);
    title(sprintf("%s  BER=%.4g", result.ids(k), result.ber(k)), ...
        "FontSize", 8);
end
sgtitle(sprintf("Received vs equalized constellations - one QPSK frame, SNR %g dB, seed %d", ...
    snrDb, randomSeed));
outDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "equalizer_outputs");
if ~exist(outDir, "dir"), mkdir(outDir); end
pngPath = fullfile(outDir, "equalizer_outputs.png");
exportgraphics(fig, pngPath, "Resolution", 110);
close(fig);
outputs = result.outputs;
estimates = result.estimates;
ids = result.ids;
ber = result.ber;
errorBits = result.errorBits;
totalBits = result.totalBits;
save(fullfile(outDir, "equalizer_outputs.mat"), "received", "outputs", ...
    "estimates", "ids", "ber", "errorBits", "totalBits", ...
    "snrDb", "randomSeed");
fprintf("Received vs equalized outputs saved: %s\n", pngPath);
for k = 1:nMethods
    fprintf("  %-18s BER=%.4g (%d/%d)\n", ids(k), ber(k), ...
        errorBits(k), totalBits(k));
end
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
