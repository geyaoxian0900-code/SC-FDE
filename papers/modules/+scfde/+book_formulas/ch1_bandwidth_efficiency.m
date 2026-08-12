function E = ch1_bandwidth_efficiency(Rb, W)
%CH1_BANDWIDTH_EFFICIENCY  Book eq.(1-12): bandwidth efficiency.
%   E = Rb * W  with Rb the data rate (bit/s) and W the bandwidth (Hz).
%   (Book prints E = RbW.)
E = Rb .* W;
end
