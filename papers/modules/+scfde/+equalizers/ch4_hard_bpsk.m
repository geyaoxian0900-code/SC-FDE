function decisions = hard_bpsk(values)
decisions = 1 - 2 * (real(values) < 0);
end
