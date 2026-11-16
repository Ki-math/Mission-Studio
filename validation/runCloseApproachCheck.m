% 新しいMATLABプロセスで最接近の確認を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "close_approach_log.txt");
try
    r = checkCloseApproach();
    lines = [sprintf("30 s: miss %.4f km, TCA %s, rel speed %.3f km/s", r.Coarse.MissDistance_km, string(r.Coarse.TCA, "HH:mm:ss.SSS"), r.Coarse.RelSpeed_kmps)
        sprintf(" 1 s: miss %.4f km, TCA %s", r.Fine.MissDistance_km, string(r.Fine.TCA, "HH:mm:ss.SSS"))
        sprintf("diff %.5f s, %.3f m, unrefined 30 s minimum %.2f km", r.TimeDiff_s, r.MissDiff_m, r.SampledMin_km)];
    writelines([lines; "CA_CHECK_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "CA_CHECK_FAILED"], logFile);
end
