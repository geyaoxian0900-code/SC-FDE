function g = ch2_lms_gradient(e, u)
%CH2_LMS_GRADIENT  Book eq.(2-13): LMS gradient estimate.
%   grad J = -2 E[e^*(n) u(n)];  instantaneous estimate: -2 e^*(n) u(n).
%   Inputs may be vectors; returns the sample-average gradient.
g = -2 * mean(conj(e(:)) .* u(:));
end
