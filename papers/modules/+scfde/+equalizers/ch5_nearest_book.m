function detected = ch5_nearest_book(observations, book)
[~, detected] = min(sum(abs(observations).^2, 2) + sum(abs(book).^2, 2).' - ...
    2 * real(observations * book'), [], 2);
detected = detected.';
end
