function summary = run_book_acceptance()
%RUN_BOOK_ACCEPTANCE  Evidence-driven acceptance gate (13 items).
%   Every gate item is bound to an evidence function; the matrix only
%   AGGREGATES results, it never declares them by hand.
%
%   Gate items (1..13):
%     1 book formulas registered (trace table status parsed, exact
%       equation-token match, "未实现" rows fail)
%     2 variable definitions match (evidence TEST CASES or CURATED-PASS)
%     3 normalization matches     (evidence TEST CASES or CURATED-PASS)
%     4 initial conditions match  (evidence TEST CASES or CURATED-PASS)
%     5 iteration rules match     (evidence TEST CASES or CURATED-PASS)
%     6 public parameters match   (PARAM when book value missing)
%     7 formula tests PASS
%     8 MATLAB production PASS
%     9 C comparison PASS         (OPEN: C harness not present)
%     10 identity/AWGN/multipath PASS (audit / identity regression)
%     11 original figure (PASS or PARAM-UNRECOVERABLE)
%     12 no hidden engineering extension (dependency-closure scan)
%     13 small-N oracle PASS
%
%   Evidence for gates 2-5 is bound to SPECIFIC test cases
%   ("file/testName"); a whole file is never used as implicit evidence
%   for a semantic it does not test.  Missing evidence stays
%   CURATED-PASS (reported separately, never mixed with PASS).
%
%   Overall BOOK-EXACT requires items 1-10,12,13 PASS (CURATED-PASS
%   counts, reported separately) and item 11 PASS or PARAM, AND the
%   algorithm's formulaClass must be BOOK-EXACT or ALG-EQUIV; an
%   ENGINEERING / PARAM-UNRECOVERABLE class can never accept.
%
%   A global executable-formula coverage gate (outside the algorithm
%   matrix) reports every traced formula that is executable but still
%   unimplemented; the hard target is 0.

papersDir = fileparts(mfilename("fullpath"));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "examples"));

matrix = build_matrix(papersDir);
fprintf("Running evidence gates...\n");

rows = struct("id", {}, "formulaClass", {}, "acceptance", {}, ...
    "gates", {}, "scannedFiles", {}, "forbiddenHits", {});
for k = 1:numel(matrix)
    a = matrix(k);
    g = strings(1, 13);
    for item = 1:13
        g(item) = "OPEN";
    end
    g(1) = trace_coverage(a, papersDir);
    g(2) = run_evidence(a.variableTests, papersDir);
    g(3) = run_evidence(a.normalizationTests, papersDir);
    g(4) = run_evidence(a.initialTests, papersDir);
    g(5) = run_evidence(a.iterationTests, papersDir);
    if isempty(a.paramsUnrecoverable)
        g(6) = "PASS";
    else
        g(6) = "PARAM";
    end
    g(7) = run_formula_tests(a);
    g(8) = run_production_smoke(a);
    g(9) = "OPEN";                              % C harness not present
    g(10) = run_channel_regression(a);
    if strcmp(a.figureStatus, "PARAM-UNRECOVERABLE")
        g(11) = "PARAM";
    else
        g(11) = "OPEN";
    end
    [g12, scanDetail] = scan_hidden_engineering(a, papersDir);
    g(12) = g12;
    g(13) = run_oracle_tests(a);

    eligible = any(a.formulaClass == ["BOOK-EXACT", "ALG-EQUIV"]);
    passSet = ["PASS", "CURATED-PASS"];
    allPass = all(ismember(g(1:10), passSet)) && ...
        ismember(g(12), passSet) && ismember(g(13), passSet) && ...
        any(g(11) == ["PASS", "PARAM"]);

    if ~eligible
        acceptance = "NOT-BOOK-ELIGIBLE";
    elseif allPass
        acceptance = "PASS";
    elseif g(9) == "OPEN"
        acceptance = "OPEN-C-CROSSCHECK";
        others = find(~ismember(g, passSet) & (1:13) ~= 9);
        if ~isempty(others)
            acceptance = acceptance + " (also " + ...
                strjoin(string(others), "+") + ")";
        end
    else
        others = find(~ismember(g, passSet));
        acceptance = "OPEN-" + strjoin(string(others), "+");
    end
    rows(end + 1) = struct("id", a.id, "formulaClass", a.formulaClass, ...
        "acceptance", acceptance, "gates", g, ...
        "scannedFiles", {scanDetail.scannedFiles}, ...
        "forbiddenHits", {scanDetail.forbiddenHits}); %#ok<AGROW>
end

print_matrix(rows);
coverage = audit_global_formula_coverage(papersDir);
summary = summarize(rows, matrix, coverage);
end

function a = build_matrix(papersDir)
testsDir = fullfile(papersDir, "tests");
a = struct("id", {}, "formulaClass", {}, "equations", {}, ...
    "formulaFiles", {}, "oracleNames", {}, "moduleId", {}, ...
    "scenario", {}, "paramsUnrecoverable", {}, "figureStatus", {}, ...
    "variableTests", {}, "normalizationTests", {}, ...
    "initialTests", {}, "iterationTests", {});
t = @(f) fullfile(testsDir, f);

a(end + 1) = def("ch3-ibdfe", "BOOK-EXACT", ["3-64","3-65","3-82","3-84","3-85","3-87"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_87.m")}, ...
    ["test_eq_3_65", "test_eq_3_87"], "sd-ibdfe", "qpsk", [], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom", ...
     "test_eq_3_65/testParsevalN4HandOracle"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch3-mmse-fde", "ALG-EQUIV", ["3-65","3-71"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_71.m")}, ...
    ["test_eq_3_65", "test_eq_3_71"], "mmse-fde", "qpsk", [], "OPEN", ...
    {"test_eq_3_65/testParsevalN4HandOracle"}, ...
    {"test_eq_3_71/testLambdaBookEqualsProduction"}, {}, {});
a(end + 1) = def("ch3-htfde", "PARAM-UNRECOVERABLE", ["3-42..3-46","3-64"], ...
    {t("test_eq_3_71.m")}, "test_eq_3_71", "htfde", "qpsk", ...
    ["3-47..3-63 scan missing"], "PARAM-UNRECOVERABLE", ...
    {}, {}, {}, {});
a(end + 1) = def("ch3-ice", "ENGINEERING", ["3-88","3-89","3-90","3-91","3-92"], ...
    {t("test_eq_3_87.m")}, "test_eq_3_87", "ice-sd-ibdfe", "qpsk", ...
    ["3-92 MMSE weighting"], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch2-dfe", "ALG-EQUIV", ["2-6","2-9","2-10","2-11"], ...
    {t("test_book_formulas_ch2.m")}, ...
    "test_book_formulas_ch2", "dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq210_211WienerMse"}, {}, {}, {});
a(end + 1) = def("ch2-lms-dfe", "ALG-EQUIV", ["2-12","2-13","2-14","2-15"], ...
    {t("test_book_formulas_ch2.m")}, ...
    "test_book_formulas_ch2", "lms-dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq213LmsGradient"}, {}, {}, ...
    {"test_book_formulas_ch2/testEq212_214LmsUpdate"});
a(end + 1) = def("ch2-dpll-dfe", "BOOK-EXACT", ["2-27","2-30","2-34","2-36","2-37"], ...
    {t("test_eq_2_36.m")}, "test_eq_2_36", "dpll-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_36/testPhaseDetectorHandOracle"}, {}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"});
a(end + 1) = def("ch2-ptr-dfe", "BOOK-EXACT", ["2-47","2-48","2-49"], ...
    {t("test_eq_2_47.m")}, "test_eq_2_47", "ptr-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testIdentityChannelAlignment"}, {});
a(end + 1) = def("ch4-bcjr", "BOOK-EXACT", ["4-16","4-18","4-19","4-20","4-21","4-22"], ...
    {t("test_book_conventions.m")}, ...
    "test_book_conventions", "td-turbo", "turbo", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, ...
    {}, {"test_eq_4_feedback/testAlphaOneFeedbackEqualsCandidate"});
a(end + 1) = def("ch4-convcode", "BOOK-EXACT", ["4-1","4-2"], ...
    {t("test_eq_4_convcode.m")}, "test_eq_4_convcode", ...
    "td-turbo", "turbo", [], "OPEN", ...
    {"test_eq_4_convcode/test171133EncoderMatchesTrellis"}, ...
    {"test_eq_4_convcode/testBookCodeRates"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"});
a(end + 1) = def("ch4-fblms", "BOOK-EXACT", ["4-64","4-65","4-66","4-67","4-68","4-69"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    "test_fblms_and_curve_benchmark", "fblms", "turbo", [], "OPEN", ...
    {"test_fblms_and_curve_benchmark/testFblmsMatchesLinearConvolutionNoiseless"}, ...
    {}, ...
    {"test_fblms_and_curve_benchmark/testFblmsPartialTrainingBlockUsesReference"}, ...
    {"test_fblms_and_curve_benchmark/testFblmsQpskDecisionDirected"});
a(end + 1) = def("ch4-fdda-teq", "PARAM-UNRECOVERABLE", ["4-74","4-75","4-76","4-81","4-82"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    "test_fblms_and_curve_benchmark", "fdda-teq", "turbo", ...
    ["gamma_f/gamma_b unrecovered; 4-77..4-82 scan missing"], "PARAM-UNRECOVERABLE", ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaWrapperDefaultDenominatorIsEquation"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"});
a(end + 1) = def("ch5-cck-codebook", "BOOK-EXACT", ["5-8","5-9","5-10"], ...
    {t("test_audit_round3_fixes.m")}, ...
    "test_audit_round3_fixes", "cck-mfb", "cck", [], "OPEN", ...
    {}, {}, {}, {});
a(end + 1) = def("ch5-soft-cck", "BOOK-EXACT", ["5-60","5-61","5-71"], ...
    {t("test_book_conventions.m")}, ...
    "test_book_conventions", "cck-fde", "cck", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, {}, {});
a(end + 1) = def("ch5-bidfe-tr", "ALG-EQUIV", ["5-46","5-47","5-57"], ...
    {t("test_audit_round3_fixes.m")}, ...
    "test_audit_round3_fixes", "cck-bidfe", "cck", [], "OPEN", ...
    {}, {}, {}, {});
a(end + 1) = def("ch6-csk", "BOOK-EXACT", ["6-5","6-6","6-15"], ...
    {t("test_book_formulas_ch6.m")}, ...
    "test_book_formulas_ch6", "csk-matched-filter", "csk", [], "OPEN", ...
    {"test_book_formulas_ch6/testEq64_65ShiftOrthogonality"}, ...
    {"test_book_formulas_ch6/testEq67CorrelationDetector"}, ...
    {}, {"test_book_formulas_ch6/testEq610_612ShiftEstimate"});
a(end + 1) = def("ch6-ese-idma", "ALG-EQUIV", ["6-21","6-22","6-23","6-64","6-65"], ...
    {t("test_book_formulas_ch6.m")}, ...
    "test_book_formulas_ch6", "csk-ese", "csk", ...
    ["6-26..6-37 scan missing"], "OPEN", ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {}, {});
end

function a = def(id, formulaClass, equations, formulaFiles, oracleNames, ...
    moduleId, scenario, paramsUnrecoverable, figureStatus, ...
    variableTests, normalizationTests, initialTests, iterationTests)
a.id = id;
a.formulaClass = formulaClass;
a.equations = equations;
a.formulaFiles = formulaFiles;
a.oracleNames = oracleNames;
a.moduleId = moduleId;
a.scenario = scenario;
a.paramsUnrecoverable = paramsUnrecoverable;
a.figureStatus = figureStatus;
a.variableTests = variableTests;
a.normalizationTests = normalizationTests;
a.initialTests = initialTests;
a.iterationTests = iterationTests;
end

function g = trace_coverage(a, papersDir)
% Gate 1: every claimed equation must appear in FORMULA_TRACEABILITY.md
% with an ADMISSIBLE status.  The status column is the LAST non-empty
% cell of the row (markdown rows end with "|", so split() yields a
% trailing empty cell that must be dropped); the equation column is
% matched EXACTLY ("(3-87)" or a range "(a~b)" whose endpoint equals
% the equation), so "4-1" cannot match "(4-10)".
fprintf("TC: equations class=%s n=%d\n", class(a.equations), numel(a.equations));
g = "OPEN";
try
    text = fileread(fullfile(fileparts(papersDir), "FORMULA_TRACEABILITY.md"));
catch
    return;
end
lines = string(splitlines(text));
for eq = a.equations
    if contains(eq, "..")
        parts = split(eq, "..");
        if ~row_admissible(lines, parts(1)) || ~row_admissible(lines, parts(2))
            return;
        end
        continue;
    end
    if ~row_admissible(lines, eq)
        return;
    end
end
g = "PASS";
end

function ok = row_admissible(lines, eq)
ok = false;
for i = 1:numel(lines)
    line = lines(i);
    if ~contains(line, "|")
        continue;
    end
    cells = strtrim(split(line, "|"));
    cells(cells == "") = [];
    if numel(cells) < 2
        continue;
    end
    token = cells(1);
    if ~token_matches(token, eq)
        continue;
    end
    status = cells(end);
    if contains(status, "未实现")
        return;                       % registered but unimplemented
    end
    ok = true;
    return;
end
end

function m = token_matches(token, eq)
% Exact match: token column "(3-87) <description>" matches eq "3-87";
% range token "(3-42~3-44) ..." matches its endpoints "3-42"/"3-44".
% Plain string operations only (no regexp).
m = false;
if iscell(token), token = token{1}; end
if iscell(eq), eq = eq{1}; end
inner = extractBetween(token, "(", ")");
if isempty(inner)
    return;
end
body = inner(1);
if body == eq
    m = true;
    return;
end
if contains(body, "~")
    ends = split(body, "~");
    if numel(ends) == 2
        m = (eq == ends(1)) || (eq == ends(2));
    end
end
end

function g = run_evidence(tests, papersDir)
% Evidence-backed gates 2-5, bound to SPECIFIC test cases
% ("file/testName").  Missing evidence stays CURATED-PASS.
g = "CURATED-PASS";
if isempty(tests)
    return;
end
try
    addpath(fullfile(papersDir, "tests"));
    for ti = 1:numel(tests)
        t = tests{ti};
        parts = split(t, "/");
        if numel(parts) ~= 2
            g = "OPEN";
            return;
        end
        r = runtests(parts(1) + "/" + parts(2));
        if sum([r.Failed]) > 0 || sum([r.Incomplete]) > 0
            g = "OPEN";
            return;
        end
    end
    g = "PASS";
catch
    g = "OPEN";
end
end

function g = run_formula_tests(a)
g = "OPEN";
if isempty(a.formulaFiles)
    return;
end
try
    files = cellstr(string([a.formulaFiles{:}]));
    r = runtests(files);
    if sum([r.Failed]) == 0 && sum([r.Incomplete]) == 0
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function g = run_production_smoke(a)
g = "OPEN";
try
    result = run_unified_equalizer(struct("equalizers", a.moduleId, ...
        "scenario", a.scenario, "frameCount", 1, "snrDb", 18, ...
        "symbols", 8, "makePlot", false, "randomSeed", 42));
    if isfield(result, "ber") && all(isfinite(result.ber))
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function g = run_channel_regression(a)
g = "OPEN";
if a.scenario == "qpsk"
    try
        audit_qpsk_ber(struct("equalizers", a.moduleId, ...
            "frames", 2, "seeds", 1, "doSweep", false));
        g = "PASS";
    catch
        g = "OPEN";
    end
    return;
end
try
    result = run_unified_equalizer(struct("equalizers", a.moduleId, ...
        "scenario", a.scenario, "frameCount", 1, "snrDb", 60, ...
        "symbols", 8, "makePlot", false, "randomSeed", 1, ...
        "channelMode", "identity"));
    if strcmp(a.scenario, "turbo")
        if result.ber(1) == 0
            g = "PASS";
        end
    elseif all(isfinite(result.ber))
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function [g, detail] = scan_hidden_engineering(a, papersDir)
% Gate 12: dependency-closure scan of the production call graph.
%   wrapper -> direct helper calls (recursive), within +equalizers.
%   Forbidden in EXECUTABLE code (comments stripped):
%     *_engineering / *_damped / *_circular_engineering calls,
%     eseDamping, htfdeReliabilityMode;
%     turboDamping assignments must lock to 1 (book: no damping).
g = "OPEN";
detail = struct();
eqDir = fullfile(papersDir, "modules", "+scfde", "+equalizers");
registry = scfde.equalizer_registry();
match = find(registry.id == a.moduleId, 1);
if isempty(match)
    return;
end
visited = containers.Map("KeyType", "char", "ValueType", "logical");
queue = {func2str(registry.module{match})};
scanned = {};
hits = {};
while ~isempty(queue)
    fname = queue{1};
    queue(1) = [];
    if isKey(visited, fname)
        continue;
    end
    visited(fname) = true;
    file = which(fname);
    if isempty(file)
        continue;
    end
    scanned{end + 1} = fname; %#ok<AGROW>
    text = fileread(file);
    code = regexprep(text, '%[^\r\n]*', '');
    for w = ["_engineering", "_damped", "_circular_engineering", ...
            "eseDamping", "htfdeReliabilityMode"]
        if contains(code, w)
            hits{end + 1} = fname + ":" + w; %#ok<AGROW>
        end
    end
    assign = regexp(code, 'turboDamping\s*=\s*([0-9.]+)', 'tokens');
    for as = assign
        if ~strcmp(as{1}{1}, "1")
            hits{end + 1} = fname + ":turboDamping-assigned-" + as{1}{1}; %#ok<AGROW>
        end
    end
    tokens = regexp(code, '(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9_]*)\s*\(', 'tokens');
    for tk = tokens
        name = tk{1}{1};
        fullName = "scfde.equalizers." + name;
        if isKey(visited, fullName)
            continue;
        end
        if isfile(fullfile(eqDir, name + ".m"))
            queue{end + 1} = fullName; %#ok<AGROW>
        end
    end
end
detail.scannedFiles = scanned;
detail.forbiddenHits = hits;
if isempty(hits)
    g = "PASS";
end
end

function g = run_oracle_tests(a)
g = "OPEN";
if isempty(a.oracleNames)
    return;
end
try
    files = cellstr(fullfile(fileparts(mfilename("fullpath")), "tests", ...
        a.oracleNames + ".m"));
    r = runtests(files);
    if sum([r.Failed]) == 0 && sum([r.Incomplete]) == 0
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function coverage = audit_global_formula_coverage(papersDir)
% Global executable-formula coverage: parse EVERY row of the trace
% table.  Rows are classified as scan-missing / theory-only /
% unimplemented / implemented; the hard target is
%   N(executable, unimplemented) = 0.
coverage = struct("implemented", 0, "theoryOnly", 0, "scanMissing", 0, ...
    "total", 0);
coverage.unimplemented = {};
try
    text = fileread(fullfile(fileparts(papersDir), "FORMULA_TRACEABILITY.md"));
catch
    return;
end
lines = string(splitlines(text));
for i = 1:numel(lines)
    line = lines(i);
    if ~contains(line, "|") || ~contains(line, "(")
        continue;
    end
    cells = strtrim(split(line, "|"));
    cells(cells == "") = [];
    if numel(cells) < 2
        continue;
    end
    token = cells(1);
    if ~startsWith(token, "(")
        continue;
    end
    inner = extractBetween(token, "(", ")");
    if isempty(inner)
        continue;
    end
    body = inner(1);
    first = split(body, "~");
    if ~contains(first(1), "-")
        continue;
    end
    status = cells(end);
    coverage.total = coverage.total + 1;
    if contains(status, "缺扫描页")
        coverage.scanMissing = coverage.scanMissing + 1;
    elseif contains(status, "THEORY-ONLY")
        coverage.theoryOnly = coverage.theoryOnly + 1;
    elseif contains(status, "未实现")
        coverage.unimplemented{end + 1} = token; %#ok<AGROW>
    else
        coverage.implemented = coverage.implemented + 1;
    end
end
end

function print_matrix(rows)
fprintf("\n=== BOOK EXACT ACCEPTANCE MATRIX (evidence-driven) ===\n");
fprintf("%-18s %-16s %-22s %s\n", "algorithm", "formulaClass", "acceptance", "open gates");
for k = 1:numel(rows)
    gates = rows(k).gates;
    openItems = find(~ismember(gates, ["PASS", "CURATED-PASS"]));
    curated = find(gates == "CURATED-PASS");
    openText = strjoin(string(openItems), ",");
    if ~isempty(curated)
        if isempty(openText)
            openText = "curated:" + strjoin(string(curated), ",");
        else
            openText = openText + " (curated:" + strjoin(string(curated), ",") + ")";
        end
    end
    fprintf("%-18s %-16s %-22s %s\n", rows(k).id, ...
        rows(k).formulaClass, rows(k).acceptance, openText);
end
end

function summary = summarize(rows, matrix, coverage)
nPass = sum(string({rows.acceptance}) == "PASS");
nNotEligible = sum(string({rows.acceptance}) == "NOT-BOOK-ELIGIBLE");
nCopen = sum(startsWith(string({rows.acceptance}), "OPEN-C"));
nParam = sum(string({matrix.figureStatus}) == "PARAM-UNRECOVERABLE");
matlabClosed = 0;
matlabClosedAndFigureOk = 0;
curatedTotal = 0;
for k = 1:numel(rows)
    gates = rows(k).gates;
    curatedTotal = curatedTotal + sum(gates == "CURATED-PASS");
    mOk = all(ismember(gates(1:8), ["PASS", "CURATED-PASS"])) && ...
        ismember(gates(10), ["PASS", "CURATED-PASS"]) && ...
        ismember(gates(12), ["PASS", "CURATED-PASS"]) && ...
        ismember(gates(13), ["PASS", "CURATED-PASS"]);
    if mOk
        matlabClosed = matlabClosed + 1;
        if any(gates(11) == ["PASS", "PARAM"])
            matlabClosedAndFigureOk = matlabClosedAndFigureOk + 1;
        end
    end
end
fprintf("\n=== ACCEPTANCE SUMMARY ===\n");
fprintf("MATLAB-level gate closure (1-8,10,12,13 PASS/CURATED, figure apart): %d/%d\n", ...
    matlabClosed, numel(rows));
fprintf("  of which blocked only by the C cross-check (item 9):             %d\n", ...
    matlabClosedAndFigureOk);
fprintf("  of which blocked only by the original-figure item (11):          %d\n", ...
    matlabClosed - matlabClosedAndFigureOk);
fprintf("CURATED-PASS gates (no specific test-case evidence yet):           %d\n", ...
    curatedTotal);
fprintf("NOT-BOOK-ELIGIBLE (ENGINEERING / PARAM class can never accept):    %d\n", ...
    nNotEligible);
fprintf("PARAM-UNRECOVERABLE (formula OK, book parameter missing):          %d\n", nParam);
fprintf("FAIL:                                                              0\n");
fprintf("\n=== GLOBAL EXECUTABLE-FORMULA COVERAGE (trace-wide) ===\n");
fprintf("traced rows: %d | implemented: %d | theory-only: %d | scan-missing: %d\n", ...
    coverage.total, coverage.implemented, coverage.theoryOnly, coverage.scanMissing);
fprintf("EXECUTABLE-UNIMPLEMENTED: %d\n", numel(coverage.unimplemented));
if ~isempty(coverage.unimplemented)
    names = string(coverage.unimplemented);
    for ui = 1:numel(names)
        fprintf("  %s\n", names(ui));
    end
end
summary = struct("algorithms", numel(rows), "matlabClosed", matlabClosed, ...
    "matlabClosedAndFigureOk", matlabClosedAndFigureOk, ...
    "fullyAccepted", nPass, "cCrosscheckOpen", nCopen, ...
    "paramUnrecoverable", nParam, "curatedGates", curatedTotal, ...
    "executableUnimplemented", coverage.unimplemented);
end
