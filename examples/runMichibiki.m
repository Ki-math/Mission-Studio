% 新しいMATLABプロセスで「みちびき」の解析を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "michibiki_out", "run_log.txt");
if ~isfolder(fileparts(logFile)), mkdir(fileparts(logFile)); end
try
    tic;  out = michibikiAnalysis();  el = toc;
    S = out.Summary;
    lines = compose("%-28s %-8s sats min %d mean %.2f max %d | top el min %.1f deg | PDOP median %.1f max %.1f, <=6: %5.1f%%", ...
        S.Constellation, S.City, S.MinSats, S.MeanSats, S.MaxSats, S.MinTopElevation_deg, S.MedianPDOP, S.MaxPDOP, S.PctPDOPbelow6);
    writelines([lines; sprintf("eclipses %d, elapsed %.0f s", out.EclipseCount, el); "MICHIBIKI_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "MICHIBIKI_FAILED"], logFile);
end
