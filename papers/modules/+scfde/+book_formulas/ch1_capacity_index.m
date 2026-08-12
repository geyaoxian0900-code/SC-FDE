function I = ch1_capacity_index(rateKbps, distKm)
%CH1_CAPACITY_INDEX  Book eq.(1-11): communication capacity index.
%   I = rate (kbit/s) * distance (km); book upper bound 100 kbit/s*km.
I = rateKbps .* distKm;
end
