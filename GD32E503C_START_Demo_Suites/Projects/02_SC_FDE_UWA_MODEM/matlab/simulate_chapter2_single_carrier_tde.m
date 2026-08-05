function results = simulate_chapter2_single_carrier_tde(options)
%SIMULATE_CHAPTER2_SINGLE_CARRIER_TDE Chapter 2 single-carrier TDE suite.
% Compares conventional DFE, adaptive NLMS DFE, PLL-DFE, multichannel DFE,
% passive time-reversal DFE, and subband passive time-reversal DFE.

if nargin < 1, options = struct(); end
cfg.snrDb = opt(options,"snrDb",12);
cfg.dopplerHz = opt(options,"dopplerHz",1.5);
cfg.symbolRate = opt(options,"symbolRate",4000);
cfg.trainingSymbols = opt(options,"trainingSymbols",256);
cfg.dataSymbols = opt(options,"dataSymbols",1200);
cfg.feedforwardTaps = opt(options,"feedforwardTaps",24);
cfg.feedbackTaps = opt(options,"feedbackTaps",12);
cfg.randomSeed = opt(options,"randomSeed",20260724);
cfg.makePlot = opt(options,"makePlot",true);
cfg.numSubbands = opt(options,"numSubbands",4);
cfg.ptrRegularization = opt(options,"ptrRegularization",0.02);
cfg.nlmsStep = opt(options,"nlmsStep",0.35);
cfg.pllStep = opt(options,"pllStep",0.015);
cfg.pathDelays = opt(options,"pathDelays",[0 2 5 8]);
cfg.pathGains = opt(options,"pathGains",[1, .72*exp(1j*.5), ...
    .48*exp(-1j*1.0), .30*exp(1j*1.7)]);
assert(numel(cfg.pathDelays)==numel(cfg.pathGains),"Path configuration mismatch.");
rng(cfg.randomSeed,"twister");
cfg.totalSymbols = cfg.trainingSymbols + cfg.dataSymbols;
training = 2*randi([0 1],1,cfg.trainingSymbols)-1;
data = 2*randi([0 1],1,cfg.dataSymbols)-1;
tx = [training data];
h = cfg.pathGains(:).'; h = h/norm(h);
[y,branches] = channel_model(tx,h,cfg.pathDelays,cfg.dopplerHz,...
    cfg.symbolRate,cfg.snrDb);

[r1,m1] = known_dfe(y,tx,h,cfg);
[r2,m2] = nlms_dfe(y,tx,cfg,false);
[r3,m3] = nlms_dfe(y,tx,cfg,true);
[r4,m4] = multichannel_dfe(branches,tx,cfg);
ptr = conj(fliplr(h));
[r5,m5] = known_dfe(filter(ptr,1,y),tx,conv(ptr,h),cfg);
subband = subband_ptr(y,h,cfg.numSubbands,cfg.ptrRegularization);
[r6,m6] = known_dfe(subband,tx,conv(ptr,h),cfg);

receivers = {r1,r2,r3,r4,r5,r6};
names = ["Conventional DFE","Adaptive NLMS DFE","PLL-assisted DFE",...
    "Multichannel DFE","Passive TR-DFE","Subband passive TR-DFE"];
ber = zeros(1,numel(receivers));
for k=1:numel(receivers)
    ber(k)=mean(receivers{k}(cfg.trainingSymbols+1:end)~=data);
end
results.config=cfg; results.names=names; results.ber=ber;
results.tx=tx; results.channel=h; results.received=y;
results.receivers=receivers; results.learningMse={m1,m2,m3,m4,m5,m6};
fprintf("\n===== Chapter 2 single-carrier TDE simulation =====\n");
fprintf("SNR=%.1f dB, Doppler=%.2f Hz, data=%d symbols\n",...
    cfg.snrDb,cfg.dopplerHz,cfg.dataSymbols);
for k=1:numel(names), fprintf("%-28s BER=%.5g\n",names(k),ber(k)); end
results.outputPath="";
if cfg.makePlot, results.outputPath=plot_results(results); end
end

function [y,b] = channel_model(x,h,delays,doppler,fs,snr)
b=zeros(2,numel(x));
for c=1:2
    hc=h.*(1+.10*randn(size(h))).*exp(1j*.25*randn(size(h)));
    hc=hc/norm(hc);
    b(c,:)=apply_channel(x,hc,delays,doppler*(1+.04*randn),fs);
end
y=b(1,:)+sqrt(.55)*b(2,:);
np=mean(abs(y).^2)/10^(snr/10);
y=y+sqrt(np/2)*(randn(size(y))+1j*randn(size(y)));
b=b+sqrt(np/2)*(randn(size(b))+1j*randn(size(b)));
end

function y=apply_channel(x,h,delays,doppler,fs)
y=zeros(size(x)); n=0:numel(x)-1;
for k=1:numel(h)
    d=delays(k); z=zeros(size(x));
    if d==0, z=x; elseif d<numel(x), z(d+1:end)=x(1:end-d); end
    y=y+h(k)*z.*exp(1j*2*pi*doppler*n/fs);
end
end

function [dout,mse]=known_dfe(y,reference,h,cfg)
lf=cfg.feedforwardTaps; lb=cfg.feedbackTaps;
delay=min(ceil(numel(h)/2),lf-1); L=numel(h)+lf-1; H=zeros(L,lf);
for k=1:lf, H(k:k+numel(h)-1,k)=h(:); end
target=zeros(L,1); target(delay+1)=1;
w=(H'*H+10^(-cfg.snrDb/10)*.03*eye(lf))\(H'*target);
g=conv(w,h(:)); z=filter(w,1,y); dout=zeros(size(reference)); mse=zeros(size(reference));
for n=delay+1:numel(reference)
    q=n+delay; if q>numel(z), break; end
    fb=0;
    for k=1:min(lb,n-1)
        t=delay+k+1; if t<=numel(g), fb=fb+g(t)*dout(n-k); end
    end
    e=z(q)-fb;
    if n<=cfg.trainingSymbols, dout(n)=reference(n); else, dout(n)=sign(real(e)); end
    if dout(n)==0, dout(n)=1; end
    mse(n)=abs(e-reference(n))^2;
end
end

function [dout,mse]=nlms_dfe(y,reference,cfg,pll)
lf=cfg.feedforwardTaps; lb=cfg.feedbackTaps; delay=min(ceil(lf/3),lf-1);
w=zeros(lf+lb,1); w(delay+1)=1; dout=zeros(size(reference)); mse=zeros(size(reference)); phase=0;
for n=max(lf,lb+delay+1):min(numel(reference),numel(y)-delay)
    u=[y(n+delay:-1:n+delay-lf+1).'; -dout(n-1:-1:n-lb).']; ehat=w'*u;
    if pll, ehat=ehat*exp(-1j*phase); end
    if n<=cfg.trainingSymbols, dout(n)=reference(n); else, dout(n)=sign(real(ehat)); end
    if dout(n)==0, dout(n)=1; end
    err=dout(n)-ehat; w=w+cfg.nlmsStep*conj(err)*u/(real(u'*u)+1e-5);
    if pll && n>cfg.trainingSymbols, phase=phase+cfg.pllStep*angle(ehat*conj(dout(n))); end
    mse(n)=abs(reference(n)-ehat)^2;
end
end

function [dout,mse]=multichannel_dfe(b,reference,cfg)
lf=cfg.feedforwardTaps; lb=cfg.feedbackTaps; delay=min(ceil(lf/3),lf-1); C=size(b,1);
w=zeros(C*lf+lb,1); w(delay+1)=1; dout=zeros(size(reference)); mse=zeros(size(reference));
for n=max(lf,lb+delay+1):min(numel(reference),size(b,2)-delay)
    u=zeros(C*lf+lb,1);
    for c=1:C, u((c-1)*lf+(1:lf))=b(c,n+delay:-1:n+delay-lf+1).'; end
    u(C*lf+1:end)=-dout(n-1:-1:n-lb).'; ehat=w'*u;
    if n<=cfg.trainingSymbols, dout(n)=reference(n); else, dout(n)=sign(real(ehat)); end
    if dout(n)==0, dout(n)=1; end
    err=dout(n)-ehat; w=w+cfg.nlmsStep*conj(err)*u/(real(u'*u)+1e-5); mse(n)=abs(reference(n)-ehat)^2;
end
end

function y=subband_ptr(x,h,bands,mu)
N=2^nextpow2(numel(x)+numel(h)-1); X=fft(x,N); H=fft([h zeros(1,N-numel(h))]); Y=zeros(1,N); f=(0:N-1)/N;
for k=1:bands
    mask=f>=(k-1)/bands & f<k/bands;
    if k==bands, mask=f>=(k-1)/bands; end
    Y(mask)=X(mask).*conj(H(mask))./(abs(H(mask)).^2+mu);
end
y=ifft(Y,"symmetric"); y=y(1:numel(x));
end

function path=plot_results(r)
path=fullfile(fileparts(mfilename("fullpath")),"results",...
    "chapter2_single_carrier_tde.png");
if ~exist(fileparts(path),"dir"), mkdir(fileparts(path)); end
figure("Color","w","Position",[80 80 1300 850]); tiledlayout(2,2,"TileSpacing","compact");
nexttile; stem(0:numel(r.channel)-1,abs(r.channel),"filled"); grid on; title("时变多径信道抽头"); xlabel("Path"); ylabel("Magnitude");
nexttile; bar(r.ber); set(gca,"YScale","log"); grid on; title("第2章均衡器 BER 对比"); ylabel("BER"); set(gca,"XTick",1:numel(r.names),"XTickLabel",r.names); xtickangle(25);
nexttile; hold on; for k=1:numel(r.learningMse), z=movmean(r.learningMse{k},32); z(z<=0)=NaN; plot(10*log10(z)); end; grid on; title("均衡器学习曲线"); xlabel("Symbol"); ylabel("MSE/dB"); legend(r.names,"Location","best");
nexttile; id=r.config.trainingSymbols+(1:min(500,r.config.dataSymbols)); plot(real(r.tx(id)),"k."); hold on; plot(real(r.receivers{2}(id)),"b."); plot(real(r.receivers{5}(id)),"r."); grid on; ylim([-1.6 1.6]); title("数据段判决"); legend("TX","Adaptive DFE","PTR-DFE");
exportgraphics(gcf,path,"Resolution",150); close(gcf);
end

function v=opt(o,n,d)
if isfield(o,n), v=o.(n); else, v=d; end
end
