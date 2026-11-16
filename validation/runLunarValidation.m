% 新しいMATLABプロセスで月遷移の比較検証を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "lunar_validation_log.txt");
try
    r = compareLunarWithGmat();
    writelines([sprintf("max %.6f km, perilune %.6f km, moon dist %.6f km", ...
        r.MaxPosDiff_km, r.PeriluneDiff_km, r.MoonDistDiff_km); "LUNAR_VALIDATION_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "LUNAR_VALIDATION_FAILED"], logFile);
end
