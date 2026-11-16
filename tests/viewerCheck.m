% 3Dビューアでのモデル表示を目視確認するためのスクリプト (新しいセッションで実行)
%   計算の軽い二体問題のシナリオで、衛星とロケットのモデルを大きく表示する
here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
logFile = fullfile(here, "viewer_log.txt");
try
    spec = mstudio.defaultSpec();
    spec.DurationHours = 2;
    spec.Propagator.Method = "two-body-keplerian";
    tic;  [sc, h] = mstudio.buildScenario(spec);  tBuild = toc;
    mstudio.applyVisualModels(h, 1500);
    v = satelliteScenarioViewer(sc);
    v.CurrentTime = spec.StartTime + seconds(1500);
    campos(v, 10, 150, 1.2e7);
    writelines(sprintf("VIEWER_READY build %.1f s", tBuild), logFile);
catch err
    writelines([string(getReport(err, "extended", hyperlinks="off")); "VIEWER_FAILED"], logFile);
end
