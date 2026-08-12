function [meanY, varY] = ch6_ptr_ese_moments(Q, muX, varX, hhat, sigmaW2)
%CH6_PTR_ESE_MOMENTS  Book eq.(6-41)/(6-42): PTR-ESE observation moments.
%   E[y^{(s)}(j)]   = sum_m sum_l Q_m(l) E[x_m(j-l)]
%   Var[y^{(s)}(j)] = sum_m sum_l |Q_m(l)|^2 Var[x_m(j-l)]
%                     + sum_n sum_l |hhat_n(l)|^2 sigma_w^2
%   Q: equivalent channels (M users x 2L-1 taps), muX/varX: soft
%   moments per user (M x 1), hhat: estimated channels (N x L),
%   sigmaW2: noise variance.
meanY = sum(muX(:) .* sum(Q, 2));
varY = sum(varX(:) .* sum(abs(Q) .^ 2, 2)) + ...
    sum(abs(hhat(:)) .^ 2) * sigmaW2;
end
