function appFigure = launch_scfde_text_app()
%LAUNCH_SCFDE_TEXT_APP Interactive visualization of the SC-FDE text link.

stageNames = {'1 文字与帧'; '2 数字调制'; '3 通带发射'; ...
    '4 时变信道接收'; '5 UW同步与均衡'; '6 CRC与文字恢复'};
stageStatus = repmat({'等待'}, numel(stageNames), 1);
advanced = default_advanced_settings();
physical = default_physical_settings();

appFigure = uifigure("Name", "SC-FDE 水声单载波通信机", ...
    "Position", [70, 60, 1480, 860], "Color", [0.96, 0.97, 0.98]);
mainGrid = uigridlayout(appFigure, [1, 3]);
mainGrid.ColumnWidth = {292, "1x", 275};
mainGrid.ColumnSpacing = 10;
mainGrid.Padding = [10, 10, 10, 10];

%% Input and channel controls
controlPanel = uipanel(mainGrid, "Title", "发送端与信道", ...
    "FontWeight", "bold", "ForegroundColor", [0.08, 0.25, 0.34]);
controlPanel.Layout.Column = 1;
controlGrid = uigridlayout(controlPanel, [17, 1]);
controlGrid.RowHeight = {22, 94, 22, 30, 22, 30, 22, 30, 22, 30, 22, 30, ...
    34, 34, 44, 22, "1x"};
controlGrid.Padding = [12, 10, 12, 12];

uilabel(controlGrid, "Text", "输入文字", "FontWeight", "bold");
inputArea = uitextarea(controlGrid, "Value", "水声单载波通信机端到端仿真", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);

uilabel(controlGrid, "Text", "传播信道模型");
channelDropdown = uidropdown(controlGrid, ...
    "Items", {'参数化四径时变信道', 'Bellhop射线到达信道'}, ...
    "ItemsData", {'analytic', 'bellhop'}, "Value", 'analytic');

uilabel(controlGrid, "Text", "通带信噪比（dB）");
snrSpinner = uispinner(controlGrid, "Limits", [0, 40], "Value", 18, ...
    "Step", 1);

uilabel(controlGrid, "Text", "公共多普勒频移（Hz）");
dopplerSpinner = uispinner(controlGrid, "Limits", [-60, 60], ...
    "Value", 8, "Step", 1);

uilabel(controlGrid, "Text", "每帧最大尝试次数");
attemptSpinner = uispinner(controlGrid, "Limits", [1, 10], ...
    "Value", 3, "Step", 1, "RoundFractionalValues", "on");

uilabel(controlGrid, "Text", "阶段播放间隔（秒）");
delaySpinner = uispinner(controlGrid, "Limits", [0, 2], ...
    "Value", 0.35, "Step", 0.05);

physicalButton = uibutton(controlGrid, "push", "Text", "物理层参数", ...
    "ButtonPushedFcn", @open_physical_dialog, ...
    "BackgroundColor", [0.89, 0.93, 0.94]);

advancedButton = uibutton(controlGrid, "push", "Text", "高级信道与接收参数", ...
    "ButtonPushedFcn", @open_advanced_dialog, ...
    "BackgroundColor", [0.89, 0.93, 0.94]);

runButton = uibutton(controlGrid, "push", "Text", "发送并显示全流程", ...
    "FontWeight", "bold", "FontSize", 14, ...
    "BackgroundColor", [0.04, 0.48, 0.55], "FontColor", [1, 1, 1], ...
    "ButtonPushedFcn", @run_simulation);

uilabel(controlGrid, "Text", "当前帧", "FontWeight", "bold");
packetLabel = uilabel(controlGrid, "Text", "尚未发送", ...
    "VerticalAlignment", "top", "WordWrap", "on", ...
    "FontName", "Consolas", "FontSize", 12);

%% Center plots
tabGroup = uitabgroup(mainGrid);
tabGroup.Layout.Column = 2;

dataTab = uitab(tabGroup, "Title", "数据与调制");
dataGrid = uigridlayout(dataTab, [2, 1]);
dataGrid.RowHeight = {"1x", "1x"};
dataGrid.Padding = [8, 8, 8, 8];
axBits = uiaxes(dataGrid);
title(axBits, "24字节物理层数据帧");
xlabel(axBits, "比特位置（LSB优先）");
ylabel(axBits, "字节序号");
axTxConstellation = uiaxes(dataGrid);
title(axTxConstellation, "发送端数字调制星座");
xlabel(axTxConstellation, "同相");
ylabel(axTxConstellation, "正交");

waveTab = uitab(tabGroup, "Title", "收发波形");
waveGrid = uigridlayout(waveTab, [2, 1]);
waveGrid.RowHeight = {"1x", "1x"};
waveGrid.Padding = [8, 8, 8, 8];
axTxWave = uiaxes(waveGrid);
title(axTxWave, "DAC发射信号：96 kHz / 12 kHz载波");
xlabel(axTxWave, "时间（ms）");
ylabel(axTxWave, "幅度");
axRxWave = uiaxes(waveGrid);
title(axRxWave, "ADC接收信号：48 kHz / 时变多径加噪");
xlabel(axRxWave, "时间（ms）");
ylabel(axRxWave, "ADC中心化幅度");

receiverTab = uitab(tabGroup, "Title", "同步与解调");
receiverGrid = uigridlayout(receiverTab, [2, 1]);
receiverGrid.RowHeight = {"1x", "1x"};
receiverGrid.Padding = [8, 8, 8, 8];
axSync = uiaxes(receiverGrid);
title(axSync, "双UW归一化同步度量");
xlabel(axSync, "候选帧起始采样点");
ylabel(axSync, "同步度量");
axRxConstellation = uiaxes(receiverGrid);
title(axRxConstellation, "MMSE频域均衡后的接收星座");
xlabel(axRxConstellation, "同相");
ylabel(axRxConstellation, "正交");

%% Receiver state and output
resultPanel = uipanel(mainGrid, "Title", "接收端", ...
    "FontWeight", "bold", "ForegroundColor", [0.08, 0.25, 0.34]);
resultPanel.Layout.Column = 3;
resultGrid = uigridlayout(resultPanel, [8, 1]);
resultGrid.RowHeight = {32, 22, 190, 22, 110, 22, "1x", 30};
resultGrid.Padding = [10, 10, 10, 10];

statusGrid = uigridlayout(resultGrid, [1, 2]);
statusGrid.ColumnWidth = {28, "1x"};
statusGrid.Padding = [0, 0, 0, 0];
statusLamp = uilamp(statusGrid, "Color", [0.55, 0.58, 0.60]);
statusText = uilabel(statusGrid, "Text", "等待输入", "FontWeight", "bold");

uilabel(resultGrid, "Text", "处理阶段", "FontWeight", "bold");
stageTable = uitable(resultGrid, "Data", [stageNames, stageStatus], ...
    "ColumnName", {"阶段", "状态"}, "RowName", {}, ...
    "ColumnWidth", {145, 72});

uilabel(resultGrid, "Text", "接收文字", "FontWeight", "bold");
outputArea = uitextarea(resultGrid, "Editable", "off", ...
    "Value", "", "FontName", "Microsoft YaHei", "FontSize", 14);

uilabel(resultGrid, "Text", "运行记录", "FontWeight", "bold");
logArea = uitextarea(resultGrid, "Editable", "off", ...
    "Value", "等待发送。", "FontName", "Consolas", "FontSize", 11);

summaryLabel = uilabel(resultGrid, "Text", "", "WordWrap", "on", ...
    "FontName", "Consolas");

initialize_axes();

    function run_simulation(~, ~)
        runButton.Enable = "off";
        cleanup = onCleanup(@enable_run_button); %#ok<NASGU>
        statusLamp.Color = [0.95, 0.64, 0.10];
        statusText.Text = "正在处理";
        outputArea.Value = "";
        summaryLabel.Text = "";
        stageTable.Data = [stageNames, repmat({'等待'}, numel(stageNames), 1)];
        logArea.Value = "开始新的端到端传输...";
        initialize_axes();
        drawnow;

        try
            textValue = strjoin(string(inputArea.Value), newline);
            options.snrDb = snrSpinner.Value;
            options.channelModel = channelDropdown.Value;
            options.fftSize = physical.fftSize;
            options.uwLength = physical.uwLength;
            options.modulation = physical.modulation;
            options.ldpcEnabled = strcmpi(char(physical.modulation), 'QPSK') && ...
                physical.fftSize - physical.uwLength == 96;
            options.symbolRate = physical.symbolRate;
            options.carrierHz = physical.carrierHz;
            options.txSampleRate = physical.txSampleRate;
            options.rxSampleRate = physical.rxSampleRate;
            options.pathDelaysMs = advanced.pathDelaysMs;
            options.pathGains = advanced.pathMagnitudes .* ...
                exp(1j * advanced.pathPhasesDeg * pi / 180);
            if advanced.perPathDoppler && strcmp(channelDropdown.Value, "analytic")
                options.dopplerHz = advanced.pathDopplerHz;
            else
                options.dopplerHz = dopplerSpinner.Value;
            end
            options.maxFrameAttempts = round(attemptSpinner.Value);
            options.leadingSamples = advanced.leadingSamples;
            options.syncThreshold = advanced.syncThreshold;
            options.channelTaps = advanced.channelTaps;
            options.txAmplitude = advanced.txAmplitude;
            options.randomSeed = advanced.randomSeed;
            options.bellhopRoot = advanced.bellhopRoot;
            options.bellhopWaterDepth = advanced.bellhopWaterDepth;
            options.bellhopSourceDepth = advanced.bellhopSourceDepth;
            options.bellhopReceiverDepth = advanced.bellhopReceiverDepth;
            options.bellhopRangeKm = advanced.bellhopRangeKm;
            options.bellhopMaxPaths = advanced.bellhopMaxPaths;
            options.bellhopMaxSpreadMs = advanced.bellhopMaxSpreadMs;
            options.makePlot = false;
            simulation = run_text_scfde_demo(textValue, options);
            firstFrame = simulation.frames(1);

            update_stage(1, "完成");
            show_packet(firstFrame);
            packetLabel.Text = sprintf("帧数: %d\n序号: %d\n载荷: %d 字节\nCRC: %s", ...
                numel(simulation.frames), firstFrame.sequence, ...
                double(firstFrame.txPacket(3)), crc_label(firstFrame.crcOk));
            append_log(sprintf("UTF-8编码得到 %d 字节，拆分为 %d 帧。", ...
                numel(simulation.txBytes), numel(simulation.frames)));
            wait_for_stage();

            update_stage(2, "完成");
            show_tx_constellation(firstFrame, simulation.config);
            append_log(sprintf("第1帧映射为 %d 个%s数据符号。", ...
                numel(firstFrame.txDataSymbols), simulation.config.modulation));
            wait_for_stage();

            update_stage(3, "完成");
            tabGroup.SelectedTab = waveTab;
            show_tx_wave(firstFrame, simulation.config);
            append_log("生成96 kHz、12 kHz载波的DAC发射波形。");
            wait_for_stage();

            update_stage(4, "完成");
            show_rx_wave(firstFrame, simulation.config);
            if simulation.config.channelModel == "bellhop"
                append_log(sprintf("Bellhop生成%d条射线，合并为%d个离散路径。", ...
                    simulation.config.bellhopInfo.totalArrivalCount, ...
                    simulation.config.bellhopInfo.discretePathCount));
            else
                append_log(sprintf("通过%d径参数化时变信道。", ...
                    numel(simulation.config.pathGains)));
            end
            append_log(sprintf("接收通带信噪比为%.1f dB。", simulation.config.snrDb));
            wait_for_stage();

            update_stage(5, "完成");
            tabGroup.SelectedTab = receiverTab;
            show_receiver(firstFrame, simulation.config);
            append_log(sprintf("同步峰值 %.3f，帧起点 %d，估计频偏 %.2f Hz。", ...
                firstFrame.syncMetric, firstFrame.frameStartSample, ...
                firstFrame.frequencyOffsetHz));
            wait_for_stage();

            if simulation.success
                update_stage(6, "通过");
                statusLamp.Color = [0.12, 0.66, 0.38];
                statusText.Text = "接收成功";
                outputArea.Value = cellstr(simulation.outputText);
                append_log("所有帧CRC通过，UTF-8文字重组完成。");
            else
                update_stage(6, "失败");
                statusLamp.Color = [0.80, 0.18, 0.16];
                statusText.Text = "接收失败";
                outputArea.Value = cellstr(simulation.outputText);
                failedFrames = simulation.frames(~[simulation.frames.valid]);
                knownErrors = [failedFrames.bitErrors];
                knownErrors = knownErrors(isfinite(knownErrors));
                if ~isempty(knownErrors)
                    append_log(sprintf("CRC失败帧检测到至少%d个硬判决比特错误。", ...
                        sum(knownErrors)));
                else
                    append_log("存在同步、帧头或CRC错误。");
                end
            end
            summaryLabel.Text = sprintf("TX %d bytes | RX %d bytes | %s", ...
                numel(simulation.txBytes), numel(simulation.rxBytes), ...
                upper(char(pass_fail_local(simulation.success))));
        catch errorInfo
            statusLamp.Color = [0.80, 0.18, 0.16];
            statusText.Text = "程序错误";
            append_log(errorInfo.message);
            uialert(appFigure, errorInfo.message, "仿真错误");
        end
    end

    function initialize_axes()
        axesList = [axBits, axTxConstellation, axTxWave, axRxWave, ...
            axSync, axRxConstellation];
        for axisHandle = axesList
            cla(axisHandle);
            grid(axisHandle, "on");
            axisHandle.Color = [0.985, 0.99, 0.99];
        end
    end

    function open_physical_dialog(~, ~)
        dialog = uifigure("Name", "物理层参数", "Position", [470, 170, 540, 500], ...
            "WindowStyle", "modal", "Color", [0.97, 0.98, 0.98]);
        layout = uigridlayout(dialog, [9, 2]);
        layout.ColumnWidth = {210, "1x"};
        layout.RowHeight = {38, 38, 38, 38, 38, 38, 38, 72, 46};
        layout.Padding = [16, 14, 16, 14];

        uilabel(layout, "Text", "调制方式");
        fields.modulation = uidropdown(layout, "Items", {'BPSK', 'QPSK', '16QAM'});
        uilabel(layout, "Text", "频域均衡FFT长度");
        fields.fftSize = uidropdown(layout, ...
            "Items", {'64', '128', '256', '512', '1024'}, ...
            "ItemsData", [64, 128, 256, 512, 1024]);
        uilabel(layout, "Text", "UW长度（符号）");
        fields.uwLength = uidropdown(layout, ...
            "Items", {'8', '16', '32', '64', '128', '256'}, ...
            "ItemsData", [8, 16, 32, 64, 128, 256]);
        uilabel(layout, "Text", "符号率（symbol/s）");
        fields.symbolRate = uieditfield(layout, "numeric", "Limits", [250, 20000]);
        uilabel(layout, "Text", "通带载波（Hz）");
        fields.carrierHz = uieditfield(layout, "numeric", "Limits", [100, 100000]);
        uilabel(layout, "Text", "发射采样率（Hz）");
        fields.txSampleRate = uieditfield(layout, "numeric", "Limits", [1000, 1000000]);
        uilabel(layout, "Text", "接收采样率（Hz）");
        fields.rxSampleRate = uieditfield(layout, "numeric", "Limits", [1000, 1000000]);

        preview = uilabel(layout, "Text", "", "WordWrap", "on", ...
            "FontName", "Consolas", "FontColor", [0.04, 0.48, 0.55]);
        preview.Layout.Row = 8;
        preview.Layout.Column = [1, 2];

        buttons = uigridlayout(layout, [1, 3]);
        buttons.Layout.Row = 9;
        buttons.Layout.Column = [1, 2];
        buttons.ColumnWidth = {"1x", "1x", "1x"};
        buttons.Padding = [0, 4, 0, 0];
        uibutton(buttons, "push", "Text", "恢复默认", ...
            "ButtonPushedFcn", @(~, ~)populate_physical_fields(fields, preview, ...
                default_physical_settings()));
        uibutton(buttons, "push", "Text", "取消", ...
            "ButtonPushedFcn", @(~, ~)close(dialog));
        uibutton(buttons, "push", "Text", "应用", ...
            "BackgroundColor", [0.04, 0.48, 0.55], "FontColor", [1, 1, 1], ...
            "ButtonPushedFcn", @(~, ~)save_physical_dialog(dialog, fields));

        controls = {fields.modulation, fields.fftSize, fields.uwLength, ...
            fields.symbolRate, fields.carrierHz, fields.txSampleRate, fields.rxSampleRate};
        for controlIndex = 1:numel(controls)
            controls{controlIndex}.ValueChangedFcn = ...
                @(~, ~)update_physical_preview(fields, preview);
        end
        populate_physical_fields(fields, preview, physical);
    end

    function populate_physical_fields(fields, preview, settings)
        fields.modulation.Value = char(settings.modulation);
        fields.fftSize.Value = settings.fftSize;
        fields.uwLength.Value = settings.uwLength;
        fields.symbolRate.Value = settings.symbolRate;
        fields.carrierHz.Value = settings.carrierHz;
        fields.txSampleRate.Value = settings.txSampleRate;
        fields.rxSampleRate.Value = settings.rxSampleRate;
        update_physical_preview(fields, preview);
    end

    function update_physical_preview(fields, preview)
        try
            candidate = physical_from_fields(fields);
            derived = validate_physical_settings(candidate);
            preview.Text = sprintf(['数据符号: %d | 包长: %d bytes | 最大载荷: %d bytes\n' ...
                'UW保护: %.3f ms | 帧长: %d symbols | 时长: %.2f ms | TX/RX采样: %d/%d'], ...
                derived.dataSymbols, derived.packetBytes, derived.maxPayload, ...
                1000*candidate.uwLength/candidate.symbolRate, derived.frameSymbols, ...
                1000*derived.frameSymbols/candidate.symbolRate, ...
                derived.txSamplesPerSymbol, derived.rxSamplesPerSymbol);
            preview.FontColor = [0.04, 0.48, 0.55];
        catch errorInfo
            preview.Text = errorInfo.message;
            preview.FontColor = [0.80, 0.18, 0.16];
        end
    end

    function save_physical_dialog(dialog, fields)
        try
            candidate = physical_from_fields(fields);
            validate_physical_settings(candidate);
            uwDurationMs = candidate.uwLength/candidate.symbolRate*1000;
            requiredDelayMs = selected_channel_delay(advanced, channelDropdown.Value);
            if requiredDelayMs >= uwDurationMs
                if advanced.autoExpandDelay
                    candidate = expand_physical_for_delay(candidate, requiredDelayMs);
                else
                    error(['当前信道最大时延%.3f ms超过新UW保护时间%.3f ms。' ...
                        '请增大UW、降低符号率，或在信道参数中启用自动扩展。'], ...
                        requiredDelayMs, uwDurationMs);
                end
            end
            requiredTaps = ceil(requiredDelayMs*candidate.symbolRate/1000) + 1;
            if advanced.autoExpandDelay
                advanced.channelTaps = min(candidate.uwLength, ...
                    max(advanced.channelTaps, requiredTaps));
            else
                assert(advanced.channelTaps >= requiredTaps, ...
                    "信道抽头数不足以覆盖当前最大多径时延。");
            end
            advanced.bellhopMaxSpreadMs = min(advanced.bellhopMaxSpreadMs, ...
                0.95*uwDurationMs);
            physical = candidate;
            append_log(sprintf("物理层已更新：%s，FFT %d，UW %d，%.0f symbol/s。", ...
                physical.modulation, physical.fftSize, physical.uwLength, ...
                physical.symbolRate));
            close(dialog);
        catch errorInfo
            uialert(dialog, errorInfo.message, "物理层参数无效");
        end
    end

    function settings = physical_from_fields(fields)
        settings.modulation = string(fields.modulation.Value);
        settings.fftSize = fields.fftSize.Value;
        settings.uwLength = fields.uwLength.Value;
        settings.symbolRate = fields.symbolRate.Value;
        settings.carrierHz = fields.carrierHz.Value;
        settings.txSampleRate = fields.txSampleRate.Value;
        settings.rxSampleRate = fields.rxSampleRate.Value;
    end

    function open_advanced_dialog(~, ~)
        dialog = uifigure("Name", "高级参数", "Position", [420, 70, 600, 700], ...
            "WindowStyle", "modal", "Color", [0.97, 0.98, 0.98]);
        gridLayout = uigridlayout(dialog, [20, 2]);
        gridLayout.ColumnWidth = {220, "1x"};
        gridLayout.RowHeight = {30, 28, 28, 28, 28, 28, 28, 28, 28, 28, ...
            24, 28, 28, 28, 28, 28, 28, 28, 30, 40};
        gridLayout.Padding = [14, 12, 14, 12];

        profile = uilabel(gridLayout, "Text", ...
            sprintf("当前物理层：FFT %d｜UW %d｜%s｜%g ksym/s｜%g kHz", ...
                physical.fftSize, physical.uwLength, physical.modulation, ...
                physical.symbolRate/1000, physical.carrierHz/1000), ...
            "FontWeight", "bold", "FontColor", [0.04, 0.48, 0.55]);
        profile.Layout.Row = 1;
        profile.Layout.Column = [1, 2];

        uilabel(gridLayout, "Text", "多径时延（ms，逗号分隔）");
        fields.delays = uieditfield(gridLayout, "text");
        uilabel(gridLayout, "Text", "多径幅度（逗号分隔）");
        fields.magnitudes = uieditfield(gridLayout, "text");
        uilabel(gridLayout, "Text", "多径相位（度，逗号分隔）");
        fields.phases = uieditfield(gridLayout, "text");
        fields.perPath = uicheckbox(gridLayout, "Text", "启用每径独立多普勒");
        fields.doppler = uieditfield(gridLayout, "text");
        uilabel(gridLayout, "Text", "前导空白（48 kHz采样点）");
        fields.leading = uispinner(gridLayout, "Limits", [0, 1000], "Step", 1);
        uilabel(gridLayout, "Text", "UW同步门限");
        fields.threshold = uieditfield(gridLayout, "numeric", "Limits", [0.01, 0.99]);
        uilabel(gridLayout, "Text", "保留信道冲激响应抽头数");
        fields.taps = uispinner(gridLayout, "Limits", [1, 128], "Step", 1, ...
            "RoundFractionalValues", "on");
        uilabel(gridLayout, "Text", "DAC中心化发射幅度");
        fields.amplitude = uispinner(gridLayout, "Limits", [100, 1400], "Step", 50);
        uilabel(gridLayout, "Text", "随机种子");
        fields.seed = uieditfield(gridLayout, "numeric", "Limits", [0, 2^32-1]);

        bellhopHeader = uilabel(gridLayout, "Text", "Bellhop环境", ...
            "FontWeight", "bold", "FontColor", [0.86, 0.34, 0.16]);
        bellhopHeader.Layout.Row = 11;
        bellhopHeader.Layout.Column = [1, 2];
        uilabel(gridLayout, "Text", "Acoustics Toolbox根目录");
        fields.bellhopRoot = uieditfield(gridLayout, "text");
        uilabel(gridLayout, "Text", "海水深度（m）");
        fields.waterDepth = uieditfield(gridLayout, "numeric", "Limits", [10, 10000]);
        uilabel(gridLayout, "Text", "发射机深度（m）");
        fields.sourceDepth = uieditfield(gridLayout, "numeric", "Limits", [0.1, 9999]);
        uilabel(gridLayout, "Text", "接收机深度（m）");
        fields.receiverDepth = uieditfield(gridLayout, "numeric", "Limits", [0.1, 9999]);
        uilabel(gridLayout, "Text", "水平距离（km）");
        fields.rangeKm = uieditfield(gridLayout, "numeric", "Limits", [0.001, 1000]);
        uilabel(gridLayout, "Text", "最多保留Bellhop射线数");
        fields.maxPaths = uispinner(gridLayout, "Limits", [1, 100], "Step", 1, ...
            "RoundFractionalValues", "on");
        uilabel(gridLayout, "Text", "最大相对时延扩展（ms）");
        fields.maxSpread = uieditfield(gridLayout, "numeric", "Limits", [0.01, 100]);

        fields.autoExpand = uicheckbox(gridLayout, ...
            "Text", "时延超限时自动扩大UW和FFT（保持循环卷积条件）", ...
            "FontWeight", "bold");
        fields.autoExpand.Layout.Row = 19;
        fields.autoExpand.Layout.Column = [1, 2];

        buttonGrid = uigridlayout(gridLayout, [1, 3]);
        buttonGrid.Layout.Row = 20;
        buttonGrid.Layout.Column = [1, 2];
        buttonGrid.ColumnWidth = {"1x", "1x", "1x"};
        buttonGrid.Padding = [0, 4, 0, 0];
        uibutton(buttonGrid, "push", "Text", "恢复默认", ...
            "ButtonPushedFcn", @(~, ~)populate_advanced_fields(fields, ...
                default_advanced_settings()));
        uibutton(buttonGrid, "push", "Text", "取消", ...
            "ButtonPushedFcn", @(~, ~)close(dialog));
        uibutton(buttonGrid, "push", "Text", "应用", ...
            "BackgroundColor", [0.04, 0.48, 0.55], "FontColor", [1, 1, 1], ...
            "ButtonPushedFcn", @(~, ~)save_advanced_dialog(dialog, fields));

        populate_advanced_fields(fields, advanced);
    end

    function populate_advanced_fields(fields, settings)
        fields.delays.Value = numeric_list_text(settings.pathDelaysMs);
        fields.magnitudes.Value = numeric_list_text(settings.pathMagnitudes);
        fields.phases.Value = numeric_list_text(settings.pathPhasesDeg);
        fields.perPath.Value = settings.perPathDoppler;
        fields.doppler.Value = numeric_list_text(settings.pathDopplerHz);
        fields.leading.Value = settings.leadingSamples;
        fields.threshold.Value = settings.syncThreshold;
        fields.taps.Value = settings.channelTaps;
        fields.amplitude.Value = settings.txAmplitude;
        fields.seed.Value = settings.randomSeed;
        fields.bellhopRoot.Value = settings.bellhopRoot;
        fields.waterDepth.Value = settings.bellhopWaterDepth;
        fields.sourceDepth.Value = settings.bellhopSourceDepth;
        fields.receiverDepth.Value = settings.bellhopReceiverDepth;
        fields.rangeKm.Value = settings.bellhopRangeKm;
        fields.maxPaths.Value = settings.bellhopMaxPaths;
        fields.maxSpread.Value = settings.bellhopMaxSpreadMs;
        fields.autoExpand.Value = settings.autoExpandDelay;
    end

    function save_advanced_dialog(dialog, fields)
        try
            candidate.pathDelaysMs = parse_numeric_list(fields.delays.Value);
            candidate.pathMagnitudes = parse_numeric_list(fields.magnitudes.Value);
            candidate.pathPhasesDeg = parse_numeric_list(fields.phases.Value);
            candidate.pathDopplerHz = parse_numeric_list(fields.doppler.Value);
            candidate.perPathDoppler = logical(fields.perPath.Value);
            candidate.leadingSamples = round(fields.leading.Value);
            candidate.syncThreshold = fields.threshold.Value;
            candidate.channelTaps = round(fields.taps.Value);
            candidate.txAmplitude = fields.amplitude.Value;
            candidate.randomSeed = round(fields.seed.Value);
            candidate.bellhopRoot = string(fields.bellhopRoot.Value);
            candidate.bellhopWaterDepth = fields.waterDepth.Value;
            candidate.bellhopSourceDepth = fields.sourceDepth.Value;
            candidate.bellhopReceiverDepth = fields.receiverDepth.Value;
            candidate.bellhopRangeKm = fields.rangeKm.Value;
            candidate.bellhopMaxPaths = round(fields.maxPaths.Value);
            candidate.bellhopMaxSpreadMs = fields.maxSpread.Value;
            candidate.autoExpandDelay = logical(fields.autoExpand.Value);

            pathCount = numel(candidate.pathDelaysMs);
            assert(pathCount >= 1, "至少需要一条传播路径。");
            assert(numel(candidate.pathMagnitudes) == pathCount, ...
                "多径时延和幅度的数量必须相同。");
            assert(numel(candidate.pathPhasesDeg) == pathCount, ...
                "多径时延和相位的数量必须相同。");
            assert(numel(candidate.pathDopplerHz) == pathCount, ...
                "多径时延和每径多普勒的数量必须相同。");
            assert(all(candidate.pathDelaysMs >= 0), "多径时延不能为负数。");
            assert(all(candidate.pathMagnitudes >= 0), "多径幅度不能为负数。");
            assert(any(candidate.pathMagnitudes > 0), "至少一条路径的幅度必须大于0。");
            requiredDelayMs = selected_channel_delay(candidate, channelDropdown.Value);
            uwDurationMs = physical.uwLength/physical.symbolRate*1000;
            if requiredDelayMs >= uwDurationMs
                if candidate.autoExpandDelay
                    oldUw = physical.uwLength;
                    oldFft = physical.fftSize;
                    physical = expand_physical_for_delay(physical, requiredDelayMs);
                    append_log(sprintf(['时延保护自动扩展：UW %d→%d，FFT %d→%d，' ...
                        '新限制 %.3f ms。'], oldUw, physical.uwLength, ...
                        oldFft, physical.fftSize, ...
                        1000*physical.uwLength/physical.symbolRate));
                else
                    error(['最大时延 %.3f ms 超过UW保护时间 %.3f ms。' ...
                        '请增大UW、降低符号率，或启用自动扩展。'], ...
                        requiredDelayMs, uwDurationMs);
                end
            end
            requiredTaps = ceil(requiredDelayMs*physical.symbolRate/1000) + 1;
            if candidate.autoExpandDelay
                candidate.channelTaps = min(physical.uwLength, ...
                    max(candidate.channelTaps, requiredTaps));
            else
                assert(candidate.channelTaps >= requiredTaps, ...
                    "信道抽头数不足；至少需要%d个抽头。", requiredTaps);
            end
            assert(candidate.bellhopSourceDepth < candidate.bellhopWaterDepth, ...
                "Bellhop发射机深度必须小于海水深度。");
            assert(candidate.bellhopReceiverDepth < candidate.bellhopWaterDepth, ...
                "Bellhop接收机深度必须小于海水深度。");
            assert(isfile(fullfile(candidate.bellhopRoot, ...
                "windows-bin-20201102", "bellhop.exe")), ...
                "指定目录中没有找到bellhop.exe。");
            advanced = candidate;
            append_log("高级信道与接收参数已更新。");
            close(dialog);
        catch errorInfo
            uialert(dialog, errorInfo.message, "参数无效");
        end
    end

    function show_packet(frame)
        tabGroup.SelectedTab = dataTab;
        bitMatrix = reshape(double(frame.txBits), 8, []).';
        imagesc(axBits, 0:7, 1:size(bitMatrix, 1), bitMatrix);
        colormap(axBits, [0.92, 0.95, 0.96; 0.04, 0.48, 0.55]);
        clim(axBits, [0, 1]);
        axBits.YDir = "reverse";
        xticks(axBits, 0:7);
        yticks(axBits, 1:2:24);
        title(axBits, sprintf("%d字节帧：A5 5A %02X %02X ... CRC %02X %02X", ...
            numel(frame.txPacket), ...
            frame.txPacket(3), frame.txPacket(4), ...
            frame.txPacket(end-1), frame.txPacket(end)));
    end

    function show_tx_constellation(frame, cfg)
        scatter(axTxConstellation, real(frame.txDataSymbols), ...
            imag(frame.txDataSymbols), 30, [0.04, 0.48, 0.55], "filled");
        axis(axTxConstellation, "equal");
        xlim(axTxConstellation, [-1.5, 1.5]);
        ylim(axTxConstellation, [-1.5, 1.5]);
        grid(axTxConstellation, "on");
        title(axTxConstellation, sprintf("%s发送星座", cfg.modulation));
    end

    function show_tx_wave(frame, cfg)
        waveform = frame.channel.txPassband96k;
        t = (0:numel(waveform)-1) / cfg.txSampleRate * 1000;
        plot(axTxWave, t, waveform, "Color", [0.04, 0.48, 0.55], ...
            "LineWidth", 0.7);
        xlim(axTxWave, [0, min(12, t(end))]);
        grid(axTxWave, "on");
        title(axTxWave, sprintf("DAC发射：%.0f kHz采样 / %.1f kHz载波", ...
            cfg.txSampleRate/1000, cfg.carrierHz/1000));
    end

    function show_rx_wave(frame, cfg)
        waveform = frame.channel.noisyCapture;
        t = (0:numel(waveform)-1) / cfg.rxSampleRate * 1000;
        plot(axRxWave, t, waveform, "Color", [0.86, 0.34, 0.16], ...
            "LineWidth", 0.7);
        xlim(axRxWave, [0, t(end)]);
        grid(axRxWave, "on");
        title(axRxWave, sprintf("ADC接收：%.0f kHz采样 / %s", ...
            cfg.rxSampleRate/1000, cfg.channelModel));
    end

    function show_receiver(frame, cfg)
        [samples, order] = sort(frame.metricSamples);
        plot(axSync, samples, frame.metricValues(order), ...
            "Color", [0.04, 0.48, 0.55], "LineWidth", 1.2);
        hold(axSync, "on");
        yline(axSync, cfg.syncThreshold, "--", "门限", ...
            "Color", [0.45, 0.47, 0.48]);
        xline(axSync, frame.frameStartSample, ":", "检测起点", ...
            "Color", [0.86, 0.34, 0.16]);
        hold(axSync, "off");
        grid(axSync, "on");

        scatter(axRxConstellation, real(frame.equalizedSymbols), ...
            imag(frame.equalizedSymbols), 22, [0.86, 0.34, 0.16], "filled");
        axis(axRxConstellation, "equal");
        grid(axRxConstellation, "on");
        title(axRxConstellation, sprintf("MMSE-FDE后的%s星座", cfg.modulation));
    end

    function update_stage(index, status)
        data = stageTable.Data;
        data{index, 2} = char(status);
        stageTable.Data = data;
        drawnow;
    end

    function append_log(message)
        values = string(logArea.Value);
        values(end+1) = string(message);
        logArea.Value = cellstr(values);
        drawnow;
    end

    function wait_for_stage()
        drawnow;
        pause(delaySpinner.Value);
    end

    function enable_run_button()
        if isvalid(runButton)
            runButton.Enable = "on";
        end
    end
end

function settings = default_advanced_settings()
settings.pathDelaysMs = [0, 0.5, 1.0, 2.0];
settings.pathMagnitudes = [1.0, 0.25, 0.12, 0.06];
settings.pathPhasesDeg = [0, 40, -63, 115];
settings.pathDopplerHz = [8, 8, 8, 8];
settings.perPathDoppler = false;
settings.leadingSamples = 173;
settings.syncThreshold = 0.18;
settings.channelTaps = 28;
settings.txAmplitude = 700;
settings.randomSeed = 20260723;
settings.bellhopRoot = "D:\MATLAB\bellhop_modern";
settings.bellhopWaterDepth = 100;
settings.bellhopSourceDepth = 20;
settings.bellhopReceiverDepth = 30;
settings.bellhopRangeKm = 1.0;
settings.bellhopMaxPaths = 12;
settings.bellhopMaxSpreadMs = 7.5;
settings.autoExpandDelay = true;
end

function settings = default_physical_settings()
settings.modulation = "QPSK";
settings.fftSize = 128;
settings.uwLength = 32;
settings.symbolRate = 4000;
settings.carrierHz = 12000;
settings.txSampleRate = 96000;
settings.rxSampleRate = 48000;
end

function derived = validate_physical_settings(settings)
switch upper(string(settings.modulation))
    case "BPSK"
        bitsPerSymbol = 1;
    case "QPSK"
        bitsPerSymbol = 2;
    case "16QAM"
        bitsPerSymbol = 4;
    otherwise
        error("不支持的调制方式。");
end
assert(settings.uwLength < settings.fftSize, "UW长度必须小于FFT长度。");
assert(mod(log2(settings.fftSize), 1) == 0 && ...
    mod(log2(settings.uwLength), 1) == 0, "FFT和UW长度必须是2的整数次幂。");
derived.dataSymbols = settings.fftSize - settings.uwLength;
derived.ldpcEnabled = strcmpi(char(settings.modulation), 'QPSK') && derived.dataSymbols == 96;
if derived.ldpcEnabled
    derived.packetBytes = 16;
else
    derived.packetBytes = derived.dataSymbols * bitsPerSymbol / 8;
end
derived.maxPayload = derived.packetBytes - 6;
derived.frameSymbols = settings.fftSize + 2*settings.uwLength;
derived.txSamplesPerSymbol = settings.txSampleRate / settings.symbolRate;
derived.rxSamplesPerSymbol = settings.rxSampleRate / settings.symbolRate;
assert(mod(derived.packetBytes, 1) == 0 && derived.maxPayload >= 1, ...
    "该组合不能形成包含帧头和CRC的整字节数据包。");
assert(mod(derived.txSamplesPerSymbol, 1) == 0 && ...
    mod(derived.rxSamplesPerSymbol, 1) == 0, ...
    "发射和接收采样率都必须是符号率的整数倍。");
assert(settings.txSampleRate >= settings.rxSampleRate && ...
    mod(settings.txSampleRate/settings.rxSampleRate, 1) == 0, ...
    "发射采样率与接收采样率之比必须是正整数。");
assert(settings.carrierHz + settings.symbolRate < settings.rxSampleRate/2, ...
    "载波频率加符号率必须低于接收端奈奎斯特频率。");
end

function settings = expand_physical_for_delay(settings, requiredDelayMs)
requiredSymbols = ceil(requiredDelayMs * settings.symbolRate / 1000) + 1;
allowedUw = [8, 16, 32, 64, 128, 256];
newUw = allowedUw(find(allowedUw >= requiredSymbols, 1, "first"));
assert(~isempty(newUw), ...
    "所需UW超过256符号；请降低符号率或缩短信道时延窗口。");
settings.uwLength = newUw;
settings.fftSize = max(settings.fftSize, 4*newUw);
assert(settings.fftSize <= 1024, "自动扩展后的FFT长度超过1024。");
validate_physical_settings(settings);
end

function delayMs = selected_channel_delay(settings, channelModel)
if strcmp(char(channelModel), 'bellhop')
    delayMs = settings.bellhopMaxSpreadMs;
else
    delayMs = max(settings.pathDelaysMs);
end
end

function values = parse_numeric_list(textValue)
normalized = strrep(strrep(char(textValue), ',', ' '), ';', ' ');
values = sscanf(normalized, '%f').';
assert(~isempty(values) && all(isfinite(values)), "参数列表中没有有效数字。");
end

function textValue = numeric_list_text(values)
textValue = char(strjoin(compose('%.6g', values), ', '));
end

function label = crc_label(isValid)
if isValid
    label = "PASS";
else
    label = "FAIL";
end
end

function label = pass_fail_local(success)
if success
    label = "pass";
else
    label = "fail";
end
end
