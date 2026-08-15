function tests = test_csk_ese_sic_eq_6_21_65
%TEST_CSK_ESE_SIC_EQ_6_21_65 Strict-formula tests for the CSK Soft-SIC
% and ESE paths (spec 6.2 / 6.3, book (6-21)~(6-37), (6-53), (6-64)/(6-65)).
%
% Independent oracles (no production helper reuse):
%   * ESE residual = r - sum_{other} p*dict and chip variance
%     = sigma_w^2 + sum_{other} (p*|dict|.^2 - |p*dict|.^2)  (6-22)/(6-24)/(6-25);
%   * hand-computed ESE LLR (6-53) on a unit-energy BPSK dictionary:
%     ln P(+)/P(-) = sum_j 4 Re{h_j* r_j}/Var_j (+ prior difference),
%     which is 2 * sum_j L_j with L_j = 2 Re{h_j*(r_j - E[zeta_j])}/Var[zeta_j];
%   * feedback statistics (6-64)/(6-65): E[x] = sum p*x and
%     Var[x] = E|x|^2 - |E[x]|^2 = 1 - |E[x]|^2 for unit-energy chips;
%   * soft SIC = serial users ordered by received power, posterior
%     soft-mean cancellation, posterior second-moment variance, NO
%     fixed damping (single-user degeneration + two-user oracle).
% Negative variants (RED against the previous production path): the old
% ch6_soft_sic_detect applied a fixed 0.45/0.55 damping and used the
% mean-codebook-energy approximation for the interference variance;
% both are forbidden by spec 6.2 and fail the two-user exact oracle.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
% Shared wrapper-level fixture (single-user CSK frame, 4 symbols,
% 8 dB chip-domain noise), built once so the wrapper tests can reuse
% the same deterministic frame for RNG-preservation assertions.
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
symbols = 4;
pair = scfde.equalizers.ch6_repeated_symbol_indices(4, symbols, 1);
idx = pair.indices(:, 1).';
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 1);
nv = 10^(-8 / 10);
rng(404, "twister");
received = complex(zeros(symbols, codeLength));
for s = 1:symbols
    received(s, :) = dicts{1}(idx(s), :) + ...
        sqrt(nv / 2) * (randn(1, codeLength) + 1j * randn(1, codeLength));
end
flat = reshape(received.', 1, []);
testCase.TestData.fixture.ch = struct("received", flat, ...
    "impulse", imp, "branches", [flat; flat]);
testCase.TestData.fixture.src = struct("data", ones(1, symbols * codeLength), ...
    "tx", flat, "training", ones(1, 32));
testCase.TestData.fixture.cfg = struct("noiseVariance", nv, ...
    "codeLength", codeLength, "cskOrder", 4, "conventionalUsers", 1, ...
    "idmaUsers", 1, "innerIterations", 3, "outerIterations", 2, ...
    "pair", pair, "snrDb", 8);
end

function testEseResidualMomentsMatchEq6_22_25(testCase)
% Hand oracle for (6-22)/(6-24)/(6-25): residual keeps the target's own
% signal and subtracts the other users' posterior soft means; the chip
% variance adds the other users' posterior second moment minus the
% squared mean.  Arbitrary small dictionaries (independent of the
% production codebook), single symbol, two users.
rng(101, "twister");
d1 = randn(2, 8) + 1j * randn(2, 8);
d2 = randn(2, 8) + 1j * randn(2, 8);
r = d1(1, :) + d2(2, :);
nv = 0.31;
observation = complex(zeros(1, 8, 2));
observation(1, :, 1) = r;
observation(1, :, 2) = r;
ctx = struct("observation", observation, "noiseVariances", [nv, nv], ...
    "dictionaries", {{d1, d2; d1, d2}});
p2 = [0.3, 0.7];
posterior = ones(1, 2, 2);
posterior(1, :, 2) = p2;
[res1, var1] = scfde.equalizers.ch6_ese_residual(1, 1, posterior, ctx);
meanWord2 = p2 * d2;
secondMoment2 = p2 * abs(d2).^2;
verifyEqual(testCase, res1, r - meanWord2, "AbsTol", 1e-12);
verifyEqual(testCase, var1, nv + secondMoment2 - abs(meanWord2).^2, ...
    "AbsTol", 1e-12);
% Symmetric check with user 2 as the target.
p1 = [0.6, 0.4];
posterior(1, :, 1) = p1;
posterior(1, :, 2) = ones(1, 2) / 2;
[res2, var2] = scfde.equalizers.ch6_ese_residual(1, 2, posterior, ctx);
meanWord1 = p1 * d1;
secondMoment1 = p1 * abs(d1).^2;
verifyEqual(testCase, res2, r - meanWord1, "AbsTol", 1e-12);
verifyEqual(testCase, var2, nv + secondMoment1 - abs(meanWord1).^2, ...
    "AbsTol", 1e-12);
end

function testEseHandComputedLlrEq6_53(testCase)
% Hand-computed (6-53) LLR chain on a single-user, single-path BPSK
% dictionary with unit per-chip energy: dict rows are +h and -h, so the
% production's codeword log-ratio must equal
%     sum_j 4 Re{h_j* r_j}/sigma^2 = 2 * sum_j L_j,  L_j = 2 Re{h_j* r_j}/sigma^2
% (E[zeta] = 0 under a uniform prior: E[r] = h*E[x] = 0).
theta = 2 * pi * (0:7) / 8;
h = exp(1j * theta);
d1 = h;
d2 = -h;
nv = 0.3;
r = h;
observation = complex(zeros(1, 8, 1));
observation(1, :, 1) = r;
ctx = struct("observation", observation, "noiseVariances", nv, ...
    "dictionaries", {{[d1; d2]}});
posterior = ones(1, 2, 1) / 2;
[residual, variance] = scfde.equalizers.ch6_ese_residual(1, 1, posterior, ctx);
verifyEqual(testCase, residual, r, "AbsTol", 1e-12);
verifyEqual(testCase, variance, nv * ones(1, 8), "AbsTol", 1e-12);
[~, ~, ~, post] = scfde.equalizers.ch6_soft_dictionary_detect( ...
    residual, ctx.dictionaries{1, 1}, variance, zeros(1, 2));
lnRatio = log(post(1) / post(2));
oracleLlr = sum(2 * real(conj(h) .* r) ./ nv);
verifyEqual(testCase, lnRatio, 2 * oracleLlr, "AbsTol", 1e-10);
% Prior add-back: codeword-level priors shift the log-ratio additively.
[~, ~, ~, postPrior] = scfde.equalizers.ch6_soft_dictionary_detect( ...
    residual, ctx.dictionaries{1, 1}, variance, [1.5, 0]);
verifyEqual(testCase, log(postPrior(1) / postPrior(2)), ...
    2 * oracleLlr + 1.5, "AbsTol", 1e-10);
end

function testFeedbackStatisticsEq6_64_65(testCase)
% (6-64) E[x] = sum p*x and (6-65) Var[x] = E|x|^2 - |E[x]|^2, which is
% 1 - |E[x]|^2 for unit per-chip energy.  Production:
% ch6_posterior_signal_estimate computes the soft mean; the variance
% identity is pinned against the hand computation.
theta = 2 * pi * (0:7) / 8;
h = exp(1j * theta);
dicts = {[h; -h]};
p = [0.8, 0.2];
posterior = ones(1, 2, 1);
posterior(1, :, 1) = p;
soft = scfde.equalizers.ch6_posterior_signal_estimate(posterior, dicts);
verifyEqual(testCase, reshape(soft(1, 1, :), 1, []), (p(1) - p(2)) * h, ...
    "AbsTol", 1e-12);
secondMoment = p * abs(dicts{1}).^2;
meanWord = p * dicts{1};
verifyEqual(testCase, secondMoment - abs(meanWord).^2, ...
    1 - abs(meanWord).^2, "AbsTol", 1e-12);
verifyEqual(testCase, secondMoment - abs(meanWord).^2, ...
    (p(1) - p(2))^2 * zeros(1, 8) + (1 - (p(1) - p(2))^2) * ones(1, 8), ...
    "AbsTol", 1e-12);
end

function testSoftSicSingleUserDegenerate(testCase)
% Single-user degeneration: no interference, so every iteration must
% reproduce the plain dictionary-domain soft detection and the user
% order is trivially [1].
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 1);
symbols = 3;
nv = 10^(-8 / 10);
rng(402, "twister");
received = complex(zeros(symbols, codeLength));
for s = 1:symbols
    received(s, :) = dicts{1}(randi(4), :) + ...
        sqrt(nv / 2) * (randn(1, codeLength) + 1j * randn(1, codeLength));
end
[hist, ~, order] = scfde.equalizers.ch6_soft_sic_detect( ...
    received, dicts, nv, 3, zeros(1, symbols, codeLength), []);
verifyEqual(testCase, order, 1);
for iteration = 2:3
    verifyEqual(testCase, hist(iteration, :, 1), hist(1, :, 1));
end
for s = 1:symbols
    distance = sum(abs(dicts{1} - received(s, :)).^2 ./ nv, 2);
    [~, expected] = min(distance);
    verifyEqual(testCase, hist(1, s, 1), expected);
end
end

function testSoftSicTwoUserSerialOrderOracleEq6_21_37(testCase)
% Two-user RED oracle: an inline serial SIC (users ordered by received
% power, posterior soft-mean cancellation, posterior second-moment
% variance, inline softmax) must reproduce the production
% decisionHistory EXACTLY over two iterations.  The old production
% (0.45/0.55 fixed damping + mean-energy variance) fails this oracle.
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 2);
energies = zeros(1, 2);
for user = 1:2
    energies(user) = mean(abs(dicts{user}(:)).^2);
end
[~, piOrder] = sort(energies, "descend");
symbols = 3;
nv = 10^(-8 / 10);
rng(403, "twister");
received = complex(zeros(symbols, codeLength));
for s = 1:symbols
    received(s, :) = dicts{1}(randi(4), :) + dicts{2}(randi(4), :) + ...
        sqrt(nv / 2) * (randn(1, codeLength) + 1j * randn(1, codeLength));
end
[hist, ~, order] = scfde.equalizers.ch6_soft_sic_detect( ...
    received, dicts, nv, 2, zeros(2, symbols, codeLength), []);
verifyEqual(testCase, order, piOrder, ...
    "user order must follow descending received power");
% Inline serial-SIC oracle (independent of the production core).
softO = complex(zeros(2, symbols, codeLength));
postO = ones(symbols, 4, 2) / 4;
histO = zeros(2, symbols, 2);
for iteration = 1:2
    upd = softO;
    updP = postO;
    for s = 1:symbols
        for pos = 1:2
            user = piOrder(pos);
            interference = complex(zeros(1, codeLength));
            variance = nv * ones(1, codeLength);
            for srcPos = 1:2
                source = piOrder(srcPos);
                if source == user
                    continue;
                end
                p = reshape(updP(s, :, source), 1, []);
                meanWord = p * dicts{source};
                secondMoment = p * abs(dicts{source}).^2;
                interference = interference + meanWord;
                variance = variance + max(0, secondMoment - abs(meanWord).^2);
            end
            residual = received(s, :) - interference;
            distance = sum(abs(dicts{user} - residual).^2 ./ variance, 2);
            metric = -distance;
            metric = metric - max(metric);
            post = exp(metric);
            post = post / sum(post);
            [~, decision] = max(post);
            histO(iteration, s, user) = decision;
            upd(user, s, :) = post.' * dicts{user};
            updP(s, :, user) = post;
        end
    end
    softO = upd;
    postO = updP;
end
verifyEqual(testCase, hist, histO, ...
    "serial SIC decisions must match the undamped spec oracle exactly");
end

function testWrapperSoftSicTraceContracts(testCase)
fixture = testCase.TestData.fixture;
before = rng;
recv = scfde.equalizers.csk_soft_sic(fixture.ch, fixture.src, fixture.cfg);
after = rng;
verifyEqual(testCase, after, before);
trace = recv.traces{1};
verifyTrue(testCase, isfield(trace, "history"));
verifyEqual(testCase, trace.damping, 1);
verifyEqual(testCase, trace.formulaStatus, "ALG-EQUIV");
verifyEqual(testCase, numel(trace.userOrder), 1);
% MATLAB's size() drops trailing singleton dimensions, so the
% (iterations, symbols, users) history is reported as [3, 4] for a
% single user; check each dimension explicitly.
verifyEqual(testCase, size(trace.history, 1), 3);
verifyEqual(testCase, size(trace.history, 2), 4);
verifyEqual(testCase, size(trace.history, 3), 1);
verifyEqual(testCase, numel(recv.outputs{1}), 4 * 63);
verifyEqual(testCase, recv.ids, "csk-soft-sic");
end

function testWrapperEseUndampedBookPath(testCase)
% The BOOK path must keep alpha = 1 even when cfg.eseDamping requests a
% smaller value (damping lives in csk_ese_damped only).
fixture = testCase.TestData.fixture;
fixture.cfg.eseDamping = 0.3;
before = rng;
recv = scfde.equalizers.csk_ese(fixture.ch, fixture.src, fixture.cfg);
after = rng;
verifyEqual(testCase, after, before);
trace = recv.traces{1};
verifyTrue(testCase, isfield(trace, "indices"));
verifyEqual(testCase, trace.damping, 1);
verifyEqual(testCase, numel(trace.indices), 4);
verifyTrue(testCase, all(trace.indices >= 1 & trace.indices <= 4));
verifyEqual(testCase, numel(recv.outputs{1}), 4 * 63);
verifyEqual(testCase, recv.ids, "csk-ese");
end

function testWrapperEseDampedKeepsEngineeringVariant(testCase)
fixture = testCase.TestData.fixture;
fixture.cfg.eseDamping = 0.3;
recv = scfde.equalizers.csk_ese_damped(fixture.ch, fixture.src, fixture.cfg);
verifyEqual(testCase, recv.traces{1}.damping, 0.3);
verifyEqual(testCase, recv.traces{1}.formulaStatus, "ENGINEERING");
verifyEqual(testCase, recv.ids, "csk-ese-damped");
end
