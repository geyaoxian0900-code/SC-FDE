function decision = slice_decision(estimate, cfg)
%SLICE_DECISION Symbol decision for the equalizer cores.
% Supports BPSK (default, book ch2) and QPSK (book ch2+ch3 shared links).
if isfield(cfg, "modulation") && strcmpi(cfg.modulation, "qpsk")
    decision = (sign(real(estimate)) + 1j * sign(imag(estimate))) / sqrt(2);
    if decision == 0
        decision = (1 + 1j) / sqrt(2);
    end
else
    decision = sign(real(estimate));
    if decision == 0
        decision = 1;
    end
end
end
