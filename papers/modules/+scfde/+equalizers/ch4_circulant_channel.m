function matrix = ch4_circulant_channel(channel, blockLength)
column = [channel(:); zeros(blockLength - numel(channel), 1)];
matrix = zeros(blockLength);
for index = 1:blockLength
    matrix(:, index) = circshift(column, index - 1);
end
end
