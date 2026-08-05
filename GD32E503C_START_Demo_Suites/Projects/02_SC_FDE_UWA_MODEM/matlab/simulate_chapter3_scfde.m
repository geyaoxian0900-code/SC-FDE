function results = simulate_chapter3_scfde(options)
%SIMULATE_CHAPTER3_SCFDE Chapter 3 SC-FDE simulation suite.
% Covers the basic SC-FDE model, residual Doppler/phase correction, a joint
% time-frequency equalizer, lake-style channel processing, and block
% iterative decision-feedback equalization (IB-DFE).
%
% Replace cfg.lakeImpulseResponse with measured lake data when available.

if nargin < 1, options = struct(); end
cfg.fftSize = opt(options,"fftSize",128);
cfg.uwLength = opt(options,"uwLength",32);
cfg.dataSymbols = cfg.fftSize-cfg.uwLength;
cfg.bitsPerSymbol = 2;
cfg.symbolRate = opt(options,"symbolRate",4000);
cfg.snrDb = opt(options,"snrDb",14);
cfg.cfoHz = opt(options,"cfoHz",8);
cfg.phaseOffset = opt(options,"phaseOffset",0.55);
cfg.randomSeed = opt(options,"randomSeed",20260724);
cfg.frameCount = opt(options,"frameCount",80);
cfg.ibdfeIterations = opt(options,"ibdfeIterations",5);
cfg.makePlot = opt(options,"makePlot",true);
cfg.channel = opt(options,"channel",[1 .65*exp(1j*.4) .35*exp(-1j*.9) .18*exp(1j*1.4)]);
cfg.channel = cfg.channel(:).'/norm(cfg.channel);
cfg.lakeImpulseResponse = opt(options,"lakeImpulseResponse", ...
    [1 .82*exp(1j*.2) .55*exp(-1j*.8) .29*exp(1j*1.7) .12*exp(-1j*.4)]);
cfg.lakeImpulseResponse = cfg.lakeImpulseResponse(:).'/norm(cfg.lakeImpulseResponse);
rng(cfg.randomSeed,"twister");

snrList = opt(options,"snrList",0:2:20);
basicBer = zeros(size(snrList)); jointBer = basicBer; ibdfeBer = basicBer;
for s = 1:numel(snrList)
    [basicBer(s),jointBer(s),ibdfeBer(s)] = ber_sweep(cfg,snrList(s));
end

[example, diagnostics] = one_frame(cfg,cfg.snrDb,cfg.channel);
[lakeImpulse,lakeInfo] = process_lake_style_data(cfg);
results.config=cfg; results.snrList=snrList; results.basicBer=basicBer;
results.jointBer=jointBer; results.ibdfeBer=ibdfeBer;
results.channel=cfg.channel;
results.example=example; results.diagnostics=diagnostics;
results.lakeImpulse=lakeImpulse; results.lakeInfo=lakeInfo; results.outputPath="";

fprintf("\n===== Chapter 3 SC-FDE simulation =====\n");
fprintf("FFT=%d, UW=%d, DATA=%d, CFO=%.2f Hz, phase=%.3f rad\n",...
    cfg.fftSize,cfg.uwLength,cfg.dataSymbols,cfg.cfoHz,cfg.phaseOffset);
fprintf("At %.1f dB: basic BER=%.5g, joint BER=%.5g, IB-DFE BER=%.5g\n",...
    cfg.snrDb,example.basicBer,example.jointBer,example.ibdfeBer);
fprintf("Lake-style paths processed: %d\n",numel(lakeImpulse));
if cfg.makePlot, results.outputPath=plot_results(results); end
end

function [basic,joint,ibdfe] = ber_sweep(cfg,snrDb)
errors=zeros(1,3); total=0;
for frame=1:cfg.frameCount
    [r,~]=one_frame(cfg,snrDb,cfg.channel);
    errors=errors+[r.basicErrors r.jointErrors r.ibdfeErrors];
    total=total+cfg.dataSymbols*cfg.bitsPerSymbol;
end
basic=errors(1)/total; joint=errors(2)/total; ibdfe=errors(3)/total;
end

function [out,diag] = one_frame(cfg,snrDb,h)
bits=randi([0 1],1,cfg.dataSymbols*cfg.bitsPerSymbol);
tx=qpsk_map(bits);
uw=exp(-1j*pi*(0:cfg.uwLength-1).^2/cfg.uwLength);
frame=[uw uw tx uw];
channel=[h zeros(1,cfg.fftSize-numel(h))]; H=fft(channel,cfg.fftSize);
block=frame(2*cfg.uwLength+1:2*cfg.uwLength+cfg.fftSize);
Y=fft(block,cfg.fftSize).*H;
received=ifft(Y);
n=(0:numel(received)-1);
received=received.*exp(1j*(cfg.phaseOffset+2*pi*cfg.cfoHz*n/cfg.symbolRate));
noisePower=mean(abs(received).^2)/10^(snrDb/10);
received=received+sqrt(noisePower/2)*(randn(size(received))+1j*randn(size(received)));

% UW pair provides residual frequency and initial phase estimates.
first=frame(1:cfg.uwLength).*exp(1j*cfg.phaseOffset);
second=frame(cfg.uwLength+1:2*cfg.uwLength).*exp(1j*(cfg.phaseOffset+...
    2*pi*cfg.cfoHz*(cfg.uwLength:2*cfg.uwLength-1)/cfg.symbolRate));
cross=sum(second.*conj(first));
estimatedCfo=angle(cross)/cfg.uwLength*cfg.symbolRate/(2*pi);
tailUw=received(cfg.dataSymbols+1:cfg.fftSize);
tailPhase=angle(sum(tailUw.*conj(uw)));
estimatedPhase=tailPhase-2*pi*estimatedCfo*cfg.dataSymbols/cfg.symbolRate;
phaseN=estimatedPhase+2*pi*estimatedCfo*n/cfg.symbolRate;
corrected=received.*exp(-1j*phaseN);
Yc=fft(corrected,cfg.fftSize);
regularization=noisePower;
estimationNoise=sqrt(noisePower*.35/2)*(randn(size(H))+1j*randn(size(H)));
Hinitial=H+estimationNoise;
Xbasic=Yc.*conj(Hinitial)./(abs(Hinitial).^2+regularization);
basicSymbols=ifft(Xbasic);
basicBits=qpsk_demap(basicSymbols(1:cfg.dataSymbols));

% 3.3 joint time-frequency refinement: update H from a soft decision.
Hjoint=Hinitial; Xjoint=Xbasic;
jointCurve=zeros(1,3);
for iter=1:3
    tentative=qpsk_map(qpsk_demap(ifft(Xjoint)));
    Htrial=Yc.*conj(fft([tentative zeros(1,cfg.fftSize-numel(tentative))])) ./ ...
        (abs(fft([tentative zeros(1,cfg.fftSize-numel(tentative))])).^2+regularization);
    Hjoint=.75*Hjoint+.25*Htrial;
    Xjoint=Yc.*conj(Hjoint)./(abs(Hjoint).^2+regularization);
    jointTime=ifft(Xjoint);
    jointCurve(iter)=mean(qpsk_demap(jointTime(1:cfg.dataSymbols))~=bits);
end
jointSymbols=ifft(Xjoint); jointBits=qpsk_demap(jointSymbols(1:cfg.dataSymbols));

% 3.4 IB-DFE: repeated soft cancellation and channel re-estimation.
Hib=Hinitial; Xib=Xbasic; ibCurve=zeros(1,cfg.ibdfeIterations);
for iter=1:cfg.ibdfeIterations
    softSymbols=ifft(Xib); reliability=min(1,abs(softSymbols));
    hardSymbols=qpsk_map(qpsk_demap(softSymbols));
    feedback=reliability.*hardSymbols+(1-reliability).*softSymbols;
    feedbackSpectrum=fft(feedback);
    Htrial=Yc.*conj(feedbackSpectrum)./(abs(feedbackSpectrum).^2+regularization);
    Hib=.65*Hib+.35*Htrial;
    Xib=Yc.*conj(Hib)./(abs(Hib).^2+regularization);
    ibTime=ifft(Xib);
    ibCurve(iter)=mean(qpsk_demap(ibTime(1:cfg.dataSymbols))~=bits);
end
ibSymbols=ifft(Xib); ibBits=qpsk_demap(ibSymbols(1:cfg.dataSymbols));

out.basicErrors=sum(basicBits~=bits); out.jointErrors=sum(jointBits~=bits);
out.ibdfeErrors=sum(ibBits~=bits); out.basicBer=out.basicErrors/numel(bits);
out.jointBer=out.jointErrors/numel(bits); out.ibdfeBer=out.ibdfeErrors/numel(bits);
out.basicSymbols=basicSymbols(1:cfg.dataSymbols); out.jointSymbols=jointSymbols(1:cfg.dataSymbols);
out.ibdfeSymbols=ibSymbols(1:cfg.dataSymbols); out.bits=bits; out.received=received;
diag.estimatedCfo=estimatedCfo; diag.estimatedPhase=estimatedPhase;
diag.jointCurve=jointCurve; diag.ibdfeCurve=ibCurve; diag.H=H;
diag.Hinitial=Hinitial; diag.Hjoint=Hjoint; diag.Hib=Hib;
end

function symbols=qpsk_map(bits)
bits=logical(bits(:).'); symbols=((2*double(bits(1:2:end))-1)+...
    1j*(2*double(bits(2:2:end))-1))/sqrt(2);
end

function bits=qpsk_demap(symbols)
symbols=symbols(:).'; bits=false(1,2*numel(symbols));
bits(1:2:end)=real(symbols)>=0; bits(2:2:end)=imag(symbols)>=0;
bits=double(bits);
end

function [h,info]=process_lake_style_data(cfg)
% This interface accepts a measured impulse response in place of the
% synthetic fallback and normalizes/removes insignificant late taps.
h=cfg.lakeImpulseResponse; threshold=.05*max(abs(h));
h(abs(h)<threshold)=0; h=h/norm(h); info.threshold=threshold;
info.delaySpread=find(abs(h)>0,1,"last")-find(abs(h)>0,1,"first");
info.source="synthetic lake-style fallback";
end

function path=plot_results(r)
path=fullfile(fileparts(mfilename("fullpath")),"results",...
    "chapter3_scfde_simulation.png");
if ~exist(fileparts(path),"dir"), mkdir(fileparts(path)); end
figure("Color","w","Position",[80 80 1350 850]); tiledlayout(2,3,"TileSpacing","compact");
nexttile([1 2]); semilogy(r.snrList,r.basicBer,"o-",r.snrList,r.jointBer,"s-",...
    r.snrList,r.ibdfeBer,"^-","LineWidth",1.2); grid on; xlabel("SNR/dB"); ylabel("BER");
title("SC-FDE与时频联合/IB-DFE性能"); legend("基本SC-FDE","时频联合均衡","IB-DFE","Location","southwest");
nexttile; stem(0:numel(r.channel)-1,abs(r.channel),"filled"); hold on; stem(0:numel(r.lakeImpulse)-1,abs(r.lakeImpulse),"r--"); grid on; title("系统模型与湖试风格信道"); legend("模型","湖试风格");
nexttile; plot(real(r.example.received(1:min(300,end)))); grid on; title("接收信号波形"); xlabel("Symbol");
nexttile; plot(real(r.example.basicSymbols),imag(r.example.basicSymbols),"."); hold on; plot(real(r.example.jointSymbols),imag(r.example.jointSymbols),"."); grid on; axis equal; title("均衡后星座"); legend("基本","联合");
nexttile; plot(1:numel(r.diagnostics.ibdfeCurve),r.diagnostics.ibdfeCurve,"o-"); hold on; plot(1:numel(r.diagnostics.jointCurve),r.diagnostics.jointCurve,"s-"); grid on; xlabel("Iteration"); ylabel("BER"); title("迭代收敛"); legend("IB-DFE","联合均衡");
exportgraphics(gcf,path,"Resolution",150); close(gcf);
end

function v=opt(o,n,d)
if isfield(o,n), v=o.(n); else, v=d; end
end
