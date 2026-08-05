function figurePaths = visualize_sc_tde_stages(results)
%VISUALIZE_SC_TDE_STAGES Export layered Chinese SC-TDE visualizations.

resultDir = fullfile(results.config.outputDir, "sc_tde_stages");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end

figurePaths = [
    fullfile(resultDir, "00_sc_tde_beginner_overview.png")
    fullfile(resultDir, "01_sc_tde_source_channel.png")
    fullfile(resultDir, "02_sc_tde_equalizer_learning.png")
    fullfile(resultDir, "03_sc_tde_result_comparison.png")
    fullfile(resultDir, "04_sc_tde_dfe_internal_terms.png")
    fullfile(resultDir, "05_sc_tde_nlms_coefficient_update.png")
    fullfile(resultDir, "06_sc_tde_all_method_outputs.png")
    fullfile(resultDir, "07_sc_tde_modular_architecture.png")
    ];

plot_beginner_overview(results, figurePaths(1));
plot_source_channel(results, figurePaths(2));
plot_equalizer_learning(results, figurePaths(3));
plot_result_comparison(results, figurePaths(4));
plot_dfe_internal_terms(results, figurePaths(5));
plot_nlms_coefficient_update(results, figurePaths(6));
plot_all_method_outputs(results, figurePaths(7));
plot_modular_architecture(results, figurePaths(8));
end

function plot_beginner_overview(results, path)
cfg = results.config;
colors.blue = [86, 180, 233] / 255;
colors.green = [0, 158, 115] / 255;
colors.orange = [230, 159, 0] / 255;
colors.gray = [0.94, 0.94, 0.94];

fig = figure("Color", "w", "Position", [40, 60, 1600, 900], "Visible", "off");
annotation(fig, "textbox", [0.04, 0.925, 0.92, 0.06], ...
    "String", "一张图看懂：SC-TDE 如何在时域消除水下回声", ...
    "FontName", "Microsoft YaHei", "FontSize", 22, "FontWeight", "bold", ...
    "HorizontalAlignment", "center", "EdgeColor", "none");
annotation(fig, "textbox", [0.08, 0.865, 0.84, 0.05], ...
    "String", sprintf("当前为 BPSK 均衡算法对比链路：%d 个训练符号 + %d 个数据符号，信噪比 %.1f dB", ...
    cfg.trainingSymbols, cfg.dataSymbols, cfg.snrDb), ...
    "FontName", "Microsoft YaHei", "FontSize", 11.5, ...
    "HorizontalAlignment", "center", "EdgeColor", "none");

lane_label(fig, [0.015, 0.63, 0.065, 0.18], "发送与信道", colors.blue);
lane_label(fig, [0.015, 0.365, 0.065, 0.18], "时域均衡", colors.orange);
lane_label(fig, [0.015, 0.12, 0.065, 0.16], "判决与评价", colors.green);

x = [0.09, 0.31, 0.53, 0.75];
boxWidth = 0.185;
boxHeight = 0.18;
topY = 0.63;
middleY = 0.365;
bottomY = 0.12;

stage_box(fig, [x(1), topY, boxWidth, boxHeight], "1  生成正负符号", ...
    sprintf("每个比特变成 +1 或 -1\n前 %d 个用于教接收机\n后 %d 个用于检验", ...
    cfg.trainingSymbols, cfg.dataSymbols), colors.blue);
stage_box(fig, [x(2), topY, boxWidth, boxHeight], "2  经过多条水下路径", ...
    sprintf("同一符号沿 %d 条路径到达\n延迟：%s 个符号\n多个副本叠加形成回声", ...
    numel(cfg.pathDelays), join(string(cfg.pathDelays), "、")), colors.blue);
stage_box(fig, [x(3), topY, boxWidth, boxHeight], "3  两个水听器接收", ...
    sprintf("两个位置看到略有不同的信道\n叠加 %.2f Hz 频移和噪声\n原来的正负符号被拉散", ...
    cfg.dopplerHz), colors.blue);
stage_box(fig, [x(4), topY, boxWidth, boxHeight], "4  送入 SC-TDE", ...
    "接收机逐个处理时域采样\n不先分块做 FFT\n可替换不同均衡方法", colors.blue);
connect_row(fig, x, boxWidth, topY + boxHeight / 2);

stage_box(fig, [x(4), middleY, boxWidth, boxHeight], "5  用训练段调滤波器", ...
    sprintf("接收机已知前 %d 个正确答案\n比较输出与答案的误差\nNLMS 据此逐步调整系数", ...
    cfg.trainingSymbols), colors.orange);
stage_box(fig, [x(3), middleY, boxWidth, boxHeight], "6  前馈滤波", ...
    sprintf("观察当前及附近的接收采样\n%d 个前馈抽头抑制干扰\n得到当前符号的初步估计", ...
    cfg.feedforwardTaps), colors.orange);
stage_box(fig, [x(2), middleY, boxWidth, boxHeight], "7  判决反馈", ...
    sprintf("利用过去已经判出的符号\n%d 个反馈抽头抵消后续回声\n这就是 DFE 的反馈部分", ...
    cfg.feedbackTaps), colors.orange);
stage_box(fig, [x(1), middleY, boxWidth, boxHeight], "8  数据段自主工作", ...
    "训练结束后不再提供答案\n输出靠近 +1 就判为 +1\n靠近 -1 就判为 -1", colors.orange);
connect_row_reverse(fig, x, boxWidth, middleY + boxHeight / 2);
vertical_arrow(fig, x(4) + boxWidth / 2, topY, middleY + boxHeight);

bestBer = min(results.ber);
bestIndex = find(results.ber == bestBer, 1);
methodNames = chinese_method_names();
stage_box(fig, [0.19, bottomY, 0.28, boxHeight], "9  与原始数据逐位比较", ...
    "只统计训练段之后的数据\n错误位数 / 数据总位数 = BER\nBER 越低，恢复越准确", colors.green);
stage_box(fig, [0.55, bottomY, 0.34, boxHeight], "10  比较六种可替换方法", ...
    sprintf("本次最低 BER：%.4g\n对应方法：%s\n各方法共享同一发送与信道输入", ...
    bestBer, methodNames(bestIndex)), colors.green);
horizontal_arrow(fig, 0.47, 0.55, bottomY + boxHeight / 2);
vertical_arrow(fig, x(1) + boxWidth / 2, middleY, bottomY + boxHeight);

annotation(fig, "textbox", [0.08, 0.02, 0.88, 0.07], ...
    "String", ["术语翻译：  SC-TDE = 单载波时域均衡    " ...
    "BPSK = 用 +1/-1 表示二进制    DFE = 用过去判决帮助消除回声    " ...
    "NLMS = 根据误差自动调节滤波器    BER = 每传 1 位数据出错的比例"], ...
    "FontName", "Microsoft YaHei", "FontSize", 11, ...
    "BackgroundColor", colors.gray, "EdgeColor", [0.7, 0.7, 0.7], ...
    "Margin", 10, "HorizontalAlignment", "left");
export_pair(fig, path);
end

function plot_source_channel(results, path)
cfg = results.config;
fig = new_technical_figure("SC-TDE 阶段 1：发送符号与水下多径信道");
layout = tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");
title(layout, "SC-TDE 阶段 1：发送符号与水下多径信道" + newline + ...
    sprintf("训练 %d 符号 + 数据 %d 符号 | 符号率 %.0f Hz | 信噪比 %.1f dB", ...
    cfg.trainingSymbols, cfg.dataSymbols, cfg.symbolRate, cfg.snrDb), ...
    "FontName", "Microsoft YaHei", "FontSize", 11);

showCount = min(100, numel(results.tx));
nexttile;
stairs(1:showCount, results.tx(1:showCount), "LineWidth", 1.2);
ylim([-1.4, 1.4]); grid on;
title("(a) BPSK 发送符号：每位变成 +1 或 -1");
xlabel("符号序号"); ylabel("符号值");

nexttile;
stem(cfg.pathDelays, abs(results.channelImpulse), "filled", "LineWidth", 1.2);
grid on;
title("(b) 多径冲激响应：多个延迟副本叠加");
xlabel("路径延迟（符号）"); ylabel("路径幅度");

receiveCount = min(220, numel(results.received));
nexttile;
plot(1:receiveCount, real(results.received(1:receiveCount)), "LineWidth", 0.9);
hold on;
plot(1:receiveCount, imag(results.received(1:receiveCount)), "LineWidth", 0.9);
grid on;
title("(c) 接收波形：回声、频移和噪声已混合");
xlabel("符号采样序号"); ylabel("接收幅度");
legend("实部", "虚部", "Location", "best");

nexttile;
sample = results.received(1:min(900, numel(results.received)));
scatter(real(sample), imag(sample), 9, 1:numel(sample), "filled");
hold on; plot([-1, 1], [0, 0], "kx", "MarkerSize", 12, "LineWidth", 2);
axis equal; grid on;
title("(d) 均衡前散点：理想的两个点已被拉散");
xlabel("实部"); ylabel("虚部");
colorbar;
apply_chinese_axes(fig);
export_pair(fig, path);
end

function plot_equalizer_learning(results, path)
cfg = results.config;
methodNames = chinese_method_names();
fig = new_technical_figure("SC-TDE 阶段 2：时域均衡器训练与输出变化");
tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile([1, 2]);
hold on;
for receiverIndex = 1:numel(results.learningMse)
    rawCurve = results.learningMse{receiverIndex};
    rawCurve(rawCurve <= 0) = NaN;
    curve = movmean(rawCurve, 32, "omitmissing");
    plot(10 * log10(curve), "LineWidth", 1.05);
end
xline(cfg.trainingSymbols, "k--", "训练结束", "LabelVerticalAlignment", "bottom");
grid on;
title("(a) 学习曲线：曲线越低，输出越接近正确符号");
xlabel("符号序号"); ylabel("滑动平均 MSE（dB）");
legend(methodNames, "Location", "eastoutside");

indices = cfg.trainingSymbols + (1:min(220, cfg.dataSymbols));
nexttile;
plot(indices, real(results.tx(indices)), "k-", "LineWidth", 1.4);
hold on;
plot(indices, real(results.equalizerEstimates{2}(indices)), ".", "MarkerSize", 8);
yline(0, "k:"); grid on;
title("(b) 自适应 NLMS-DFE：判决前连续输出");
xlabel("符号序号"); ylabel("估计值实部");
legend("原始 +1/-1", "均衡器输出", "判决边界", "Location", "best");

nexttile;
before = results.received(indices);
after = results.equalizerEstimates{2}(indices);
scatter(real(before), imag(before), 14, [0.55, 0.55, 0.55], "filled");
hold on;
scatter(real(after), imag(after), 16, [0, 0.45, 0.70], "filled");
plot([-1, 1], [0, 0], "kx", "MarkerSize", 11, "LineWidth", 1.8);
axis equal; grid on;
title("(c) 均衡前后：散点重新聚向 +1 和 -1");
xlabel("实部"); ylabel("虚部");
legend("均衡前", "均衡后", "理想位置", "Location", "best");
apply_chinese_axes(fig);
sgtitle(fig, "SC-TDE 阶段 2：时域均衡器训练与输出变化", ...
    "FontName", "Microsoft YaHei", "FontSize", 18, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_result_comparison(results, path)
cfg = results.config;
methodNames = chinese_method_names();
fig = new_technical_figure("SC-TDE 阶段 3：判决结果与六种方法对比");
tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
berForPlot = max(results.ber, 0.5 / cfg.dataSymbols);
bar(berForPlot, "FaceColor", [0, 0.62, 0.45]);
set(gca, "YScale", "log", "XTick", 1:numel(methodNames), ...
    "XTickLabel", methodNames);
xtickangle(20); grid on;
ylim([min(berForPlot) / 2, 1]);
title("(a) 数据段误码率（越低越好）");
ylabel("BER（对数坐标）");

showCount = min(90, cfg.dataSymbols);
indices = cfg.trainingSymbols + (1:showCount);
nexttile;
stairs(1:showCount, results.tx(indices), "k-", "LineWidth", 1.5);
hold on;
stairs(1:showCount, results.receivers{2}(indices), "LineWidth", 1.0);
grid on; ylim([-1.4, 1.4]);
title("(b) 自适应 NLMS-DFE 硬判决与原始数据");
xlabel("数据符号序号"); ylabel("判决值");
legend("发送数据", "接收判决", "Location", "best");

payload = cfg.trainingSymbols + (1:cfg.dataSymbols);
errors = false(numel(results.receivers), cfg.dataSymbols);
for receiverIndex = 1:numel(results.receivers)
    errors(receiverIndex, :) = results.receivers{receiverIndex}(payload) ~= results.source.data;
end
nexttile;
imagesc(errors);
colormap(gca, [0.92, 0.92, 0.92; 0.84, 0.15, 0.16]);
set(gca, "YTick", 1:numel(methodNames), "YTickLabel", methodNames);
title("(c) 错误位置：红色表示该数据位判错");
xlabel("数据符号序号"); ylabel("接收方法");

nexttile;
axis off;
[sortedBer, order] = sort(results.ber);
lines = strings(numel(order) + 2, 1);
lines(1) = "本次仿真结论";
lines(2) = sprintf("共同输入：同一组 %d 位数据、同一水下信道", cfg.dataSymbols);
for rank = 1:numel(order)
    lines(rank + 2) = sprintf("%d. %-18s  BER = %.5g", ...
        rank, methodNames(order(rank)), sortedBer(rank));
end
text(0.02, 0.94, join(lines, newline), "Units", "normalized", ...
    "VerticalAlignment", "top", "FontName", "Microsoft YaHei", ...
    "FontSize", 11, "Interpreter", "none");
apply_chinese_axes(fig);
sgtitle(fig, "SC-TDE 阶段 3：判决结果与六种方法对比", ...
    "FontName", "Microsoft YaHei", "FontSize", 18, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_dfe_internal_terms(results, path)
cfg = results.config;
trace = results.equalizerTraces{2};
windowCount = min(48, cfg.dataSymbols);
indices = cfg.trainingSymbols + (1:windowCount);
localIndex = 1:windowCount;

fig = new_technical_figure("SC-TDE 细节 4：一个符号在 DFE 内部如何变化");
tiledlayout(fig, 3, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
plot(localIndex, real(results.received(indices)), "LineWidth", 1.0);
hold on; plot(localIndex, imag(results.received(indices)), "LineWidth", 0.9);
grid on;
title("(a) DFE 输入 r(k)：仍包含多径、频移和噪声");
xlabel("数据符号序号"); ylabel("接收值");
legend("实部", "虚部", "Location", "best");

nexttile;
plot(localIndex, real(trace.feedforwardOutput(indices)), "LineWidth", 1.1);
hold on; yline(1, "k:"); yline(-1, "k:"); grid on;
title(sprintf("(b) 前馈输出 y_{FF}(k)：由 %d 个接收抽头形成", cfg.feedforwardTaps));
xlabel("数据符号序号"); ylabel("前馈项实部");

nexttile;
bar(localIndex, real(trace.feedbackCancellation(indices)), 0.85, ...
    "FaceColor", [0.90, 0.55, 0.10]);
grid on;
title(sprintf("(c) 反馈抵消量 y_{FB}(k)：来自过去 %d 个判决", cfg.feedbackTaps));
xlabel("数据符号序号"); ylabel("需要减去的回声估计");

nexttile;
plot(localIndex, real(trace.feedforwardOutput(indices)), "Color", [0.45, 0.45, 0.45]);
hold on;
plot(localIndex, real(results.equalizerEstimates{2}(indices)), "o-", ...
    "MarkerSize", 3, "LineWidth", 0.9);
stairs(localIndex, results.tx(indices), "k-", "LineWidth", 1.3);
yline(0, "k:"); grid on;
title("(d) 最终估计 z(k) = y_{FF}(k) - y_{FB}(k)");
xlabel("数据符号序号"); ylabel("实部");
legend("仅前馈", "前馈减反馈", "正确符号", "判决边界", "Location", "best");

nexttile;
stem(localIndex, abs(trace.error(indices)), "filled", "MarkerSize", 3);
grid on;
title("(e) 逐符号误差 |e(k)| = |d(k)-z(k)|");
xlabel("数据符号序号"); ylabel("绝对误差");

nexttile;
axis off;
tableCount = min(12, windowCount);
lines = strings(tableCount + 3, 1);
lines(1) = "前 12 个数据符号的数值变化";
lines(2) = " k     发送d     前馈yFF     反馈yFB     最终z      判决";
lines(3) = "----------------------------------------------------------";
for row = 1:tableCount
    symbolIndex = indices(row);
    lines(row + 3) = sprintf("%2d      %+2.0f       %+7.3f       %+7.3f      %+7.3f      %+2.0f", ...
        row, results.tx(symbolIndex), real(trace.feedforwardOutput(symbolIndex)), ...
        real(trace.feedbackCancellation(symbolIndex)), ...
        real(results.equalizerEstimates{2}(symbolIndex)), ...
        results.receivers{2}(symbolIndex));
end
text(0.01, 0.98, join(lines, newline), "Units", "normalized", ...
    "VerticalAlignment", "top", "FontName", "Microsoft YaHei", ...
    "FontSize", 9.5, "Interpreter", "none");
apply_chinese_axes(fig);
sgtitle(fig, "SC-TDE 细节 4：一个符号在 DFE 内部如何变化", ...
    "FontName", "Microsoft YaHei", "FontSize", 18, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_nlms_coefficient_update(results, path)
cfg = results.config;
trace = results.equalizerTraces{2};
valid = find(trace.weightNorm > 0);
firstValid = valid(1);
lastValid = valid(end);
symbolRange = firstValid:lastValid;
history = trace.coefficientHistory(:, symbolRange);
sampleStep = max(1, floor(numel(symbolRange) / 500));
displayColumns = 1:sampleStep:numel(symbolRange);

fig = new_technical_figure("SC-TDE 细节 5：NLMS 如何逐步更新滤波器");
tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
errorPower = abs(trace.error).^2;
errorPower(errorPower <= 0) = NaN;
plot(10 * log10(movmean(errorPower, 32, "omitmissing")), "LineWidth", 1.1);
xline(cfg.trainingSymbols, "k--", "训练结束"); grid on;
title("(a) NLMS 依据误差 e(k) 调整权值");
xlabel("符号序号"); ylabel("滑动平均误差功率（dB）");

nexttile;
plot(symbolRange, trace.weightNorm(symbolRange), "LineWidth", 1.1);
xline(cfg.trainingSymbols, "k--", "训练结束"); grid on;
title("(b) 权值向量范数：反映滤波器整体调整幅度");
xlabel("符号序号"); ylabel("||w(k)||_2");

nexttile;
imagesc(symbolRange(displayColumns), 1:size(history, 1), ...
    20 * log10(abs(history(:, displayColumns)) + 1e-3));
axis xy; colorbar; colormap(gca, parula);
yline(cfg.feedforwardTaps + 0.5, "w--", "前馈/反馈分界", ...
    "LabelHorizontalAlignment", "left");
title("(c) 每个抽头随时间的幅度变化");
xlabel("符号序号"); ylabel("权值编号");

nexttile;
finalWeights = history(:, end);
stem(1:numel(finalWeights), abs(finalWeights), "filled", "MarkerSize", 3);
xline(cfg.feedforwardTaps + 0.5, "r--", "前馈 | 反馈"); grid on;
title(sprintf("(d) 最终 %d 个前馈权值和 %d 个反馈权值", ...
    cfg.feedforwardTaps, cfg.feedbackTaps));
xlabel("权值编号"); ylabel("最终权值幅度");
apply_chinese_axes(fig);
sgtitle(fig, "SC-TDE 细节 5：NLMS 如何逐步更新滤波器", ...
    "FontName", "Microsoft YaHei", "FontSize", 18, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_all_method_outputs(results, path)
cfg = results.config;
methodNames = chinese_method_names();
payload = cfg.trainingSymbols + (1:min(600, cfg.dataSymbols));
fig = new_technical_figure("SC-TDE 细节 6：六种均衡器的判决前输出");
tiledlayout(fig, 2, 3, "TileSpacing", "compact", "Padding", "compact");
for receiverIndex = 1:numel(methodNames)
    nexttile;
    values = results.equalizerEstimates{receiverIndex}(payload);
    scatter(real(values), imag(values), 9, [0, 0.45, 0.70], "filled");
    hold on;
    plot([-1, 1], [0, 0], "kx", "MarkerSize", 11, "LineWidth", 1.8);
    xline(0, "k:"); axis equal; grid on;
    title(sprintf("(%c) %s | BER = %.4g", ...
        char('a' + receiverIndex - 1), methodNames(receiverIndex), results.ber(receiverIndex)));
    xlabel("实部"); ylabel("虚部");
end
apply_chinese_axes(fig);
sgtitle(fig, "SC-TDE 细节 6：六种均衡器的判决前输出", ...
    "FontName", "Microsoft YaHei", "FontSize", 18, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_modular_architecture(results, path)
cfg = results.config;
colors = [86, 180, 233; 230, 159, 0; 204, 121, 167; 0, 158, 115; 0, 114, 178] / 255;
fig = figure("Color", "w", "Position", [40, 60, 1600, 900], "Visible", "off");
annotation(fig, "textbox", [0.04, 0.91, 0.92, 0.07], ...
    "String", "SC-TDE 细节 7：模块化链路与可替换接口", ...
    "FontName", "Microsoft YaHei", "FontSize", 22, "FontWeight", "bold", ...
    "HorizontalAlignment", "center", "EdgeColor", "none");
annotation(fig, "textbox", [0.12, 0.84, 0.76, 0.05], ...
    "String", "每个方框都通过 function handle 接口连接，可单独换成其他方法而不改主流程", ...
    "FontName", "Microsoft YaHei", "FontSize", 12, ...
    "HorizontalAlignment", "center", "EdgeColor", "none");

x = [0.06, 0.255, 0.45, 0.645, 0.84];
width = 0.14;
height = 0.28;
y = 0.48;
stage_box(fig, [x(1), y, width, height], "1  信源模块 source", ...
    sprintf("默认：BPSK 生成器\n输入：配置 cfg\n输出：training、data、tx\n当前长度：%d", numel(results.tx)), colors(1, :));
stage_box(fig, [x(2), y, width, height], "2  信道模块 channel", ...
    sprintf("默认：双水听器多径\n输入：tx、cfg\n输出：received、branches\n路径数：%d", numel(cfg.pathDelays)), colors(2, :));
stage_box(fig, [x(3), y, width, height], "3  接收模块 receiverBank", ...
    sprintf("默认：六种 SC-TDE\n输入：channel、source、cfg\n输出：判决、估计、追踪\n方法数：%d", numel(results.names)), colors(3, :));
stage_box(fig, [x(4), y, width, height], "4  评价模块 metric", ...
    sprintf("默认：数据段 BER\n输入：receiver、source、cfg\n输出：每种方法的 BER\n数据位：%d", cfg.dataSymbols), colors(4, :));
stage_box(fig, [x(5), y, width, height], "5  绘图模块 plot", ...
    "默认：八张中文图\n输入：完整 results\n输出：PNG 和矢量 PDF\n也可替换自定义绘图", colors(5, :));
connect_row(fig, x, width, y + height / 2);

codeText = join(["替换示例", "", ...
    "options.modules.channel = @my_channel;     % 换成 Bellhop、实测信道或其他模型", ...
    "options.modules.receiverBank = @my_tde;    % 换成 LMS、RLS、神经网络均衡器等", ...
    "result = simulate_chapter2_single_carrier_tde(options);"], newline);
annotation(fig, "textbox", [0.08, 0.21, 0.84, 0.17], ...
    "String", codeText, "FontName", "Microsoft YaHei", ...
    "FontSize", 11, "Interpreter", "none", ...
    "BackgroundColor", [0.95, 0.95, 0.95], "EdgeColor", [0.7, 0.7, 0.7], ...
    "Margin", 12, "HorizontalAlignment", "left");
annotation(fig, "textbox", [0.08, 0.08, 0.84, 0.08], ...
    "String", "保持不变的契约：模块只交换结构化数据；替换算法时，主仿真入口、参数管理和结果目录不需要改动。", ...
    "FontName", "Microsoft YaHei", "FontSize", 11.5, ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "BackgroundColor", [0.93, 0.97, 0.95], "EdgeColor", colors(4, :));
export_pair(fig, path);
end

function fig = new_technical_figure(titleText)
fig = figure("Color", "w", "Position", [60, 60, 1500, 900], "Visible", "off");
sgtitle(fig, titleText, "FontName", "Microsoft YaHei", ...
    "FontSize", 18, "FontWeight", "bold");
end

function names = chinese_method_names()
names = ["传统 DFE", "自适应 NLMS-DFE", "PLL 辅助 DFE", ...
    "多通道 DFE", "被动时反 DFE", "子带被动时反 DFE"];
end

function apply_chinese_axes(fig)
axesList = findall(fig, "Type", "axes");
set(axesList, "FontName", "Microsoft YaHei", "FontSize", 10);
end

function export_pair(fig, path)
exportgraphics(fig, path, "Resolution", 220);
[folder, name] = fileparts(path);
exportgraphics(fig, fullfile(folder, name + ".pdf"), "ContentType", "vector");
close(fig);
end

function stage_box(fig, position, heading, body, color)
body = replace(string(body), "\n", newline);
annotation(fig, "textbox", position, "String", heading + newline + newline + body, ...
    "FontName", "Microsoft YaHei", "FontSize", 10.5, ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "BackgroundColor", 0.84 * color + 0.16, "EdgeColor", color * 0.72, ...
    "LineWidth", 1.6, "Margin", 8, "Interpreter", "none");
end

function lane_label(fig, position, textValue, color)
annotation(fig, "textbox", position, "String", textValue, ...
    "FontName", "Microsoft YaHei", "FontSize", 13, "FontWeight", "bold", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "BackgroundColor", color, "Color", "w", "EdgeColor", "none");
end

function connect_row(fig, x, boxWidth, y)
for index = 1:numel(x) - 1
    horizontal_arrow(fig, x(index) + boxWidth, x(index + 1), y);
end
end

function connect_row_reverse(fig, x, boxWidth, y)
for index = numel(x):-1:2
    horizontal_arrow(fig, x(index), x(index - 1) + boxWidth, y);
end
end

function horizontal_arrow(fig, xStart, xEnd, y)
annotation(fig, "arrow", [xStart + 0.005, xEnd - 0.005], [y, y], ...
    "Color", [0.35, 0.35, 0.35], "LineWidth", 1.3, "HeadLength", 8);
end

function vertical_arrow(fig, x, yStart, yEnd)
annotation(fig, "arrow", [x, x], [yStart - 0.008, yEnd + 0.008], ...
    "Color", [0.35, 0.35, 0.35], "LineWidth", 1.5, "HeadLength", 9);
end
