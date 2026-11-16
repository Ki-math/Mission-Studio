% 新しいMATLABプロセスで回線計算の確認を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "link_check_log.txt");
try
    r = checkLinkBudget();
    lines = compose("%-18s MS %9.4f  hand %9.4f  diff %+.4f dB", r.Quantity, r.MissionStudio_dB, r.Hand_dB, r.Diff_dB);
    writelines([lines; "LINK_CHECK_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "LINK_CHECK_FAILED"], logFile);
end
