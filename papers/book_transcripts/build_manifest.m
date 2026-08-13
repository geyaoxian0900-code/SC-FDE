function manifest = build_manifest()
%BUILD_MANIFEST  Unique, executable transcription manifest generator.
%   Parses every file in papers/book_transcripts/, extracts formula IDs
%   with ONE fixed rule set, and compares against the trace's 394 IDs.
%   Outputs covered / pending / duplicates / out-of-trace IDs and the
%   covered ratio.  The acceptance runner and README statistics both use
%   this function - there is no second counting path.
%
%   Extraction rules (fixed, reproducible):
%     - tool log lines ("injected env", "dotenvx", "secrets for agents")
%       are skipped;
%     - a formula ID is any of:
%         \tag{2-16}              (LaTeX tag)
%         **(2-16)**              (bold number)
%         (2-16) / （2-16）        (parenthesized number, N-N form only)
%     - page numbers / reference page numbers (plain integers) never
%       match because only the "chapter-number" form is accepted.

papersDir = fileparts(fileparts(mfilename("fullpath")));
if isempty(papersDir)
    papersDir = fullfile(pwd, "..");   % -batch fallback (cwd = book_transcripts)
end
transcriptsDir = fullfile(papersDir, "book_transcripts");

% 1) trace IDs (the ground set)
traceIds = trace_equation_ids(fullfile(fileparts(papersDir), ...
    "FORMULA_TRACEABILITY.md"));

% 2) transcription coverage
files = dir(fullfile(transcriptsDir, "book_*.md"));
covered = containers.Map("KeyType", "char", "ValueType", "char");
duplicates = containers.Map("KeyType", "char", "ValueType", "double");
for f = 1:numel(files)
    name = files(f).name;
    text = fileread(fullfile(transcriptsDir, name));
    lines = string(splitlines(text));
    for i = 1:numel(lines)
        ln = lines(i);
        if contains(ln, "injected env") || contains(ln, "dotenvx") || ...
                contains(ln, "secrets for agents")
            continue;
        end
        ids = extract_ids(ln);
        for k = 1:numel(ids)
            id = char(ids(k));
            if isKey(covered, id)
                if isKey(duplicates, id)
                    duplicates(id) = duplicates(id) + 1;
                else
                    duplicates(id) = 1;
                end
            else
                covered(id) = name;
            end
        end
    end
end

% 3) classification
pending = strings(0);
outOfTrace = strings(0);
coveredIds = strings(0);
coveredFiles = strings(0);
for k = 1:numel(traceIds)
    id = char(traceIds(k));
    if isKey(covered, id)
        coveredIds(end + 1) = id; %#ok<AGROW>
        coveredFiles(end + 1) = covered(id); %#ok<AGROW>
    else
        pending(end + 1) = id; %#ok<AGROW>
    end
end
allTranscriptIds = keys(covered);
for k = 1:numel(allTranscriptIds)
    id = allTranscriptIds{k};
    if ~any(traceIds == string(id))
        outOfTrace(end + 1) = string(id); %#ok<AGROW>
    end
end

manifest = struct( ...
    "total", numel(traceIds), ...
    "covered", numel(coveredIds), ...
    "pending", numel(pending), ...
    "duplicates", numel(keys(duplicates)), ...
    "outOfTrace", numel(outOfTrace), ...
    "coveredIds", coveredIds, ...
    "coveredFiles", coveredFiles, ...
    "pendingIds", pending, ...
    "outOfTraceIds", outOfTrace);

fprintf("TRANSCRIPTION MANIFEST\n");
fprintf("  trace IDs:          %d\n", manifest.total);
fprintf("  covered:            %d (%.1f%%)\n", manifest.covered, ...
    100 * manifest.covered / max(manifest.total, 1));
fprintf("  pending:            %d\n", manifest.pending);
fprintf("  duplicates:         %d\n", manifest.duplicates);
fprintf("  out-of-trace:       %d\n", manifest.outOfTrace);
end

function ids = extract_ids(line)
% One fixed rule set: LaTeX tag, bold number, or parenthesized N-N.
ids = strings(0);
t = regexp(line, '\\tag\{(\d+-\d+)\}', 'tokens', 'once');
if ~isempty(t)
    ids(end + 1) = t{1}; %#ok<AGROW>
end
t = regexp(line, '\*\*\((\d+-\d+)\)\*\*', 'tokens', 'once');
if ~isempty(t)
    ids(end + 1) = t{1}; %#ok<AGROW>
end
t = regexp(line, '[\(（](\d+-\d+)[\)）]', 'tokens');
for k = 1:numel(t)
    ids(end + 1) = t{k}{1}; %#ok<AGROW>
end
ids = unique(ids, "stable");
end

function ids = trace_equation_ids(tracePath)
ids = strings(0);
text = fileread(tracePath);
lines = string(splitlines(text));
for i = 1:numel(lines)
    cells = strtrim(split(lines(i), "|"));
    cells(cells == "") = [];
    if isempty(cells)
        continue;
    end
    got = book_acceptance.parse_equation_ids(cells(1));
    if ~isempty(got)
        ids = [ids, got]; %#ok<AGROW>
    end
end
ids = unique(ids, "stable");
end
