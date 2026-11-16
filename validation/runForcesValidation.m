% 新しいMATLABプロセスで力モデルの比較検証を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "forces_validation_log.txt");
try
    r = compareForcesWithGmat();
    lines = compose("%-14s diff %.6f km, effect %.4f km", r.Case, r.MaxDiff_km, r.Effect_km);
    writelines([lines; "FORCES_VALIDATION_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "FORCES_VALIDATION_FAILED"], logFile);
end
