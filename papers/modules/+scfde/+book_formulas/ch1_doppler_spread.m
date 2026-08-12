function df = ch1_doppler_spread(vmax, f, c)
%CH1_DOPPLER_SPREAD  Book eq.(1-5): maximum Doppler spread.
%   df_max = (v_max / c) * f
%   Default c = 1500 m/s (book mean sound speed).
if nargin < 3 || isempty(c)
    c = 1500;
end
df = (vmax ./ c) .* f;
end
