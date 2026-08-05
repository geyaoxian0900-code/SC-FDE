function figurePaths = visualize_text_link_stages(frame, cfg)
%VISUALIZE_TEXT_LINK_STAGES Export detailed transmitter-to-decoder figures.

resultDir = fullfile(fileparts(mfilename("fullpath")), "results", "text_link_stages");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

colors.blue = [0, 114, 178] / 255;
colors.orange = [230, 159, 0] / 255;
colors.green = [0, 158, 115] / 255;
colors.red = [213, 94, 0] / 255;
colors.sky = [86, 180, 233] / 255;
colors.purple = [204, 121, 167] / 255;
colors.gray = [0.35, 0.35, 0.35];

figurePaths = strings(1, 4);
figurePaths(1) = plot_digital_framing(frame, cfg, colors, resultDir);
figurePaths(2) = plot_transmit_channel(frame, cfg, colors, resultDir);
figurePaths(3) = plot_synchronization_estimation(frame, cfg, colors, resultDir);
figurePaths(4) = plot_equalization_decoding(frame, cfg, colors, resultDir);
end

function path = plot_digital_framing(frame, cfg, colors, resultDir)
fig = new_figure("数字组帧与调制");
layout = tiledlayout(fig, 3, 2, "TileSpacing", "compact", "Padding", "compact");
title(layout, "数字信源、信道编码、星座调制与 UW 物理帧");

ax = nexttile(layout);
categories = [ones(1, 4), 2 * ones(1, cfg.maxPayload), 3, 3];
imagesc(ax, categories);
colormap(ax, [colors.sky; colors.green; colors.orange]);
set(ax, "YTick", [], "XTick", 1:numel(frame.txPacket));
xlabel(ax, "数据包字节序号");
title(ax, "数据包字节：包头 | 载荷区 | CRC16");
for index = 1:numel(frame.txPacket)
    text(ax, index, 1, sprintf("%02X", frame.txPacket(index)), ...
        "HorizontalAlignment", "center", "FontName", "Consolas", ...
        "FontSize", 8, "Color", "k");
end
panel_label(ax, "A");

ax = nexttile(layout);
bitMatrix = reshape(double(frame.txPacketBits), 8, []);
imagesc(ax, bitMatrix);
colormap(ax, [1, 1, 1; colors.blue]);
set(ax, "YDir", "normal", "YTick", 1:8, "YTickLabel", 0:7, ...
    "XTick", 1:numel(frame.txPacket));
xlabel(ax, "数据包字节序号");
ylabel(ax, "位序号（最低有效位优先）");
title(ax, sprintf("信息位，k = %d", numel(frame.txPacketBits)));
panel_label(ax, "B");

ax = nexttile(layout);
codeMatrix = reshape(double(frame.txCodeBits), 64, []).';
imagesc(ax, codeMatrix);
colormap(ax, [1, 1, 1; colors.red]);
set(ax, "YDir", "normal", "YTick", 1:size(codeMatrix, 1), ...
    "YTickLabel", ["信息位 1-64", "信息位 65-128", "校验位 1-64"]);
xlabel(ax, "每组内的比特序号");
title(ax, sprintf("系统型 LDPC(%d,%d)，码率 %.3f", ...
    cfg.ldpcN, cfg.ldpcK, cfg.ldpcRate));
panel_label(ax, "C");

ax = nexttile(layout);
scatter(ax, real(frame.txDataSymbols), imag(frame.txDataSymbols), 24, ...
    1:numel(frame.txDataSymbols), "filled");
hold(ax, "on");
plot(ax, [-1, 1, -1, 1], [-1, -1, 1, 1], "kx", ...
    "MarkerSize", 9, "LineWidth", 1.3);
axis(ax, "equal");
grid(ax, "on");
xlabel(ax, "同相分量");
ylabel(ax, "正交分量");
title(ax, sprintf("%s：%d 个编码位映射为 %d 个符号", ...
    cfg.modulation, numel(frame.txCodeBits), numel(frame.txDataSymbols)));
colorScale = colorbar(ax);
colorScale.Label.String = "符号序号";
panel_label(ax, "D");

ax = nexttile(layout);
symbolIndex = 1:numel(frame.txFrameSymbols);
plot(ax, symbolIndex, abs(frame.txFrameSymbols), "Color", colors.blue, ...
    "LineWidth", 1.0);
hold(ax, "on");
frame_boundaries(ax, cfg);
ylim(ax, [0, 1.55]);
grid(ax, "on");
xlabel(ax, "物理帧符号序号");
ylabel(ax, "幅度");
title(ax, "物理帧幅度：UW1 | UW2 | 数据 | UW3");
panel_label(ax, "E");

ax = nexttile(layout);
plot(ax, symbolIndex, unwrap(angle(frame.txFrameSymbols)), ...
    "Color", colors.purple, "LineWidth", 0.9);
hold(ax, "on");
frame_boundaries(ax, cfg);
grid(ax, "on");
xlabel(ax, "物理帧符号序号");
ylabel(ax, "展开相位（rad）");
title(ax, "物理帧相位变化");
panel_label(ax, "F");

path = export_stage(fig, resultDir, "01_digital_framing");
end

function path = plot_transmit_channel(frame, cfg, colors, resultDir)
fig = new_figure("脉冲成形与信道");
layout = tiledlayout(fig, 3, 2, "TileSpacing", "compact", "Padding", "compact");
title(layout, "脉冲成形、频谱、多径信道与通带波形");

ax = nexttile(layout);
if isempty(frame.channel.txFilter)
    stem(ax, 0, 1, "filled", "Color", colors.blue);
    title(ax, "矩形脉冲成形模式");
else
    taps = frame.channel.txFilter;
    timeSymbols = ((0:numel(taps)-1) - (numel(taps)-1)/2) / ...
        cfg.txSamplesPerSymbol;
    plot(ax, timeSymbols, taps, "Color", colors.blue, "LineWidth", 1.2);
    title(ax, sprintf("发射 RRC 冲激响应，滚降系数 = %.2f", ...
        cfg.rrcRolloff));
end
grid(ax, "on");
xlabel(ax, "时间（符号）");
ylabel(ax, "抽头幅度");
panel_label(ax, "A");

ax = nexttile(layout);
sampleCount = min(12 * cfg.txSamplesPerSymbol, numel(frame.channel.txBaseband));
samples = 1:sampleCount;
plot(ax, samples / cfg.txSamplesPerSymbol, ...
    real(frame.channel.txUpsampled(samples)), ".", "Color", colors.gray);
hold(ax, "on");
plot(ax, samples / cfg.txSamplesPerSymbol, ...
    real(frame.channel.txBaseband(samples)), "Color", colors.orange, ...
    "LineWidth", 1.1);
grid(ax, "on");
xlabel(ax, "时间（符号）");
ylabel(ax, "同相分量幅度");
legend(ax, "零插值脉冲", "RRC 成形波形", ...
    "Location", "best");
title(ax, "零插值到脉冲成形基带");
panel_label(ax, "B");

ax = nexttile(layout);
plot_spectrum(ax, frame.channel.txBaseband, cfg.txSampleRate, colors.blue);
xlim(ax, 2 * [-cfg.symbolRate, cfg.symbolRate] / 1e3);
xlabel(ax, "基带频率（kHz）");
ylabel(ax, "归一化幅度（dB）");
title(ax, "RRC 成形基带频谱");
panel_label(ax, "C");

ax = nexttile(layout);
stem(ax, cfg.pathDelaysMs, abs(cfg.pathGains), "filled", ...
    "Color", colors.green, "LineWidth", 1.2);
grid(ax, "on");
xlabel(ax, "路径时延（ms）");
ylabel(ax, "路径幅度");
title(ax, sprintf("解析多径信道，多普勒频移 %.1f Hz", ...
    cfg.dopplerHz(1)));
panel_label(ax, "D");

ax = nexttile(layout);
count = min(10 * cfg.txSamplesPerSymbol, numel(frame.channel.channelBaseband));
timeMs = (0:count-1) / cfg.txSampleRate * 1e3;
plot(ax, timeMs, real(frame.channel.channelBaseband(1:count)), ...
    "Color", colors.blue, "LineWidth", 0.9);
hold(ax, "on");
plot(ax, timeMs, imag(frame.channel.channelBaseband(1:count)), ...
    "--", "Color", colors.orange, "LineWidth", 0.9);
grid(ax, "on");
xlabel(ax, "时间（ms）");
ylabel(ax, "复基带幅度");
legend(ax, "同相分量", "正交分量", "Location", "best");
title(ax, "经过多径与多普勒后的复基带");
panel_label(ax, "E");

ax = nexttile(layout);
count = min(round(4e-3 * cfg.txSampleRate), ...
    numel(frame.channel.txPassband96k));
timeMs = (0:count-1) / cfg.txSampleRate * 1e3;
plot(ax, timeMs, frame.channel.txPassband96k(1:count), ...
    "Color", colors.red, "LineWidth", 0.75);
grid(ax, "on");
xlabel(ax, "时间（ms）");
ylabel(ax, "通带幅度");
title(ax, sprintf("信道后的 %.1f kHz 实通带波形", cfg.carrierHz/1e3));
panel_label(ax, "F");

path = export_stage(fig, resultDir, "02_transmit_channel");
end

function path = plot_synchronization_estimation(frame, cfg, colors, resultDir)
fig = new_figure("同步与信道估计");
layout = tiledlayout(fig, 3, 2, "TileSpacing", "compact", "Padding", "compact");
title(layout, "ADC 采样、匹配滤波、帧捕获与信道估计");

ax = nexttile(layout);
timeMs = (0:numel(frame.adcSamples)-1) / cfg.rxSampleRate * 1e3;
plot(ax, timeMs, double(frame.adcSamples) - 2048, ...
    "Color", colors.gray, "LineWidth", 0.65);
hold(ax, "on");
xline(ax, frame.frameStartSample / cfg.rxSampleRate * 1e3, ...
    ":", "检测到的帧", "Color", colors.red);
grid(ax, "on");
xlabel(ax, "时间（ms）");
ylabel(ax, "去中心后的 ADC 计数");
title(ax, sprintf("12 位 ADC 采样，共 %d 点", numel(frame.adcSamples)));
panel_label(ax, "A");

ax = nexttile(layout);
range = receiver_window(frame, cfg, 8);
timeSymbols = (range - frame.frameStartSample) / cfg.rxSamplesPerSymbol;
plot(ax, timeSymbols, real(frame.downconvertedSamples(range)), ...
    "Color", colors.sky, "LineWidth", 0.7);
hold(ax, "on");
plot(ax, timeSymbols, real(frame.matchedFilterSamples(range)), ...
    "Color", colors.blue, "LineWidth", 1.0);
grid(ax, "on");
xlabel(ax, "相对检测起点的时间（符号）");
ylabel(ax, "同相分量幅度");
legend(ax, "下变频后", "RRC 匹配滤波后", "Location", "best");
title(ax, "数字下变频与匹配滤波");
panel_label(ax, "B");

ax = nexttile(layout);
[samples, order] = sort(frame.metricSamples);
plot(ax, samples, frame.metricValues(order), ".", ...
    "Color", colors.blue, "MarkerSize", 4);
hold(ax, "on");
yline(ax, cfg.syncThreshold, "--", "门限", "Color", colors.orange);
xline(ax, frame.frameStartSample, ":", "检测起点", "Color", colors.red);
grid(ax, "on");
xlabel(ax, "候选帧起始采样点");
ylabel(ax, "归一化双 UW 度量");
title(ax, sprintf("帧捕获，同步峰值 %.3f", frame.syncMetric));
panel_label(ax, "C");

ax = nexttile(layout);
plot(ax, 0:numel(frame.phaseCorrection)-1, frame.phaseCorrection, ...
    "Color", colors.purple, "LineWidth", 1.1);
grid(ax, "on");
xlabel(ax, "帧内符号序号");
ylabel(ax, "补偿相位（rad）");
title(ax, sprintf("多普勒/载波频偏补偿，估计值 %.2f Hz", ...
    frame.frequencyOffsetHz));
panel_label(ax, "D");

ax = nexttile(layout);
plot(ax, real(frame.synchronizedSymbols), imag(frame.synchronizedSymbols), ...
    ".", "Color", colors.orange, "MarkerSize", 7);
hold(ax, "on");
plot(ax, real(frame.correctedSymbols), imag(frame.correctedSymbols), ...
    ".", "Color", colors.blue, "MarkerSize", 7);
axis(ax, "equal");
grid(ax, "on");
xlabel(ax, "同相分量");
ylabel(ax, "正交分量");
legend(ax, "补偿前", "补偿后", "Location", "best");
title(ax, "同步符号的频偏补偿前后对比");
panel_label(ax, "E");

ax = nexttile(layout);
tapDelayMs = (0:numel(frame.channelImpulse)-1) / cfg.symbolRate * 1e3;
stem(ax, tapDelayMs, abs(frame.channelImpulse), "filled", ...
    "Color", colors.green, "LineWidth", 1.0);
grid(ax, "on");
xlabel(ax, "估计时延（ms）");
ylabel(ax, "冲激响应幅度");
title(ax, sprintf("UW2-LS 信道估计，保留 %d 个抽头", ...
    cfg.channelTaps));
panel_label(ax, "F");

path = export_stage(fig, resultDir, "03_sync_channel_estimation");
end

function path = plot_equalization_decoding(frame, cfg, colors, resultDir)
fig = new_figure("均衡与译码");
layout = tiledlayout(fig, 3, 2, "TileSpacing", "compact", "Padding", "compact");
title(layout, "SC-FDE 均衡、软译码与数据包校验");

ax = nexttile(layout);
frequency = (0:cfg.fftSize-1) * cfg.symbolRate / cfg.fftSize / 1e3;
plot(ax, frequency, 20 * log10(abs(frame.channelResponse) + eps), ...
    "Color", colors.green, "LineWidth", 1.1);
grid(ax, "on");
xlabel(ax, "基带频率（kHz）");
ylabel(ax, "幅度（dB）");
title(ax, sprintf("估计信道频响，正则化参数 = %.3g", ...
    frame.regularization));
panel_label(ax, "A");

ax = nexttile(layout);
receivedMagnitude = abs(frame.receivedBlockSpectrum);
receivedMagnitude = receivedMagnitude / max(receivedMagnitude + eps);
equalizedSpectrum = abs(fft([frame.equalizedSymbols, ...
    frame.txFrameSymbols(end-cfg.uwLength+1:end)]));
equalizedSpectrum = equalizedSpectrum / max(equalizedSpectrum + eps);
plot(ax, frequency, 20 * log10(receivedMagnitude + eps), ...
    "Color", colors.orange, "LineWidth", 0.9);
hold(ax, "on");
plot(ax, frequency, 20 * log10(equalizedSpectrum + eps), ...
    "Color", colors.blue, "LineWidth", 1.0);
grid(ax, "on");
xlabel(ax, "基带频率（kHz）");
ylabel(ax, "归一化幅度（dB）");
legend(ax, "接收块", "均衡后块", "Location", "best");
title(ax, "128 点 SC-FDE 块频谱");
panel_label(ax, "B");

ax = nexttile(layout);
plot(ax, real(frame.equalizedSymbols), imag(frame.equalizedSymbols), ...
    ".", "Color", colors.blue, "MarkerSize", 9);
hold(ax, "on");
plot(ax, real(frame.txDataSymbols), imag(frame.txDataSymbols), ...
    "x", "Color", colors.red, "MarkerSize", 6, "LineWidth", 1.0);
axis(ax, "equal");
grid(ax, "on");
xlabel(ax, "同相分量");
ylabel(ax, "正交分量");
legend(ax, "均衡后", "发送符号", "Location", "best");
title(ax, sprintf("均衡后的 %s 星座图", cfg.modulation));
panel_label(ax, "C");

ax = nexttile(layout);
stem(ax, 1:numel(frame.demodulation.llr), frame.demodulation.llr, ...
    ".", "Color", colors.purple, "MarkerSize", 4);
hold(ax, "on");
yline(ax, 0, "k-");
grid(ax, "on");
xlabel(ax, "LDPC 码字比特序号");
ylabel(ax, "软信息值");
title(ax, "QPSK 软解调输出");
panel_label(ax, "D");

ax = nexttile(layout);
decisionRows = [double(frame.txCodeBits); ...
    double(frame.demodulation.codeHardBits)];
imagesc(ax, decisionRows);
colormap(ax, [1, 1, 1; colors.red]);
set(ax, "YTick", [1, 2], "YTickLabel", ["发送码字", "接收硬判决"]);
xlabel(ax, "LDPC 码字比特序号");
title(ax, sprintf("译码前硬判决误码数：%d", ...
    sum(frame.txCodeBits ~= frame.demodulation.codeHardBits)));
panel_label(ax, "E");

ax = nexttile(layout);
packetRows = [double(frame.txPacket); double(frame.rxPacket)];
imagesc(ax, packetRows);
colormap(ax, "parula");
set(ax, "YTick", [1, 2], "YTickLabel", ["发送", "接收"], ...
    "XTick", 1:numel(frame.txPacket));
for row = 1:2
    for column = 1:size(packetRows, 2)
        text(ax, column, row, sprintf("%02X", packetRows(row, column)), ...
            "HorizontalAlignment", "center", "FontName", "Consolas", ...
            "FontSize", 8, "Color", "k");
    end
end
xlabel(ax, "数据包字节序号");
title(ax, sprintf("包头 %s | CRC %s | 比特错误数 %g", ...
    pass_text(frame.headerOk), pass_text(frame.crcOk), frame.bitErrors));
panel_label(ax, "F");

path = export_stage(fig, resultDir, "04_equalization_decoding");
end

function fig = new_figure(name)
fig = figure("Name", name, "Color", "w", ...
    "Position", [60, 40, 1450, 1050], "Visible", "off");
set(fig, "DefaultAxesFontName", "Microsoft YaHei", ...
    "DefaultAxesFontSize", 9, ...
    "DefaultTextFontName", "Microsoft YaHei");
end

function frame_boundaries(ax, cfg)
xline(ax, cfg.uwLength + 0.5, ":", "UW1/UW2");
xline(ax, 2 * cfg.uwLength + 0.5, ":", "UW2/数据");
xline(ax, 2 * cfg.uwLength + cfg.dataSymbols + 0.5, ":", "数据/UW3");
end

function range = receiver_window(frame, cfg, symbolCount)
halfWidth = symbolCount * cfg.rxSamplesPerSymbol;
first = max(1, frame.frameStartSample - halfWidth + 1);
last = min(numel(frame.matchedFilterSamples), ...
    frame.frameStartSample + halfWidth + 1);
range = first:last;
end

function plot_spectrum(ax, signal, sampleRate, color)
fftLength = 2^nextpow2(max(4096, numel(signal)));
spectrum = fftshift(fft(signal, fftLength));
magnitude = abs(spectrum);
magnitude = magnitude / max(magnitude + eps);
frequency = (-fftLength/2:fftLength/2-1) * sampleRate / fftLength / 1e3;
plot(ax, frequency, 20 * log10(magnitude + eps), ...
    "Color", color, "LineWidth", 1.0);
grid(ax, "on");
ylim(ax, [-100, 5]);
end

function panel_label(ax, label)
text(ax, -0.11, 1.06, label, "Units", "normalized", ...
    "FontWeight", "bold", "FontSize", 11, ...
    "HorizontalAlignment", "left", "VerticalAlignment", "top");
end

function path = export_stage(fig, resultDir, stem)
path = fullfile(resultDir, stem + ".png");
exportgraphics(fig, path, "Resolution", 220);
exportgraphics(fig, fullfile(resultDir, stem + ".pdf"), ...
    "ContentType", "vector");
close(fig);
end

function text = pass_text(value)
if value
    text = "通过";
else
    text = "失败";
end
end
