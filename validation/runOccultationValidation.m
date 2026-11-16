% 新しいMATLABプロセスで掩蔽の比較検証を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "occultation_validation_log.txt");
try
    r = compareOccultationWithGmat();
    lines = [sprintf("intervals %s, max diff %.3f s", r.Counts, r.MaxDiff_s)
        "MS:";   compose("  %s  %s", string(r.MissionStudio.StartTime, "dd HH:mm:ss.SSS"), string(r.MissionStudio.EndTime, "dd HH:mm:ss.SSS"))
        "GMAT:"; compose("  %s  %s", string(r.Gmat.StartTime, "dd HH:mm:ss.SSS"), string(r.Gmat.EndTime, "dd HH:mm:ss.SSS"))];
    writelines([lines; "OCC_VALIDATION_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "OCC_VALIDATION_FAILED"], logFile);
end
