function codeword = scfde_ldpc_encode(infoBits, code)
%SCFDE_LDPC_ENCODE Encode one systematic codeword for scfde_make_ldpc.

u = mod(infoBits(:), 2);
assert(numel(u) == code.K, "Information length does not match LDPC code.");
rhs = mod(code.A * u, 2);
parity = zeros(code.M, 1);
parity(1) = rhs(1);
for row = 2:code.M
    parity(row) = mod(rhs(row) + parity(row - 1), 2);
end
codeword = [u; parity];
assert(all(mod(code.H * codeword, 2) == 0), "LDPC encoding failed.");
end
