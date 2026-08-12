function E = ch1_bandwidth_efficiency(Rb, W)
%CH1_BANDWIDTH_EFFICIENCY  Book eq.(1-12): bandwidth efficiency.
%   E = R_b / W  [bit/s/Hz]
%   Book page 14, eq. (1-12); the book also gives the worked example
%   R_b = 10 kbit/s, W = 5 kHz -> E = 2 bit/(s*Hz).
E = Rb ./ W;
end
