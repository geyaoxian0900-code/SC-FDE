function J = ch2_mse(w, Ru, Rdu, dPower)
%CH2_MSE  Book eq.(2-10): MMSE objective.
%   J(w) = E|d - w^H u|^2
%        = E|d|^2 - w^H R_du - R_du^H w + w^H R_u w
if nargin < 4 || isempty(dPower)
    dPower = 1;
end
J = dPower - w' * Rdu - Rdu' * w + w' * Ru * w;
end
