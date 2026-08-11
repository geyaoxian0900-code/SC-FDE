function domains = equalizer_output_domains()
%EQUALIZER_OUTPUT_DOMAINS Declared output semantics of all 37
% registered equalizers (review requirement: the plotted quantity and
% the BER source must be declared per method, so "draws A / BER counts
% B" cannot happen silently).
%
%   domains.id           - equalizer ID
%   domains.outputDomain - what receiver.outputs/estimates contain:
%       "soft-symbol"        QPSK symbol estimates (constellation)
%       "hard-symbol"        QPSK hard decisions
%       "information-bit"    decoder information decisions (Turbo)
%       "chip"               soft/hard chip estimates (CCK/CSK)
%       "codeword-index"     CCK codeword / CSK cyclic-shift indices
%       "correlation-metric" soft correlation values
%   domains.berSource    - what the unified scenario BER counts:
%       "decisions"        receiver.outputs (final hard decisions)
%       "indices"          trace.indices (codeword/shift indices)
%   domains.plotSource   - what the constellation plot draws:
%       "estimates"        receiver.estimates (soft)
%       "trace-soft"       trace.softEstimates (turbo complex output)
%       "hard-fallback"    outputs when the soft output is zero

registry = scfde.equalizer_registry();
ids = registry.id;
n = numel(ids);
outputDomain = strings(n, 1);
berSource = strings(n, 1);
plotSource = strings(n, 1);
for k = 1:n
    switch registry.scenario(k)
        case "qpsk"
            outputDomain(k) = "soft-symbol";
            berSource(k) = "decisions";
            plotSource(k) = "estimates";
        case "turbo"
            outputDomain(k) = "information-bit";
            berSource(k) = "decisions";
            plotSource(k) = "trace-soft";
        case "cck"
            outputDomain(k) = "codeword-index";
            berSource(k) = "indices";
            plotSource(k) = "estimates";
        case "csk"
            outputDomain(k) = "codeword-index";
            berSource(k) = "indices";
            plotSource(k) = "estimates";
    end
end
domains = struct("id", {ids}, "scenario", {registry.scenario}, ...
    "outputDomain", {outputDomain}, "berSource", {berSource}, ...
    "plotSource", {plotSource});
end
