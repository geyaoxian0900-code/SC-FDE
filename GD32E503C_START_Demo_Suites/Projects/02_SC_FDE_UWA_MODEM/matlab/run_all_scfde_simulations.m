function summary=run_all_scfde_simulations(options)
%RUN_ALL_SCFDE_SIMULATIONS Run and index the Chapter 2 through 6 suites.
% profile="quick" is for regression checks; profile="full" uses defaults.
if nargin<1, options=struct(); end
profile=string(opt(options,"profile","quick")); chapters=opt(options,"chapters",2:6);
stopOnError=opt(options,"stopOnError",false); makePlot=opt(options,"makePlot",true);
if ~any(profile==["quick" "full"]), error("profile must be quick or full."); end
summary.profile=profile; summary.startedAt=datetime("now");
summary.chapters=struct("chapter",{},"status",{},"elapsedSeconds",{},"outputPath",{},"message",{});
fprintf("\n===== SC-FDE simulation runner (%s) =====\n",profile);
for chapter=chapters
    started=tic; entry=struct("chapter",chapter,"status","FAIL","elapsedSeconds",0,"outputPath","","message","");
    try
        chapterOptions=chapter_options(chapter,profile,makePlot);
        switch chapter
            case 2, result=simulate_chapter2_single_carrier_tde(chapterOptions);
            case 3, result=simulate_chapter3_scfde(chapterOptions);
            case 4, result=simulate_chapter4_iterative_equalization(chapterOptions);
            case 5, result=simulate_chapter5_cck(chapterOptions);
            case 6, result=simulate_chapter6_csk_multiuser(chapterOptions);
            otherwise, error("Unsupported chapter: %d",chapter);
        end
        entry.status="PASS"; if isfield(result,"outputPath"), entry.outputPath=string(result.outputPath); end
    catch exception
        entry.message=string(exception.message); if stopOnError, rethrow(exception); end
    end
    entry.elapsedSeconds=toc(started); summary.chapters(end+1)=entry; %#ok<AGROW>
    fprintf("Chapter %d: %s (%.2f s)\n",chapter,entry.status,entry.elapsedSeconds);
end
summary.completedAt=datetime("now"); folder=fullfile(fileparts(mfilename("fullpath")),"results");
if ~exist(folder,"dir"), mkdir(folder); end
summary.summaryPath=fullfile(folder,"all_simulations_summary.mat"); save(summary.summaryPath,"summary");
fprintf("Summary: %s\n",summary.summaryPath);
end

function options=chapter_options(chapter,profile,makePlot)
options=struct("makePlot",makePlot); if profile=="full", return; end
switch chapter
    case 2, options.trainingSymbols=128; options.dataSymbols=500;
    case 3, options.frameCount=5; options.snrList=[4 10 16];
    case 4, options.frameCount=2; options.infoBits=48; options.snrList=[-6 -2 2];
    case 5, options.frameCount=2; options.symbols=40; options.snrList=[0 6 12]; options.snrDb=6;
    case 6, options.frameCount=2; options.symbolsPerFrame=40; options.snrDb=[-4 4 12];
end
end

function value=opt(options,name,defaultValue)
if isfield(options,name), value=options.(name); else, value=defaultValue; end
end
