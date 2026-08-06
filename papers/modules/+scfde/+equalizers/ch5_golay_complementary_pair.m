function [A, B] = ch5_golay_complementary_pair(levels)
% 濞?(5-8): A_k=[A_{k-1} B_{k-1}], B_k=[A_{k-1} -B_{k-1}]
% 缂佸绉撮悺?(5-9): A_1=[1 1], B_1=[1 -1]闁靛棔搴積vels=1 鐎?A_2=[1 1 1 -1]闁? 濞达絽绋勭槐?A = [1, 1];
B = [1, -1];
for level = 1:levels
    nextA = [A, B];
    nextB = [A, -B];
    A = nextA;
    B = nextB;
end
end
