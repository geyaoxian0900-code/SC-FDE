function w = ch2_lms_update(w, u, e, mu)
%CH2_LMS_UPDATE  Book eq.(2-12)/(2-14): LMS recursion.
%   w(n+1) = w(n) - mu grad J(n)        (2-12)
%   grad J(n) = -2 e*(n) u(n)           (2-13)
%   => w(n+1) = w(n) + 2 mu e*(n) u(n)  (2-14)
w = w + 2 * mu * conj(e) * u;
end
