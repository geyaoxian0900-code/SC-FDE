function [hardBits, posteriorLlr, iterations] = scfde_ldpc_decode( ...
        channelLlr, code, maxIterations)
%SCFDE_LDPC_DECODE Normalized min-sum LDPC decoding.

arguments
    channelLlr (:, 1) double
    code struct
    maxIterations (1, 1) double {mustBeInteger, mustBePositive} = 20
end

assert(numel(channelLlr) == code.N, "LLR length does not match LDPC code.");
alpha = 0.78;
checkIndex = code.checkIndex;
variableIndex = code.variableIndex;
variableToCheck = channelLlr(variableIndex);
checkToVariable = zeros(code.edgeCount, 1);
posteriorLlr = channelLlr;

for iterations = 1:maxIterations
    for check = 1:code.M
        edges = code.checkEdges{check};
        values = variableToCheck(edges);
        signs = sign(values);
        signs(signs == 0) = 1;
        magnitudes = abs(values);
        [minimum1, position] = min(magnitudes);
        if numel(magnitudes) > 1
            temporary = magnitudes;
            temporary(position) = inf;
            minimum2 = min(temporary);
        else
            minimum2 = minimum1;
        end
        totalSign = prod(signs);
        outgoingMagnitude = repmat(minimum1, numel(edges), 1);
        outgoingMagnitude(position) = minimum2;
        checkToVariable(edges) = alpha * totalSign .* signs .* outgoingMagnitude;
    end

    posteriorLlr = channelLlr + accumarray(variableIndex, ...
        checkToVariable, [code.N, 1]);
    hardBits = posteriorLlr < 0;
    if all(mod(code.H * hardBits, 2) == 0)
        return;
    end
    variableToCheck = posteriorLlr(variableIndex) - checkToVariable;
end
end
