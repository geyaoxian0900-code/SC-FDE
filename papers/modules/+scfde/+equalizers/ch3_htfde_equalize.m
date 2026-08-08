function [symbols, trace] = ch3_htfde_equalize(received, H, ...
        noiseVariance, uw, cfg)
N = cfg.fftSize;
segmentLength = N / cfg.htfdeBranches;
symbols = ifft(scfde.equalizers.ch3_mmse_frequency_equalize(fft(received), H, noiseVariance));
h = ifft(H);
h(cfg.channelEstimateLength + 1:end) = 0;
trace.errorCurve = zeros(1, cfg.htfdeIterations);
trace.branchPhase = zeros(cfg.htfdeIterations, cfg.htfdeBranches);
trace.initialSymbols = symbols;
trace.symbolsByIteration = complex(zeros(cfg.htfdeIterations, N));

for iteration = 1:cfg.htfdeIterations
    decision = scfde.equalizers.ch3_qpsk_map(scfde.equalizers.ch3_qpsk_demap(symbols));
    decision(cfg.dataSymbols + 1:end) = uw;
    % Reliability weighting of the feedback cancellation.  The book's
    % scanned pages do not specify the reliability formula; the
    % posterior-mean reliability is an engineering choice and is
    % selectable via cfg.htfdeReliabilityMode:
    %   "posterior" (default) - mean |E[x|soft]|^2 of the QPSK
    %                             posterior mean
    %   "none"                - reliability = 1 (full cancellation,
    %                             hard-decision HTF-DFE)
    %   function handle       - user-supplied reliability
    %                               reliability(symbols, noiseVariance)
    reliability = htfde_reliability(symbols(1:cfg.dataSymbols), ...
        noiseVariance, cfg);
    predicted = ifft(H .* fft(decision));
    phaseCorrected = complex(zeros(1, N));
    for branch = 1:cfg.htfdeBranches
        indices = (branch - 1) * segmentLength + (1:segmentLength);
        phase = angle(sum(received(indices) .* conj(predicted(indices))));
        trace.branchPhase(iteration, branch) = phase;
        phaseCorrected(indices) = received(indices) * exp(-1j * phase);
    end
    postcursor = scfde.equalizers.ch3_circular_postcursor(decision, h);
    timeEqualized = phaseCorrected - reliability * postcursor;
    effectiveImpulse = h;
    effectiveImpulse(2:end) = (1 - reliability) * effectiveImpulse(2:end);
    effectiveChannel = fft(effectiveImpulse);
    branchSpectrum = complex(zeros(1, N));
    for branch = 1:cfg.htfdeBranches
        indices = (branch - 1) * segmentLength + (1:segmentLength);
        branchSignal = complex(zeros(1, N));
        branchSignal(indices) = timeEqualized(indices);
        branchSpectrum = branchSpectrum + fft(branchSignal);
    end
    symbols = ifft(scfde.equalizers.ch3_mmse_frequency_equalize( ...
        branchSpectrum, effectiveChannel, noiseVariance));
    trace.symbolsByIteration(iteration, :) = symbols;
    trace.errorCurve(iteration) = mean(abs(symbols - decision).^2);
end
trace.effectiveChannel = effectiveChannel;
end

function reliability = htfde_reliability(symbols, noiseVariance, cfg)
mode = "posterior";
if isfield(cfg, "htfdeReliabilityMode")
    mode = cfg.htfdeReliabilityMode;
end
if isa(mode, "function_handle")
    reliability = mode(symbols, noiseVariance);
elseif strcmpi(mode, "none")
    reliability = 1;
else % "posterior" (default)
    reliability = scfde.equalizers.ch3_symbol_reliability( ...
        symbols, noiseVariance);
end
end
