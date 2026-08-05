function output = merge_struct(defaults, overrides)
%MERGE_STRUCT Recursively merge scalar configuration structures.

output = defaults;
if nargin < 2 || isempty(overrides)
    return;
end
assert(isstruct(overrides) && isscalar(overrides), ...
    "SCFDE:InvalidOptions", "Overrides must be a scalar structure.");

names = fieldnames(overrides);
for index = 1:numel(names)
    name = names{index};
    value = overrides.(name);
    if isfield(output, name) && isstruct(output.(name)) && ...
            isscalar(output.(name)) && isstruct(value) && isscalar(value)
        output.(name) = scfde.merge_struct(output.(name), value);
    else
        output.(name) = value;
    end
end
end
