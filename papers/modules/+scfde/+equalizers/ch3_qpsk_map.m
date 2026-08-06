function symbols = ch3_qpsk_map(bits)
bits = logical(bits(:).');
symbols = ((2 * double(bits(1:2:end)) - 1) + ...
    1j * (2 * double(bits(2:2:end)) - 1)) / sqrt(2);
end
