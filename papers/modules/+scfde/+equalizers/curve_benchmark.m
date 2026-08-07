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
reference.ber = max(reference.ber, eps);
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

% -- log10(BER) RMSE over reference SNR points -------------------------
logSim = interp1(snrSim, log10(berSim).', refSnr, "linear", "extrap").';
logRef = log10(refBer);
valid = isfinite(logRef) & isfinite(logSim);
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
maxSnrDeviation = 0;
for method = 1:numMethods
    for r = 1:numel(refSnr)
        target = refBer(method, r);
        if ~isfinite(target)
            continue;
        end
        [~, nearest] = min(abs(berSim(method, :) - target));
        maxSnrDeviation = max(maxSnrDeviation, ...
            abs(snrSim(nearest) - refSnr(r)));
    end
end

% -- method ordering agreement ------------------------------------------
orderAgreement = nan;
if numMethods >= 2
    matches = 0;
    counted = 0;
    for r = 1:numel(refSnr)
        simOrder = rank_order(berSim(:, r));
        refOrder = rank_order(refBer(:, r));
        if all(isfinite(refBer(:, r)))
            matches = matches + sum(simOrder == refOrder);
            counted = counted + numMethods;
        end
    end
    if counted > 0
        orderAgreement = matches / counted;
    end
end

% -- per-method metrics and grade ---------------------------------------
perMethod.logRmse = nan(1, numMethods);
perMethod.grade = strings(1, numMethods);
for method = 1:numMethods
    methodValid = valid(method, :);
    if any(methodValid)
        perMethod.logRmse(method) = sqrt(mean(...
            (logSim(method, methodValid) - logRef(method, methodValid)).^2));
    end
    perMethod.grade(method) = grade_of(perMethod.logRmse(method));
end

benchmark.logRmse = logRmse;
benchmark.zoneRmse = zoneRmse;
benchmark.maxSnrDeviation = maxSnrDeviation;
benchmark.orderAgreement = orderAgreement;
benchmark.grade = grade_of(logRmse);
benchmark.perMethod = perMethod;
benchmark.methodNames = methodNames;
benchmark.reference = reference;
end

function order = rank_order(values)
order = zeros(size(values));
[~, sorted] = sort(values, "ascend");
order(sorted) = 1:numel(values);
end

function grade = grade_of(logRmse)
if isempty(logRmse) || isnan(logRmse)
    grade = "D";
elseif logRmse <= 0.15
    grade = "A";
elseif logRmse <= 0.30
    grade = "B";
else
    grade = "C";
end
end
