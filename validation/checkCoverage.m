function r = checkCoverage()
%CHECKCOVERAGE  カバレッジ解析を解析解と可視解析に照らして確認する
%   r = checkCoverage() は次の2点を調べ、結果を表示します。
%
%   1. 静止衛星1機が見える地表面積の割合を、球の地球での解析解
%        面積率 = (1 - cos(lambda)) / 2,  lambda = acos(Re cos(e) / r) - e
%      と比べる (e は最小仰角)。格子 1 度。地球の扁平による差は 0.1% 程度。
%   2. 低軌道衛星について、1つの格子点の「見えている時間の割合」と通過回数を、
%      同じ場所に地上局を置いた mstudio.computeAccess の結果と比べる。
%      カバレッジは刻みごとの判定なので、差は 通過回数×刻み 程度まで出る。
%
%   GMAT にはカバレッジ解析が無いため、この確認は自己整合と解析解によります。
%
%   See also mstudio.computeCoverage, mstudio.computeAccess

addpath(fileparts(fileparts(mfilename("fullpath"))));

spec = mstudio.defaultSpec();
spec.DurationHours = 24;  spec.SampleTime = 30;
spec.Launcher.Enabled = false;
spec.Propagator.Method = "two-body-keplerian";

% --- 1. 静止衛星の可視面積
geo = spec;  geo.Satellites = geo.Satellites(3, :);  geo.DurationHours = 1;
cov = mstudio.defaultCoverage();  cov.GridStep_deg = 1;
r.GeoArea = table;
for minEl = [0 5 10 20]
    cov.MinEl_deg = minEl;
    [~, h] = mstudio.buildScenario(geo);
    c = mstudio.computeCoverage(h, cov);
    radius = geo.Satellites.a_km;
    lambda = acosd(6378.137 * cosd(minEl) / radius) - minEl;
    r.GeoArea(end+1, :) = {minEl, mean(c.AreaCovered), 100 * (1 - cosd(lambda)) / 2};
end
r.GeoArea.Properties.VariableNames = ["MinEl_deg","Computed_pct","Analytic_pct"];
disp(r.GeoArea)

% --- 2. 格子点と地上局の比較
leo = spec;  leo.Satellites = leo.Satellites(1:2, :);
cov = mstudio.defaultCoverage();  cov.GridStep_deg = 10;  cov.MinEl_deg = 10;
probe = [35 135; -45 25; 75 -95; 5 -55];              % 格子点 (セル中心) に一致する場所
leo.Stations = table("P" + (1:4)', probe(:,1), probe(:,2), repmat(cov.MinEl_deg, 4, 1), ...
    VariableNames=["Name","Lat_deg","Lon_deg","MinEl_deg"]);
[~, h] = mstudio.buildScenario(leo);
c = mstudio.computeCoverage(h, cov);
access = mstudio.computeAccess(h);

r.Points = table;
for k = 1:4
    i = find(c.Lat == probe(k,1) & c.Lon == probe(k,2));
    a = access(access.Target == "P" + k, :);
    covered = mergedDuration(a.StartTime, a.EndTime);
    r.Points(end+1, :) = {probe(k,1), probe(k,2), c.PercentTime(i), ...
        100 * covered / (leo.DurationHours*3600), c.NumAccess(i), height(a)};
end
r.Points.Properties.VariableNames = ["Lat","Lon","Coverage_pct","Access_pct", ...
    "CoveragePasses","AccessPasses"];
disp(r.Points)
end

function total = mergedDuration(tStart, tEnd)
% 重なりを除いた区間の合計時間 [s] (複数の衛星の通過が重なる場合がある)
total = 0;
if isempty(tStart), return, end
[tStart, order] = sort(tStart);  tEnd = tEnd(order);
curStart = tStart(1);  curEnd = tEnd(1);
for k = 2:numel(tStart)
    if tStart(k) > curEnd
        total = total + seconds(curEnd - curStart);
        curStart = tStart(k);  curEnd = tEnd(k);
    else
        curEnd = max(curEnd, tEnd(k));
    end
end
total = total + seconds(curEnd - curStart);
end
