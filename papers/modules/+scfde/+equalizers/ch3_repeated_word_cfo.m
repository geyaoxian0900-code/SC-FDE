function estimatedCfo = ch3_repeated_word_cfo(received, period, sampleRate)
% (3-51): 閾绘牞鐖滈搹?= (1/P)鐠侯垶鍩?閸?r*(n)鐠虹棾(n+P)); (3-53): f閾忓儫d = 閾绘牞鐖滈搹?(2閿滈缚鐭綪鐠虹柖_s)
part1 = received(1:period);
part2 = received(period + (1:period));
phasePerPeriod = angle(sum(conj(part1) .* part2));
estimatedCfo = phasePerPeriod * sampleRate / (2 * pi * period);
end
