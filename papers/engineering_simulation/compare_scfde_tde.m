function comparison = compare_scfde_tde(inputText, options)
%COMPARE_SCFDE_TDE Compare frequency-domain and time-domain SC equalization.
%   The channel, random seed, frame format, LDPC, and Doppler settings are
%   kept identical. Set options.tdeTaps/tdeDelay to tune the FIR TDE.

if nargin < 1 || strlength(string(inputText)) == 0
    inputText = "SC equalizer comparison";
end
if nargin < 2
    options = struct();
end
options.makePlot = false;

frequencyOptions = options;
frequencyOptions.equalizerDomain = "frequency";
timeOptions = options;
timeOptions.equalizerDomain = "time";

comparison.frequency = run_text_scfde_demo(inputText, frequencyOptions);
comparison.time = run_text_scfde_demo(inputText, timeOptions);
comparison.frequencyValidFrames = sum([comparison.frequency.frames.valid]);
comparison.timeValidFrames = sum([comparison.time.frames.valid]);
comparison.frequencyBitErrors = sum([comparison.frequency.frames.bitErrors], "omitnan");
comparison.timeBitErrors = sum([comparison.time.frames.bitErrors], "omitnan");

fprintf("\n===== SC equalizer comparison =====\n");
fprintf("SC-FDE: %d/%d valid frames, bit errors=%g\n", ...
    comparison.frequencyValidFrames, numel(comparison.frequency.frames), ...
    comparison.frequencyBitErrors);
fprintf("Time-domain MMSE FIR: %d/%d valid frames, bit errors=%g\n", ...
    comparison.timeValidFrames, numel(comparison.time.frames), ...
    comparison.timeBitErrors);
end
