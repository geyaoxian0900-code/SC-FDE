function code = scfde_make_ldpc(K)
%SCFDE_MAKE_LDPC Build a deterministic rate-1/2 sparse LDPC code.
% H = [A B], where B is lower bidiagonal and can be encoded recursively.

arguments
    K (1, 1) double {mustBeInteger, mustBePositive} = 448
end

M = K;
shifts = [0, 73, 181];
columns = repmat((1:K).', numel(shifts), 1);
rows = zeros(size(columns));
for shiftIndex = 1:numel(shifts)
    range = (shiftIndex - 1) * K + (1:K);
    rows(range) = mod((1:K).' - 1 + shifts(shiftIndex), M) + 1;
end
A = sparse(rows, columns, 1, M, K);
B = speye(M) + sparse(2:M, 1:M-1, 1, M, M);
H = spones([A, B]);
[checkIndex, variableIndex] = find(H);

code.K = K;
code.M = M;
code.N = 2 * K;
code.A = A;
code.H = H;
code.checkIndex = checkIndex;
code.variableIndex = variableIndex;
code.edgeCount = numel(checkIndex);
code.checkEdges = accumarray(checkIndex, (1:code.edgeCount).', ...
    [M, 1], @(edges) {edges});
end
