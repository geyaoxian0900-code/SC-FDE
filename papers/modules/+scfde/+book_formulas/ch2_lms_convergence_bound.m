function lmax = ch2_lms_convergence_bound(R)
%CH2_LMS_CONVERGENCE_BOUND  Book eq.(2-15): LMS convergence bound.
%   0 < mu < 1/lambda_max,  lambda_max = largest eigenvalue of R.
lmax = max(eig(R));
end
