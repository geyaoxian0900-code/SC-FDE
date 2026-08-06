function [A, B] = ch5_golay_complementary_pair(levels)
%CH5_GOLAY_COMPLEMENTARY_PAIR Golay pair recurrence (book 5-8/5-9).
% A_k = [A_{k-1} B_{k-1}], B_k = [A_{k-1} -B_{k-1}], seed A_1=[1 1], B_1=[1 -1].
A = [1, 1];
B = [1, -1];
for level = 1:levels
    nextA = [A, B];
    nextB = [A, -B];
    A = nextA;
    B = nextB;
end
end
