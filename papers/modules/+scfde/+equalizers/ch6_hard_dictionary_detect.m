function [decision, expected] = ch6_hard_dictionary_detect(observation, dictionary)
distance = sum(abs(dictionary - observation).^2, 2);
[~, decision] = min(distance);
expected = dictionary(decision, :);
end
