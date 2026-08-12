function ids = parse_equation_ids(token)
%PARSE_EQUATION_IDS  Single equation-ID parser for the whole project.
%   Supports every token format used in FORMULA_TRACEABILITY.md:
%     "(4-1)"            -> "4-1"
%     "(3-39~3-41)"      -> 3-39, 3-40, 3-41
%     "(2-16)~(2-25)"    -> 2-16 .. 2-25
%     "(3-4)/(3-5)"      -> 3-4, 3-5
%   Returns strings(1,0) when the token is not an equation token.
%   g1, the global coverage audit and the formulaClass derivation all
%   use this single parser.

token = strtrim(string(token));
s = char(token);

% (3-39~3-41)
t = regexp(s, '^\((\d+)-(\d+)\s*~\s*(\d+)-(\d+)\)', 'tokens', 'once');
if ~isempty(t)
    ids = expand_ids(t{1}, t{2}, t{3}, t{4});
    return;
end

% (2-16)~(2-25)
t = regexp(s, '^\((\d+)-(\d+)\)\s*~\s*\((\d+)-(\d+)\)', 'tokens', 'once');
if ~isempty(t)
    ids = expand_ids(t{1}, t{2}, t{3}, t{4});
    return;
end

% (3-4)/(3-5)
t = regexp(s, '^\((\d+)-(\d+)\)\s*/\s*\((\d+)-(\d+)\)', 'tokens', 'once');
if ~isempty(t)
    ids = [string(t{1}) + "-" + string(t{2}), ...
        string(t{3}) + "-" + string(t{4})];
    return;
end

% (4-1)
t = regexp(s, '^\((\d+)-(\d+)\)', 'tokens', 'once');
if ~isempty(t)
    ids = string(t{1}) + "-" + string(t{2});
    return;
end

ids = strings(1, 0);
end

function ids = expand_ids(ch1, n1, ch2, n2)
assert(strcmp(ch1, ch2), "SCFDE:CrossChapterRange", ...
    "Equation range crosses chapters: %s-%s ~ %s-%s", ch1, n1, ch2, n2);
a = str2double(n1);
b = str2double(n2);
assert(b >= a, "SCFDE:InvalidEquationRange", ...
    "Equation range end %d < start %d.", b, a);
ids = string(ch1) + "-" + string(a:b);
end
