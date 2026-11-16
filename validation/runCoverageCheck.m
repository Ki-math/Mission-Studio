% 新しいMATLABプロセスでカバレッジの確認を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "coverage_check_log.txt");
try
    tic;  r = checkCoverage();  el = toc;
    lines = ["GEO visible area [%]: min el / computed / analytic"
        compose("  %4.0f  %8.3f  %8.3f", r.GeoArea.MinEl_deg, r.GeoArea.Computed_pct, r.GeoArea.Analytic_pct)
        "LEO point vs ground station: lat lon / coverage % / access % / passes"
        compose("  %4.0f %5.0f  %7.3f  %7.3f  %d / %d", r.Points.Lat, r.Points.Lon, r.Points.Coverage_pct, r.Points.Access_pct, r.Points.CoveragePasses, r.Points.AccessPasses)
        sprintf("elapsed %.0f s", el)];
    writelines([lines; "COVERAGE_CHECK_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "COVERAGE_CHECK_FAILED"], logFile);
end
