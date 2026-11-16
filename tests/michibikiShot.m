% みちびきのシナリオを GUI で開き、Navigation と Coverage のタブを画像に残す
here = fileparts(mfilename("fullpath"));
root = fileparts(here);
addpath(root);  addpath(fullfile(root, "examples"));
logFile = fullfile(here, "michibiki_shot_log.txt");
try
    spec = michibikiSpec(true);
    file = fullfile(tempdir, "michibiki_scenario_test.mat");
    save(file, "spec");
    tic;  app = MissionStudioApp();  app.loadSpec(file);  elapsed = toc;     % GUI の Open と同じ経路
    tabs = findobj(app.Fig, "Type", "uitabgroup");
    tabs.SelectedTab = findobj(tabs, "Type", "uitab", "Title", "Navigation");
    app.selectDropdown("NavStation", "Tokyo");
    drawnow;  pause(4);
    exportapp(app.Fig, fullfile(here, "shot_navigation.png"));
    tabs.SelectedTab = findobj(tabs, "Type", "uitab", "Title", "Coverage");
    app.selectDropdown("CoverageMetric", "Median PDOP");
    drawnow;  pause(4);
    exportapp(app.Fig, fullfile(here, "shot_coverage_pdop.png"));
    labels = string({findobj(app.Fig, "Type", "uilabel").Text});
    writelines([sprintf("elapsed %.0f s", elapsed); labels(startsWith(labels, ["解析完了","エラー"]))'; ...
        "MICHIBIKI_SHOT_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "MICHIBIKI_SHOT_FAILED"], logFile);
end
