function results=simulate_chapter5_cck(options)
%SIMULATE_CHAPTER5_CCK Chapter 5 CCK/Turbo/spatial-modulation suite.
% Includes FR-CCK, HR-CCK, GCCK, extended CCK, ISI-aware reception,
% MAP-like CCK Turbo detection, reduced-list detection, and 2x2 CCK-SM.

if nargin<1,options=struct();end
cfg.snrList=opt(options,"snrList",0:3:15);
cfg.snrDb=opt(options,"snrDb",9);
cfg.symbols=opt(options,"symbols",120);
cfg.frameCount=opt(options,"frameCount",5);
cfg.randomSeed=opt(options,"randomSeed",20260724);
cfg.turboIterations=opt(options,"turboIterations",4);
cfg.reducedList=opt(options,"reducedList",32);
cfg.makePlot=opt(options,"makePlot",true);
cfg.isiChannel=opt(options,"isiChannel",[1 .62*exp(1j*.5) .30*exp(-1j*1.0)]);
cfg.isiChannel=cfg.isiChannel(:).'/norm(cfg.isiChannel);
rng(cfg.randomSeed,"twister");
[frBook,frBits]=cck_codebook("FR"); [hrBook,hrBits]=cck_codebook("HR");
[gcckBook,gcckBits]=cck_codebook("GCCK"); [extBook,extBits]=cck_codebook("EXT");
books={frBook,hrBook,gcckBook,extBook}; bitTables={frBits,hrBits,gcckBits,extBits};
names=["FR-CCK","HR-CCK","GCCK","Extended CCK"];
awgnBer=zeros(4,numel(cfg.snrList)); isiBer=zeros(2,numel(cfg.snrList));
turboBer=zeros(2,numel(cfg.snrList)); smBer=zeros(1,numel(cfg.snrList));
for s=1:numel(cfg.snrList)
    errors=zeros(4,1); totals=zeros(4,1); ie=zeros(2,1); itotal=0;
    te=zeros(2,1); ttotal=0; se=0; stotal=0;
    for frame=1:cfg.frameCount
        for m=1:4
            [e,t]=simulate_awgn(books{m},bitTables{m},cfg.symbols,cfg.snrList(s));
            errors(m)=errors(m)+e; totals(m)=totals(m)+t;
        end
        [a,b,t]=simulate_isi(frBook,frBits,cfg,cfg.snrList(s));
        ie=ie+[a;b]; itotal=itotal+t;
        [a,b,t]=simulate_turbo(frBook,frBits,cfg,cfg.snrList(s));
        te=te+[a;b]; ttotal=ttotal+t;
        [a,t]=simulate_sm(hrBook,hrBits,cfg,cfg.snrList(s)); se=se+a; stotal=stotal+t;
    end
    awgnBer(:,s)=errors./totals; isiBer(:,s)=ie/itotal;
    turboBer(:,s)=te/ttotal; smBer(s)=se/stotal;
end

diag=diagnostic_frame(frBook,frBits,cfg);
results.config=cfg;results.names=names;results.awgnBer=awgnBer;
results.isiBer=isiBer;results.turboBer=turboBer;results.smBer=smBer;
results.frBook=frBook;results.frBits=frBits;results.diagnostics=diag;results.outputPath="";
fprintf("\n===== Chapter 5 CCK simulation =====\n");
for m=1:4, fprintf("%-16s BER@%.1fdB=%.5g\n",names(m),cfg.snrDb,interp1(cfg.snrList,awgnBer(m,:),cfg.snrDb));end
fprintf("ISI block/DFE BER=%.5g / %.5g\n",interp1(cfg.snrList,isiBer(1,:),cfg.snrDb),interp1(cfg.snrList,isiBer(2,:),cfg.snrDb));
fprintf("MAP-like/reduced Turbo BER=%.5g / %.5g\n",interp1(cfg.snrList,turboBer(1,:),cfg.snrDb),interp1(cfg.snrList,turboBer(2,:),cfg.snrDb));
if cfg.makePlot,results.outputPath=plot_results_clean(results);end
end

function [book,bits]=cck_codebook(mode)
switch mode
    case "FR", bitCount=8; lengthCode=8;
    case "HR", bitCount=4; lengthCode=8;
    case "GCCK", bitCount=6; lengthCode=8;
    otherwise, bitCount=8; lengthCode=16;
end
M=2^bitCount; bits=zeros(M,bitCount); book=zeros(M,lengthCode);
phaseMap=[0 pi/2 3*pi/2 pi];
for index=0:M-1
    b=bitget(index,1:bitCount); bits(index+1,:)=b;
    dibits=zeros(1,4);
    for k=1:min(4,ceil(bitCount/2))
        pair=b(2*k-1:min(2*k,bitCount)); if numel(pair)==1,pair(2)=0;end
        dibits(k)=pair(1)+2*pair(2);
    end
    if mode=="HR", dibits(3:4)=[mod(dibits(1)+1,4) mod(dibits(2)+2,4)];end
    if mode=="GCCK", dibits(4)=mod(sum(dibits(1:3)),4);end
    p=phaseMap(dibits+1); c=cck_word(p);
    if lengthCode==16
        spreading=[ones(1,8) 1 -1 1 -1 -1 1 -1 1]; book(index+1,:)=[c c].*spreading;
    else,book(index+1,:)=c;end
end
book=book/sqrt(lengthCode);
end

function c=cck_word(p)
p1=p(1);p2=p(2);p3=p(3);p4=p(4);
c=exp(1j*[p1+p2+p3+p4,p1+p3+p4,p1+p2+p4,p1+p4,...
    p1+p2+p3,p1+p3,p1+p2,p1]); c([4 7])=-c([4 7]);
end

function [errors,total]=simulate_awgn(book,bits,count,snrDb)
M=size(book,1);index=randi(M,1,count);tx=book(index,:);
nv=10^(-snrDb/10);y=tx+sqrt(nv/2)*(randn(size(tx))+1j*randn(size(tx)));
det=nearest_book(y,book);errors=sum(bits(det,:)~=bits(index,:),"all");total=numel(bits(index,:));
end

function detected=nearest_book(y,book)
detected=zeros(1,size(y,1));
for k=1:size(y,1)
    [~,detected(k)]=min(sum(abs(book-y(k,:)).^2,2));
end
end

function [blockErrors,dfeErrors,total]=simulate_isi(book,bits,cfg,snrDb)
M=size(book,1);L=size(book,2);idx=randi(M,1,cfg.symbols);chips=reshape(book(idx,:).',1,[]);
h=cfg.isiChannel;nv=10^(-snrDb/10);y=filter(h,1,chips)+sqrt(nv/2)*(randn(size(chips))+1j*randn(size(chips)));
block=zeros(1,cfg.symbols);dfe=block;tail=zeros(1,numel(h)-1);
candidate=cell(M,1);for m=1:M,candidate{m}=conv(book(m,:),h);end
for k=1:cfg.symbols
    r=y((k-1)*L+(1:L));block(k)=nearest_book(r,book);
    distance=zeros(M,1);
    for m=1:M,p=candidate{m};distance(m)=sum(abs(r-(p(1:L)+[tail zeros(1,L-numel(tail))])).^2);end
    [~,dfe(k)]=min(distance);p=candidate{dfe(k)};tail=p(L+1:end);
end
blockErrors=sum(bits(block,:)~=bits(idx,:),"all");dfeErrors=sum(bits(dfe,:)~=bits(idx,:),"all");total=numel(bits(idx,:));
end

function [mapErrors,reducedErrors,total]=simulate_turbo(book,bits,cfg,snrDb)
M=size(book,1);L=size(book,2);idx=randi(M,1,cfg.symbols);chips=reshape(book(idx,:).',1,[]);
h=cfg.isiChannel;nv=10^(-snrDb/10);y=filter(h,1,chips)+sqrt(nv/2)*(randn(size(chips))+1j*randn(size(chips)));
[mapDecision,mapCurve]=turbo_detect(y,book,h,nv,cfg.turboIterations,M);
[reducedDecision,reducedCurve]=turbo_detect(y,book,h,nv,cfg.turboIterations,min(cfg.reducedList,M));
mapErrors=sum(bits(mapDecision,:)~=bits(idx,:),"all");reducedErrors=sum(bits(reducedDecision,:)~=bits(idx,:),"all");total=numel(bits(idx,:));
if isempty(mapCurve)||isempty(reducedCurve),error("Turbo detector failed.");end
end

function [decision,curve]=turbo_detect(y,book,h,nv,iterations,listSize)
M=size(book,1);L=size(book,2);K=floor(numel(y)/L);soft=zeros(1,numel(y));decision=ones(1,K);curve=zeros(1,iterations);
for iter=1:iterations
    residual=y-filter(h,1,soft);confidence=0;
    for k=1:K
        r=residual((k-1)*L+(1:L));distance=sum(abs(book-r).^2,2);
        [sorted,order]=sort(distance);active=order(1:min(listSize,M));weights=exp(-(sorted(1:numel(active))-sorted(1))/max(nv,1e-6));weights=weights/sum(weights);
        [~,best]=min(distance);decision(k)=best;estimate=weights.'*book(active,:);
        soft((k-1)*L+(1:L))=.65*soft((k-1)*L+(1:L))+.35*estimate;confidence=confidence+weights(1);
    end
    curve(iter)=confidence/K;
end
end

function [errors,total]=simulate_sm(book,bits,cfg,snrDb)
M=size(book,1);L=size(book,2);K=cfg.symbols;H=(randn(2,2)+1j*randn(2,2))/2;idx=randi(M,1,K);antenna=randi(2,1,K);nv=10^(-snrDb/10);detIdx=zeros(1,K);detAnt=zeros(1,K);
for k=1:K
    y=H(:,antenna(k))*book(idx(k),:)+sqrt(nv/2)*(randn(2,L)+1j*randn(2,L));best=inf;
    for a=1:2
        for m=1:M
            d=sum(abs(y-H(:,a)*book(m,:)).^2,"all");if d<best,best=d;detIdx(k)=m;detAnt(k)=a;end
        end
    end
end
errors=sum(bits(detIdx,:)~=bits(idx,:),"all")+sum(detAnt~=antenna);total=numel(bits(idx,:))+K;
end

function d=diagnostic_frame(book,bits,cfg)
M=size(book,1);L=size(book,2);idx=randi(M,1,cfg.symbols);chips=reshape(book(idx,:).',1,[]);h=cfg.isiChannel;nv=10^(-cfg.snrDb/10);y=filter(h,1,chips)+sqrt(nv/2)*(randn(size(chips))+1j*randn(size(chips)));
[decision,curve]=turbo_detect(y,book,h,nv,cfg.turboIterations,M);d.curve=curve;d.errors=sum(bits(decision,:)~=bits(idx,:),"all");d.tx=chips;d.rx=y;
corr=abs(book*book');corr(1:M+1:end)=0;d.crossCorrelation=max(corr,[],2);
end

function path=plot_results(r)
path=fullfile(fileparts(mfilename("fullpath")),"results","chapter5_cck_simulation.png");if ~exist(fileparts(path),"dir"),mkdir(fileparts(path));end
figure("Color","w","Position",[60 60 1400 850]);tiledlayout(2,3,"TileSpacing","compact");
nexttile([1 2]);hold on;for k=1:4,semilogy(r.config.snrList,r.awgnBer(k,:),"o-","LineWidth",1.1);end;grid on;xlabel("SNR/dB");ylabel("BER");title("FR/HR/GCCK/扩展CCK性能");legend(r.names,"Location","southwest");
nexttile;plot(r.diagnostics.crossCorrelation);grid on;title("FR-CCK最大互相关");xlabel("Codeword");ylabel("Correlation");
nexttile;semilogy(r.config.snrList,r.isiBer(1,:),"o-",r.config.snrList,r.isiBer(2,:),"s-");grid on;title("有ISI时的CCK接收");xlabel("SNR/dB");ylabel("BER");legend("Block ML","DFE-ML");
nexttile;semilogy(r.config.snrList,r.turboBer(1,:),"o-",r.config.snrList,r.turboBer(2,:),"s-");grid on;title("MAP-CCK Turbo与降复杂度方法");xlabel("SNR/dB");ylabel("BER");legend("Full list","Reduced list");
nexttile;plot(1:r.config.turboIterations,r.diagnostics.curve,"o-");yyaxis right;semilogy(r.config.snrList,r.smBer,"s-");grid on;title("Turbo收敛与CCK-SM");xlabel("Iteration / SNR index");legend("Turbo confidence","CCK-SM BER");
exportgraphics(gcf,path,"Resolution",150);close(gcf);
end

function v=opt(o,n,d)
if isfield(o,n),v=o.(n);else,v=d;end
end

function path=plot_results_clean(r)
path=fullfile(fileparts(mfilename("fullpath")),"results","chapter5_cck_simulation.png");
if ~exist(fileparts(path),"dir"),mkdir(fileparts(path));end
figure("Color","w","Position",[60 60 1400 850]); tiledlayout(2,3,"TileSpacing","compact");
nexttile([1 2]); hold on;
for k=1:4,semilogy(r.config.snrList,r.awgnBer(k,:),"o-","LineWidth",1.1);end
grid on;xlabel("SNR (dB)");ylabel("BER");title("FR/HR/GCCK/Extended CCK");legend(r.names,"Location","southwest");
nexttile;plot(r.diagnostics.crossCorrelation);grid on;title("FR-CCK maximum cross-correlation");xlabel("Codeword");ylabel("Correlation");
nexttile;semilogy(r.config.snrList,r.isiBer(1,:),"o-",r.config.snrList,r.isiBer(2,:),"s-");
grid on;title("CCK reception with ISI");xlabel("SNR (dB)");ylabel("BER");legend("Block ML","DFE-ML");
nexttile;semilogy(r.config.snrList,r.turboBer(1,:),"o-",r.config.snrList,r.turboBer(2,:),"s-");
grid on;title("MAP-like and reduced-list detection");xlabel("SNR (dB)");ylabel("BER");legend("Full list","Reduced list");
nexttile;semilogy(r.config.snrList,r.smBer,"s-","LineWidth",1.1);grid on;
title("2x2 CCK spatial modulation");xlabel("SNR (dB)");ylabel("BER");
exportgraphics(gcf,path,"Resolution",150);close(gcf);
end
