function results=simulate_chapter4_iterative_equalization(options)
%SIMULATE_CHAPTER4_ITERATIVE_EQUALIZATION Chapter 4 Turbo equalizer suite.
% Includes convolutional coding/interleaving, Log-MAP and Max-Log-MAP,
% time-domain Turbo equalization, frequency-domain decision feedback,
% unidirectional/bidirectional time-frequency Turbo equalization, and BLMS.

if nargin<1, options=struct(); end
cfg.infoBits=opt(options,"infoBits",64);
cfg.frameCount=opt(options,"frameCount",8);
cfg.iterations=opt(options,"iterations",4);
cfg.snrList=opt(options,"snrList",-8:2:4);
cfg.snrDb=opt(options,"snrDb",-2);
cfg.randomSeed=opt(options,"randomSeed",20260724);
cfg.makePlot=opt(options,"makePlot",true);
cfg.blmsStep=opt(options,"blmsStep",0.06);
cfg.channel=opt(options,"channel",[1 .72*exp(1j*.45) .43*exp(-1j*.9) .22*exp(1j*1.5)]);
cfg.channel=cfg.channel(:).'/norm(cfg.channel);
rng(cfg.randomSeed,"twister");
methods=["Time Turbo","Frequency DFE","TF Turbo","Bidirectional TF","BLMS TF Turbo"];
ber=zeros(numel(methods),numel(cfg.snrList));
for s=1:numel(cfg.snrList)
    errors=zeros(numel(methods),1); total=0;
    for f=1:cfg.frameCount
        frame=run_frame(cfg,cfg.snrList(s));
        errors=errors+frame.errors; total=total+cfg.infoBits;
    end
    ber(:,s)=errors/total;
end
example=run_frame(cfg,cfg.snrDb);
results.config=cfg; results.methods=methods; results.ber=ber;
results.example=example; results.outputPath="";
fprintf("\n===== Chapter 4 iterative equalization =====\n");
fprintf("Information bits=%d, iterations=%d, convolutional code rate=1/2\n",cfg.infoBits,cfg.iterations);
for k=1:numel(methods)
    fprintf("%-24s BER@%.1fdB=%.5g\n",methods(k),cfg.snrDb,example.errors(k)/cfg.infoBits);
end
fprintf("Decoder comparison: Log-MAP BER=%.5g, Max-Log-MAP BER=%.5g\n",...
    example.logMapErrors/cfg.infoBits,example.maxLogErrors/cfg.infoBits);
if cfg.makePlot, results.outputPath=plot_results(results); end
end

function out=run_frame(cfg,snrDb)
info=randi([0 1],1,cfg.infoBits); coded=conv_encode(info);
N=numel(coded); permutation=randperm(N); inverse(permutation)=1:N;
interleaved=coded(permutation); x=1-2*interleaved;
h=[cfg.channel zeros(1,N-numel(cfg.channel))]; H=fft(h); X=fft(x);
noiseVariance=10^(-snrDb/10); y=ifft(H.*X);
y=y+sqrt(noiseVariance/2)*(randn(size(y))+1j*randn(size(y))); Y=fft(y);
Hinitial=H+sqrt(noiseVariance*.15/2)*(randn(size(H))+1j*randn(size(H)));
W=conj(Hinitial)./(abs(Hinitial).^2+noiseVariance);
initial=ifft(W.*Y); initialLlr=2*real(initial)/noiseVariance;
[logInfo,~]=bcjr_decode(initialLlr(inverse),"logmap");
[maxInfo,~]=bcjr_decode(initialLlr(inverse),"maxlog");
out.logMapErrors=sum((logInfo<0)~=info); out.maxLogErrors=sum((maxInfo<0)~=info);

% Time-domain Turbo equalizer: linear MMSE correction of soft cancellation.
C=circulant_channel(cfg.channel,N);
Wt=(C'*C+noiseVariance*eye(N))\C';
[timeBits,timeCurve]=iterate_time(y,C,Wt,info,permutation,inverse,cfg);

% Frequency-domain decision-feedback equalizer.
[fdBits,fdCurve]=iterate_frequency(Y,Hinitial,noiseVariance,info,permutation,inverse,cfg,false,false);

% Unidirectional time-frequency Turbo combines both extrinsic estimates.
[tfBits,tfCurve]=iterate_time_frequency(y,Y,C,Wt,Hinitial,noiseVariance,...
    info,permutation,inverse,cfg,false);

% Bidirectional processing averages forward and reversed soft decisions.
[biBits,biCurve]=iterate_time_frequency(y,Y,C,Wt,Hinitial,noiseVariance,...
    info,permutation,inverse,cfg,true);

% BLMS frequency adaptive Turbo equalizer updates H every iteration.
[blmsBits,blmsCurve,Hblms]=iterate_frequency(Y,Hinitial,noiseVariance,...
    info,permutation,inverse,cfg,true,false);
out.errors=[sum(timeBits~=info);sum(fdBits~=info);sum(tfBits~=info);...
    sum(biBits~=info);sum(blmsBits~=info)];
out.curves=[timeCurve;fdCurve;tfCurve;biCurve;blmsCurve];
out.info=info; out.initial=initial; out.H=H; out.Hinitial=Hinitial; out.Hblms=Hblms;
out.logMapBits=logInfo<0; out.maxLogBits=maxInfo<0;
end

function [bits,curve]=iterate_time(y,C,Wt,info,p,ip,cfg)
N=numel(y); soft=zeros(N,1); curve=zeros(1,cfg.iterations);
for iter=1:cfg.iterations
    estimate=soft+Wt*(y(:)-C*soft);
    llr=2*real(estimate).'; [decoder,~]=bcjr_decode(llr(ip),"logmap");
    bits=decoder<0; reliability=min(.98,mean(abs(tanh(decoder/2))));
    feedback=1-2*conv_encode(bits); soft=reliability*feedback(p).';
    curve(iter)=mean(bits~=info);
end
end

function [bits,curve,Hest]=iterate_frequency(Y,Hest,nv,info,p,ip,cfg,blms,unused)
N=numel(Y); soft=zeros(1,N); curve=zeros(1,cfg.iterations); %#ok<NASGU>
for iter=1:cfg.iterations
    W=conj(Hest)./(abs(Hest).^2+nv);
    estimate=soft+ifft(W.*(Y-Hest.*fft(soft)));
    llr=2*real(estimate)/nv; [decoder,~]=bcjr_decode(llr(ip),"logmap");
    bits=decoder<0; reliability=min(.98,mean(abs(tanh(decoder/2))));
    feedback=1-2*conv_encode(bits); soft=reliability*feedback(p);
    if blms
        Xsoft=fft(soft); error=Y-Hest.*Xsoft;
        denominator=abs(Xsoft).^2+nv*numel(Y);
        Hest=Hest+cfg.blmsStep*conj(Xsoft).*error./denominator;
    end
    curve(iter)=mean(bits~=info);
end
end

function [bits,curve]=iterate_time_frequency(y,Y,C,Wt,H,nv,info,p,ip,cfg,bidirectional)
N=numel(y); soft=zeros(1,N); curve=zeros(1,cfg.iterations);
for iter=1:cfg.iterations
    timeEstimate=soft(:)+Wt*(y(:)-C*soft(:));
    W=conj(H)./(abs(H).^2+nv);
    freqEstimate=soft+ifft(W.*(Y-H.*fft(soft)));
    estimate=.5*timeEstimate.'+.5*freqEstimate;
    if bidirectional
        reverseEstimate=fliplr(conj(fliplr(estimate)));
        estimate=.5*estimate+.5*reverseEstimate;
    end
    llr=2*real(estimate)/nv;
    [decoder,~]=bcjr_decode(llr(ip),"logmap");
    bits=decoder<0; reliability=min(.98,mean(abs(tanh(decoder/2))));
    feedback=1-2*conv_encode(bits); soft=reliability*feedback(p);
    curve(iter)=mean(bits~=info);
end
end

function coded=conv_encode(bits)
state=[0 0]; coded=zeros(1,2*numel(bits));
for k=1:numel(bits)
    u=bits(k); coded(2*k-1)=mod(u+state(1)+state(2),2);
    coded(2*k)=mod(u+state(2),2); state=[u state(1)];
end
end

function [infoLlr,metric]=bcjr_decode(codedLlr,mode)
T=numel(codedLlr)/2; S=4; [next,out]=trellis();
alpha=-inf(T+1,S); beta=-inf(T+1,S); alpha(1,1)=0; beta(T+1,:)=0;
for t=1:T
    L=codedLlr(2*t-1:2*t);
    for s=1:S
        for u=0:1
            ns=next(s,u+1); c=squeeze(out(s,u+1,:)).';
            g=.5*sum((1-2*c).*L); alpha(t+1,ns)=combine(alpha(t+1,ns),alpha(t,s)+g,mode);
        end
    end
end
for t=T:-1:1
    L=codedLlr(2*t-1:2*t);
    for s=1:S
        for u=0:1
            ns=next(s,u+1); c=squeeze(out(s,u+1,:)).'; g=.5*sum((1-2*c).*L);
            beta(t,s)=combine(beta(t,s),g+beta(t+1,ns),mode);
        end
    end
end
infoLlr=zeros(1,T);
for t=1:T
    value=[-inf -inf]; L=codedLlr(2*t-1:2*t);
    for s=1:S
        for u=0:1
            ns=next(s,u+1); c=squeeze(out(s,u+1,:)).'; g=.5*sum((1-2*c).*L);
            value(u+1)=combine(value(u+1),alpha(t,s)+g+beta(t+1,ns),mode);
        end
    end
    infoLlr(t)=value(1)-value(2);
end
metric=alpha;
end

function z=combine(a,b,mode)
if mode=="maxlog", z=max(a,b); else
    m=max(a,b); if isinf(m), z=m; else, z=m+log(exp(a-m)+exp(b-m)); end
end
end

function [next,out]=trellis()
next=zeros(4,2); out=zeros(4,2,2);
for s=0:3
    memory=[bitget(s,2) bitget(s,1)];
    for u=0:1
        next(s+1,u+1)=u*2+memory(1)+1;
        out(s+1,u+1,:)=[mod(u+sum(memory),2) mod(u+memory(2),2)];
    end
end
end

function C=circulant_channel(h,N)
column=[h(:);zeros(N-numel(h),1)]; C=zeros(N);
for k=1:N, C(:,k)=circshift(column,k-1); end
end

function path=plot_results(r)
path=fullfile(fileparts(mfilename("fullpath")),"results","chapter4_iterative_equalization.png");
if ~exist(fileparts(path),"dir"),mkdir(fileparts(path));end
figure("Color","w","Position",[80 80 1350 820]); tiledlayout(2,2,"TileSpacing","compact");
nexttile; hold on; for k=1:numel(r.methods),semilogy(r.config.snrList,r.ber(k,:),"o-","LineWidth",1.1);end; grid on;xlabel("SNR/dB");ylabel("BER");title("第4章迭代均衡性能");legend(r.methods,"Location","southwest");
nexttile; plot(1:r.config.iterations,r.example.curves.',"o-");grid on;xlabel("Iteration");ylabel("BER");title("Turbo迭代收敛");legend(r.methods);
nexttile; stem(abs(r.example.H-r.example.Hinitial));hold on;stem(abs(r.example.H-r.example.Hblms));grid on;title("BLMS信道估计误差");legend("Initial","After BLMS");xlabel("Frequency bin");
nexttile; bar([r.example.logMapErrors r.example.maxLogErrors]/r.config.infoBits);grid on;set(gca,"XTickLabel",["Log-MAP","Max-Log-MAP"]);ylabel("BER");title("MAP近似算法比较");
exportgraphics(gcf,path,"Resolution",150);close(gcf);
end

function v=opt(o,n,d)
if isfield(o,n),v=o.(n);else,v=d;end
end
