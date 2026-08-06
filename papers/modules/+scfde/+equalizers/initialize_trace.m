function trace = initialize_trace(reference, weightCount)
%INITIALIZE_TRACE Shared trace structure for the equalizer package.
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.weightNorm = zeros(size(reference));
trace.coefficientHistory = zeros(weightCount, numel(reference));
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
end
