function plot_equalizer_outputs(options)
%PLOT_EQUALIZER_OUTPUTS Received vs equalized constellation comparison
% for EVERY registered equalizer, grouped by its scenario.
%   PLOT_EQUALIZER_OUTPUTS()               % all 37 methods (4 figures)
%   PLOT_EQUALIZER_OUTPUTS(STRUCT("scenario", "turbo"))
%   PLOT_EQUALIZER_OUTPUTS(STRUCT("equalizers", {"mmse-fde","zf-fde"}))
%
% For each scenario the SAME received frame is rebuilt (same seed,
% same channel) and drawn once WITHOUT equalization, followed by one
% equalized soft-output constellation per method:
%   - qpsk (17): QPSK symbol frame (184)
%   - turbo (10): BPSK coded frame (256 training + 1024 data)
%   - cck (7): 8-chip CCK frames
%   - csk (3): length-63 spreading frames
%
% Outputs (papers/results/equalizer_outputs/):
%   equalizer_outputs_<scenario>.png / .mat
%
% OPTIONS:
%   scenario   - "qpsk" | "turbo" | "cck" | "csk" | "all" (default)
%   equalizers - explicit IDs (must belong to one scenario)
%   snrDb      - SNR (default 12)
%   randomSeed - seed (default 42)

if nargin < 1
    options = struct();
end
equalizers = field_default(options, "equalizers", []);
scenario = field_default(options, "scenario", "all");
snrDb = field_default(options, "snrDb", 12);
randomSeed = field_default(options, "randomSeed", 42);

registry = scfde.equalizer_registry();
if isempty(equalizers)
    if strcmpi(scenario, "all")
        scenarios = ["qpsk", "turbo", "cck", "csk"];
    else
        scenarios = string(scenario);
    end
else
    % Explicit IDs: resolve their scenario(s).
    eqs = string(equalizers);
    if iscell(eqs)
        eqs = string([eqs{:}]);
    end
    scenarios = strings(1, 0);
    for k = 1:numel(eqs)
        match = find(registry.id == eqs(k), 1);
        if isempty(match)
            error("SCFDE:UnknownEqualizer", "Unknown equalizer ID: %s.", eqs(k));
        end
        if ~any(scenarios == registry.scenario(match))
            scenarios(end + 1) = registry.scenario(match); %#ok<AGROW>
        end
    end
end

outDir = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
    "results", "equalizer_outputs");
if ~exist(outDir, "dir"), mkdir(outDir); end
for s = scenarios
    plot_scenario(s, equalizers, snrDb, randomSeed, registry, outDir);
end
end

function plot_scenario(scenario, equalizers, snrDb, randomSeed, registry, outDir)
registryScenario = registry.scenario == scenario;
if isempty(equalizers)
    ids = registry.id(registryScenario);
else
    eqs = string(equalizers);
    if iscell(eqs)
        eqs = string([eqs{:}]);
    end
    keep = false(size(eqs));
    for k = 1:numel(eqs)
        match = find(registry.id == eqs(k), 1);
        keep(k) = ~isempty(match) && registry.scenario(match) == scenario;
    end
    ids = eqs(keep);
end
if isempty(ids)
    return;
end
result = run_unified_equalizer(struct("equalizers", {cellstr(ids)}, ...
    "scenario", scenario, "snrDb", snrDb, "frameCount", 1, ...
    "makePlot", false, "randomSeed", randomSeed));
received = rebuild_received(scenario, snrDb, randomSeed);

nMethods = numel(ids);
cols = 4;
gridRows = ceil((nMethods + 4) / cols);
fig = figure("Color", "w", "Position", [40, 40, 1400, 340 * gridRows], "Visible", "off");
subplot(gridRows, cols, [1, 2, 5, 6]);
plot(real(received), imag(received), ".", "MarkerSize", 4); hold on;
plot([-1 1 1 -1 -1] / sqrt(2), [-1 -1 1 1 -1] / sqrt(2), "r--", "LineWidth", 1);
grid on; axis equal; axis([-2 2 -2 2]);
title(sprintf("Received (no equalization), %s, SNR %g dB", scenario, snrDb), "FontSize", 9);
cellIndex = 3;
for k = 1:nMethods
    if cellIndex == 5
        cellIndex = 7;
    end
    if isfield(result, "estimates") && numel(result.estimates) >= k && ...
            ~isempty(result.estimates{k})
        out = result.estimates{k}(:).';
        if max(abs(out)) < 1e-9
            out = result.outputs{k}(:).';
        elseif isHard(out)
            % Hard-decision estimates (turbo decoders report decisions):
            % fall back to the decoder soft LLR of the last iteration
            % when available so the soft constellation is visible.
            if strcmpi(scenario, "turbo") && isfield(result, "traces") && ...
                    numel(result.traces) >= k && ...
                    isfield(result.traces{k}, "equalizerLlr")
                llr = result.traces{k}.equalizerLlr(end, :);
                out = tanh(llr / 2);
            end
        end
    else
        out = result.outputs{k}(:).';
    end
    peak = max(abs(out));
    if peak > 0
        out = out / peak;
    end
    subplot(gridRows, cols, cellIndex);
    cellIndex = cellIndex + 1;
    plot(real(out(abs(out) > 1e-3)), imag(out(abs(out) > 1e-3)), ...
        ".", "MarkerSize", 4); hold on;
    plot([-1 1 1 -1 -1] / sqrt(2), [-1 -1 1 1 -1] / sqrt(2), "r--", "LineWidth", 1);
    grid on; axis equal; axis([-2 2 -2 2]);
    title(sprintf("%s  BER=%.4g", ids(k), result.ber(k)), "FontSize", 8);
end
sgtitle(sprintf("Received vs equalized constellations - %s, SNR %g dB, seed %d", ...
    scenario, snrDb, randomSeed));
pngPath = fullfile(outDir, sprintf("equalizer_outputs_%s.png", scenario));
exportgraphics(fig, pngPath, "Resolution", 110);
close(fig);
outputs = result.outputs;
estimates = result.estimates;
idsOut = ids;
ber = result.ber;
errorBits = result.errorBits;
totalBits = result.totalBits;
save(fullfile(outDir, sprintf("equalizer_outputs_%s.mat", scenario)), ...
    "received", "outputs", "estimates", "idsOut", "ber", ...
    "errorBits", "totalBits", "snrDb", "randomSeed");
fprintf("%s: %d methods -> %s\n", scenario, nMethods, pngPath);
for k = 1:nMethods
    fprintf("  %-20s BER=%.4g (%d/%d)\n", ids(k), ber(k), ...
        errorBits(k), totalBits(k));
end
end

function received = rebuild_received(scenario, snrDb, randomSeed)
% Rebuild the SAME frame that the scenario transmitted (same seed,
% same channel) so the received constellation matches the equalizer
% inputs exactly.
switch lower(scenario)
    case "qpsk"
        N = 184; dataSymbols = 120; uwLength = N - dataSymbols;
        impulse = zeros(1, N);
        impulse(1) = 1; impulse(2) = 0.7 * exp(1j * 0.5);
        impulse(4) = 0.3 * exp(-1j * 0.8);
        impulse = impulse / norm(impulse);
        H = fft(impulse); nv = 10^(-snrDb / 10);
        rng(randomSeed, "twister");
        bits = randi([0, 1], 1, 2 * dataSymbols);
        data = ((2 * bits(1:2:end) - 1) + 1j * (2 * bits(2:2:end) - 1)) / sqrt(2);
        uw = scfde.equalizers.ch3_zadoff_chu(uwLength, 1);
        block = [data, uw];
        received = ifft(H .* fft(block)) + sqrt(nv / 2) * ...
            (randn(size(block)) + 1j * randn(size(block)));
    case "turbo"
        infoBits = 512; trainingSymbols = 256;
        impulse = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
        nv = 10^(-snrDb / 10);
        rng(randomSeed, "twister");
        permutation = randperm(2 * infoBits);
        info = randi([0, 1], 1, infoBits);
        coded = scfde.equalizers.ch4_convolutional_encode(info);
        dataSymbols = 1 - 2 * coded(permutation);
        training = 1 - 2 * randi([0, 1], 1, trainingSymbols);
        tx = [training, dataSymbols];
        N = numel(tx);
        H = fft([impulse, zeros(1, N - numel(impulse))]);
        received = ifft(H .* fft(tx)) + sqrt(nv / 2) * ...
            (randn(size(tx)) + 1j * randn(size(tx)));
    case "cck"
        [book, ~] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
        impulse = scfde.equalizers.ch5_short_turbo_channel();
        nv = 10^(-snrDb / 10);
        rng(randomSeed, "twister");
        idx = randi(size(book, 1), 1, 8);
        chips = reshape(book(idx, :).', 1, []);
        received = filter(impulse, 1, [chips, zeros(1, numel(impulse) - 1)]);
        received = received + sqrt(nv / 2) * ...
            (randn(size(received)) + 1j * randn(size(received)));
    case "csk"
        codeLength = 63;
        root = scfde.equalizers.ch6_select_csk_root(codeLength);
        [book, ~] = scfde.equalizers.ch6_csk_codebook(root, 4);
        impulse = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
        nv = 1 / (2 * 10^(snrDb / 10));
        rng(randomSeed, "twister");
        idx6 = randi(4, 8, 1);
        received = zeros(8, codeLength);
        for s = 1:8
            filtered = filter(impulse, 1, ...
                [book(idx6(s), :), zeros(1, numel(impulse) - 1)]);
            received(s, :) = filtered(1:codeLength);
        end
        received = received + sqrt(nv / 2) * ...
            (randn(size(received)) + 1j * randn(size(received)));
        received = reshape(received.', 1, []);
    otherwise
        error("SCFDE:UnknownScenario", "Unknown scenario: %s", scenario);
end
received = received(:).';
end

function isHard = isHard(symbols)
% True when the output collapses onto a few theoretical constellation
% points (hard decisions) rather than a soft cloud.
rounded = round(real(symbols) * 10) / 10 + 1j * round(imag(symbols) * 10) / 10;
isHard = numel(unique(rounded)) <= 4;
end

function value = field_default(options, name, defaultValue)
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
