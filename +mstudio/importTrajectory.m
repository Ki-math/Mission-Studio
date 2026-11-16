function traj = importTrajectory(file)
%IMPORTTRAJECTORY  飛行経路の時刻歴 (CSV / MAT) を読み込む
%   traj = mstudio.importTrajectory(file)
%
%   CSV : 列名 t_s, lat_deg, lon_deg, alt_m を持つ表
%   MAT : 同じ列名を持つ table / timetable 変数を1つ含むファイル
%         (timetable の場合は行時間を経過時間として使用)
%
%   シミュレーション結果 (ロケットの飛行履歴など) をこの形式で書き出せば、
%   衛星と同じシナリオ上で可視・回線解析の対象にできます。
%
%   See also mstudio.sampleTrajectory, mstudio.buildScenario

arguments
    file (1,1) string {mustBeFile}
end

[~, name, ext] = fileparts(file);
switch lower(ext)
    case ".csv"
        T = readtable(file);
    case ".mat"
        S = load(file);
        f = fieldnames(S);
        isTab = cellfun(@(n) istable(S.(n)) || istimetable(S.(n)), f);
        assert(any(isTab), "mstudio:import:noTable", ...
            "MATファイルに table / timetable が見つかりません。");
        T = S.(f{find(isTab,1)});
        if istimetable(T)
            t = seconds(T.Properties.RowTimes - T.Properties.RowTimes(1));
            T = timetable2table(T, ConvertRowTimes=false);
            T.t_s = t;
        end
    otherwise
        error("mstudio:import:format", "未対応の形式です: %s", ext);
end

required = ["t_s","lat_deg","lon_deg","alt_m"];
missing  = setdiff(required, string(T.Properties.VariableNames));
assert(isempty(missing), "mstudio:import:columns", ...
    "必要な列がありません: %s", strjoin(missing, ", "));

[t, idx] = unique(T.t_s);
traj = struct(Name=string(name), Time=t, ...
    LLA=[T.lat_deg(idx) T.lon_deg(idx) T.alt_m(idx)]);
end
