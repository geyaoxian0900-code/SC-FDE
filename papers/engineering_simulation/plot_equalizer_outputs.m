function plot_equalizer_outputs(options)
%PLOT_EQUALIZER_OUTPUTS Equalized output constellation for every
% requested equalizer on the SAME received frame.
%   PLOT_EQUALIZER_OUTPUTS()                      % all 17 QPSK methods
%   PLOT_EQUALIZER_OUTPUTS(STRUCT("equalizers", {"mmse-fde","zf-fde"}))
%
% A single QPSK frame (Chapter 2/3 link: 120 data + 64 UW, 3-path
% channel, fixed seed) is equalized by each registered method through
% the unified entry; the equalizer's raw output symbols (before slicing)
% are plotted as a constellation per method together with its BER.
%
% Outputs (papers/results/equalizer_outputs/):
%   equalizer_outputs.png - constellation grid
%   equalizer_outputs.mat - outputs, ids, ber and the received frame
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

nMethods = numel(result.ids);
cols = 4;
rows = ceil(nMethods / cols);
fig = figure("Color", "w", "Position", [40, 40, 1400, 320 * rows], "Visible", "off");
for k = 1:nMethods
    subplot(rows, cols, k);
    % Draw the SOFT equalizer output (estimates) when available - the
    % hard decisions in outputs{1} collapse every method to 4 points.
    % A zero soft output (e.g. a PTR front end whose DFE does not
    % converge on this frame) falls back to the hard decisions and is
    % annotated.
    hardFallback = false;
    if isfield(result, "estimates") && numel(result.estimates) >= k && ...
            ~isempty(result.estimates{k})
        out = result.estimates{k}(:).';
        if max(abs(out)) < 1e-9
            out = result.outputs{k}(:).';
            hardFallback = true;
        end
    else
        out = result.outputs{k}(:).';
    end
    plot(real(out(abs(out) > 1e-6)), imag(out(abs(out) > 1e-6)), ...
        ".", "MarkerSize", 6); hold on;
    plot([-1 1 1 -1 -1] / sqrt(2), [-1 -1 1 1 -1] / sqrt(2), "r--", "LineWidth", 1);
    grid on; axis equal; axis([-2 2 -2 2]);
    if hardFallback
        title(sprintf("%s\nBER=%.4g (%d/%d) [soft=0, hard shown]", ...
            result.ids(k), result.ber(k), result.errorBits(k), ...
            result.totalBits(k)), "FontSize", 9);
    else
        title(sprintf("%s\nBER=%.4g (%d/%d)", result.ids(k), ...
            result.ber(k), result.errorBits(k), result.totalBits(k)), ...
            "FontSize", 9);
    end
end
sgtitle(sprintf("Equalized output constellations - one QPSK frame, SNR %g dB, seed %d", ...
    snrDb, randomSeed));
outDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "equalizer_outputs");
if ~exist(outDir, "dir"), mkdir(outDir); end
pngPath = fullfile(outDir, "equalizer_outputs.png");
exportgraphics(fig, pngPath, "Resolution", 120);
close(fig);
outputs = result.outputs;
estimates = result.estimates;
ids = result.ids;
ber = result.ber;
errorBits = result.errorBits;
totalBits = result.totalBits;
save(fullfile(outDir, "equalizer_outputs.mat"), "outputs", "estimates", ...
    "ids", "ber", "errorBits", "totalBits", "snrDb", "randomSeed");
fprintf("Equalized outputs saved: %s\n", pngPath);
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
