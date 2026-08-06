function postcursor = ch3_circular_postcursor(decisions, impulse)
postcursor = complex(zeros(size(decisions)));
for tap = 2:numel(impulse)
    postcursor = postcursor + impulse(tap) * ...
        circshift(decisions, [0, tap - 1]);
end
end
