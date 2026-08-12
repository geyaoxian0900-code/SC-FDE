function R = ch3_freq_model(r, F, Phi, H, S)
%CH3_FREQ_MODEL  Book eq.(3-38): frequency-domain received model.
%   R = F r = F D F^H F H F s + W = Phi H S + W (noise-free part).
%   Phi = F D F^H (circulant); H = diag(H_k) the diagonal channel;
%   S = F s.  Oracle: R must equal Phi * H * S.
R = Phi * H * S;
end
