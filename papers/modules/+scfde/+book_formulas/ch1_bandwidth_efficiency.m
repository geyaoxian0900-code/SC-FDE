function E = ch1_bandwidth_efficiency(Rb, W)
%CH1_BANDWIDTH_EFFICIENCY  Book eq.(1-12): bandwidth efficiency.
%   E = R_b / W  [bit/s/Hz]
%   NOTE: the book PRINTS "E = RbW" (eq. 1-12, page 14), but the
%   surrounding definition ("每赫兹频带每秒可以传输多少比特") and the
%   worked example (R_b = 10 kbit/s, W = 5 kHz -> E = 2 bit/(s*Hz))
%   show the intended form is the RATIO R_b/W; the printed RbW is a
%   typographical error (verified against book/4.png 2026-08-12).
E = Rb ./ W;
end
