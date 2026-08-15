% Regenerate the fdda-teq benchmark against book Fig. 4-31 under
% book-STRUCTURE / TREND conditions (uncoded QPSK, I_outer=3, 1024 data
% symbols/block, 256 training, Eb/N0 axis), using the true adaptive
% FDDA-TEQ implementation (feedforward W / feedback B updates).  This is
% NOT an experiment-identical reproduction: the book experiment channel
% is undisclosed and the run uses the project synthetic 3-tap channel,
% so only the curve structure/trend is graded, never pointwise offsets.
%
% Zero-error points are censored with the Clopper-Pearson 95% upper
% bound (p_up = 1 - alpha^(1/n)) instead of machine eps, so the
% log-BER RMSE is not distorted.
%
% Usage: run from papers/:  run('curve_reference/ch4_fig431_fdda_teq_benchmark_run.m')
cd(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile("..")));
reference = load(fullfile(pwd, "ch4_fig431_fdda_teq.mat"));
reference = reference.reference;
snrGrid = reference.snrDb;          % book axis is Eb/N0 (uncoded QPSK)
framesPerSnr = 100;                 % 100 frames x 1024 syms x 2 bits
berSim = zeros(1, numel(snrGrid));
errBits = zeros(1, numel(snrGrid));
totBits = zeros(1, numel(snrGrid));
for s = 1:numel(snrGrid)
    berSim(s) = scfde.equalizers.ch4_fdda_teq_uncoded_qpsk( ...
        snrGrid(s), framesPerSnr, 1000 + s);
    errBits(s) = round(berSim(s) * framesPerSnr * 2048);
    totBits(s) = framesPerSnr * 2048;
    fprintf("Eb/N0=%2d dB  BER=%.4e  (%d/%d)\n", snrGrid(s), ...
        berSim(s), errBits(s), totBits(s));
end
% Censor zero-error points with the Clopper-Pearson 95% upper bound.
alpha = 0.05;
censored = berSim;
for s = 1:numel(snrGrid)
    if berSim(s) == 0
        censored(s) = 1 - alpha^(1 / totBits(s));
    end
end
% Full benchmark object (monotonicity, rank order, grade); the censored
% curve enters the log-BER RMSE so zero points are not distorted to eps.
benchmark = scfde.equalizers.curve_benchmark(censored, snrGrid, ...
    reference, reference.method);
fprintf("\n=== FDDA-TEQ uncoded QPSK vs book Fig 4-31 (book-structure/trend benchmark; project synthetic channel) ===\n");
fprintf("logRmse      = %.4f (censored, Clopper-Pearson 95%% upper)\n", ...
    benchmark.logRmse);
fprintf("maxSnrDev    = %.3f dB\n", benchmark.maxSnrDeviation);
fprintf("grade        = %s\n", benchmark.grade);
fprintf("zero points  = %d\n", sum(berSim == 0));
fprintf("\nEb/N0  sim           ref\n");
for s = 1:numel(snrGrid)
    fprintf("%3d  %.3e  %.3e\n", snrGrid(s), censored(s), ...
        reference.ber(s));
end
benchmark.censored = censored;
benchmark.censorMethod = "Clopper-Pearson 95% upper bound";
benchmark.framesPerSnr = framesPerSnr;
benchmark.bitsPerSnr = totBits(1);
benchmark.conditions = reference.parameters;
benchmark.gitCommit = git_commit_short();
benchmark.matlabVersion = version;
benchmark.timestamp = datetime("now");
benchmark.notes = "book-structure/trend benchmark (NOT experiment-identical): shared-kernel FDDA-TEQ with the book Eq. (4-82) scalar denominator (denomMode=equation, mu_f=0.2, mu_b=0.01, I_outer=3) on the project synthetic 3-tap channel; the absolute offsets and the high-SNR plateau are the mathematical consequence of the book's small step under the full spectral block energy, plus the undisclosed book channel realization; trend and ordering match, grade C";
save(fullfile(pwd, "ch4_fig431_fdda_teq_true_benchmark.mat"), ...
    "berSim", "censored", "errBits", "totBits", "benchmark", "reference");
fprintf("Saved ch4_fig431_fdda_teq_true_benchmark.mat (gitCommit=%s)\n", ...
    benchmark.gitCommit);

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
