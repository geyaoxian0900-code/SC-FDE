function active = ch5_candidate_list(observation, book, count)
distance = sum(abs(book - observation).^2, 2);
[~, order] = sort(distance, "ascend");
active = order(1:count).';
end
