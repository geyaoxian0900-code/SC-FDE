function Q = ch6_ptr_equivalent_channel(h, bhat)
%CH6_PTR_EQUIVALENT_CHANNEL  Book eq.(6-38): PTR equivalent channel.
%   Q_m(t) = sum_n h_{m,n}(t) * bhat_n(-t)   (linear convolution)
%   h: channel (1 x L), bhat: estimated CIR (1 x L).
Q = conv(h(:), conj(flipud(bhat(:))));
end
