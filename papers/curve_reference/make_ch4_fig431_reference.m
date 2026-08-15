% Book curve reference data: digitized from scanned pages.
% Chapter 4, Fig 4-31: FDDA-TEQ (I_outer=3) uncoded BER vs SNR.
% Source: book/27.png, digitized 2026-08 (visual estimate, log-BER grid).
% SNR axis -5..10 dB, BER axis 10^-5..10^0 (log).
% NOTE: the book chapter 4 does NOT contain a standalone BLMS/FDBNLMS BER
% curve; the frequency-domain adaptive family reference is this FDDA-TEQ
% curve (same algorithmic family as the block-frequency-domain adaptive
% equalizers).  BLMS formula/structure figures are 4-24/4-25.
reference.chapter = 4;
reference.figure = "4-31";
reference.method = "FDDA-TEQ";
reference.parameters = "I_outer=3 (uncoded), QPSK, 1024 info symbols per block, 256 training";
reference.modulation = "uncoded QPSK";
reference.channel = "undisclosed book experiment channel (synthetic 3-tap used in the benchmark run)";
reference.frameLength = 1024;          % data symbols per block (uncoded)
reference.iterationCount = 3;          % I_outer
reference.knownMismatch = "synthetic channel instead of the undisclosed book channel; absolute offsets and high-SNR plateau are expected";
reference.snrDb = -5:1:10;
reference.ber = [
    8e-1, 6e-1, 4e-1, 2e-1, 8e-2, 3e-2, 1e-2, 4e-3, 1.5e-3, ...
    5e-4, 2e-4, 8e-5, 3e-5, 1e-5, 4e-6, 1.5e-6
];
reference.source = "book/27.png (Fig 4-31)";
reference.digitizer = "vision-assisted visual readout";
reference.date = datetime("now");
reference.gitCommit = git_commit_short();
reference.matlabVersion = version;
reference.timestamp = datetime("now");
reference.notes = "No standalone BLMS BER curve in book chapter 4; " + ...
    "FDDA-TEQ is the frequency-domain adaptive family reference.";
save(fullfile(fileparts(mfilename("fullpath")), ...
    "ch4_fig431_fdda_teq.mat"), "reference");
fprintf("Saved ch4_fig431_fdda_teq.mat (gitCommit=%s)\n", ...
    reference.gitCommit);

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
