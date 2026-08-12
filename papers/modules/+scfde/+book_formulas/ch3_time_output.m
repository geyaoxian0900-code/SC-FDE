function [shat, beta] = ch3_time_output(F, C, Phi, H, s)
%CH3_TIME_OUTPUT  Book eq.(3-45)/(3-46): equalized time-domain output.
%   shat = F^H C Phi H F s + w'  (noise-free part)
%   = A H s with A circulant; per-sample shat_k = beta_k s_k + w'_k,
%   beta_k = diag of F^H C Phi H F (the main-tap response).
A = F' * C * Phi * H * F / numel(s);
shat = A * s(:);
beta = diag(A);
end
