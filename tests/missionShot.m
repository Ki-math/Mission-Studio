% カバレッジと接近解析を有効にして GUI を起動し、該当タブを画像に残す
here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
logFile = fullfile(here, "mission_shot_log.txt");
try
    spec = mstudio.defaultSpec();
    spec.DurationHours = 24;
    spec.Coverage.Enabled = true;
    spec.Propagator.Method = "two-body-keplerian";
    spec.Launcher.Enabled = false;
    tic;  app = MissionStudioApp(spec);  elapsed = toc;
    tabs = findobj(app.Fig, "Type", "uitabgroup");
    for name = ["Coverage","Proximity"]
        tabs.SelectedTab = findobj(tabs, "Type", "uitab", "Title", name);
        drawnow;  pause(4);
        exportapp(app.Fig, fullfile(here, "shot_" + lower(name) + ".png"));
    end
    writelines([sprintf("startup + analysis %.0f s, approaches %d", elapsed, height(app.CloseApproaches)); ...
        "MISSION_SHOT_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "MISSION_SHOT_FAILED"], logFile);
end
