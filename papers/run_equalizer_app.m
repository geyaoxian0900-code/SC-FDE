function run_equalizer_app
%RUN_EQUALIZER_APP  Interactive APP: pick equalizers + channel + SNR
%   sweep, run and plot BER vs SNR curves.
%
%   RUN_EQUALIZER_APP()
%   - left panel: multi-select any of the 37 registered equalizers
%   - middle panel: channel (synthetic paths / Bellhop shallow water)
%     and SNR sweep settings
%   - right panel: BER vs SNR curve + per-ID BER table
%   - figures saved to papers/results/ber_snr_curves/
%
%   Built with uifigure (no App Designer dependency), fully scripted and
%   version-controllable.

rootDir = fileparts(mfilename("fullpath"));
addpath(rootDir);
addpath(fullfile(rootDir, "modules"));
addpath(fullfile(rootDir, "engineering_simulation"));
addpath(fullfile(rootDir, "examples"));

registry = scfde.equalizer_registry();
n = numel(registry.id);
itemLabels = arrayfun(@(k) sprintf('[ch%d/%s] %s', registry.chapter(k), ...
    registry.scenario(k), registry.id(k)), 1:n, "UniformOutput", false);

fig = uifigure("Name", "水声均衡器仿真平台 - BER vs SNR", ...
    "Position", [80 60 1200 720], "Color", "w");
grid = uigridlayout(fig, [1 3], "ColumnWidth", {280, 300, "1x"}, ...
    "RowHeight", {"1x"}, "Padding", 10, "ColumnSpacing", 10);

%% Left: equalizer selection
selPanel = uipanel(grid, "Title", "均衡方式选择（多选）", "FontWeight", "bold");
selGrid = uigridlayout(selPanel, [2 1], "RowHeight", {"1x", 28});
selList = uilistbox(selGrid, "Items", itemLabels, "Value", {itemLabels{1}}, ...
    "Multiselect", "on", "ValueChangedFcn", @onSel);
selInfo = uilabel(selGrid, "Text", "已选 1 个", "FontColor", [0.2 0.2 0.2]);
function onSel(~, ~)
    v = selList.Value;
    if isempty(v)
        selList.Value = itemLabels(1);
        v = selList.Value;
    end
    selInfo.Text = sprintf("已选 %d 个", numel(v));
end

%% Middle: channel + SNR
midPanel = uipanel(grid, "Title", "信道与仿真参数", "FontWeight", "bold");
midGrid = uigridlayout(midPanel, [13 2], "RowHeight", ...
    {22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22}, ...
    "ColumnWidth", {"1x", "1x"}, "RowSpacing", 6);

uilabel(midGrid, "Text", "信道模式");
chMode = uidropdown(midGrid, 'Items', {'synthetic', 'bellhop'}, ...
    "Value", "synthetic", "ValueChangedFcn", @onChMode);
uilabel(midGrid, "Text", "时延（符号周期）");
delaysEdit = uieditfield(midGrid, "text", "Value", "0, 1, 3");
uilabel(midGrid, "Text", "路径增益");
gainsEdit = uieditfield(midGrid, "text", ...
    "Value", "1, 0.7*exp(1j*0.5), 0.3*exp(-1j*0.8)");
uilabel(midGrid, "Text", "水深 (m)");
depthEdit = uieditfield(midGrid, "numeric", "Value", 100);
uilabel(midGrid, "Text", "距离 (km)");
rangeEdit = uieditfield(midGrid, "numeric", "Value", 1.0);
uilabel(midGrid, "Text", "海底类型");
sedimentDrop = uidropdown(midGrid, 'Items', {'custom', 'mud', 'clay', 'fine-sand', 'coarse-sand', 'rock', 'silt'}, ...
    "Value", "custom");
uilabel(midGrid, "Text", "SNR 起始 (dB)");
snrFromEdit = uieditfield(midGrid, "numeric", "Value", 6);
uilabel(midGrid, "Text", "SNR 终止 (dB)");
snrToEdit = uieditfield(midGrid, "numeric", "Value", 18);
uilabel(midGrid, "Text", "SNR 步长 (dB)");
snrStepEdit = uieditfield(midGrid, "numeric", "Value", 2);
uilabel(midGrid, "Text", "帧数 (frameCount)");
framesEdit = uieditfield(midGrid, "numeric", "Value", 100);
uilabel(midGrid, "Text", "结果保存目录");
saveDirLabel = uilabel(midGrid, "Text", "results\ber_snr_curves", ...
    "FontColor", [0.3 0.3 0.3]);

runBtn = uibutton(midGrid, "push", "Text", "运行仿真", ...
    "FontWeight", "bold", "BackgroundColor", [0.15 0.45 0.75], ...
    "FontColor", "w", "ButtonPushedFcn", @onRun);
resetBtn = uibutton(midGrid, "push", "Text", "恢复默认参数", ...
    "ButtonPushedFcn", @onReset);
cancelBtn = uibutton(midGrid, "push", "Text", "取消", ...
    "Enable", "off", "ButtonPushedFcn", @onCancel);

st = struct();   % shared sweep state across nested functions
sweepTimer = timer("TimerFcn", @stepOnce, "ExecutionMode", "fixedRate", ...
    "Period", 0.05, "BusyMode", "drop");

function onCancel(~, ~)
    st.cancelRequested = true;
    selInfo.Text = "正在取消…";
end

function onReset(~, ~)
    delaysEdit.Value = "0, 1, 3";
    gainsEdit.Value = "1, 0.7*exp(1j*0.5), 0.3*exp(-1j*0.8)";
    snrFromEdit.Value = 6;
    snrToEdit.Value = 18;
    snrStepEdit.Value = 2;
    framesEdit.Value = 100;
    chMode.Value = "synthetic";
    onChMode();
    selInfo.Text = "已恢复默认参数";
end

function onChMode(~, ~)
    on = strcmp(chMode.Value, "synthetic");
    delaysEdit.Enable = on;
    gainsEdit.Enable = on;
    depthEdit.Enable = ~on;
    rangeEdit.Enable = ~on;
    sedimentDrop.Enable = ~on;
end
onChMode();

%% Right: plot + table
rightGrid = uigridlayout(grid, [2 1], "RowHeight", {"1x", "0.8x"});
ax = uiaxes(rightGrid, "XScale", "linear", "YScale", "log", ...
    "YLim", [1e-4 1], "Box", "on", "XGrid", "on", "YGrid", "on", ...
    "FontSize", 11);
xlabel(ax, "SNR (dB)"); ylabel(ax, "BER");
title(ax, "BER vs SNR");
hold(ax, "on");
tbl = uitable(rightGrid, "ColumnName", {"均衡器", "场景"}, ...
    "ColumnWidth", {160, 70});

function onRun(~, ~)
    v = selList.Value;
    if isempty(v)
        uialert(fig, "请至少选择一个均衡方式。", "无选择");
        return;
    end
    ids = extractId(v);
    snrs = snrFromEdit.Value:snrStepEdit.Value:snrToEdit.Value;
    if isempty(snrs)
        uialert(fig, "SNR 范围无效。", "参数错误");
        return;
    end
    chOpts = struct("channelMode", chMode.Value);
    if strcmp(chMode.Value, "synthetic")
        try
            chOpts.pathDelays = parseNum(delaysEdit.Value);
            chOpts.pathGains = eval(char(["[" gainsEdit.Value "]"]));
            if isempty(chOpts.pathDelays) || isempty(chOpts.pathGains)
                error("empty parse result");
            end
        catch err
            chOpts.pathDelays = [0 1 3];
            chOpts.pathGains = [1, 0.7 * exp(1j * 0.5), 0.3 * exp(-1j * 0.8)];
            fprintf("路径参数解析失败，已回退默认信道 [0 1 3]。\n原因：%s\n时延=[%s]\n增益=[%s]\n", ...
                err.message, char(delaysEdit.Value), char(gainsEdit.Value));
            selInfo.Text = "路径参数无效，已回退默认信道";
            drawnow;
        end
    else
        chOpts.bellhopWaterDepth = depthEdit.Value;
        chOpts.bellhopRangeKm = rangeEdit.Value;
        chOpts.bellhopSediment = sedimentDrop.Value;
    end
    st.ids = ids;
    st.snrs = snrs;
    st.frames = framesEdit.Value;
    st.chOpts = chOpts;
    st.scs = unique(registry.scenario(ismember(registry.id, ids)), "stable");
    st.curS = 1;
    st.curI = 1;
    st.done = 0;
    st.total = numel(st.scs) * numel(snrs);
    st.berTable = {};
    st.cancelRequested = false;
    st.idle = false;
    cla(ax);
    legend(ax, "off");
    hold(ax, "on");
    title(ax, "BER vs SNR");
    runBtn.Text = "运行中…";
    runBtn.Enable = "off";
    cancelBtn.Enable = "on";
    selInfo.Text = "运行中…";
    drawnow;
    try
        if strcmp(sweepTimer.Running, "on")
            stop(sweepTimer);
        end
        start(sweepTimer);
    catch err
        fprintf("=== 启动失败 ===\n%s\n", getReport(err, "extended"));
        runBtn.Text = "运行仿真";
        runBtn.Enable = "on";
        cancelBtn.Enable = "off";
        uialert(fig, getReport(err, "basic"), "启动失败");
    end
end

function stepOnce(src, ~)
    if ~isfield(st, "idle") || st.idle
        return;
    end
    if st.cancelRequested
        stop(src);
        finalizeSweep("已取消");
        return;
    end
    sc = st.scs(st.curS);
    scIds = registry.id(ismember(registry.id, st.ids) & ...
        registry.scenario == sc);
    if st.curI == 1
        st.ber = nan(numel(scIds), numel(st.snrs));
    end
    i = st.curI;
    selInfo.Text = sprintf("运行中… 已完成 %d/%d 个 SNR 点（当前 %s %d dB）", ...
        st.done, st.total, sc, st.snrs(i));
    drawnow;
    if strcmp(st.chOpts.channelMode, "bellhop")
        r = run_unified_equalizer(struct("equalizers", scIds, ...
            "scenario", sc, "snrDb", st.snrs(i), "frameCount", st.frames, ...
            "makePlot", false, "channelMode", "bellhop", ...
            "bellhopOptions", rmfield(st.chOpts, "channelMode")));
    else
        r = run_unified_equalizer(struct("equalizers", scIds, ...
            "scenario", sc, "snrDb", st.snrs(i), "frameCount", st.frames, ...
            "makePlot", false, "pathDelays", st.chOpts.pathDelays, ...
            "pathGains", st.chOpts.pathGains, "channelMode", "synthetic"));
    end
    st.ber(:, i) = r.ber;
    st.done = st.done + 1;
    st.curI = st.curI + 1;
    if st.curI > numel(st.snrs)
        for k = 1:numel(scIds)
            semilogy(ax, st.snrs, max(st.ber(k, :), 1e-6), "o-", ...
                "LineWidth", 1.5, "DisplayName", scIds(k));
            st.berTable(end + 1, :) = {char(scIds(k)), char(sc), ...
                char(strjoin(compose("%.2g", st.ber(k, :)), ", "))}; %#ok<AGROW>
        end
        drawnow;
        if st.curS == numel(st.scs)
            stop(sweepTimer);
            finalizeSweep("完成");
            return;
        end
        st.curS = st.curS + 1;
        st.curI = 1;
    end
end

function finalizeSweep(msg)
    try
        if strcmp(sweepTimer.Running, "on")
            stop(sweepTimer);
        end
    catch
    end
    st.cancelRequested = false;
    st.idle = true;
    hold(ax, "off");
    legend(ax, "Location", "southwest", "Interpreter", "none", "FontSize", 9);
    title(ax, sprintf("BER vs SNR (frameCount=%d, channel=%s) - %s", ...
        st.frames, st.chOpts.channelMode, msg));
    tbl.Data = st.berTable;
    tbl.ColumnName = {"均衡器", "场景", "BER（各 SNR 点）"};
    if ~strcmp(msg, "已取消")
        outDir = fullfile(rootDir, "results", "ber_snr_curves");
        if ~exist(outDir, "dir")
            mkdir(outDir);
        end
        name = sprintf("app_ber_snr_%s.png", ...
            strrep(strjoin(st.ids, "_"), "-", "_"));
        exportgraphics(ax, fullfile(outDir, name), "Resolution", 200);
        fprintf("saved: %s\n", fullfile(outDir, name));
    end
    runBtn.Text = "运行仿真";
    runBtn.Enable = "on";
    cancelBtn.Enable = "off";
    selInfo.Text = sprintf("%s：%d 个均衡器 × %d 个 SNR 点", msg, numel(st.ids), numel(st.snrs));
    drawnow;
end
end

function ids = extractId(labels)
ids = strings(0);
for i = 1:numel(labels)
    parts = regexp(labels{i}, "^\[ch\d+/(\w+)\] (\S+)$", "tokens", "once");
    if ~isempty(parts)
        ids(end + 1) = parts{2}; %#ok<AGROW>
    end
end
ids = string(ids);
end

function v = field_default(opts, name, def)
if isfield(opts, name) && ~isempty(opts.(name))
    v = opts.(name);
else
    v = def;
end
end

function nums = parseNum(text)
toks = regexp(text, "-?\d+(\.\d+)?", "match");
nums = str2double(toks);
end
