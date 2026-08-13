function summary = run_book_acceptance()
%RUN_BOOK_ACCEPTANCE  Final acceptance system (evidence-driven, frozen).
%   Single equation-ID parser (book_acceptance.parse_equation_ids) is
%   shared by g1, the global coverage audit and the formulaClass
%   derivation; every claimed equation spec is expanded through
%   expand_claimed_equations (no per-function ".." handling).
%   Gate states: PASS / CURATED-PASS / OPEN / PARAM / FAIL.
%   Overall PASS requires MATLAB PASS and C PASS and (figure PASS|PARAM).

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
    g(13) = run_evidence(a.oracleTests, papersDir);

    eligible = any(a.formulaClass == ...
        ["BOOK-EXACT", "ALG-EQUIV", "OPEN-OCR", "OPEN-SOURCE", ...
         "OPEN-SCAN", "OPEN-UNIMPLEMENTED"]);

    matlabRequired = [1:8, 10, 12, 13];
    matlabHard = all(g(matlabRequired) == "PASS");
    cHard = g(9) == "PASS";
    figureHard = any(g(11) == ["PASS", "PARAM"]);

    if any(g == "FAIL")
        overall = "FAIL";
    elseif ~eligible
        overall = "NOT-BOOK-ELIGIBLE";
    elseif ~matlabHard
        if any(g(matlabRequired) == "CURATED-PASS")
            overall = "OPEN-CURATED-EVIDENCE";
        else
            overall = "OPEN-MATLAB";
        end
    elseif ~cHard
        overall = "OPEN-C";
    elseif ~figureHard
        overall = "OPEN-FIGURE";
    else
        overall = "PASS";
    end

    if all(g(matlabRequired) == "PASS")
        matlabStatus = "PASS";
    elseif any(g(matlabRequired) == "FAIL")
        matlabStatus = "FAIL";
    elseif any(g(matlabRequired) == "CURATED-PASS")
        matlabStatus = "OPEN-CURATED";
    else
        matlabStatus = "OPEN";
    end

    rows(end + 1) = struct("id", a.id, "formulaClass", a.formulaClass, ...
        "matlabStatus", matlabStatus, "cStatus", g(9), ...
        "figureStatus", g(11), "overallStatus", overall, ...
        "gates", g, "scannedFiles", {scanDetail.scannedFiles}, ...
        "forbiddenHits", {scanDetail.forbiddenHits}); %#ok<AGROW>
end

coverage = audit_global_formula_coverage(papersDir);
print_matrix(rows);
summary = summarize(rows, matrix, coverage);
end

function ids = expand_claimed_equations(specs)
% Single expansion of every claimed equation spec (parser-native
% formats, e.g. "(3-42~3-46)"), deduplicated.
ids = strings(1, 0);
for spec = specs
    ids = [ids, book_acceptance.parse_equation_ids(spec)]; %#ok<AGROW>
end
ids = unique(ids, "stable");
end

function statusMap = build_status_map(papersDir)
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

function class_ = derive_formula_class(equations, statusMap)
% Lowest-class aggregation across the algorithm's claimed equation set.
statuses = strings(0);
for id = expand_claimed_equations(equations)
    if isKey(statusMap, char(id))
        statuses(end + 1) = statusMap(char(id)).FormulaStatus; %#ok<AGROW>
    else
        statuses(end + 1) = "TRANSCRIPTION-PENDING"; %#ok<AGROW>
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
elseif any(statuses == "TRANSCRIPTION-PENDING")
    class_ = "OPEN-TRANSCRIPTION";
elseif any(statuses == "OCR-UNCERTAIN")
    class_ = "OPEN-OCR";
elseif any(statuses == "SOURCE-INCONSISTENT")
    class_ = "OPEN-SOURCE";
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
    "oracleTests", {}, "moduleId", {}, "scenario", {}, ...
    "paramsUnrecoverable", {}, "figureStatus", {}, ...
    "variableTests", {}, "normalizationTests", {}, ...
    "initialTests", {}, "iterationTests", {});
t = @(f) fullfile(testsDir, f);

a(end + 1) = def("ch3-ibdfe", ...
    ["(3-64)","(3-65)","(3-82)","(3-84)","(3-85)","(3-87)"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_87.m")}, ...
    {"test_eq_3_65/testParsevalN4HandOracle", ...
     "test_eq_3_87/testGammaHandOracleN4"}, ...
    "sd-ibdfe", "qpsk", [], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom", ...
     "test_eq_3_65/testParsevalN4HandOracle"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch3-mmse-fde", ["(3-65)","(3-71)"], ...
    {t("test_eq_3_65.m"), t("test_eq_3_71.m")}, ...
    {"test_eq_3_65/testParsevalN4HandOracle", ...
     "test_eq_3_71/testLambdaBookEqualsProduction"}, ...
    "mmse-fde", "qpsk", [], "OPEN", ...
    {"test_eq_3_65/testParsevalN4HandOracle"}, ...
    {"test_eq_3_71/testLambdaBookEqualsProduction"}, {}, {});
a(end + 1) = def("ch3-htfde", ["(3-42~3-46)","(3-64)","(3-47~3-63)"], ...
    {t("test_eq_3_71.m")}, {"test_eq_3_71/testLambdaBookEqualsProduction"}, ...
    "htfde", "qpsk", [], "PARAM-UNRECOVERABLE", {}, {}, {}, {});
a(end + 1) = def("ch3-ice", ["(3-88)","(3-89)","(3-90)","(3-91)","(3-92)"], ...
    {t("test_eq_3_87.m")}, {"test_eq_3_87/testGammaHandOracleN4"}, ...
    "ice-sd-ibdfe", "qpsk", [], "OPEN", ...
    {"test_eq_3_87/testGammaHandOracleN4"}, ...
    {"test_eq_3_87/testUnitGainInvariantRandom"}, ...
    {}, {"test_eq_3_87/testProductionIbdFeTrace"});
a(end + 1) = def("ch2-dfe", ["(2-6)","(2-9)","(2-10)","(2-11)"], ...
    {t("test_book_formulas_ch2.m")}, ...
    {"test_book_formulas_ch2/testEq210_211WienerMse"}, ...
    "dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq210_211WienerMse"}, {}, {}, {});
a(end + 1) = def("ch2-lms-dfe", ["(2-12)","(2-13)","(2-14)","(2-15)"], ...
    {t("test_book_formulas_ch2.m")}, ...
    {"test_book_formulas_ch2/testEq212_214LmsUpdate"}, ...
    "lms-dfe", "qpsk", [], "OPEN", ...
    {"test_book_formulas_ch2/testEq213LmsGradient"}, {}, {}, ...
    {"test_book_formulas_ch2/testEq212_214LmsUpdate"});
a(end + 1) = def("ch2-dpll-dfe", ["(2-27)","(2-30)","(2-34)","(2-36)","(2-37)"], ...
    {t("test_eq_2_36.m")}, {"test_eq_2_36/testPhaseDetectorHandOracle"}, ...
    "dpll-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_36/testPhaseDetectorHandOracle"}, {}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"}, ...
    {"test_eq_2_36/testLoopConvergesToRotation"});
a(end + 1) = def("ch2-ptr-dfe", ["(2-47)","(2-48)","(2-49)"], ...
    {t("test_eq_2_47.m")}, {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    "ptr-dfe", "qpsk", [], "OPEN", ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testLinearPtrHandOracle"}, ...
    {"test_eq_2_47/testIdentityChannelAlignment"}, {});
a(end + 1) = def("ch4-bcjr", ["(4-16)","(4-18)","(4-19)","(4-20)","(4-21)","(4-22)"], ...
    {t("test_book_conventions.m")}, ...
    {"test_book_conventions/testLlrSignConvention"}, ...
    "td-turbo", "turbo", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, ...
    {}, {"test_eq_4_feedback/testAlphaOneFeedbackEqualsCandidate"});
a(end + 1) = def("ch4-convcode", ["(4-1)","(4-2)"], ...
    {t("test_eq_4_convcode.m")}, ...
    {"test_eq_4_convcode/test171133EncoderMatchesTrellis"}, ...
    "td-turbo", "turbo", [], "OPEN", ...
    {"test_eq_4_convcode/test171133EncoderMatchesTrellis"}, ...
    {"test_eq_4_convcode/testBookCodeRates"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"}, ...
    {"test_eq_4_convcode/test75TrellisMatchesEncoder"});
a(end + 1) = def("ch4-fblms", ["(4-64)","(4-65)","(4-66)","(4-67)","(4-68)","(4-69)"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    {"test_fblms_and_curve_benchmark/testFblmsMatchesLinearConvolutionNoiseless"}, ...
    "fblms", "turbo", [], "OPEN", ...
    {"test_fblms_and_curve_benchmark/testFblmsMatchesLinearConvolutionNoiseless"}, ...
    {}, ...
    {"test_fblms_and_curve_benchmark/testFblmsPartialTrainingBlockUsesReference"}, ...
    {"test_fblms_and_curve_benchmark/testFblmsQpskDecisionDirected"});
a(end + 1) = def("ch4-fdda-teq", ["(4-74)","(4-75)","(4-76)","(4-77~4-82)"], ...
    {t("test_fblms_and_curve_benchmark.m")}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    "fdda-teq", "turbo", ["gamma_f/gamma_b unrecovered"], ...
    "PARAM-UNRECOVERABLE", ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaWrapperDefaultDenominatorIsEquation"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"}, ...
    {"test_fblms_and_curve_benchmark/testFddaFeedbackAndOuterLoop"});
a(end + 1) = def("ch5-cck-codebook", ["(5-8)","(5-9)","(5-10)"], ...
    {t("test_audit_round3_fixes.m")}, ...
    {"test_audit_round3_fixes/testCckBitLevelBerCounting"}, ...
    "cck-mfb", "cck", [], "OPEN", {}, {}, {}, {});
a(end + 1) = def("ch5-soft-cck", ["(5-60)","(5-61)","(5-71)"], ...
    {t("test_book_conventions.m")}, ...
    {"test_book_conventions/testLlrSignConvention"}, ...
    "cck-fde", "cck", [], "OPEN", ...
    {}, {"test_book_conventions/testLlrSignConvention"}, {}, {});
a(end + 1) = def("ch5-bidfe-tr", ["(5-46)","(5-47)","(5-57)"], ...
    {t("test_audit_round3_fixes.m")}, ...
    {"test_audit_round3_fixes/testPtrEquivalentChannelHasNoCrossTerms"}, ...
    "cck-bidfe", "cck", [], "OPEN", {}, {}, {}, {});
a(end + 1) = def("ch6-csk", ["(6-5)","(6-6)","(6-15)"], ...
    {t("test_book_formulas_ch6.m")}, ...
    {"test_book_formulas_ch6/testEq64_65ShiftOrthogonality"}, ...
    "csk-matched-filter", "csk", [], "OPEN", ...
    {"test_book_formulas_ch6/testEq64_65ShiftOrthogonality"}, ...
    {"test_book_formulas_ch6/testEq69DemodCorrelation"}, ...
    {}, {"test_book_formulas_ch6/testEq610_612ShiftEstimate"});
a(end + 1) = def("ch6-ese-idma", ...
    ["(6-21)","(6-22)","(6-23)","(6-26~6-37)","(6-64)","(6-65)"], ...
    {t("test_book_formulas_ch6.m")}, ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    "csk-ese", "csk", [], "OPEN", ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {"test_book_formulas_ch6/testEq641_642Moments"}, ...
    {}, {});

for k = 1:numel(a)
    a(k).formulaClass = derive_formula_class(a(k).equations, statusMap);
end
end

function a = def(id, equations, formulaFiles, oracleTests, ...
    moduleId, scenario, paramsUnrecoverable, figureStatus, ...
    variableTests, normalizationTests, initialTests, iterationTests)
a.id = id;
a.equations = equations;
a.formulaFiles = formulaFiles;
a.oracleTests = oracleTests;
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
% formula status (BOOK-EXACT or ALG-EQUIV only).
g = "OPEN";
for id = expand_claimed_equations(a.equations)
    if ~isKey(statusMap, char(id))
        return;
    end
    fs = statusMap(char(id)).FormulaStatus;
    if ~(strcmp(fs, "BOOK-EXACT") || strcmp(fs, "ALG-EQUIV"))
        return;
    end
end
g = "PASS";
end

function g = run_evidence(tests, papersDir)
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
% Identity-channel regression: for turbo/cck/csk the unified entry runs
% the identity channel and the BER must be EXACTLY 0 (identity sanity,
% not a performance benchmark).  qpsk-scenario algorithms use the audit
% identity/AWGN sanity instead.
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
    if isfield(result, "ber") && all(isfinite(result.ber)) && ...
            all(result.ber == 0)
        g = "PASS";
    else
        g = "FAIL";
    end
catch
    g = "FAIL";
end
end

function [g, detail] = scan_hidden_engineering(a, papersDir)
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

function coverage = audit_global_formula_coverage(papersDir)
coverage = struct("total", 0, "bookExact", 0, "algEquiv", 0, ...
    "scanMissing", 0, "transcriptionPending", 0, ...
    "ocrUncertain", 0, "sourceInconsistent", 0, ...
    "engineering", 0, "theoryOnly", 0, "paramUnrecoverable", 0, ...
    "unknown", 0, "duplicateIds", 0, "invalidColumnRows", 0, ...
    "missingImplementationRefs", 0, "invalidImplementationRefs", 0, ...
    "missingTestRefs", 0, "invalidTestRefs", 0, "evidenceClosed", 0);
coverage.unimplemented = {};
seen = containers.Map("KeyType", "char", "ValueType", "logical");
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
    ids = book_acceptance.parse_equation_ids(cells(1));
    if isempty(ids)
        continue;
    end
    n = numel(ids);
    % hard 10-column schema: formula rows must have exactly 10 cells
    if numel(cells) ~= 10
        coverage.invalidColumnRows = coverage.invalidColumnRows + n;
        continue;
    end
    fs = cells(end - 1);
    ps = cells(end);
    prod = cells(5);
    oracle = cells(6);
    testRef = cells(8);
    coverage.total = coverage.total + n;
    if fs == "TRANSCRIPTION-PENDING"
        coverage.transcriptionPending = coverage.transcriptionPending + n;
    elseif fs == "THEORY-ONLY"
        coverage.theoryOnly = coverage.theoryOnly + n;
    elseif fs == "OCR-UNCERTAIN"
        coverage.ocrUncertain = coverage.ocrUncertain + n;
    elseif fs == "SOURCE-INCONSISTENT"
        coverage.sourceInconsistent = coverage.sourceInconsistent + n;
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
    % structure integrity: duplicate IDs; implementation and test
    % references for BOOK/ALG rows must exist
    if any(fs == ["BOOK-EXACT", "ALG-EQUIV"])
        implOk = false;
        if prod == "—" && oracle == "—"
            coverage.missingImplementationRefs = ...
                coverage.missingImplementationRefs + n;
        else
            for ref = [prod, oracle]
                if ref == "—"
                    continue;
                end
                st = check_ref_exists(ref, papersDir);
                if st == 0
                    coverage.invalidImplementationRefs = ...
                        coverage.invalidImplementationRefs + n;
                elseif st == 1
                    implOk = true;
                end
            end
        end
        testOk = false;
        if testRef == "—"
            coverage.missingTestRefs = coverage.missingTestRefs + n;
        elseif ~check_test_ref_exists(testRef, papersDir)
            fprintf("BADTEST %s test=%s\\n", cells(1), testRef);
            coverage.invalidTestRefs = coverage.invalidTestRefs + n;
        else
            testOk = true;
        end
        if implOk && testOk
            coverage.evidenceClosed = coverage.evidenceClosed + n;
        end
    end
    for id = ids
        if isKey(seen, char(id))
            coverage.duplicateIds = coverage.duplicateIds + 1;
        else
            seen(char(id)) = true;
        end
    end
end
coverage.traceStructureIntegrity = coverage.unknown == 0 && ...
    coverage.duplicateIds == 0 && coverage.invalidColumnRows == 0 && ...
    coverage.missingImplementationRefs == 0 && ...
    coverage.invalidImplementationRefs == 0 && ...
    coverage.missingTestRefs == 0 && coverage.invalidTestRefs == 0;
coverage.sourceIntegrity = coverage.sourceInconsistent == 0;
coverage.hardClosed = coverage.traceStructureIntegrity && ...
    coverage.sourceIntegrity && coverage.scanMissing == 0 && ...
    coverage.transcriptionPending == 0 && coverage.ocrUncertain == 0 && ...
    isempty(coverage.unimplemented) && coverage.engineering == 0;
end
function ok = check_test_ref_exists(ref, papersDir)
% Test reference: "file" or "file/testCase"; the file must exist in
% papers/tests and, when a test case is given, the function must exist.
ok = false;
try
    ref = string(ref);
    parts = split(ref, "/");
    if numel(parts) == 1
        file = parts(1);
        testCase = "";
    elseif numel(parts) == 2
        file = parts(1);
        testCase = parts(2);
    else
        return;
    end
    if ~endsWith(file, ".m")
        path = fullfile(papersDir, "tests", file + ".m");
    else
        path = fullfile(papersDir, "tests", file);
    end
    if ~isfile(path)
        return;
    end
    if testCase == ""
        ok = true;
        return;
    end
    text = fileread(path);
    pattern = "function\s+" + regexptranslate("escape", testCase) + "\s*\(";
    ok = ~isempty(regexp(text, pattern, "once"));
catch
    ok = false;
end
end

function st = check_ref_exists(ref, papersDir)
% 1 = valid implementation reference, 0 = invalid (name does not
% resolve), -1 = descriptive text / parameter reference (no function
% reference, counted as a missing implementation reference).
st = -1;
try
    r = char(ref);
    r = regexprep(r, '^`|`$', '');
    r = regexprep(r, '[（(].*$', '');
    r = strtrim(r);
    if isempty(r)
        return;
    end
    if strcmp(r, "BOOK_CONVENTIONS")
        st = 1;
        return;
    end
    if startsWith(r, "cfg.")
        st = -1;                       % parameter reference
        return;
    end
    if any(r < 128 == false) || any(r == '/')
        % Chinese descriptive text or a slash-separated multi-function
        % list: check each slash-separated token as a function name
        parts = strsplit(r, {'/', '、'});
        resolved = false;
        for pt = parts
            p = strtrim(pt{1});
            if isempty(p)
                continue;
            end
            if ~isempty(which(p)) || ...
                    isfile(fullfile(papersDir, "modules", "+scfde", ...
                    "+equalizers", p + ".m")) || ...
                    isfile(fullfile(papersDir, "modules", "+scfde", ...
                    "+book_formulas", p + ".m"))
                resolved = true;
                break;
            end
        end
        if resolved
            st = 1;
        else
            st = -1;                   % descriptive text
        end
        return;
    end
    if ~isempty(which(r))
        st = 1;
        return;
    end
    stem = r;
    if endsWith(stem, ".m")
        stem = extractBefore(stem, ".m");
    end
    cands = [fullfile(papersDir, "modules", "+scfde", "+equalizers", ...
        stem + ".m"), fullfile(papersDir, "modules", "+scfde", ...
        "+book_formulas", stem + ".m")];
    if isfile(cands(1)) || isfile(cands(2))
        st = 1;
        return;
    end
    if endsWith(r, ".m") || contains(r, "\") || contains(r, "/")
        st = 0;
    else
        st = -1;                       % field/descriptive reference
    end
catch
    st = 0;
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

fprintf("\n=== FORMULA COVERAGE ===\n");
fprintf("TOTAL EQUATION IDS:          %d\n", coverage.total);
fprintf("BOOK-EXACT:                  %d\n", coverage.bookExact);
fprintf("ALG-EQUIV:                   %d\n", coverage.algEquiv);
fprintf("FORMULA STATUS VERIFIED:     %d\n", verified);
fprintf("FORMULA EVIDENCE CLOSED:     %d\n", coverage.evidenceClosed);
fprintf("TRANSCRIPTION-PENDING:      %d\n", coverage.transcriptionPending);
fprintf("OCR-UNCERTAIN:               %d\n", coverage.ocrUncertain);
fprintf("SOURCE-INCONSISTENT:         %d\n", coverage.sourceInconsistent);
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
fprintf("TRACE STRUCTURE INTEGRITY (unknown=%d, dup=%d, colRows=%d, missingRef=%d, badRef=%d, missingTest=%d, badTest=%d): %d\n", ...
    coverage.unknown, coverage.duplicateIds, coverage.invalidColumnRows, ...
    coverage.missingImplementationRefs, coverage.invalidImplementationRefs, ...
    coverage.missingTestRefs, coverage.invalidTestRefs, ...
    coverage.traceStructureIntegrity);
fprintf("SOURCE INTEGRITY (source-inconsistent=%d): %d\n", ...
    coverage.sourceInconsistent, coverage.sourceIntegrity);
fprintf("EXECUTABLE FORMULA CLOSURE:  %d/%d (%.1f%%)\n", ...
    verified, closureDenom, 100 * verified / max(closureDenom, 1));
fprintf("HARD CLOSURE (structure+source+scan+ocr+unimpl+eng=0): %d\n", ...
    coverage.hardClosed);

fprintf("\n=== ALGORITHM ACCEPTANCE SUMMARY ===\n");
fprintf("MATLAB HARD PASS:            %d/%d\n", hard, numel(rows));
fprintf("MATLAB CURATED/REVIEW PASS:  %d/%d\n", hard + curated, numel(rows));
fprintf("NOT-BOOK-ELIGIBLE:           %d\n", notEligible);
fprintf("FAILED GATES:                %d\n", nFailGates);
fprintf("FAILED ALGORITHMS:           %d\n", nFailAlgos);

summary = struct("algorithms", numel(rows), "matlabHard", hard, ...
    "matlabReview", hard + curated, "totalIds", coverage.total, ...
    "verifiedFormulas", verified, "hardClosed", coverage.hardClosed, ...
    "traceStructureIntegrity", coverage.traceStructureIntegrity, ...
    "sourceIntegrity", coverage.sourceIntegrity, ...
    "evidenceClosed", coverage.evidenceClosed, ...
    "failedGates", nFailGates, "failedAlgorithms", nFailAlgos, ...
    "executableUnimplemented", coverage.unimplemented);
end
