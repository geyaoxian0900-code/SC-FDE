function summary = run_book_acceptance()
%RUN_BOOK_ACCEPTANCE  Final acceptance system (evidence-driven, frozen).
%   Single equation-ID parser (book_acceptance.parse_equation_ids) is
%   shared by g1, the global coverage audit and the formulaClass
%   derivation.  Gate states are five-valued:
%     PASS          automatic evidence executed and passed
%     CURATED-PASS  human-reviewed, no specific automatic test
%     OPEN          evidence/tooling missing (scan, C harness, figures)
%     PARAM         book parameter genuinely unpublished
%     FAIL          evidence exists and explicitly fails
%   Hard acceptance requires every required gate to be PASS; any
%   CURATED-PASS yields OPEN-CURATED-EVIDENCE (never PASS).
%
%   Gate items (1..13):
%     1 formula registered with admissible status (BOOK-EXACT/ALG-EQUIV)
%     2 variable definitions (specific test cases or CURATED-PASS)
%     3 normalization matches     (specific test cases or CURATED-PASS)
%     4 initial conditions match  (specific test cases or CURATED-PASS)
%     5 iteration rules match     (specific test cases or CURATED-PASS)
%     6 public parameters match   (PARAM when book value missing)
%     7 formula tests PASS
%     8 MATLAB production PASS
%     9 C comparison PASS         (OPEN: C harness not present)
%     10 identity/AWGN/multipath PASS
%     11 original figure (PASS or PARAM)
%     12 no hidden engineering (dependency-closure scan; hits = FAIL)
%     13 small-N oracle PASS

papersDir = fileparts(mfilename("fullpath"));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "examples"));

statusMap = build_status_map(papersDir);
matrix = build_matrix(papersDir, statusMap);
fprintf("Running evidence gates...\n");

rows = struct("id", {}, "formulaClass", {}, "matlabStatus", {}, ...
    "cStatus", {}, "figureStatus", {}, "overallStatus", {}, ...
    "gates", {}, "scannedFiles", {}, "forbiddenHits", {});
for k = 1:numel(matrix)
    a = matrix(k);
    g = strings(1, 13);
    for item = 1:13
        g(item) = "OPEN";
    end
    g(1) = trace_coverage(a, statusMap);
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

    eligible = any(a.formulaClass == ...
        ["BOOK-EXACT", "ALG-EQUIV", "OPEN-OCR", "OPEN-SCAN", ...
         "OPEN-UNIMPLEMENTED"]);

    required = [1:8, 10, 12, 13];
    hardPass = all(g(required) == "PASS") && ...
        any(g(11) == ["PASS", "PARAM"]);
    reviewPass = all(ismember(g(required), ["PASS", "CURATED-PASS"])) && ...
        any(g(11) == ["PASS", "PARAM"]);

    if ~eligible
        overall = "NOT-BOOK-ELIGIBLE";
    elseif any(g == "FAIL")
        overall = "FAIL";
    elseif hardPass
        overall = "PASS";
    elseif any(g(required) == "CURATED-PASS")
        overall = "OPEN-CURATED-EVIDENCE";
    elseif g(9) == "OPEN"
        overall = "OPEN-C";
    elseif g(11) == "OPEN"
        overall = "OPEN-FIGURE";
    else
        overall = "OPEN-MATLAB";
    end

    if all(g(required) == "PASS")
        matlabStatus = "PASS";
    elseif any(g(required) == "FAIL")
        matlabStatus = "FAIL";
    elseif any(g(required) == "CURATED-PASS")
        matlabStatus = "OPEN-CURATED";
    else
        matlabStatus = "OPEN";
    end
    cStatus = g(9);
    figureStatus = g(11);

    rows(end + 1) = struct("id", a.id, "formulaClass", a.formulaClass, ...
        "matlabStatus", matlabStatus, "cStatus", cStatus, ...
        "figureStatus", figureStatus, "overallStatus", overall, ...
        "gates", g, "scannedFiles", {scanDetail.scannedFiles}, ...
        "forbiddenHits", {scanDetail.forbiddenHits}); %#ok<AGROW>
end

coverage = audit_global_formula_coverage(papersDir);
print_matrix(rows);
summary = summarize(rows, matrix, coverage);
end

function statusMap = build_status_map(papersDir)
% eqID -> struct(FormulaStatus, ParameterStatus)
statusMap = containers.Map("KeyType", "char", "ValueType", "any");
try
    text = fileread(fullfile(fileparts(papersDir), "FORMULA_TRACEABILITY.md"));
catch
    return;
end
lines = string(splitlines(text));
for i = 1:numel(lines)
    line = lines(i);
    if ~contains(line, "|")
        continue;
    end
    cells = strtrim(split(line, "|"));
    cells(cells == "") = [];
    if numel(cells) < 4
        continue;
    end
    ids = book_acceptance.parse_equation_ids(cells(1));
    if isempty(ids)
        continue;
    end
    fs = cells(end - 1);
    ps = cells(end);
    for id = ids
        statusMap(char(id)) = struct("FormulaStatus", char(fs), ...
            "ParameterStatus", char(ps));
    end
end
end

function fs = formula_status(a, statusMap)
fs = "";
if isKey(statusMap, char(a))
    fs = statusMap(char(a)).FormulaStatus;
end
end

function class_ = derive_formula_class(equations, statusMap)
% Lowest-class aggregation across the algorithm's equation set.
statuses = strings(0);
for eq = equations
    if isKey(statusMap, char(eq))
        statuses(end + 1) = statusMap(char(eq)).FormulaStatus; %#ok<AGROW>
    else
        statuses(end + 1) = "SCAN-MISSING"; %#ok<AGROW>  % untraced ID
    end
end
if isempty(statuses)
    class_ = "OPEN";
    return;
end
if any(statuses == "ENGINEERING")
    class_ = "ENGINEERING";
elseif any(statuses == "EXECUTABLE-UNIMPLEMENTED")
    class_ = "OPEN-UNIMPLEMENTED";
elseif any(statuses == "SCAN-MISSING")
    class_ = "OPEN-SCAN";
elseif any(statuses == "OCR-UNCERTAIN")
    class_ = "OPEN-OCR";
elseif any(statuses == "ALG-EQUIV")
    class_ = "ALG-EQUIV";
elseif all(statuses == "BOOK-EXACT")
    class_ = "BOOK-EXACT";
else
    class_ = "OPEN";
end
end

function a = build_matrix(papersDir, statusMap)
testsDir = fullfile(papersDir, "tests");
a = struct("id", {}, "equations", {}, "formulaFiles", {}, ...
    "oracleNames", {}, "moduleId", {}, "scenario", {}, ...
    "paramsUnrecoverable", {}, "figureStatus", {}, ...
    "variableTests", {}, "normalizationTests", {}, ...
    "initialTests", {}, "iterationTests", {});
t = @(f) fullfile(testsDir, f);

a(end + 1) = def("ch3-ibdfe", ["3-64","3-65","3-82","3-84","3-85","3-87"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_87.m")}, ...
    ["test_eq_3_65", "test_eq_3_87"], "sd-ibdfe", "qpsk", [], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom", ...
     "test_eq_3_65/testParsevalN4HandOracle"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch3-mmse-fde", ["3-65","3-71"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_71.m")}, ...
    ["test_eq_3_65", "test_eq_3_71"], "mmse-fde", "qpsk", [], "OPEN", ...
    {"test_eq_3_65/testParsevalN4HandOracle"}, ...
    {"test_eq_3_71/testLambdaBookEqualsProduction"}, {}, {});
a(end + 1) = def("ch3-htfde", ["3-42..3-46","3-64","3-47..3-63"], ...
    {t("test_eq_3_71.m")}, "test_eq_3_71", "htfde", "qpsk", ...
    ["3-47..3-63 scan missing"], "PARAM-UNRECOVERABLE", ...
    {}, {}, {}, {});
a(end + 1) = def("ch3-ice", ["3-88","3-89","3-90","3-91","3-92"], ...
    {t("test_eq_3_87.m")}, "test_eq_3_87", "ice-sd-ibdfe", "qpsk", ...
    ["3-92 MMSE weighting"], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch2-dfe", ["2-6","2-9","2-10","2-11"], ...
    {t("test_book_formulas_ch2.m")}, ...
    "test_book_formulas_ch2", "dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq210_211WienerMse"}, {}, {}, {});
a(end + 1) = def("ch2-lms-dfe", ["2-12","2-13","2-14","2-15"], ...
    {t("test_book_formulas_ch2.m")}, ...
    "test_book_formulas_ch2", "lms-dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq213LmsGradient"}, {}, {}, ...
    {"test_book_formulas_ch2/testEq212_214LmsUpdate"});
a(end + 1) = def("ch2-dpll-dfe", ["2-27","2-30","2-34","2-36","2-37"], ...
    {t("test_eq_2_36.m")}, "test_eq_2_36", "dpll-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_36/testPhaseDetectorHandOracle"}, {}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"});
a(end + 1) = def("ch2-ptr-dfe", ["2-47","2-48","2-49"], ...
    {t("test_eq_2_47.m")}, "test_eq_2_47", "ptr-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testIdentityChannelAlignment"}, {});
a(end + 1) = def("ch4-bcjr", ["4-16","4-18","4-19","4-20","4-21","4-22"], ...
    {t("test_book_conventions.m")}, ...
    "test_book_conventions", "td-turbo", "turbo", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, ...
    {}, {"test_eq_4_feedback/testAlphaOneFeedbackEqualsCandidate"});
a(end + 1) = def("ch4-convcode", ["4-1","4-2"], ...
    {t("test_eq_4_convcode.m")}, "test_eq_4_convcode", ...
    "td-turbo", "turbo", [], "OPEN", ...
    {"test_eq_4_convcode/test171133EncoderMatchesTrellis"}, ...
    {"test_eq_4_convcode/testBookCodeRates"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"});
a(end + 1) = def("ch4-fblms", ["4-64","4-65","4-66","4-67","4-68","4-69"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    "test_fblms_and_curve_benchmark", "fblms", "turbo", [], "OPEN", ...
    {"test_fblms_and_curve_benchmark/testFblmsMatchesLinearConvolutionNoiseless"}, ...
    {}, ...
    {"test_fblms_and_curve_benchmark/testFblmsPartialTrainingBlockUsesReference"}, ...
    {"test_fblms_and_curve_benchmark/testFblmsQpskDecisionDirected"});
a(end + 1) = def("ch4-fdda-teq", ["4-74","4-75","4-76","4-77..4-82"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    "test_fblms_and_curve_benchmark", "fdda-teq", "turbo", ...
    ["gamma_f/gamma_b unrecovered; 4-77..4-82 scan missing"], "PARAM-UNRECOVERABLE", ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaWrapperDefaultDenominatorIsEquation"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"});
a(end + 1) = def("ch5-cck-codebook", ["5-8","5-9","5-10"], ...
    {t("test_audit_round3_fixes.m")}, ...
    "test_audit_round3_fixes", "cck-mfb", "cck", [], "OPEN", ...
    {}, {}, {}, {});
a(end + 1) = def("ch5-soft-cck", ["5-60","5-61","5-71"], ...
    {t("test_book_conventions.m")}, ...
    "test_book_conventions", "cck-fde", "cck", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, {}, {});
a(end + 1) = def("ch5-bidfe-tr", ["5-46","5-47","5-57"], ...
    {t("test_audit_round3_fixes.m")}, ...
    "test_audit_round3_fixes", "cck-bidfe", "cck", [], "OPEN", ...
    {}, {}, {}, {});
a(end + 1) = def("ch6-csk", ["6-5","6-6","6-15"], ...
    {t("test_book_formulas_ch6.m")}, ...
    "test_book_formulas_ch6", "csk-matched-filter", "csk", [], "OPEN", ...
    {"test_book_formulas_ch6/testEq64_65ShiftOrthogonality"}, ...
    {"test_book_formulas_ch6/testEq67CorrelationDetector"}, ...
    {}, {"test_book_formulas_ch6/testEq610_612ShiftEstimate"});
a(end + 1) = def("ch6-ese-idma", ["6-21","6-22","6-23","6-64","6-65"], ...
    {t("test_book_formulas_ch6.m")}, ...
    "test_book_formulas_ch6", "csk-ese", "csk", ...
    ["6-26..6-37 scan missing"], "OPEN", ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {}, {});

for k = 1:numel(a)
    a(k).formulaClass = derive_formula_class(a(k).equations, statusMap);
end
end

function a = def(id, equations, formulaFiles, oracleNames, ...
    moduleId, scenario, paramsUnrecoverable, figureStatus, ...
    variableTests, normalizationTests, initialTests, iterationTests)
a.id = id;
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

function g = trace_coverage(a, statusMap)
% Gate 1: every claimed equation must be registered with an admissible
% formula status (BOOK-EXACT or ALG-EQUIV).  OCR-UNCERTAIN, SCAN-MISSING,
% EXECUTABLE-UNIMPLEMENTED and ENGINEERING rows all fail the gate.
g = "OPEN";
for eq = a.equations
    if contains(eq, "..")
        parts = split(eq, "..");
        ids = book_acceptance.parse_equation_ids( ...
            "(" + parts(1) + "~" + parts(2) + ")");
    else
        ids = book_acceptance.parse_equation_ids("(" + eq + ")");
    end
    for id = ids
        if ~isKey(statusMap, char(id))
            return;
        end
        fs = statusMap(char(id)).FormulaStatus;
        if ~(strcmp(fs, "BOOK-EXACT") || strcmp(fs, "ALG-EQUIV"))
            return;
        end
    end
end
g = "PASS";
end

function g = run_evidence(tests, papersDir)
% Evidence-backed gates 2-5, bound to SPECIFIC test cases
% ("file/testName").  Missing evidence stays CURATED-PASS; a failing
% test case is FAIL.
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
        if isempty(r)
            g = "OPEN";
        elseif any([r.Failed])
            g = "FAIL";
        elseif any([r.Incomplete])
            g = "OPEN";
        else
            g = "PASS";
        end
        if g ~= "PASS"
            return;
        end
    end
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
    if isempty(r)
        g = "OPEN";
    elseif any([r.Failed])
        g = "FAIL";
    elseif any([r.Incomplete])
        g = "OPEN";
    else
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function g = run_production_smoke(a)
% A production correctness exception is FAIL (evidence exists and fails);
% only the absent C harness is OPEN.
try
    result = run_unified_equalizer(struct("equalizers", a.moduleId, ...
        "scenario", a.scenario, "frameCount", 1, "snrDb", 18, ...
        "symbols", 8, "makePlot", false, "randomSeed", 42));
    if isfield(result, "ber") && all(isfinite(result.ber))
        g = "PASS";
    else
        g = "FAIL";
    end
catch
    g = "FAIL";
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
        g = "FAIL";
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
        else
            g = "FAIL";
        end
    elseif all(isfinite(result.ber))
        g = "PASS";
    else
        g = "FAIL";
    end
catch
    g = "FAIL";
end
end

function [g, detail] = scan_hidden_engineering(a, papersDir)
% Gate 12: dependency-closure scan; forbidden hits are FAIL (evidence
% exists and the violation is explicit).
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
else
    g = "FAIL";
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
    if isempty(r)
        g = "OPEN";
    elseif any([r.Failed])
        g = "FAIL";
    elseif any([r.Incomplete])
        g = "OPEN";
    else
        g = "PASS";
    end
catch
    g = "OPEN";
end
end

function coverage = audit_global_formula_coverage(papersDir)
% Global executable-formula coverage: parse EVERY trace row with the
% single parser; count expanded equation IDs per FormulaStatus and
% ParameterStatus.  Hard gate: scan-missing, OCR-uncertain,
% executable-unimplemented and ENGINEERING must all be zero for
% "six-chapter complete".
coverage = struct("total", 0, "bookExact", 0, "algEquiv", 0, ...
    "scanMissing", 0, "ocrUncertain", 0, ...
    "engineering", 0, "theoryOnly", 0, "paramUnrecoverable", 0, ...
    "unknown", 0);
coverage.unimplemented = {};
try
    text = fileread(fullfile(fileparts(papersDir), "FORMULA_TRACEABILITY.md"));
catch
    return;
end
lines = string(splitlines(text));
for i = 1:numel(lines)
    line = lines(i);
    if ~contains(line, "|")
        continue;
    end
    cells = strtrim(split(line, "|"));
    cells(cells == "") = [];
    if numel(cells) < 4
        continue;
    end
    ids = book_acceptance.parse_equation_ids(cells(1));
    if isempty(ids)
        continue;
    end
    fs = cells(end - 1);
    ps = cells(end);
    n = numel(ids);
    coverage.total = coverage.total + n;
    if fs == "SCAN-MISSING"
        coverage.scanMissing = coverage.scanMissing + n;
    elseif fs == "THEORY-ONLY"
        coverage.theoryOnly = coverage.theoryOnly + n;
    elseif fs == "OCR-UNCERTAIN"
        coverage.ocrUncertain = coverage.ocrUncertain + n;
    elseif fs == "ENGINEERING"
        coverage.engineering = coverage.engineering + n;
    elseif fs == "EXECUTABLE-UNIMPLEMENTED"
        for id = ids
            coverage.unimplemented{end + 1} = "(" + id + ")"; %#ok<AGROW>
        end
    elseif fs == "BOOK-EXACT"
        coverage.bookExact = coverage.bookExact + n;
    elseif fs == "ALG-EQUIV"
        coverage.algEquiv = coverage.algEquiv + n;
    else
        coverage.unknown = coverage.unknown + n;
    end
    if ps == "PARAM-UNRECOVERABLE"
        coverage.paramUnrecoverable = coverage.paramUnrecoverable + n;
    end
end
end

function print_matrix(rows)
fprintf("\n=== ALGORITHM ACCEPTANCE (evidence-driven) ===\n");
fprintf("%-18s %-16s %-12s %-8s %-10s %s\n", "algorithm", ...
    "formulaClass", "matlab", "C", "figure", "overall");
for k = 1:numel(rows)
    fprintf("%-18s %-16s %-12s %-8s %-10s %s\n", rows(k).id, ...
        rows(k).formulaClass, rows(k).matlabStatus, rows(k).cStatus, ...
        rows(k).figureStatus, rows(k).overallStatus);
end
end

function summary = summarize(rows, matrix, coverage)
hard = sum(string({rows.matlabStatus}) == "PASS");
curated = sum(string({rows.matlabStatus}) == "OPEN-CURATED");
notEligible = sum(startsWith(string({rows.overallStatus}), "NOT-BOOK"));
allGates = vertcat(rows.gates);
nFailGates = sum(allGates(:) == "FAIL");
nFailAlgos = sum(arrayfun(@(r) any(r.gates == "FAIL"), rows));
verified = coverage.bookExact + coverage.algEquiv;
closureDenom = coverage.total - coverage.theoryOnly;
hardClosed = coverage.scanMissing == 0 && coverage.ocrUncertain == 0 && ...
    isempty(coverage.unimplemented) && coverage.engineering == 0;

fprintf("\n=== FORMULA COVERAGE ===\n");
fprintf("TOTAL EQUATION IDS:          %d\n", coverage.total);
fprintf("BOOK-EXACT:                  %d\n", coverage.bookExact);
fprintf("ALG-EQUIV:                   %d\n", coverage.algEquiv);
fprintf("VERIFIED FORMULAS:           %d\n", verified);
fprintf("SCAN-MISSING:                %d\n", coverage.scanMissing);
fprintf("OCR-UNCERTAIN:               %d\n", coverage.ocrUncertain);
fprintf("EXECUTABLE-UNIMPLEMENTED:    %d\n", numel(coverage.unimplemented));
fprintf("THEORY-ONLY:                 %d\n", coverage.theoryOnly);
fprintf("ENGINEERING (book path):     %d\n", coverage.engineering);
fprintf("PARAM-UNRECOVERABLE:         %d\n", coverage.paramUnrecoverable);
if ~isempty(coverage.unimplemented)
    names = string(coverage.unimplemented);
    for ui = 1:numel(names)
        fprintf("    unimplemented %s\n", names(ui));
    end
end
fprintf("EXECUTABLE FORMULA CLOSURE:  %d/%d (%.1f%%)\n", ...
    verified, closureDenom, 100 * verified / max(closureDenom, 1));
fprintf("HARD CLOSURE (scan=0, ocr=0, unimpl=0, eng=0): %d\n", hardClosed);

fprintf("\n=== ALGORITHM ACCEPTANCE SUMMARY ===\n");
fprintf("MATLAB HARD PASS:            %d/%d\n", hard, numel(rows));
fprintf("MATLAB CURATED/REVIEW PASS:  %d/%d\n", hard + curated, numel(rows));
fprintf("NOT-BOOK-ELIGIBLE:           %d\n", notEligible);
fprintf("FAILED GATES:                %d\n", nFailGates);
fprintf("FAILED ALGORITHMS:           %d\n", nFailAlgos);

summary = struct("algorithms", numel(rows), "matlabHard", hard, ...
    "matlabReview", hard + curated, "totalIds", coverage.total, ...
    "verifiedFormulas", verified, "hardClosed", hardClosed, ...
    "failedGates", nFailGates, "failedAlgorithms", nFailAlgos, ...
    "executableUnimplemented", coverage.unimplemented);
end
