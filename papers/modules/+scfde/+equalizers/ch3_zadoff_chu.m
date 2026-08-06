function sequence = ch3_zadoff_chu(lengthValue, root)
assert(gcd(lengthValue, root) == 1, ...
    "The Zadoff-Chu root and length must be coprime.");
index = 0:lengthValue - 1;
if mod(lengthValue, 2) == 0
    sequence = exp(-1j * pi * root * index.^2 / lengthValue);
else
    sequence = exp(-1j * pi * root * index .* (index + 1) / lengthValue);
end
end
