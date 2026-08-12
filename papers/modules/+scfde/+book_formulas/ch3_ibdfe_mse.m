function J = ch3_ibdfe_mse(xhat, x)
%CH3_IBDFE_MSE  Book eq.(3-67): IBDFE mean squared error.
%   J^IB = (1/N) sum_{k=0}^{N-1} E| xhat_k - x_k |^2
J = mean(abs(xhat(:) - x(:)).^2);
end
