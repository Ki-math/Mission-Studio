function [state, contacts, eclipses, log] = runGmat(scriptFile, cfg)
%RUNGMAT  GMAT スクリプトを実行し、状態量・可視区間・食を読み込む
%   [state, contacts, eclipses, log] = runGmat(scriptFile, cfg)
%     state    : [経過秒, X, Y, Z] (km, ICRF)
%     contacts : table (Station, StartTime, EndTime)
%     eclipses : table (Type, StartTime, EndTime)。Type は mstudio.computeEclipse
%                と同じ定義 ("Umbra" = 本影、"Eclipse" = 半影を含む日陰全体)
%     log      : GmatConsole の出力
%
%   GMAT の場所は環境変数 GMAT_ROOT、無ければ C:\Work\GMAT\GMAT_R2025a。
%
%   See also writeGmatScript, compareWithGmat

root = getenv("GMAT_ROOT");
if isempty(root), root = "C:\Work\GMAT\GMAT_R2025a"; end
exe = fullfile(root, "bin", "GmatConsole.exe");
assert(isfile(exe), "GmatConsole が見つかりません: %s", exe);

for f = string({cfg.StateFile, cfg.ContactFile, cfg.EclipseFile})
    if isfile(f), delete(f); end
end
[status, log] = system(sprintf('"%s" --run "%s"', exe, scriptFile));
assert(status == 0 && isfile(cfg.StateFile), "GMAT の実行に失敗しました:\n%s", log);

state    = readmatrix(cfg.StateFile, FileType="text");
contacts = readContactReport(cfg.ContactFile, cfg.Stations);
eclipses = readEclipseReport(cfg.EclipseFile);
end

function T = readContactReport(file, stations)
% ContactLocator のレポート: "Observer: GS1" の見出しに続いて
%   "01 Jun 2024 00:12:34.567    01 Jun 2024 00:22:01.234    566.667"
T = emptyIntervals("Station");
if ~isfile(file), return, end
station = "";
for line = readlines(file)'
    tok = regexp(line, "^Observer:\s*GS(\d+)", "tokens", "once");
    if ~isempty(tok)
        station = string(stations.Name(str2double(tok)));
        continue
    end
    [t, ok] = parseTimes(line);
    if ok, T(end+1, :) = {station, t(1), t(2)}; end %#ok<AGROW>
end
end

function T = readEclipseReport(file)
% EclipseLocator のレポート: 1行が1つの位相 (半影 → 本影 → 半影) で、
%   "開始  終了  継続時間  Earth  Umbra|Penumbra  イベント番号  合計時間"
% 同じイベント番号の行をまとめたものが、日陰全体 ("Eclipse") の区間になる
T = emptyIntervals("Type");
if ~isfile(file), return, end
phase = emptyIntervals("Type");  eventId = [];
for line = readlines(file)'
    [t, ok] = parseTimes(line);
    if ~ok, continue, end
    tok = regexp(line, "Earth\s+(\w+)\s+(\d+)", "tokens", "once");
    phase(end+1, :) = {string(tok(1)), t(1), t(2)}; %#ok<AGROW>
    eventId(end+1, 1) = str2double(tok(2)); %#ok<AGROW>
end
T = phase(phase.Type == "Umbra", :);
for id = unique(eventId)'
    rows = phase(eventId == id, :);
    T(end+1, :) = {"Eclipse", min(rows.StartTime), max(rows.EndTime)}; %#ok<AGROW>
end
end

function [t, ok] = parseTimes(line)
% 行頭の開始・終了時刻 ("01 Jun 2024 00:12:34.567" が2つ) を読む
datePattern = "\d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2}\.\d{3}";
tok = regexp(line, "(" + datePattern + ")\s+(" + datePattern + ")", "tokens", "once");
ok = ~isempty(tok);
t  = NaT(1, 2, TimeZone="UTC");
if ok
    t = datetime(tok, InputFormat="dd MMM yyyy HH:mm:ss.SSS", Locale="en_US", TimeZone="UTC");
end
end

function T = emptyIntervals(keyName)
T = table(Size=[0 3], VariableTypes=["string","datetime","datetime"], ...
    VariableNames=[keyName,"StartTime","EndTime"]);
T.StartTime.TimeZone = "UTC";  T.EndTime.TimeZone = "UTC";
end
