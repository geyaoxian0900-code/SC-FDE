function deltaHat = ch6_shift_detect(theta)
%CH6_SHIFT_DETECT  Book eq.(6-12): cyclic-shift detection.
%   Delta_hat = arg max_g theta(g)
%   theta: the shifted correlation vector from (6-10); the returned
%   shift is zero-based (MATLAB 1-based peak minus 1), matching the CSK
%   shift alphabet.
[~, idx] = max(real(theta(:)));
deltaHat = idx - 1;
end
