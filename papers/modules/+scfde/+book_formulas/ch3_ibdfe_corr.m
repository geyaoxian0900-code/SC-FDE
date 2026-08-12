function r = ch3_ibdfe_corr(X, Xhat)
%CH3_IBDFE_CORR  Book eq.(3-66): correlation between transmitted and
%   estimated spectra:  r_{Xk,Xhatk*} = E[ X_k Xhat_k^* ].
r = mean(X(:) .* conj(Xhat(:)));
end
