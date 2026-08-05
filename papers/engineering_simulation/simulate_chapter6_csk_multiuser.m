function results = simulate_chapter6_csk_multiuser(options)
%SIMULATE_CHAPTER6_CSK_MULTIUSER Run the modular Chapter 6 simulation suite.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.run_chapter6_spread_spectrum_suite"))
    addpath(moduleDir);
end
results = scfde.run_chapter6_spread_spectrum_suite(options, ...
    fileparts(mfilename("fullpath")));
return
end

%{

cfg.snrDb=opt(options,"snrDb",-6:2:14);
cfg.frameCount=opt(options,"frameCount",8);
cfg.symbolsPerFrame=opt(options,"symbolsPerFrame",120);
cfg.codeLength=opt(options,"codeLength",16);
cfg.modulationOrder=opt(options,"modulationOrder",16);
cfg.multiUserCounts=opt(options,"multiUserCounts",[1 3 5]);
cfg.idmaUsers=opt(options,"idmaUsers",4);
cfg.idmaIterations=opt(options,"idmaIterations",[1 4]);
cfg.picIterations=opt(options,"picIterations",4);
cfg.randomSeed=opt(options,"randomSeed",20260724);
cfg.measuredChannelFile=opt(options,"measuredChannelFile","");
cfg.makePlot=opt(options,"makePlot",true);
if 2^round(log2(cfg.codeLength))~=cfg.codeLength
    error("codeLength must be a power of two.");
end
if cfg.modulationOrder>cfg.codeLength || 2^round(log2(cfg.modulationOrder))~=cfg.modulationOrder
    error("modulationOrder must be a power of two no larger than codeLength.");
end
rng(cfg.randomSeed,"twister");
[h,channelInfo]=load_channel(cfg.measuredChannelFile,cfg.codeLength);
root=select_csk_root(cfg.codeLength);
[cskBook,bitTable]=csk_codebook(root,cfg.modulationOrder);
walsh=sylvester_hadamard(cfg.codeLength)/sqrt(cfg.codeLength);
orthBook=walsh(1:cfg.modulationOrder,:);

methodBer=zeros(3,numel(cfg.snrDb));
multiMfBer=zeros(numel(cfg.multiUserCounts),numel(cfg.snrDb));
multiPicBer=multiMfBer; idmaBer=zeros(4,numel(cfg.snrDb));
for s=1:numel(cfg.snrDb)
    methodErrors=zeros(1,3); methodTotals=zeros(1,3);
    mfErrors=zeros(size(cfg.multiUserCounts)); picErrors=mfErrors; multiTotals=mfErrors;
    idmaErrors=zeros(1,4); idmaTotal=0;
    for frame=1:cfg.frameCount
        [e,t]=simulate_ds(root,cfg.symbolsPerFrame,cfg.snrDb(s));
        methodErrors(1)=methodErrors(1)+e; methodTotals(1)=methodTotals(1)+t;
        [e,t]=simulate_codebook(orthBook,bitTable,cfg.symbolsPerFrame,cfg.snrDb(s));
        methodErrors(2)=methodErrors(2)+e; methodTotals(2)=methodTotals(2)+t;
        [e,t]=simulate_codebook(cskBook,bitTable,cfg.symbolsPerFrame,cfg.snrDb(s));
        methodErrors(3)=methodErrors(3)+e; methodTotals(3)=methodTotals(3)+t;
        for u=1:numel(cfg.multiUserCounts)
            users=cfg.multiUserCounts(u);
            dicts=make_user_dictionaries(cskBook,walsh,h,users);
            [a,b,t]=simulate_multiuser(dicts,bitTable,cfg.symbolsPerFrame, ...
                cfg.snrDb(s),cfg.picIterations);
            mfErrors(u)=mfErrors(u)+a; picErrors(u)=picErrors(u)+b;
            multiTotals(u)=multiTotals(u)+t;
        end
        [traditional,cyclic]=make_idma_dictionaries(cskBook,bitTable,h,cfg.idmaUsers,cfg.codeLength);
        [a,b,t]=simulate_idma(traditional,bitTable,cfg.symbolsPerFrame,cfg.snrDb(s),cfg.idmaIterations);
        [c,d,~]=simulate_idma(cyclic,bitTable,cfg.symbolsPerFrame,cfg.snrDb(s),cfg.idmaIterations);
        idmaErrors=idmaErrors+[a b c d]; idmaTotal=idmaTotal+t;
    end
    methodBer(:,s)=(methodErrors./methodTotals).';
    multiMfBer(:,s)=(mfErrors./multiTotals).';
    multiPicBer(:,s)=(picErrors./multiTotals).';
    idmaBer(:,s)=(idmaErrors/idmaTotal).';
end

corrMatrix=abs(cskBook*cskBook'); corrMatrix(1:size(corrMatrix,1)+1:end)=0;
results.config=cfg; results.channel=h; results.channelInfo=channelInfo;
results.rootSequence=root; results.cskBook=cskBook; results.crossCorrelation=corrMatrix;
results.methodBer=methodBer; results.multiMfBer=multiMfBer;
results.multiPicBer=multiPicBer; results.idmaBer=idmaBer;
results.outputPath=""; results.channelPlotPath="";
fprintf("\n===== Chapter 6 cyclic-shift spread spectrum =====\n");
fprintf("Channel: %s, taps=%d, CSK length=%d, M=%d\n",channelInfo.source,numel(h),cfg.codeLength,cfg.modulationOrder);
fprintf("Maximum off-diagonal CSK correlation: %.4f\n",max(corrMatrix(:)));
fprintf("BER at %.1f dB: DS=%.5g, M-ary=%.5g, CSK=%.5g\n",cfg.snrDb(end),methodBer(1,end),methodBer(2,end),methodBer(3,end));
fprintf("%d-user CSK at %.1f dB: MF=%.5g, PIC=%.5g\n",cfg.multiUserCounts(end),cfg.snrDb(end),multiMfBer(end,end),multiPicBer(end,end));
if cfg.makePlot
    [results.outputPath,results.channelPlotPath]=plot_results(results);
end
end

function [errors,total]=simulate_ds(root,count,ebn0Db)
bits=randi([0 1],count,1); tx=(1-2*bits).*root;
nv=10^(-ebn0Db/10); y=tx+sqrt(nv/2)*(randn(size(tx))+1j*randn(size(tx)));
detected=real(y*root')<0; errors=sum(detected~=bits); total=count;
end

function [errors,total]=simulate_codebook(book,bits,count,ebn0Db)
M=size(book,1); k=size(bits,2); index=randi(M,count,1); tx=book(index,:);
nv=1/(k*10^(ebn0Db/10)); y=tx+sqrt(nv/2)*(randn(size(tx))+1j*randn(size(tx)));
decision=nearest_codeword(y,book);
errors=sum(bits(decision,:)~=bits(index,:),"all"); total=count*k;
end

function decision=nearest_codeword(y,book)
[~,decision]=max(real(y*book'),[],2);
end

function [mfErrors,picErrors,total]=simulate_multiuser(dicts,bits,count,ebn0Db,iterations)
users=numel(dicts); M=size(dicts{1},1); k=size(bits,2); L=size(dicts{1},2);
index=randi(M,count,users); nv=1/(k*10^(ebn0Db/10));
mfDecision=zeros(count,users); picDecision=mfDecision;
for n=1:count
    y=zeros(1,L);
    for u=1:users, y=y+dicts{u}(index(n,u),:); end
    y=y+sqrt(nv/2)*(randn(1,L)+1j*randn(1,L));
    [mfDecision(n,:),picDecision(n,:)]=iterative_ic(y,dicts,iterations);
end
truth=reshape(bits(index(:),:),count,users,k);
mfBits=reshape(bits(mfDecision(:),:),count,users,k);
picBits=reshape(bits(picDecision(:),:),count,users,k);
mfErrors=sum(mfBits~=truth,"all"); picErrors=sum(picBits~=truth,"all"); total=count*users*k;
end

function [firstErrors,lastErrors,total]=simulate_idma(dicts,bits,count,ebn0Db,iterationPair)
users=numel(dicts); M=size(dicts{1},1); k=size(bits,2); L=size(dicts{1},2);
index=randi(M,count,users); nv=1/(k*10^(ebn0Db/10));
first=zeros(count,users); last=first; maxIterations=max(iterationPair);
for n=1:count
    y=zeros(1,L);
    for u=1:users, y=y+dicts{u}(index(n,u),:); end
    y=y+sqrt(nv/2)*(randn(1,L)+1j*randn(1,L));
    [first(n,:),last(n,:)]=iterative_ic(y,dicts,maxIterations);
end
truth=reshape(bits(index(:),:),count,users,k);
firstBits=reshape(bits(first(:),:),count,users,k); lastBits=reshape(bits(last(:),:),count,users,k);
firstErrors=sum(firstBits~=truth,"all"); lastErrors=sum(lastBits~=truth,"all"); total=count*users*k;
end

function [firstDecision,lastDecision]=iterative_ic(y,dicts,iterations)
users=numel(dicts); decision=zeros(1,users); estimates=zeros(users,numel(y));
for u=1:users
    distance=sum(abs(dicts{u}-y).^2,2); [~,decision(u)]=min(distance);
    estimates(u,:)=dicts{u}(decision(u),:);
end
firstDecision=decision;
initialEstimates=estimates;
for iter=2:iterations
    for u=1:users
        residual=y-sum(estimates([1:u-1 u+1:users],:),1);
        distance=sum(abs(dicts{u}-residual).^2,2); [~,candidate]=min(distance);
        estimates(u,:)=dicts{u}(candidate,:); decision(u)=candidate;
    end
end
initialResidual=sum(abs(y-sum(initialEstimates,1)).^2);
finalResidual=sum(abs(y-sum(estimates,1)).^2);
% A frame receiver can reject an unstable cancellation update by its
% reconstructed-signal residual (or by packet CRC in the complete modem).
if finalResidual < .85*initialResidual
    lastDecision=decision;
else
    lastDecision=firstDecision;
end
end

function dicts=make_user_dictionaries(book,walsh,h,users)
L=size(book,2); dicts=cell(1,users);
for u=1:users
    scramble=walsh(1+mod(3*u-2,L),:)*sqrt(L);
    userBook=circshift(book.*scramble,mod(2*u-2,L),2);
    dicts{u}=circular_channel(userBook,h);
end
end

function [traditional,cyclic]=make_idma_dictionaries(cskBook,bits,h,users,L)
k=size(bits,2); repeat=L/k; base=zeros(size(cskBook));
for m=1:size(bits,1)
    chips=reshape(repmat(1-2*bits(m,:).',1,repeat).',1,[]);
    base(m,:)=chips/sqrt(L);
end
traditional=cell(1,users); cyclic=traditional;
for u=1:users
    permutation=randperm(L);
    traditional{u}=circular_channel(base(:,permutation),h);
    cyclic{u}=circular_channel(cskBook(:,permutation),h);
end
end

function output=circular_channel(book,h)
L=size(book,2); hp=zeros(1,L); hp(1:min(L,numel(h)))=h(1:min(L,numel(h)));
output=ifft(fft(book,[],2).*fft(hp),[],2);
energy=sqrt(sum(abs(output).^2,2)); output=output./max(energy,eps);
end

function [book,bits]=csk_codebook(root,M)
k=round(log2(M)); bits=zeros(M,k); book=zeros(M,numel(root));
for m=0:M-1, bits(m+1,:)=bitget(m,1:k); book(m+1,:)=circshift(root,m); end
end

function root=select_csk_root(L)
bestScore=inf; root=ones(1,L);
for trial=1:300
    candidate=2*randi([0 1],1,L)-1;
    if abs(sum(candidate))>2, continue; end
    correlation=abs(ifft(abs(fft(candidate)).^2))/L; score=max(correlation(2:end));
    if score<bestScore, bestScore=score; root=candidate; end
end
root=root/sqrt(L);
end

function H=sylvester_hadamard(L)
H=zeros(L); H(1,1)=1; n=1;
while n<L
    block=H(1:n,1:n);
    H(1:n,n+1:2*n)=block; H(n+1:2*n,1:n)=block; H(n+1:2*n,n+1:2*n)=-block;
    n=2*n;
end
end

function [h,info]=load_channel(fileName,maxLength)
if strlength(string(fileName))>0
    if ~isfile(fileName), error("Measured channel file not found: %s",fileName); end
    data=load(fileName); names=["h","ir","impulseResponse"]; h=[];
    for n=names, if isfield(data,n), h=data.(n); break; end, end
    if isempty(h), error("MAT file must contain h, ir, or impulseResponse."); end
    info.source="measured MAT file"; info.file=string(fileName);
else
    h=zeros(1,12); h([1 3 7 11])=[1 .52*exp(1j*.80) .29*exp(-1j*1.10) .16*exp(1j*2.25)];
    info.source="reference multipath model"; info.file="";
end
h=h(:).'; h=h(1:min(numel(h),maxLength)); h=h/max(norm(h),eps);
info.pathCount=sum(abs(h)>max(abs(h))*1e-3);
end

function [mainPath,channelPath]=plot_results(r)
folder=fullfile(fileparts(mfilename("fullpath")),"results"); if ~exist(folder,"dir"), mkdir(folder); end
mainPath=fullfile(folder,"chapter6_csk_multiuser.png"); channelPath=fullfile(folder,"chapter6_csk_channel_profile.png");
colors=lines(max(6,numel(r.config.multiUserCounts)));
figure("Color","w","Position",[40 40 1450 900]); tiledlayout(2,3,"TileSpacing","compact","Padding","compact");
nexttile; semilogy(r.config.snrDb,r.methodBer.',"o-","LineWidth",1.2); grid on;
xlabel("E_b/N_0 (dB)"); ylabel("BER"); title("6.1 Spread-spectrum principles");
legend("DS-BPSK","M-ary orthogonal","CSK","Location","southwest");
nexttile; imagesc(r.crossCorrelation); axis image; colorbar; xlabel("Codeword index"); ylabel("Codeword index"); title("CSK cross-correlation");
nexttile; hold on;
for u=1:numel(r.config.multiUserCounts)
    semilogy(r.config.snrDb,r.multiMfBer(u,:),"--o","Color",colors(u,:),"LineWidth",1.1);
    semilogy(r.config.snrDb,r.multiPicBer(u,:),"-s","Color",colors(u,:),"LineWidth",1.2);
end
grid on; xlabel("E_b/N_0 (dB)"); ylabel("BER"); title("6.2 Conventional multiuser CSK");
legend(multiuser_legend(r.config.multiUserCounts),"Location","southwest");
nexttile; semilogy(r.config.multiUserCounts,r.multiMfBer(:,end),"o--",r.config.multiUserCounts,r.multiPicBer(:,end),"s-","LineWidth",1.2);
grid on; xlabel("Number of users"); ylabel("BER"); title(sprintf("User loading at %g dB",r.config.snrDb(end)));
legend("Matched filter","Iterative IC","Location","northwest");
nexttile([1 2]); semilogy(r.config.snrDb,r.idmaBer.',"o-","LineWidth",1.2); grid on;
xlabel("E_b/N_0 (dB)"); ylabel("BER"); title("6.3 Interleaving multiple access");
legend(sprintf("Traditional IDMA, %d iter",r.config.idmaIterations(1)),sprintf("Traditional IDMA, %d iter",r.config.idmaIterations(end)), ...
    sprintf("CSK-IDMA, %d iter",r.config.idmaIterations(1)),sprintf("CSK-IDMA, %d iter",r.config.idmaIterations(end)),"Location","southwest");
exportgraphics(gcf,mainPath,"Resolution",160); close(gcf);
figure("Color","w","Position",[120 120 1050 520]); stem(0:numel(r.channel)-1,abs(r.channel),"filled","LineWidth",1.2); grid on;
xlabel("Delay (chip samples)"); ylabel("Normalized magnitude"); title("Chapter 6 channel profile: "+r.channelInfo.source);
exportgraphics(gcf,channelPath,"Resolution",160); close(gcf);
end

function labels=multiuser_legend(counts)
labels=strings(1,2*numel(counts));
for k=1:numel(counts), labels(2*k-1)=sprintf("%d users, MF",counts(k)); labels(2*k)=sprintf("%d users, iterative IC",counts(k)); end
end

function value=opt(options,name,defaultValue)
if isfield(options,name), value=options.(name); else, value=defaultValue; end
end
%}
