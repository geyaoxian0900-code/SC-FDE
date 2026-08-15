% run_37_curve_grading.m - Multi-SNR / multi-seed BER survey and curve
% grading driver for all 37 registered equalizers (batch-11/12 closeout).
%
% What this script does:
%   * runs every registered method in its scenario bank (qpsk 17, turbo
%     10, cck 7, csk 3) over snrGrid with several seeds and frameCount
%     frames per seed;
%   * accumulates INTEGER errorBits/totalBits (never floats) and reports
%     the pooled BER with the exact 95% Clopper-Pearson interval;
%   * emits a per-method BER-vs-SNR trend diagnostic (relative-worsening
%     flags only - anomalies must be audited in the algorithm, never
%     papered over by parameter tuning);
%   * grades curves ONLY where an original digitized book curve exists
%     (FDDA-TEQ vs book Fig. 4-31 via curve_benchmark; the archived
%     book-structure/trend benchmark ch4_fig431_fdda_teq_true_benchmark.mat
%     is reused if present - NOT experiment-identical, the book channel
%     is undisclosed).  Every other method is recorded as
%     "不适用（无原文数字化曲线）" - the scenario-bank curve is
%     engineering evidence, NOT a book-curve reproduction, and formula
%     tests can never substitute for it;
%   * saves one artifact .mat with the full metadata contract
%     (scenario / equalizerIds / snrGrid / seeds / frameCount /
%     errorBits / totalBits / ber / berLower95 / berUpper95 /
%     gitCommit / matlabVersion / timestamp / rngSeeds / gradePerMethod
%     / gradeSource / trendFlags / effectiveParameters per method).
%
% Usage (run from papers/):
%     run('curve_reference/run_37_curve_grading.m')
%
% NOTE: artifact .mat files are committed SEPARATELY from source; this
% run records the CURRENT git commit.  The final closeout re-runs this
% script on the final source commit so the artifacts carry that hash.

cfg.snrGrid = 0:2:18;                 % dB, four scenario banks
cfg.seeds = [2024, 2025, 2026];       % >= 3 seeds per the grading rules
cfg.frameCount = 10;                  % frames per seed-SNR point
cfg.symbols = 8;                      % per-frame symbol count per bank
cfg.scenarios = ["qpsk", "turbo", "cck", "csk"];
cfg.saveEveryScenario = true;         % checkpoint after each scenario

% Reduced-config PRE-RUN (before committing batch-12 source): define a
% gradingCfgOverride struct in the caller workspace, e.g.
%   gradingCfgOverride = struct("snrGrid", [12, 18], "seeds", 2024, ...
%       "frameCount", 2, "saveEveryScenario", true);
%   run('curve_reference/run_37_curve_grading.m'); clear gradingCfgOverride
% A pre-run on uncommitted source records the CURRENT (pre-batch-12)
% gitCommit and is evidence only; the closeout re-runs on the final hash.
if exist("gradingCfgOverride", "var") && isstruct(gradingCfgOverride)
    overrideFields = fieldnames(gradingCfgOverride);
    for fieldIndex = 1:numel(overrideFields)
        cfg.(overrideFields{fieldIndex}) = ...
            gradingCfgOverride.(overrideFields{fieldIndex});
    end
end

here = fileparts(mfilename("fullpath"));
if isempty(here)
    here = pwd;
end
addpath(fullfile(here, ".."));

survey = struct();
survey.snrGrid = cfg.snrGrid;
survey.seeds = cfg.seeds;
survey.rngSeeds = cfg.seeds;
survey.frameCount = cfg.frameCount;
survey.symbols = cfg.symbols;
survey.scenarios = string(cfg.scenarios);
survey.equalizerIds = cell(1, numel(cfg.scenarios));
survey.errorBits = cell(1, numel(cfg.scenarios));
survey.totalBits = cell(1, numel(cfg.scenarios));
survey.ber = cell(1, numel(cfg.scenarios));
survey.berLower95 = cell(1, numel(cfg.scenarios));
survey.berUpper95 = cell(1, numel(cfg.scenarios));
survey.gradePerMethod = cell(1, numel(cfg.scenarios));
survey.gradeSource = cell(1, numel(cfg.scenarios));
survey.trendFlags = cell(1, numel(cfg.scenarios));
survey.effectiveParameters = cell(1, numel(cfg.scenarios));
survey.gitCommit = git_commit_short();
survey.matlabVersion = version;
survey.timestamp = datetime("now");
survey.notes = "scenario-bank curves are engineering evidence only; " + ...
    "only methods with an original digitized book curve receive a " + ...
    "curve_benchmark grade, all others are 不适用";

for scenarioIndex = 1:numel(cfg.scenarios)
    scenario = cfg.scenarios(scenarioIndex);
    ids = [];
    errBits = [];
    totBits = [];
    fprintf("=== scenario %s : snr %s dB, seeds %s, %d frames/point ===\n", ...
        scenario, mat2str(cfg.snrGrid), mat2str(cfg.seeds), cfg.frameCount);
    for snrIndex = 1:numel(cfg.snrGrid)
        snrDb = cfg.snrGrid(snrIndex);
        perSnrErrors = [];
        perSnrBits = [];
        for seedIndex = 1:numel(cfg.seeds)
            seed = cfg.seeds(seedIndex);
            r = run_unified_equalizer(struct("equalizers", "all", ...
                "scenario", scenario, "frameCount", cfg.frameCount, ...
                "symbols", cfg.symbols, "snrDb", snrDb, ...
                "makePlot", false, "randomSeed", seed));
            if seedIndex == 1
                ids = r.ids;
                perSnrErrors = zeros(1, numel(ids));
                perSnrBits = zeros(1, numel(ids));
            end
            perSnrErrors = perSnrErrors + double(r.errorBits);
            perSnrBits = perSnrBits + double(r.totalBits);
        end
        errBits(:, snrIndex) = perSnrErrors(:); %#ok<SAGROW>
        totBits(:, snrIndex) = perSnrBits(:); %#ok<SAGROW>
        fprintf("  snr %2d dB done\n", snrDb);
    end
    % Pooled per-method BER + exact 95% Clopper-Pearson intervals.
    ber = errBits ./ max(totBits, 1);
    [berLo, berHi] = clopper_pearson_95(errBits, totBits);
    % Trend diagnostic: flag relative BER worsening between adjacent SNR
    % points (report only - anomalies go back to the algorithm audit).
    trend = strings(numel(ids), numel(cfg.snrGrid));
    for m = 1:numel(ids)
        for s = 2:numel(cfg.snrGrid)
            if totBits(m, s - 1) > 0 && totBits(m, s) > 0 && ...
                    ber(m, s - 1) > 0 && ...
                    ber(m, s) > 1.5 * ber(m, s - 1) + 1e-9
                trend(m, s) = sprintf("up %.2gx @%ddB", ...
                    ber(m, s) / max(ber(m, s - 1), eps), cfg.snrGrid(s));
            end
        end
    end
    % Grades: only FDDA-TEQ has an original digitized book curve (Fig
    % 4-31, book/27.png).  Reuse the book-condition benchmark result if
    % present; otherwise mark it 待执行.  All other methods: 不适用.
    grades = repmat("不适用（无原文数字化曲线）", 1, numel(ids));
    gradeSources = grades;
    for m = 1:numel(ids)
        if ids(m) == "fdda-teq"
            benchFile = fullfile(here, "ch4_fig431_fdda_teq_true_benchmark.mat");
            if exist(benchFile, "file") == 2
                b = load(benchFile);
                grades(m) = b.benchmark.grade;
                gradeSources(m) = "book Fig. 4-31 (book/27.png) digitized reference, curve_benchmark, book-structure/trend benchmark on the project synthetic 3-tap channel (NOT experiment-identical: book channel undisclosed)";
            else
                grades(m) = "待执行";
                gradeSources(m) = "book Fig. 4-31 reference present; re-run ch4_fig431_fdda_teq_benchmark_run.m to grade";
            end
        end
    end
    % Effective parameters: one representative 1-frame run per method
    % (first seed, first SNR point).
    ep = cell(1, numel(ids));
    rLast = run_unified_equalizer(struct("equalizers", "all", ...
        "scenario", scenario, "frameCount", 1, ...
        "symbols", cfg.symbols, "snrDb", cfg.snrGrid(1), ...
        "makePlot", false, "randomSeed", cfg.seeds(1)));
    for m = 1:numel(ids)
        if m <= numel(rLast.traces) && ...
                isfield(rLast.traces{m}, "effectiveParameters")
            ep{m} = rLast.traces{m}.effectiveParameters;
        end
    end
    % Store per scenario.
    survey.equalizerIds{scenarioIndex} = ids;
    survey.errorBits{scenarioIndex} = errBits;
    survey.totalBits{scenarioIndex} = totBits;
    survey.ber{scenarioIndex} = ber;
    survey.berLower95{scenarioIndex} = berLo;
    survey.berUpper95{scenarioIndex} = berHi;
    survey.gradePerMethod{scenarioIndex} = grades;
    survey.gradeSource{scenarioIndex} = gradeSources;
    survey.trendFlags{scenarioIndex} = trend;
    survey.effectiveParameters{scenarioIndex} = ep;
    % Compact printout.
    fprintf("\n%-18s %-30s %s\n", "method", "BER @18dB (95% CI)", "trend flags");
    for m = 1:numel(ids)
        sLast = numel(cfg.snrGrid);
        nonEmptyFlags = trend(m, :);
        nonEmptyFlags = nonEmptyFlags(strlength(nonEmptyFlags) > 0);
        if isempty(nonEmptyFlags)
            flagStr = "-";
        else
            flagStr = strjoin(nonEmptyFlags, "; ");
        end
        fprintf("%-18s %8.3e [%8.3e, %8.3e]  %s\n", ids(m), ...
            ber(m, sLast), berLo(m, sLast), berHi(m, sLast), flagStr);
    end
    if scenario == "turbo"
        td = find(ids == "tdda-teq", 1);
        if ~isempty(td)
            fprintf("\n>>> tdda-teq BER vs SNR (priority audit):\n");
            for s = 1:numel(cfg.snrGrid)
                fprintf("    %2d dB  %8.3e  (%d/%d)\n", cfg.snrGrid(s), ...
                    ber(td, s), errBits(td, s), totBits(td, s));
            end
        end
    end
    if cfg.saveEveryScenario
        save(fullfile(here, sprintf("run_37_curve_grading_%s_%s_partial.mat", ...
            survey.gitCommit, scenario)), "-struct", "survey");
    end
end

outFile = fullfile(here, sprintf("run_37_curve_grading_%s.mat", ...
    survey.gitCommit));
save(outFile, "-struct", "survey");
fprintf("\nSaved %s\n", outFile);
fprintf("gradePerMethod: only fdda-teq has a digitized original book curve\n");
fprintf("(Fig. 4-31) and received a curve_benchmark grade; every other\n");
fprintf("method is 不适用 - the scenario curves are engineering evidence.\n");

function [lo95, hi95] = clopper_pearson_95(errors, bits)
% Exact 95% Clopper-Pearson binomial interval (0 when errors = 0),
% identical definition to run_unified_equalizer's internal helper.
% The input SHAPE is preserved: the caller indexes the result as a
% matrix (methods x SNR), so the flat computation is reshaped back.
inputSize = size(errors);
errors = double(errors(:));
bits = double(bits(:));
alpha = 0.05;
lo95 = zeros(size(errors));
hi95 = zeros(size(errors));
for index = 1:numel(errors)
    x = errors(index);
    n = bits(index);
    if x == 0
        lo95(index) = 0;
        hi95(index) = 1 - (alpha / 2)^(1 / max(n, 1));
    elseif x == n
        lo95(index) = (alpha / 2)^(1 / max(n, 1));
        hi95(index) = 1;
    else
        lo95(index) = betainv(alpha / 2, x, n - x + 1);
        hi95(index) = betainv(1 - alpha / 2, x + 1, n - x);
    end
end
lo95 = reshape(lo95, inputSize);
hi95 = reshape(hi95, inputSize);
end

function commit = git_commit_short()
commit = "";
try
    here = fileparts(mfilename("fullpath"));
    if isempty(here)
        here = pwd;
    end
    repo = fileparts(here);
    [status, out] = system("git -C " + string(repo) + ...
        " rev-parse --short HEAD 2>nul");
    if status == 0
        commit = strtrim(string(out));
    end
catch
    commit = "";
end
end
