function run_unified_equalizer_interactive()
%RUN_UNIFIED_EQUALIZER_INTERACTIVE Interactive equalizer picker.
%
% Shows a numbered menu of all 36 equalizers grouped by book chapter,
% lets you pick any subset by number (e.g. "3" or "3,8,15" or "all"),
% chooses the matching scenario automatically, runs the simulation, and
% prints a BER table. Repeat until you enter "q".
%
% Example:
%   >> run_unified_equalizer_interactive

rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "modules"));
addpath(fullfile(rootDir, "engineering_simulation"));
addpath(fullfile(rootDir, "examples"));

groups = {
    "第2章 时域均衡", ["dfe", "lms-dfe", "nlms-dfe", "rls-dfe", ...
        "dpll-dfe", "mc-lms-dfe", "mc-nlms-dfe", "mc-rls-dfe", ...
        "ptr-dfe", "subband-ptr-dfe"]
    "第3章 频域均衡", ["mmse-fde", "zf-fde", "htfde", "sd-ibdfe", ...
        "hd-ibdfe", "ice-sd-ibdfe", "ice-hd-ibdfe"]
    "第4章 迭代均衡", ["td-turbo", "fd-dfe", "fd-turbo", "tf-turbo", ...
        "bitf-turbo", "blms-tf-turbo", "tdda-teq", "fdda-teq", ...
        "fdda-dfe-teq"]
    "第5章 CCK", ["cck-rake", "cck-dfe", "cck-bidfe", "cck-bidfe2", ...
        "cck-tr-diversity", "cck-fde", "cck-mfb"]
    "第6章 CSK", ["csk-matched-filter", "csk-soft-sic", "csk-ese"]
    };

while true
    fprintf("\n============== 均衡器选择器 ==============\n");
    fprintf("输入编号选择均衡器（逗号分隔，如 3,8,15；输入 all 选全部；q 退出）\n\n");
    allIds = strings(1, 0);
    for g = 1:size(groups, 1)
        fprintf("【%s】\n", groups{g, 1});
        ids = groups{g, 2};
        for k = 1:numel(ids)
            fprintf("  %2d. %s\n", numel(allIds) + k, ids(k));
        end
        allIds = [allIds, ids]; %#ok<AGROW>
        fprintf("\n");
    end
    fprintf("  q. 退出\n");

    choice = strtrim(input("> ", "s"));
    if isempty(choice)
        continue;
    end
    if strcmpi(choice, "q")
        fprintf("退出。\n");
        break;
    end

    selected = parse_choice(choice, allIds);
    if isempty(selected)
        fprintf("输入无效，请重新选择。\n");
        continue;
    end

    snrStr = strtrim(input("SNR (dB，直接回车用 18): ", "s"));
    if isempty(snrStr)
        snrDb = 18;
    else
        snrDb = str2double(snrStr);
    end
    if isnan(snrDb) || snrDb <= 0
        snrDb = 18;
    end

    framesStr = strtrim(input("帧数（回车用 50）: ", "s"));
    if isempty(framesStr)
        frameCount = 50;
    else
        frameCount = round(str2double(framesStr));
    end
    if isnan(frameCount) || frameCount < 1
        frameCount = 50;
    end

    options = struct("equalizers", selected, "scenario", "auto", ...
        "snrDb", snrDb, "frameCount", frameCount, "makePlot", false);
    % Group the selected equalizers by scenario so each frame type is
    % matched correctly (ch2/3 -> qpsk, ch4 -> turbo, ch5 -> cck, ch6 -> csk)
    scenarioIds = struct("qpsk", strings(1, 0), ...
        "turbo", strings(1, 0), "cck", strings(1, 0), "csk", strings(1, 0));
    for k = 1:numel(selected)
        id = selected(k);
        if startsWith(id, "cck-")
            scenarioIds.cck(end + 1) = id;
        elseif startsWith(id, "csk-")
            scenarioIds.csk(end + 1) = id;
        elseif any(startsWith(id, ["td-turbo", "fd-dfe", "fd-turbo", ...
                "tf-turbo", "bitf-turbo", "blms-tf-turbo", ...
                "tdda-teq", "fdda-teq", "fdda-dfe-teq"]))
            scenarioIds.turbo(end + 1) = id;
        else
            scenarioIds.qpsk(end + 1) = id;
        end
    end
    scenarios = fieldnames(scenarioIds);
    for s = 1:numel(scenarios)
        group = scenarioIds.(scenarios{s});
        if isempty(group)
            continue;
        end
        options.equalizers = group;
        options.scenario = scenarios{s};
        try
            results = run_unified_equalizer(options);
            fprintf("\n===== 结果（%s 场景, SNR=%g dB, %d 帧）=====\n", ...
                results.scenario, snrDb, frameCount);
            for k = 1:numel(results.ids)
                fprintf("  %-18s BER=%.6f\n", results.ids(k), results.ber(k));
            end
        catch exception
            fprintf("运行失败（%s）: %s\n", scenarios{s}, exception.message);
        end
    end
end
end

function selected = parse_choice(choice, allIds)
choice = lower(strtrim(choice));
if strcmpi(choice, "all")
    selected = allIds;
    return;
end
parts = strsplit(choice, [",", " ", char(65292)]);
selected = strings(1, 0);
for p = 1:numel(parts)
    token = strtrim(parts{p});
    if isempty(token)
        continue;
    end
    number = str2double(token);
    if ~isnan(number) && number >= 1 && number <= numel(allIds)
        selected(end + 1) = allIds(round(number)); %#ok<AGROW>
    else
        match = find(strcmpi(allIds, token), 1);
        if ~isempty(match)
            selected(end + 1) = allIds(match); %#ok<AGROW>
        end
    end
end
selected = unique(selected, "stable");
end
