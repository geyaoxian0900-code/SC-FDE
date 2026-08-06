function output = ch3_add_awgn(input, snrDb)
signalPower = mean(abs(input).^2);
noisePower = signalPower * 10^(-snrDb / 10);
output = input + sqrt(noisePower / 2) * ...
    (randn(size(input)) + 1j * randn(size(input)));
end
