function book = ch6_shifted_codebook(root, codeCount)
lengthCode = numel(root);
book = zeros(codeCount, lengthCode, "like", root);
shifts = round((0:codeCount - 1) * lengthCode / codeCount);
for codeIndex = 1:codeCount
    book(codeIndex, :) = circshift(root, shifts(codeIndex));
end
end
