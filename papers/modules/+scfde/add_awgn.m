function output = add_awgn(input, snrDb)
%ADD_AWGN Add complex white Gaussian noise at measured signal power.

signalPower = mean(abs(input(:)).^2);
noisePower = signalPower / 10^(snrDb / 10);
noise = sqrt(noisePower / 2) * ...
    (randn(size(input)) + 1j * randn(size(input)));
output = input + noise;
end
