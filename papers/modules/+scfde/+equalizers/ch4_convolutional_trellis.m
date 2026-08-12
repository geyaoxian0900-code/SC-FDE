function [nextState, outputBits] = ch4_convolutional_trellis(genPoly)
%CH4_CONVOLUTIONAL_TRELLIS Convolutional trellis, parameterized.
%   [nextState, outputBits] = ch4_convolutional_trellis(genPoly)
%   genPoly default [7 5] (octal), book 4.5.3 FDDA experiment.
%   Book 4.3 experiment (table 4-4) uses [171 133] octal.
%
%   Generator bit mapping (MSB = current input bit):
%     G1 = 171 (octal) = 1111001 (binary) -> c1 = u + s1 + s2 + s3 + s6
%     G2 = 133 (octal) = 1011011 (binary) -> c2 = u + s2 + s3 + s5 + s6
%   State vector [s_m ... s_1] with s_m the most recent input.
%   nextState and outputBits have the same layout as the fixed (7,5)
%   version: nextState(state+1, inputBit+1), outputBits(state+1, inputBit+1, :).
if nargin < 1 || isempty(genPoly)
    genPoly = [7 5];
end
genBits = cell(1, numel(genPoly));
constraintLength = 0;
for j = 1:numel(genPoly)
    b = de2bi_local(genPoly(j));
    genBits{j} = b;
    constraintLength = max(constraintLength, numel(b));
end
m = constraintLength - 1;                 % memory length
stateCount = 2 ^ m;
nextState = zeros(stateCount, 2);
outputBits = zeros(stateCount, 2, numel(genPoly));
for state = 0:stateCount - 1
    regState = bitget(state, m:-1:1);     % [s_m ... s_1]
    for inputBit = 0:1
        reg = [inputBit, regState];       % [u, s_m ... s_1]
        for j = 1:numel(genPoly)
            g = genBits{j};
            gpad = [zeros(1, numel(reg) - numel(g)), g];  % align to LSB
            outputBits(state + 1, inputBit + 1, j) = mod(sum(reg .* gpad), 2);
        end
        nextState(state + 1, inputBit + 1) = ...
            inputBit * 2 ^ (m - 1) + floor(state / 2) + 1;
    end
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
