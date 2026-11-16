function results = compareWithGmat(caseIndex)
%COMPAREWITHGMAT  Mission Studio の軌道伝播・可視・食の解析を GMAT と比較する
%   results = compareWithGmat() は gmatCases の全ケースを両ツールで計算し、
%   比較結果の table を返します。compareWithGmat(idx) は指定ケースのみ実行。
%
%   results の列
%     Case           ケース名
%     MaxPosDiff_m   24時間の最大位置差 [m]
%     PosTol_m       その許容値 [m]
%     Passes         可視パス数 (Mission Studio / GMAT)
%     MaxPassDiff_s  対応するパスの開始・終了時刻の最大差 [s]
%     Eclipses       食の区間数 (本影 + 日陰全体。Mission Studio / GMAT)
%     MaxEclDiff_s   対応する食の開始・終了時刻の最大差 [s]
%     OK             位置差が許容値内、区間数が一致、時刻差が許容値内
%
%   出力ファイルは validation/work に残ります (GMAT スクリプト、レポート、
%   両ツールの区間を並べた *_detail.mat)。
%
%   See also gmatCases, writeGmatScript, runGmat

passTol_s    = 1;       % 可視の開始・終了時刻の許容差
eclipseTol_s = 2;       % 食の開始・終了時刻の許容差

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
work = fullfile(here, "work");
if ~isfolder(work), mkdir(work); end

cases = gmatCases();
if nargin > 0, cases = cases(caseIndex); end

cfg.Epoch         = datetime(2024, 6, 1, 0, 0, 0, TimeZone="UTC");
cfg.DurationHours = 24;
cfg.Step_s        = 10;
cfg.Stations      = table(["Tanegashima"; "Svalbard"], [30.40; 78.23], ...
    [130.97; 15.39], [5; 5], VariableNames=["Name","Lat_deg","Lon_deg","MinEl_deg"]);
span = [cfg.Epoch, cfg.Epoch + hours(cfg.DurationHours)];

results = table;
for k = 1:numel(cases)
    c   = cases(k);
    timer = tic;
    tag = matlab.lang.makeValidName(c.Name);
    cfg.StateFile   = fullfile(work, tag + "_state.txt");
    cfg.ContactFile = fullfile(work, tag + "_contact.txt");
    cfg.EclipseFile = fullfile(work, tag + "_eclipse.txt");
    script = fullfile(work, tag + ".script");

    writeGmatScript(script, c, cfg);
    [gmatState, gmatContacts, gmatEclipses] = runGmat(script, cfg);
    [msPos, msContacts, msEclipses] = runMissionStudio(c, cfg);

    posDiff = max(vecnorm(msPos - gmatState(:, 2:4)'*1e3));
    pass = compareIntervals(renamevars(msContacts, "Target", "Key"), ...
        renamevars(gmatContacts, "Station", "Key"), span, cfg.Step_s);
    ecl  = compareIntervals(renamevars(msEclipses, "Type", "Key"), ...
        renamevars(gmatEclipses, "Type", "Key"), span, cfg.Step_s);

    save(fullfile(work, tag + "_detail.mat"), "msContacts", "gmatContacts", ...
        "msEclipses", "gmatEclipses");      % 個別の区間を後から見比べるため

    ok = posDiff <= c.PosTol_m ...
        && pass.CountMatches && ~(pass.MaxDiff > passTol_s) ...
        && ecl.CountMatches  && ~(ecl.MaxDiff > eclipseTol_s);
    results(end+1, :) = {string(c.Name), posDiff, c.PosTol_m, pass.Counts, ...
        pass.MaxDiff, ecl.Counts, ecl.MaxDiff, ok}; %#ok<AGROW>
    fprintf("[%d/%d] %-24s pos %.2f m, pass %.3f s, eclipse %.3f s (%.0f s)\n", ...
        k, numel(cases), c.Name, posDiff, pass.MaxDiff, ecl.MaxDiff, toc(timer));
end
results.Properties.VariableNames = ["Case","MaxPosDiff_m","PosTol_m", ...
    "Passes","MaxPassDiff_s","Eclipses","MaxEclDiff_s","OK"];
disp(results)
end

function [pos, contacts, eclipses] = runMissionStudio(c, cfg)
% 同じケースを Mission Studio (satelliteScenario) で計算する
spec = mstudio.defaultSpec();
spec.StartTime     = cfg.Epoch;
spec.DurationHours = cfg.DurationHours;
spec.SampleTime    = cfg.Step_s;
spec.Satellites    = spec.Satellites(1, :);
spec.Satellites{1, 2:end} = c.Elements;
spec.Satellites.Name = "Sat";
spec.Stations      = cfg.Stations;
spec.Propagator    = c.Propagator;
spec.Launcher.Enabled = false;

[~, h]   = mstudio.buildScenario(spec);
pos      = states(h.Assets{1});            % GCRF [m]
contacts = mstudio.computeAccess(h);
eclipses = mstudio.computeEclipse(h);
end

function r = compareIntervals(ms, gm, span, step)
% 同じ Key (地上局名 / 食の種類) の区間同士を、中央時刻が最も近いもので対応付け、
% 開始・終了時刻の差の最大値を返す。解析期間の両端で切れた区間は、切り方が
% ツールで違うため時刻の比較から除く (区間数には数える)
r.Counts = sprintf("%d / %d", height(ms), height(gm));
r.CountMatches = height(ms) == height(gm);
r.MaxDiff = NaN;

mid   = @(T) T.StartTime + (T.EndTime - T.StartTime)/2;
diffs = [];
for i = 1:height(ms)
    cand = gm(gm.Key == ms.Key(i), :);
    if isempty(cand), continue, end
    [~, j] = min(abs(mid(cand) - mid(ms(i, :))));
    clipped = ms.StartTime(i) - span(1) < seconds(2*step) ...
           || span(2) - ms.EndTime(i) < seconds(2*step);
    if clipped, continue, end
    diffs(end+1) = abs(seconds(ms.StartTime(i) - cand.StartTime(j))); %#ok<AGROW>
    diffs(end+1) = abs(seconds(ms.EndTime(i) - cand.EndTime(j))); %#ok<AGROW>
end
if ~isempty(diffs), r.MaxDiff = max(diffs); end
end
