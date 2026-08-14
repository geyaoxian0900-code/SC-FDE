function [subarrayOutputs, trace] = ch3_htfde_equalize(branches, ...
        branchImpulses, noiseVariance, cfg)
%CH3_HTFDE_EQUALIZE  Book (3-61)/(3-62): per-element frequency-domain
% MMSE joint equalization inside each sub-array (HTF-DFE front end).
%
%   For sub-array m (m = 1..P) with K elements (k = 1..K), each element
%   carries its own channel H_{m,k}(nu) and received spectrum R_{m,k}(nu):
%
%     C_{m,k}(nu) = conj(lambda_{m,k}) * conj(H_{m,k}(nu))
%                   / (|lambda_{m,k}|^2 * |H_{m,k}(nu)|^2 + sigma_w^2)   (3-61)
%     x_m = IFFT{ sum_{k=1..K} C_{m,k} .* R_{m,k} }                     (3-62)
%
%   The per-element scalar lambda is the residual-phase factor from
%   (3-39)~(3-41) (Phi = F D F^H, D = diag(e^{j*theta_n}),
%   lambda = (1/N) sum e^{j*theta_n}); when no residual phase estimate is
%   available the strict degradation is D = I, Phi = I, lambda = 1.  The
%   downstream DPLL never feeds lambda back into this front end.
%
%   Index convention (never reuse k for both meanings):
%     subarrayIndex m = 1..P, elementIndex k = 1..K,
%     frequencyBin nu = 0..N-1.
%
%   INPUTS
%     branches        M x N complex matrix of independent element signals
%                     (rows = elements; M = P * K required)
%     branchImpulses  M x L per-element impulse responses (rows are
%                     zero-padded to a common length L <= N)
%     noiseVariance    scalar sigma_w^2 > 0
%     cfg             .htfdeSubarrayCount (P), .htfdeElementsPerSubarray
%                     (K), optional .htfdeElementLambdas (1 x M complex;
%                     absent -> ones(1, M), the strict lambda = 1 form)
%   OUTPUT
%     subarrayOutputs P x N complex matrix: row m = x_m of (3-62)
%     trace           structural metadata used by the caller
if ~isscalar(noiseVariance) || ~isreal(noiseVariance) || ...
        ~isfinite(noiseVariance) || noiseVariance <= 0
    error("SCFDE:InvalidNoiseVariance", ...
        "noiseVariance must be a positive real scalar.");
end
if ~ismatrix(branches) || ~ismatrix(branchImpulses)
    error("SCFDE:ArrayStructure", ...
        "branches and branchImpulses must be 2-D matrices.");
end
M = size(branches, 1);
N = size(branches, 2);
if size(branchImpulses, 1) ~= M
    error("SCFDE:ArrayStructure", ...
        "branch count (%d) and per-branch impulse count (%d) must match.", ...
        M, size(branchImpulses, 1));
end
if ~isfield(cfg, "htfdeSubarrayCount") || ~isfield(cfg, "htfdeElementsPerSubarray")
    error("SCFDE:BookParameterUnavailable", ...
        "The BOOK structure needs explicit htfdeSubarrayCount (P) and " + ...
        "htfdeElementsPerSubarray (K): the book experiment values are " + ...
        "not published (PARAM-UNRECOVERABLE).");
end
subarrayCount = cfg.htfdeSubarrayCount;
elementsPerSubarray = cfg.htfdeElementsPerSubarray;
if ~isscalar(subarrayCount) || ~isscalar(elementsPerSubarray) || ...
        subarrayCount < 1 || elementsPerSubarray < 1 || ...
        mod(subarrayCount, 1) ~= 0 || mod(elementsPerSubarray, 1) ~= 0
    error("SCFDE:ArrayStructure", ...
        "htfdeSubarrayCount and htfdeElementsPerSubarray must be positive integers.");
end
if M ~= subarrayCount * elementsPerSubarray
    error("SCFDE:ArrayStructure", ...
        "Element count M=%d must equal P*K=%d.", M, subarrayCount * elementsPerSubarray);
end
if isfield(cfg, "htfdeElementLambdas")
    elementLambdas = cfg.htfdeElementLambdas(:).';
    if numel(elementLambdas) ~= M || any(~isfinite(elementLambdas))
        error("SCFDE:ArrayStructure", ...
            "htfdeElementLambdas must hold exactly M finite values.");
    end
else
    elementLambdas = ones(1, M);   % strict degradation: Phi = I, lambda = 1
end

subarrayOutputs = zeros(subarrayCount, N);
for subarrayIndex = 1:subarrayCount
    jointSpectrum = zeros(1, N);
    for elementIndex = 1:elementsPerSubarray
        globalIndex = (subarrayIndex - 1) * elementsPerSubarray + elementIndex;
        lambda = elementLambdas(globalIndex);
        rElement = branches(globalIndex, :);
        hElement = branchImpulses(globalIndex, :);
        RElement = fft(rElement);
        HElement = fft(hElement, N);
        % (3-61) diagonal form: C = (|lambda|^2 H^H H + sigma^2 I)^{-1}
        % lambda* H^H  ->  per frequency bin:
        CElement = conj(lambda) * conj(HElement) ./ ...
            (abs(lambda)^2 .* abs(HElement).^2 + noiseVariance);
        jointSpectrum = jointSpectrum + CElement .* RElement;
    end
    subarrayOutputs(subarrayIndex, :) = ifft(jointSpectrum);
end
trace.elementLambdas = elementLambdas;
trace.branchCount = M;
trace.subarrayCount = subarrayCount;
trace.elementsPerSubarray = elementsPerSubarray;
trace.blockLength = N;
end
