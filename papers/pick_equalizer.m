function results = pick_equalizer(options)
%PICK_EQUALIZER Interactive equalizer selection and run.
%   RESULTS = PICK_EQUALIZER()           % interactive menu
%   RESULTS = PICK_EQUALIZER(OPTIONS)    % with run options
%
% The menu lists all 37 registered equalizers grouped by scenario with
% numbers; the user types numbers separated by commas, spaces or
% hyphen ranges (e.g. "1,3,5" or "18-27"; empty input selects ALL).
% The scenario is resolved from the registry: a single-scenario
% selection runs automatically, a cross-scenario selection asks for a
% target scenario (or rejects it).
%
% Non-interactive mode for scripts/tests:
%   RESULTS = PICK_EQUALIZER(STRUCT("ids", [1, 3, 5], "snrDb", 10))
%
% OPTIONS fields (passed through to run_unified_equalizer):
%   ids, snrDb, symbols, frameCount, randomSeed, makePlot.

if nargin < 1
    options = struct();
end
registry = scfde.equalizer_registry();
n = numel(registry.id);
print_menu(registry, n);
if isfield(options, "ids") && ~isempty(options.ids)
    selected = options.ids;
else
    fprintf("\nSelect equalizer numbers (e.g. 1,3,5 / 18-27 / empty=all): ");
    text = strtrim(input("", "s"));
    if isempty(text)
        selected = 1:n;
    else
        selected = parse_selection(text, n);
    end
end
if isempty(selected)
    fprintf("No equalizer selected.\n");
    results = [];
    return;
end
ids = registry.id(selected);
scenarios = unique(registry.scenario(selected));
if numel(scenarios) == 1
    scenario = scenarios(1);
else
    fprintf("\nSelection spans scenarios: %s\n", strjoin(scenarios, ", "));
    fprintf("Run in [%s]: ", strjoin(scenarios, "/"));
    answer = strtrim(input("", "s"));
    if ~any(strcmpi(answer, scenarios))
        fprintf("Cancelled.\n");
        results = [];
        return;
    end
    scenario = string(answer);
end
fprintf("\nRunning %d equalizer(s) in scenario %s: %s\n", ...
    numel(ids), scenario, strjoin(ids, ", "));
runOptions = rmfield(options, "ids");
runOptions.equalizers = ids;
runOptions.scenario = scenario;
results = run_unified_equalizer(runOptions);
print_results(results);
end

function print_menu(registry, n)
fprintf("\n===== Equalizer selection menu =====\n");
for s = ["qpsk", "turbo", "cck", "csk"]
    idx = find(registry.scenario == s);
    if isempty(idx)
        continue;
    end
    fprintf("\n[%s] (%d methods)\n", s, numel(idx));
    for k = 1:numel(idx)
        fprintf("  %2d. %s\n", idx(k), registry.id(idx(k)));
    end
end
fprintf("----------------------------------\n");
end

function selected = parse_selection(text, n)
selected = zeros(1, 0);
for token = strsplit(strrep(text, " ", ","), ",")
    item = strtrim(token{1});
    if isempty(item)
        continue;
    end
    dash = strfind(item, "-");
    if ~isempty(dash)
        lo = str2double(item(1:dash(1) - 1));
        hi = str2double(item(dash(1) + 1:end));
        if isfinite(lo) && isfinite(hi) && lo >= 1 && hi <= n && lo <= hi
            selected = [selected, lo:hi]; %#ok<AGROW>
        end
    else
        value = str2double(item);
        if isfinite(value) && value >= 1 && value <= n
            selected(end + 1) = value; %#ok<AGROW>
        end
    end
end
selected = unique(selected);
end

function print_results(results)
fprintf("\n===== Results =====\n");
for k = 1:numel(results.ids)
    fprintf("%-20s ber=%.4e err=%d bits=%d CI=[%.3e, %.3e]\n", ...
        results.ids(k), results.ber(k), results.errorBits(k), ...
        results.totalBits(k), results.berLower95(k), results.berUpper95(k));
end
end
