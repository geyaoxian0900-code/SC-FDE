function report = run_all_equalizers(options)
%RUN_ALL_EQUALIZERS Execute every registered equalizer ID in its
% declared scenario and return a 37-row audit table.
%   REPORT = RUN_ALL_EQUALIZERS(OPTIONS)
%
% OPTIONS:
%   frameCount - frames per ID (default 1)
%   snrDb      - SNR (default 18)
%   symbols    - data blocks for CCK/CSK (default 8)
%   randomSeed - RNG seed (default 42)
%
% Each ID runs in ISOLATION (one equalizer per run_unified_equalizer
% call), so a failing method cannot mask later methods; failures are
% recorded per row with status "ERROR" and the report still has 37
% rows.  REPORT.Properties.UserData carries gitCommit, matlabVersion,
% timestamp and the seed for auditable result artifacts.

if nargin < 1
    options = struct();
end
rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "modules"));
frameCount = field_default(options, "frameCount", 1);
snrDb = field_default(options, "snrDb", 18);
symbols = field_default(options, "symbols", 8);
randomSeed = field_default(options, "randomSeed", 42);
registry = scfde.equalizer_registry();
n = numel(registry.id);
rows = repmat(struct("id", "", "chapter", 0, "scenario", "", ...
    "status", "", "ber", NaN, "errorBits", NaN, "totalBits", NaN, ...
    "berLower95", NaN, "berUpper95", NaN, "durationSeconds", NaN, ...
    "message", ""), 1, n);
for k = 1:n
    timer = tic;
    rows(k).id = registry.id(k);
    rows(k).chapter = registry.chapter(k);
    rows(k).scenario = registry.scenario(k);
    try
        result = run_unified_equalizer(struct( ...
            "equalizers", registry.id(k), ...
            "scenario", registry.scenario(k), ...
            "frameCount", frameCount, "snrDb", snrDb, ...
            "symbols", symbols, "makePlot", false, ...
            "randomSeed", randomSeed));
        rows(k).status = "PASS";
        rows(k).ber = result.ber(1);
        rows(k).errorBits = result.errorBits(1);
        rows(k).totalBits = result.totalBits(1);
        rows(k).berLower95 = result.berLower95(1);
        rows(k).berUpper95 = result.berUpper95(1);
    catch exception
        rows(k).status = "ERROR";
        rows(k).message = string(getReport(exception, ...
            "extended", "hyperlinks", "off"));
    end
    rows(k).durationSeconds = toc(timer);
end
report = struct2table(rows);
report.Properties.UserData = struct("gitCommit", git_commit_short(), ...
    "matlabVersion", version, "timestamp", datetime("now"), ...
    "randomSeed", randomSeed);
end

function value = field_default(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function commit = git_commit_short()
commit = "";
try
    repoDir = string(fileparts(fileparts(mfilename("fullpath"))));
    [status, out] = system("git -C """ + repoDir + ...
        """ rev-parse --short HEAD 2>nul");
    if status == 0
        commit = strtrim(string(out));
    end
catch
    commit = "";
end
end
