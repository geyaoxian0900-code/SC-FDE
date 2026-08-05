function results = simulate_chapter6_formula_complete(options)
%SIMULATE_CHAPTER6_FORMULA_COMPLETE Run the Chapter 6 paper-parameter suite.
%   The default profile follows the Chapter 6 model: PN/m-sequence CSK,
%   a 256-chip spreading block, CSK-CDMA, and PTR-ESE CSK-IDMA iterations.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.run_chapter6_spread_spectrum_suite"))
    addpath(moduleDir);
end

defaults.snrDb = -2:2:6;
defaults.frameCount = 500;
defaults.symbolsPerFrame = 40;
defaults.codeLength = 256;
defaults.modulationOrders = [2, 4, 8, 16];
defaults.cskOrder = 32;
defaults.conventionalUsers = 4;
defaults.multiUserCounts = [2, 4, 6];
defaults.idmaUsers = 8;
defaults.idmaUserCounts = [8, 12, 16];
defaults.comparisonUserCounts = [8, 10];
defaults.innerIterations = 3;
defaults.outerIterations = 3;
defaults.diagnosticSnrDb = 2;
defaults.cskRootFamily = "m-sequence";
defaults.enablePtr = true;
defaults.eseDamping = 0.58;
defaults.sequenceLength = 63;
defaults.sequenceCodeCount = 8;
defaults.sequenceUsers = 4;
defaults.sequenceFrameCount = 8;
defaults.sequenceSymbolsPerFrame = 64;
defaults.groups = "all";
defaults.receiverChain = "paper-full-idma";
defaults.makePlot = true;
defaults.exportData = true;
defaults.outputDir = fullfile(papersDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
if strcmpi(string(cfg.receiverChain), "paper-full-idma")
    results = scfde.run_chapter6_paper_full_chain(cfg, papersDir);
elseif strcmpi(string(cfg.receiverChain), "legacy-suite")
    results = scfde.run_chapter6_spread_spectrum_suite(cfg, papersDir);
else
    error("SCFDE:UnknownChapter6Receiver", ...
        "receiverChain must be paper-full-idma or legacy-suite.");
end
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
