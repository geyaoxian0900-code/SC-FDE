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
reference.snrDb = -5:1:10;
reference.ber = [
    8e-1, 6e-1, 4e-1, 2e-1, 8e-2, 3e-2, 1e-2, 4e-3, 1.5e-3, ...
    5e-4, 2e-4, 8e-5, 3e-5, 1e-5, 4e-6, 1.5e-6
];
reference.source = "book/27.png (Fig 4-31)";
reference.digitizer = "vision-assisted visual readout";
reference.date = datetime("now");
reference.notes = "No standalone BLMS BER curve in book chapter 4; " + ...
    "FDDA-TEQ is the frequency-domain adaptive family reference.";
save(fullfile(fileparts(mfilename("fullpath")), ...
    "ch4_fig431_fdda_teq.mat"), "reference");
fprintf("Saved ch4_fig431_fdda_teq.mat\n");
