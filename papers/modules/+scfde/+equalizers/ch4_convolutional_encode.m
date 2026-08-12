function coded = ch4_convolutional_encode(bits, genPoly)
%CH4_CONVOLUTIONAL_ENCODE Convolutional encoder, parameterized.
%   coded = ch4_convolutional_encode(bits, genPoly)
%   genPoly default [7 5] octal (book 4.5.3 FDDA experiment);
%   book 4.3 experiment uses [171 133] octal (table 4-4).
%   Output layout: coded(2k-1) = first generator output, coded(2k) =
%   second generator output, matching the fixed (7,5) version.
if nargin < 2 || isempty(genPoly)
    genPoly = [7 5];
end
genBits = cell(1, numel(genPoly));
constraintLength = 0;
for j = 1:numel(genPoly)
    b = de2bi_local(genPoly(j));
    genBits{j} = b;
    constraintLength = max(constraintLength, numel(b));
end
m = constraintLength - 1;
state = zeros(1, m);
coded = zeros(1, numel(genPoly) * numel(bits));
for index = 1:numel(bits)
    reg = [bits(index), state];
    for j = 1:numel(genPoly)
        g = genBits{j};
        gpad = [zeros(1, numel(reg) - numel(g)), g];
        coded(numel(genPoly) * (index - 1) + j) = mod(sum(reg .* gpad), 2);
    end
    state = [bits(index), state(1:end - 1)];
end
end

function b = de2bi_local(value)
% Octal value -> binary row (MSB first), dropping leading zeros.
% The input is interpreted as an OCTAL number (poly2trellis convention):
% 171 -> octal 171 -> decimal 121 -> 1111001 (binary).
dec = 0;
octStr = sprintf('%d', value);
for d = octStr
    dec = dec * 8 + (d - '0');
end
bin = dec2bin(dec, 32);
firstOne = find(bin == '1', 1);
b = double(bin(firstOne:end) == '1');
end
