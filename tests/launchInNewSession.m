% 新しいMATLABセッションの起動時に実行: 動作確認を行い、結果をログとスクリーンショットに残す
here = fileparts(mfilename("fullpath"));
logFile = fullfile(here, "launch_log.txt");
fid = fopen(logFile, "w");  fclose(fid);
diary(logFile);
try
    smokeTest();
    fig  = findall(groot, "Type", "figure", "Name", "Mission Studio");
    tabs = findobj(fig(1), "Type", "uitabgroup");
    for k = 1:numel(tabs.Children)
        tabs.SelectedTab = tabs.Children(k);  drawnow;  pause(2);
        exportapp(fig(1), fullfile(here, sprintf("shot%d.png", k)));
    end
    tabs.SelectedTab = tabs.Children(1);
    disp("SHOTS_OK")
catch err
    disp(getReport(err, "extended", hyperlinks="off"));
    disp("FAILED")
end
diary off
