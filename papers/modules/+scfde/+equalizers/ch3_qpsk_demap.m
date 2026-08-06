function bits = ch3_qpsk_demap(symbols)
symbols = symbols(:).';
bits = false(1, 2 * numel(symbols));
bits(1:2:end) = real(symbols) >= 0;
bits(2:2:end) = imag(symbols) >= 0;
bits = double(bits);
end
