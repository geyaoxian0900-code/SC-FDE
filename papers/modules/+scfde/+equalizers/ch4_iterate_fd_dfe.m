function [bits, curve, trace] = ch4_iterate_fd_dfe(Y, H, ...
        noiseVariance, frame, cfg)
%CH4_ITERATE_FD_DFE Strict frequency-domain DFE on the validated
% Chapter-4 frame contract (book (4-55)~(4-58), recovered from
% book/P90.png, 2026-08-17):
%   iteration 1: previous = 0 (zero feedback), rho = 0 (4-55 with no
%     prior decisions);
%   iterations >= 2: previous = hard BPSK decisions of the previous
%     estimate; rho = mean(|previous|^2) (4-55);
%   [W, B, lambda] = ch4_fd_dfe_weights(H, rho, noiseVariance);
%   estimate = ifft(W .* Y - B .* fft(previous));
%   equalizer LLR = 2*real(estimate)/noiseVariance.
% The BCJR sees only the coded-data LLRs and returns exactly 512
% information bits (ch4_decoder_feedback_frame).  No empirical damping
% or true-channel assistance enters the BOOK path.
N = frame.frameLength;
previous = zeros(1, N);
rho = 0;                                   % no prior decisions (4-55)
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, H);
trace.rhoHistory = zeros(1, cfg.iterations);
trace.lambdaHistory = zeros(1, cfg.iterations);
for iteration = 1:cfg.iterations
    [feedforward, feedback, lambda] = ...
        scfde.equalizers.ch4_fd_dfe_weights(H, rho, noiseVariance);
    trace.rhoHistory(iteration) = rho;
    trace.lambdaHistory(iteration) = lambda;
    estimate = ifft(feedforward .* Y - feedback .* fft(previous));
    hardDecision = scfde.equalizers.ch4_hard_bpsk(estimate);
    previous = hardDecision;
    rho = mean(abs(previous).^2);          % (4-55)
    trace.softEstimates(iteration, :) = estimate;
    trace.frequencyWeights(iteration, :) = feedforward;
end
equalizerLlr = 2 * real(estimate) / noiseVariance;
previousSoft = zeros(1, N);
previousSoft(frame.trainingIndices) = frame.trainingSymbols;
[bits, decoderLlr, softFrame] = ...
    scfde.equalizers.ch4_decoder_feedback_frame( ...
        equalizerLlr, frame, previousSoft, 1, cfg.baselineDecoder);
curve(:) = mean(bits ~= frame.informationBits);
for iteration = 1:cfg.iterations
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softFrame, []);
end
trace.finalChannel = H;
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.sourcePages = "book/P90.png";
trace.sourceEquations = "(4-55)~(4-58)";
trace.effectiveParameters = struct("iterations", cfg.iterations, ...
    "decoderMode", string(cfg.baselineDecoder), ...
    "noiseVariance", noiseVariance, "frameLength", N);
trace.formulaNote = "(4-55)~(4-58) strict FD-DFE (book/P90.png): rho=mean(|previous|^2), D_k=sigma^2+(1-rho)|h_k|^2, lambda per (4-58) (imposes sum_k b_k=0 algebraically, asserted not projected), b_k per (4-57), w_k per (4-56); hard-decision feedback, zero feedback on iteration 1";
end
