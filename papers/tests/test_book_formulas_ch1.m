function tests = test_book_formulas_ch1
%TEST_BOOK_FORMULAS_CH1  Chapter-1 executable formula oracles.
%   eq.(1-1) sound speed, (1-2)/(1-3) propagation loss, (1-4) Thorp
%   absorption, (1-5) Doppler spread, (1-6)~(1-8) noise PSD, (1-11)
%   capacity index.  These are THEORY-ONLY in the receiver sense but are
%   implemented as executable oracles so the trace has no dead rows.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testEq11SoundSpeed(testCase)
% t=10, S=35, H=0 -> c = 1449.2 + 46 - 5.5 + 0.29 = 1489.99
c = scfde.book_formulas.ch1_sound_speed(10, 35, 0);
verifyEqual(testCase, c, 1489.99, "AbsTol", 1e-10);
% depth term: +0.016*H
c2 = scfde.book_formulas.ch1_sound_speed(10, 35, 100);
verifyEqual(testCase, c2 - c, 1.6, "AbsTol", 1e-10);
end

function testEq14Thorp(testCase)
% f=10 kHz: 0.11*100/101 + 44*100/4200 + 2.75e-4*100 + 0.003
a = scfde.book_formulas.ch1_thorp_absorption(10);
expected = 0.11 * 100 / 101 + 44 * 100 / 4200 + 2.75e-4 * 100 + 0.003;
verifyEqual(testCase, a, expected, "RelTol", 1e-12);
% f=1 kHz ~ 0.11*0.5 + 44/4101 + 0.000275 + 0.003 ~ 0.0659
a1 = scfde.book_formulas.ch1_thorp_absorption(1);
verifyGreaterThan(testCase, a1, 0.06);
verifyLessThan(testCase, a1, 0.08);
end

function testEq12_13PropagationLoss(testCase)
% l=1 km, f=10 kHz, k=2: TL = 2*10*lg(1000/1) + 1*a(10) = 60 + a(10)
a = scfde.book_formulas.ch1_thorp_absorption(10);
tl = scfde.book_formulas.ch1_propagation_loss(1, 10, 2);
verifyEqual(testCase, tl, 60 + a, "AbsTol", 1e-10);
% spherical vs cylindrical: k=2 gives +10*lg(1000/l) more than k=1
tl2 = scfde.book_formulas.ch1_propagation_loss(10, 10, 2);
tl1 = scfde.book_formulas.ch1_propagation_loss(10, 10, 1);
verifyEqual(testCase, tl2 - tl1, 20, "AbsTol", 1e-10);  % 10*lg(1000/10)=20
end

function testEq15DopplerSpread(testCase)
% v=1.5 m/s, f=10 kHz, c=1500 -> df = 10 Hz
df = scfde.book_formulas.ch1_doppler_spread(1.5, 10e3, 1500);
verifyEqual(testCase, df, 10, "AbsTol", 1e-10);
end

function testEq16_18NoisePsd(testCase)
[n, comps] = scfde.book_formulas.ch1_noise_psd([1, 10], 0.5, 5);
verifyEqual(testCase, size(comps), [4, 2]);
% Components sum to the total (linear domain)
verifyEqual(testCase, n, 10 * log10(sum(10 .^ (comps / 10), 1)), ...
    "AbsTol", 1e-10);
% Thermal component is -15 + 20 log10(f)
verifyEqual(testCase, comps(4, :), -15 + 20 * log10([1, 10]), ...
    "AbsTol", 1e-10);
end

function testEq111CapacityIndex(testCase)
I = scfde.book_formulas.ch1_capacity_index(40, 2);
verifyEqual(testCase, I, 80, "AbsTol", 1e-12);   % book 40 kbit/s*km example
end
