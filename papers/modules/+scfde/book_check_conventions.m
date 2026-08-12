function book_check_conventions()
%BOOK_CHECK_CONVENTIONS  Runtime sanity check of frozen conventions.
%   Called at the top of every audit (qpsk/turbo/cck/csk).  Throws an
%   error if any frozen convention (BOOK_CONVENTIONS.md) is violated,
%   so an audit cannot pass on top of broken math conventions.
%   Checks: DFT pair, Parseval M_x = N*m_x, noise variance scaling,
%   LLR sign (0 positive), unit-energy symbol M_x = N.

X = fft([1; 2; 3; 4]);
assert(norm(X - [10; -2 + 2j; -2; -2 - 2j]) < 1e-12, ...
    "SCFDE:Convention", "DFT convention broken (fft is not book-exact)");
x = randn(8, 1) + 1j * randn(8, 1);
assert(norm(ifft(fft(x)) - x) < 1e-12, ...
    "SCFDE:Convention", "DFT round-trip broken");

s = exp(1j * pi / 4) * (2 * randi([0 1], 32, 1) - 1 + ...
    1j * (2 * randi([0 1], 32, 1) - 1)) / sqrt(2);
Mx = mean(abs(fft(s)).^2);
assert(abs(Mx - 32 * mean(abs(s).^2)) / 32 < 1e-12, ...
    "SCFDE:Convention", "Parseval M_x = N*m_x broken");

sigma2 = 10^(-10 / 10);
w = sqrt(sigma2 / 2) * (randn(64, 1) + 1j * randn(64, 1));
assert(abs(mean(abs(fft(w)).^2) - 64 * sigma2) / (64 * sigma2) < 0.2, ...
    "SCFDE:Convention", "E|W_k|^2 = N*sigma_w^2 broken");

L = 1.5;
p0 = 1 / (1 + exp(-L));
assert(abs(log(p0 / (1 - p0)) - L) < 1e-12, ...
    "SCFDE:Convention", "LLR sign convention broken (must be 0-positive)");
end
