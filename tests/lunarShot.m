% 月遷移を有効にしたシナリオで GUI を起動し、Lunar タブなどを画像に残す
here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
logFile = fullfile(here, "lunar_shot_log.txt");
try
    spec = mstudio.defaultSpec();
    spec.LunarTransfer.Enabled = true;
    spec.LunarTransfer.BurnModel = "finite";
    spec.LunarTransfer.IncludeSRP = true;
    spec.LunarTransfer.MoonGravityDegree = 20;
    spec.DurationHours = 130;
    spec.SampleTime = 60;
    spec.Propagator.Method = "two-body-keplerian";
    spec.Launcher.Enabled = false;
    spec.Stations(end+1, :) = {"Usuda", 36.13, 138.36, 5};
    tic;  app = MissionStudioApp(spec);  elapsed = toc;
    tabs = findobj(app.Fig, "Type", "uitabgroup");
    for name = "Lunar"
        tabs.SelectedTab = findobj(tabs, "Type", "uitab", "Title", name);
        drawnow;  pause(3);
        exportapp(app.Fig, fullfile(here, "shot_lunar_" + replace(lower(name), " ", "") + ".png"));
    end
    probe = app.AccessTable(app.AccessTable.Source == "LunarProbe", :);
    writelines([sprintf("startup + analysis %.0f s, probe passes %d", elapsed, height(probe)); ...
        "LUNAR_SHOT_DONE"], logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "LUNAR_SHOT_FAILED"], logFile);
end
