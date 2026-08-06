function [symbols, trace, H] = ch3_ibdfe_equalize(receivedData, ...
        receivedTraining, training, H, noiseVariance, uw, cfg, ...
        feedbackMode, updateChannel)
N = cfg.fftSize;
Y = fft(receivedData);
trainingSpectrum = fft(training);
trainingReceivedSpectrum = fft(receivedTraining);
feedbackSpectrum = complex(zeros(1, N));
reliability = 0;
trace.errorCurve = zeros(1, cfg.ibdfeIterations);
trace.reliability = zeros(1, cfg.ibdfeIterations);
trace.feedforward = complex(zeros(cfg.ibdfeIterations, N));
trace.feedback = complex(zeros(cfg.ibdfeIterations, N));
trace.normalization = complex(zeros(1, cfg.ibdfeIterations));
trace.feedbackMode = string(feedbackMode);
trace.updatesChannel = logical(updateChannel);

for iteration = 1:cfg.ibdfeIterations
    symbolVariance = max(1 - reliability, eps);
    A = conj(H) .* symbolVariance ./ ...
        max(abs(H).^2 .* symbolVariance + noiseVariance, eps);
    Gamma = mean(A .* H);
    feedforward = A ./ max(Gamma, eps);
    feedback = feedforward .* H - 1;
    trace.normalization(iteration) = mean(feedforward .* H);
    estimateSpectrum = feedforward .* Y - feedback .* feedbackSpectrum;
    symbols = ifft(estimateSpectrum);

    hardDecision = scfde.equalizers.ch3_qpsk_map(scfde.equalizers.ch3_qpsk_demap(symbols));
    if feedbackMode == "soft"
        feedbackMean = scfde.equalizers.ch3_qpsk_posterior_mean(symbols, noiseVariance);
        reliability = min(0.999, mean(abs( ...
            feedbackMean(1:cfg.dataSymbols)).^2));
    else
        feedbackMean = hardDecision;
        reliability = scfde.equalizers.ch3_symbol_reliability( ...
            symbols(1:cfg.dataSymbols), noiseVariance);
    end
    feedbackMean(cfg.dataSymbols + 1:end) = uw;
    feedbackSpectrum = fft(feedbackMean);

    if updateChannel
        regularization = cfg.channelRegularization * N * noiseVariance;
        numerator = conj(trainingSpectrum) .* trainingReceivedSpectrum + ...
            reliability * conj(feedbackSpectrum) .* Y;
        channelDenominator = abs(trainingSpectrum).^2 + ...
            reliability * abs(feedbackSpectrum).^2 + regularization;
        channelEstimate = numerator ./ channelDenominator;
        impulse = ifft(channelEstimate);
        impulse(cfg.channelEstimateLength + 1:end) = 0;
        H = fft(impulse);
    end

    hardDecision(cfg.dataSymbols + 1:end) = uw;
    trace.errorCurve(iteration) = mean(abs(symbols - hardDecision).^2);
    trace.reliability(iteration) = reliability;
    trace.feedforward(iteration, :) = feedforward;
    trace.feedback(iteration, :) = feedback;
end
assert(max(abs(trace.normalization - 1)) < 1e-10, ...
    "IBDFE feedforward coefficients violate the unit-gain constraint.");
end
