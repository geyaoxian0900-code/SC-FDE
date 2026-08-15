function [bits, curve, trace] = ch4_iterate_time_frequency_turbo(received, Y, ...
        channelMatrix, timeEqualizer, Hest, Hreference, noiseVariance, ...
        frame, cfg, bidirectional, adaptiveChannel) %#ok<INUSD>
%CH4_ITERATE_TIME_FREQUENCY_TURBO Time-frequency turbo equalization on the
% validated Chapter-4 frame contract (spec 4.4/4.5):
%   feedforward: single-channel HTF front end x_m = F^{-1}{C .* R} with
%     C = H*/(|H|^2+sigma^2) (the decision-equivalent (3-61) form);
%   feedback: time-domain soft feedback g^H x_bar_{n-1} with g taken
%     from the equivalent-channel TAIL taps (ALG-EQUIV tap design -
%     the book's exact g derivation is not itemized in the spec);
%   x_bar = E[x|L_D^e] from the decoder EXTRINSIC (training locked).
%   Bidirectional (spec 4.5): the reversed pass runs with INDEPENDENT
%   filter state on rev(received); its output is restored to the
%   original time order and merged with EQUAL weight
%       d_bar = (d_hat_F + d_hat_B^R) / 2   ((2-53) box).
%   The previous fixed 0.5 time/frequency mixing is REMOVED (spec 4.4
%   forbids fixed 0.5 mixing; CHANNELMATRIX/TIMEEQUALIZER are kept in
%   the signature for compatibility and ignored).  The optional per-bin
%   BLMS channel adaptation (adaptiveChannel) is an ENGINEERING
%   extension kept for blms-tf-turbo and recorded as such (spec 4.6
%   requires the strict block FBLMS kernel instead).
N = frame.frameLength;
feedbackTaps = min(cfg.feedbackTaps, N - 1);
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
feedforward = conj(Hest) ./ (abs(Hest).^2 + noiseVariance);
effForward = ifft(feedforward .* Hest);
[~, mainForward] = max(abs(effForward));
gForward = effForward(mainForward + 1:min(mainForward + feedbackTaps, N));
gForward = [gForward, zeros(1, feedbackTaps - numel(gForward))];
if bidirectional
    hImp = ifft(Hest);
    reverseH = fft([hImp(1), hImp(N:-1:2)]);
    feedforwardRev = conj(reverseH) ./ (abs(reverseH).^2 + noiseVariance);
    effRev = ifft(feedforwardRev .* reverseH);
    [~, mainRev] = max(abs(effRev));
    gRev = effRev(mainRev + 1:min(mainRev + feedbackTaps, N));
    gRev = [gRev, zeros(1, feedbackTaps - numel(gRev))];
    reverseReceived = [received(1), received(N:-1:2)];   % circular reversal
    reverseY = fft(reverseReceived);
end
for iteration = 1:cfg.iterations
    estimate = ifft(feedforward .* Y) - ...
        timeFeedback(softSymbols, gForward, N, feedbackTaps);
    if bidirectional
        reverseSoft = [softSymbols(1), softSymbols(N:-1:2)];
        reverseEstimate = ifft(feedforwardRev .* reverseY) - ...
            timeFeedback(reverseSoft, gRev, N, feedbackTaps);
        % (2-53)/(4.5): restore the original time order, then merge
        % with equal weight 1/2 (independent filter states per branch).
        estimate = 0.5 * estimate + ...
            0.5 * [reverseEstimate(1), reverseEstimate(N:-1:2)];
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, 1, "Log-MAP");
    if adaptiveChannel
        softSpectrum = fft(softSymbols);
        innovation = Y - Hest .* softSpectrum;
        Hest = Hest + cfg.blmsStep * conj(softSpectrum) .* innovation ./ ...
            (abs(softSpectrum).^2 + noiseVariance * N);
    end
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, scfde.equalizers.ch4_channel_nmse(Hest, Hreference));
    trace.softEstimates(iteration, :) = estimate;
end
trace.finalChannel = Hest;
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("iterations", cfg.iterations, ...
    "feedbackTaps", feedbackTaps, "noiseVariance", noiseVariance, ...
    "frameLength", N, "bidirectional", logical(bidirectional), ...
    "adaptiveChannel", logical(adaptiveChannel));
if bidirectional
    trace.formulaMode = "book";
    trace.formulaStatus = "BOOK-EXACT-STRUCTURE";
    trace.formulaNote = "(2-50)~(2-53)/(4-42)~(4-49): forward and time-reversed TF passes with independent states, rev restoration and equal-weight 1/2 merge; no fixed 0.5 time/frequency mixing; feedback tap design ALG-EQUIV";
elseif adaptiveChannel
    trace.formulaMode = "engineering";
    trace.formulaStatus = "ENGINEERING";
    trace.formulaNote = "spec 4.6 requires the strict block FBLMS feedforward (4-64)~(4-73); the per-bin BLMS channel adaptation kept here is an ENGINEERING extension (recorded); soft feedback = decoder extrinsic mean";
else
    trace.formulaMode = "book";
    trace.formulaStatus = "BOOK-EXACT-STRUCTURE";
    trace.formulaNote = "(3-61)/(4-43)~(4-49): HTF front end (single-channel degenerate) + time-domain soft feedback; no fixed 0.5 mixing (spec 4.4); feedback tap design ALG-EQUIV";
end
end

function feedback = timeFeedback(softSymbols, g, N, feedbackTaps)
% Causal time-domain soft feedback sum_t g_t x_bar_{n-t} with circular
% past (the Chapter-4 block is cyclic).
feedback = zeros(1, N);
for n = 1:N
    for t = 1:feedbackTaps
        idx = mod(n - t - 1, N) + 1;
        feedback(n) = feedback(n) + g(t) * softSymbols(idx);
    end
end
end
