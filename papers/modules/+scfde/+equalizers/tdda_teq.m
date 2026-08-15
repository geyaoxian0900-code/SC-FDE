function receiver = tdda_teq(channel, source, cfg)
%TDDA_TEQ Time-domain direct adaptive turbo equalizer module (book 4.5.2).
% The scenario owns the interleaver; the module returns exactly 512
% information-symbol decisions and never resets the global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
% No true-channel quantity enters the equalizer: spec 4.8 forbids
% true-channel initial weights, and the first round has NO data prior
% (no channel-assisted MMSE initialization).  Y/Hinitial/Hreference are
% all passed empty; the equalizer adapts from the training segment only.
[bits, ~, trace] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, [], [], [], cfg.noiseVariance, frame, cfg);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("TDDA-TEQ", "tdda-teq", ...
    decisions, zeros(size(decisions)), decisions, trace);
end
