function [bits, curve, trace] = ch4_iterate_td_nlms_turbo(received, Y, ...
        Hinitial, Hreference, noiseVariance, frame, cfg)
%CH4_ITERATE_TD_NLMS_TURBO Time-domain direct-adaptive turbo equalization
% (spec 4.8, boxed LMS form - project combination, at most ALG-EQUIV):
%     z(n)     = w_f^H(n) r_n - w_b^H(n) x_bar_{n-1}
%     e(n)     = d_a(n) - z(n),   d_a = d (training) / E[x|L_D^e] (data)
%     w_f(n+1) = w_f(n) + mu_f r_n e*(n)
%     w_b(n+1) = w_b(n) - mu_b x_bar_{n-1} e*(n)
%   Initial weights are ZERO (spec 4.8: no true-channel initial
%   weights - the previous MMSE-from-true-channel initialization is
%   removed); the update is the boxed UNNORMALIZED LMS (the previous
%   NLMS normalization is removed).  softSymbols carries the training
%   symbols locked to d on the training positions, so d_a = softSymbols.
%   BCJR sees only the coded-data LLRs and returns exactly 512
%   information bits; the BOOK path is undamped.
N = frame.frameLength;
feedforwardTaps = min(cfg.tdAdaptiveTaps, N);
feedbackTaps = min(cfg.feedbackTaps, N - 1);
muF = cfg.tdNlmsStep;              % boxed mu_f (recorded)
muB = cfg.tdNlmsStep;              % boxed mu_b (recorded)
weightsF = complex(zeros(feedforwardTaps, 1));   % zero init (spec 4.8)
weightsB = complex(zeros(feedbackTaps, 1));
referenceWeights = scfde.equalizers.ch4_normalized_mmse(Hreference, noiseVariance);
softSymbols = scfde.equalizers.ch4_initial_soft_feedback(Y, Hinitial, ...
    noiseVariance, frame, cfg);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    residual = zeros(1, N);
    for sampleIndex = 1:N
        inputIndices = mod(sampleIndex - 1 - (0:feedforwardTaps - 1), N) + 1;
        inputVector = received(inputIndices).';
        feedbackVector = complex(zeros(feedbackTaps, 1));
        if sampleIndex > 1
            count = min(feedbackTaps, sampleIndex - 1);
            feedbackVector(1:count) = ...
                softSymbols(sampleIndex - 1:-1:sampleIndex - count).';
        end
        adaptiveOutput = weightsF' * inputVector - ...
            weightsB' * feedbackVector;
        residual(sampleIndex) = softSymbols(sampleIndex) - adaptiveOutput;
        weightsF = weightsF + muF * inputVector * conj(residual(sampleIndex));
        weightsB = weightsB - muB * feedbackVector * conj(residual(sampleIndex));
    end
    estimate = zeros(1, N);
    for sampleIndex = 1:N
        inputIndices = mod(sampleIndex - 1 - (0:feedforwardTaps - 1), N) + 1;
        inputVector = received(inputIndices).';
        feedbackVector = complex(zeros(feedbackTaps, 1));
        if sampleIndex > 1
            count = min(feedbackTaps, sampleIndex - 1);
            feedbackVector(1:count) = ...
                softSymbols(sampleIndex - 1:-1:sampleIndex - count).';
        end
        estimate(sampleIndex) = weightsF' * inputVector - ...
            weightsB' * feedbackVector;
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, 1, "Log-MAP");
    weightSpectrum = fft([weightsF.', zeros(1, N - feedforwardTaps)]);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.softEstimates(iteration, :) = estimate;
    trace.frequencyWeights(iteration, :) = weightSpectrum;
    trace.weightNmse(iteration) = scfde.equalizers.ch4_channel_nmse(weightSpectrum, referenceWeights);
    trace.errorPower(iteration) = mean(abs(residual).^2);
end
trace.finalChannel = fft([weightsF.', zeros(1, N - feedforwardTaps)]);
trace.formulaStatus = "ALG-EQUIV";
trace.formulaMode = "project-combination";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("muF", muF, "muB", muB, ...
    "feedforwardTaps", feedforwardTaps, "feedbackTaps", feedbackTaps, ...
    "iterations", cfg.iterations, "frameLength", N);
trace.formulaNote = "spec 4.8 boxed TD direct-adaptive DFE: LMS updates with mu_f/mu_b, d_a = d (training) / E[x|L_D^e] (data), ZERO initial weights (no true-channel init); project combination, at most ALG-EQUIV";
trace.stepParameters = struct("muF", muF, "muB", muB, ...
    "feedforwardTaps", feedforwardTaps, "feedbackTaps", feedbackTaps);
end
