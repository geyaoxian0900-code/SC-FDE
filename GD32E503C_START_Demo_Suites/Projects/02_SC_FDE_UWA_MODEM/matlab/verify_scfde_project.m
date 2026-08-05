function report=verify_scfde_project()
%VERIFY_SCFDE_PROJECT Check required files and the GD32E503CE Keil target.
matlabFolder=fileparts(mfilename("fullpath")); projectFolder=fileparts(matlabFolder);
required=["main.c","scfde_app.c","scfde_app.h","scfde_modem.c","scfde_modem.h","scfde_fft.c","scfde_ldpc.c","scfde_ldpc.h", ...
    "scfde_equalizer.c","scfde_equalizer.h", ...
    "MDK-ARM/GD32E503C_START.uvprojx","EWARM/GD32E503C_START.eww", ...
    "matlab/run_text_scfde_demo.m","matlab/run_all_scfde_simulations.m"];
missing=strings(0,1); for file=required, if ~isfile(fullfile(projectFolder,file)), missing(end+1)=file; end, end %#ok<AGROW>
projectText=fileread(fullfile(projectFolder,"MDK-ARM","GD32E503C_START.uvprojx"));
targetOk=contains(projectText,"<Device>GD32E503CE</Device>");
report.target="GD32E503CE"; report.targetOk=targetOk; report.missingFiles=missing; report.pass=targetOk && isempty(missing);
fprintf("\n===== SC-FDE project verification =====\n");
fprintf("MCU target GD32E503CE: %s\n",pass_text(targetOk));
fprintf("Required files: %s (%d missing)\n",pass_text(isempty(missing)),numel(missing));
fprintf("Overall structural check: %s\n",pass_text(report.pass));
end

function text=pass_text(value)
if value, text="PASS"; else, text="FAIL"; end
end
