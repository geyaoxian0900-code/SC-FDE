function [n, nComponents] = ch1_noise_psd(f, s, w)
%CH1_NOISE_PSD  Book eq.(1-6)/(1-7)/(1-8): ambient noise power spectral
%   density (dB re uPa).  Components: turbulence N_s, shipping N_v,
%   surface N_h, thermal N_t.  s: shipping density in (0,1); w: wind
%   speed m/s; f [kHz].  Returns total N(f) in dB and the 4 components.
fs = f(:).';
if nargin < 2 || isempty(s), s = 0.5; end
if nargin < 3 || isempty(w), w = 5; end
ns = -17 - 30 * log10(fs);
nv = 40 + 20 * (s - 0.5) + 26 * log10(fs) - 60 * log10(fs + 0.03);
nh = 50 + 7.5 * sqrt(w) + 20 * log10(fs) - 40 * log10(fs + 0.4);
nt = -15 + 20 * log10(fs);
nComponents = [ns; nv; nh; nt];
n = 10 * log10(sum(10 .^ (nComponents / 10), 1));
end
