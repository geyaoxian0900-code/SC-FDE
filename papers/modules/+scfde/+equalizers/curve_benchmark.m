function benchmark = curve_benchmark(berSim, snrSim, reference, methodNames)
%CURVE_BENCHMARK Quantitative comparison of simulated BER curves against
% a digitized reference (book figures).
%   BENCHMARK = CURVE_BENCHMARK(BERSIM, SNRSIM, REFERENCE, METHODNAMES)
%
% BERSIM    - M x S matrix of simulated BER (rows: methods, cols: SNR).
% SNRSIM    - 1 x S SNR grid of the simulation.
% REFERENCE - struct with fields snrDb (1 x R) and ber (M x R) from the
%             digitized book figure; ber may contain NaN where the
%             reference has no data point.
% METHODNAMES - 1 x M strings for reporting.
%
% Returns
%   benchmark.logRmse          - log10(BER) RMSE over reference SNRs
%   benchmark.zoneRmse         - log-BER RMSE in low/mid/high SNR thirds
%   benchmark.maxSnrDeviation  - max horizontal SNR offset at equal BER
%   benchmark.orderAgreement   - fraction of SNRs where the method
%                                ordering matches the reference
%   benchmark.grade            - A/B/C/D per the acceptance table
%   benchmark.perMethod        - per-method logRmse / grade
arguments
    berSim (:, :) double
    snrSim (1, :) double
    reference struct
    methodNames (1, :) string = []
end
berSim = max(berSim, eps);
% NaN in reference.ber marks missing data points and MUST be preserved
% (max(x, eps) would silently turn NaN into eps, fabricating a
% near-zero reference).  Only finite non-positive values are clipped.
finiteRef = isfinite(reference.ber);
reference.ber(finiteRef) = max(reference.ber(finiteRef), eps);
if isvector(berSim) && size(berSim, 1) == 1
    berSim = berSim(:).'; % keep 1 x S for a single method
end
[numMethods, ~] = size(berSim);
if isempty(methodNames)
    methodNames = "method" + (1:numMethods);
end
methodNames = reshape(string(methodNames), 1, []);

refSnr = reference.snrDb(:).';
refBer = reference.ber;
if size(refBer, 1) == 1 && numMethods > 1
    refBer = repmat(refBer, numMethods, 1);
end

% -- SNR coverage mask -------------------------------------------------
% A reference point is covered only if its SNR lies INSIDE the
% simulation SNR range (no extrapolation).  Only covered points may
% contribute to the RMSE, ordering and grade.  Points outside the range
% are excluded and flagged, and a too-low coverage downgrades the grade.
snrCoverage = refSnr >= min(snrSim) & refSnr <= max(snrSim);
snrCoverage = repmat(snrCoverage, numMethods, 1);
% Coverage fraction is relative to the number of FINITE reference
% points actually present (NaN = missing data point, not a BER of eps).
numRefPoints = sum(any(isfinite(refBer), 1));

% -- log10(BER) RMSE over covered reference SNR points ------------------
logSim = interp1(snrSim, log10(berSim).', refSnr, "linear").';
logSim = reshape(logSim, numMethods, numel(refSnr));
logRef = log10(refBer);
valid = isfinite(logRef) & isfinite(logSim) & snrCoverage;
logRmse = sqrt(mean((logSim(valid) - logRef(valid)).^2, "all"));

% -- zone RMSE (low / mid / high SNR thirds of the reference) ----------
zoneRmse = nan(1, 3);
for zone = 1:3
    zoneIdx = round((zone - 1) * numel(refSnr) / 3) + 1:...
        round(zone * numel(refSnr) / 3);
    zoneIdx = zoneIdx(zoneIdx <= numel(refSnr));
    zoneValid = valid(:, zoneIdx);
    if any(zoneValid, "all")
        zoneRmse(zone) = sqrt(mean(...
            (logSim(zoneValid) - logRef(zoneValid)).^2, "all"));
    end
end

% -- max horizontal SNR deviation at equal BER --------------------------
% Invert the monotonized log10(BER) simulation curve: for each reference
% point, find the simulation SNR whose log-BER equals the reference
% log-BER, then take the SNR difference.  horizontalCoverage additionally
% requires the target BER to lie inside the invertible curve span.
maxSnrDeviation = 0;
horizontalCoverage = snrCoverage;
for method = 1:numMethods
    simLog = log10(max(berSim(method, :), eps));
    [monoSnr, monoLog, ~] = monotonize(snrSim, simLog);
    % Remove duplicate log-BER values so the inverse interpolation is
    % well defined (keep the first / lowest-SNR occurrence).
    [monoLog, keepIndex] = unique(monoLog, "stable");
    monoSnr = monoSnr(keepIndex);
    for r = 1:numel(refSnr)
        target = refBer(method, r);
        if ~isfinite(target)
            horizontalCoverage(method, r) = false;
            continue;
        end
        targetLog = log10(target);
        % Only invert inside the monotonic span of the simulation.
        if targetLog < min(monoLog) || targetLog > max(monoLog)
            horizontalCoverage(method, r) = false;
            continue;
        end
        simSnrAtRef = interp1(monoLog, monoSnr, targetLog, "linear");
        maxSnrDeviation = max(maxSnrDeviation, ...
            abs(simSnrAtRef - refSnr(r)));
    end
end

% -- method ordering agreement ------------------------------------------
% Only covered reference SNRs participate (no extrapolation).
orderAgreement = nan;
if numMethods >= 2
    matches = 0;
    counted = 0;
    for r = 1:numel(refSnr)
        if ~all(isfinite(refBer(:, r))) || ~snrCoverage(1, r)
            continue;
        end
        simOrder = rank_order(logSim(:, r));
        refOrder = rank_order(refBer(:, r));
        matches = matches + sum(simOrder == refOrder);
        counted = counted + numMethods;
    end
    if counted > 0
        orderAgreement = matches / counted;
    end
end

% -- per-method metrics and grade ---------------------------------------
% Coverage fraction = covered points / finite reference points (a
% low fraction means insufficient evidence; NaN reference points do
% not count against coverage).
coverageFraction = sum(valid, 2) / max(numRefPoints, 1);
perMethod.logRmse = nan(1, numMethods);
perMethod.grade = strings(1, numMethods);
for method = 1:numMethods
    methodValid = valid(method, :);
    if any(methodValid)
        perMethod.logRmse(method) = sqrt(mean(...
            (logSim(method, methodValid) - logRef(method, methodValid)).^2));
    end
    perMethod.grade(method) = grade_of(perMethod.logRmse(method), ...
        coverageFraction(method));
end

benchmark.logRmse = logRmse;
benchmark.zoneRmse = zoneRmse;
benchmark.maxSnrDeviation = maxSnrDeviation;
benchmark.orderAgreement = orderAgreement;
benchmark.snrCoverage = snrCoverage;
benchmark.coverageFraction = coverageFraction;
benchmark.horizontalCoverage = horizontalCoverage;
benchmark.coverage = horizontalCoverage; % backwards-compatible alias
benchmark.grade = grade_of(logRmse, mean(coverageFraction));
benchmark.perMethod = perMethod;
benchmark.methodNames = methodNames;
benchmark.reference = reference;
end

function [monoSnr, monoLog, monoFlag] = monotonize(snr, logBer)
% Monotonize a log-BER curve: keep only the points where log-BER
% decreases (or stays) as SNR increases, so the curve is invertible.
% Returns the monotonic (snr, logBer) pairs and a flag per original
% point indicating whether it was kept.
monoSnr = [];
monoLog = [];
monoFlag = false(size(snr));
runningMin = inf;
for index = 1:numel(snr)
    if isfinite(logBer(index)) && logBer(index) <= runningMin + 1e-12
        monoSnr(end + 1) = snr(index); %#ok<AGROW>
        monoLog(end + 1) = logBer(index); %#ok<AGROW>
        monoFlag(index) = true;
        runningMin = logBer(index);
    end
end
end

function order = rank_order(values)
order = zeros(size(values));
[~, sorted] = sort(values, "ascend");
order(sorted) = 1:numel(values);
end

function grade = grade_of(logRmse, coverageFraction)
% Grade with the SNR coverage requirement: an A/B claim needs at least
% half of the reference SNR points covered; otherwise the evidence is
% insufficient and the grade is downgraded to D.
if nargin < 2 || isempty(coverageFraction)
    coverageFraction = 1;
end
if isempty(logRmse) || isnan(logRmse) || coverageFraction < 0.5
    grade = "D";
elseif logRmse <= 0.15
    grade = "A";
elseif logRmse <= 0.30
    grade = "B";
else
    grade = "C";
end
end
