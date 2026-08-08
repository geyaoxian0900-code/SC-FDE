% ESE damping sensitivity analysis (book chapter 6 does not specify the
% damping coefficient; it is an engineering parameter).
% Runs the Chapter-6 IDMA/ESE chain at several damping values and saves
% the per-damping BER results to a MAT file for reproducibility.
%
% Usage: run from papers/:  run('curve_reference/ese_damping_sensitivity.m')
cd(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile("..")));
dampingValues = [0, 0.3, 0.58, 0.8, 1.0];
results.damping = dampingValues;
results.outerBer = nan(size(dampingValues));
results.innerBer = nan(size(dampingValues));
results.totalBits = zeros(size(dampingValues));
for index = 1:numel(dampingValues)
    opts = struct("snrDb", 6, "frameCount", 1, ...
        "symbolsPerFrame", 32, "makePlot", false, ...
        "randomSeed", 7, "eseDamping", dampingValues(index));
    r = simulate_chapter6_formula_complete(opts);
    id = r.idma;
    results.outerBer(index) = min(id.outerBer);
    results.innerBer(index) = min(id.innerBer);
    results.totalBits(index) = id.totalBits;
    fprintf("damping=%.2f outerBer=%.6f innerBer=%.6f bits=%d\n", ...
        dampingValues(index), min(id.outerBer), min(id.innerBer), id.totalBits);
end
results.timestamp = datetime("now");
results.gitCommit = git_commit_short();
results.notes = "Book chapter 6 does not specify the ESE/PIC damping; " + ...
    "the default in simulate_chapter6_formula_complete is 0.58. " + ...
    "Damping 0 diverges (random BER), 0.3 partially converges, " + ...
    "0.8-1.0 give the best BER in this configuration.";
save(fullfile(pwd, "ese_damping_sensitivity.mat"), "results");
fprintf("Saved ese_damping_sensitivity.mat\n");

function commit = git_commit_short()
commit = "";
try
    [status, out] = system("git -C " + string(fileparts(pwd)) + ...
        " rev-parse --short HEAD 2>nul");
    if status == 0
        commit = strtrim(string(out));
    end
catch
    commit = "";
end
end
