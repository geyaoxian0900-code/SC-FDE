function channel = channel_two_branch_multipath(input, cfg)
%CHANNEL_TWO_BRANCH_MULTIPATH Simulate two related hydrophone branches.

baseChannel = cfg.pathGains(:).';
baseChannel = baseChannel / norm(baseChannel);
branches = zeros(2, numel(input));
branchImpulses = zeros(2, max(cfg.pathDelays) + 1);
branchDopplers = zeros(2, 1);
for branchIndex = 1:2
    branchChannel = baseChannel .* (1 + 0.10 * randn(size(baseChannel))) .* ...
        exp(1j * 0.25 * randn(size(baseChannel)));
    branchChannel = branchChannel / norm(branchChannel);
    branchDoppler = cfg.dopplerHz * (1 + 0.04 * randn);
    branchImpulses(branchIndex, cfg.pathDelays + 1) = branchChannel;
    branchDopplers(branchIndex) = branchDoppler;
    branches(branchIndex, :) = scfde.apply_multipath(input, branchChannel, ...
        cfg.pathDelays, branchDoppler, cfg.symbolRate);
end

combined = branches(1, :) + sqrt(0.55) * branches(2, :);
signalPower = mean(abs(combined).^2);
noisePower = signalPower / 10^(cfg.snrDb / 10);
combined = combined + sqrt(noisePower / 2) * ...
    (randn(size(combined)) + 1j * randn(size(combined)));
branches = branches + sqrt(noisePower / 2) * ...
    (randn(size(branches)) + 1j * randn(size(branches)));

channel.received = combined;
channel.branches = branches;
channel.impulse = branchImpulses(1, :) + sqrt(0.55) * branchImpulses(2, :);
channel.branchImpulses = branchImpulses;
channel.branchDopplers = branchDopplers;
end
