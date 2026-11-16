function T = computeAccess(h)
%COMPUTEACCESS  全ビークル×全地上局の可視区間を求める
%   T = mstudio.computeAccess(h) は Source, Target, StartTime, EndTime,
%   Duration[s] を列に持つ table を返します。h は mstudio.buildScenario の出力。
%
%   可視条件
%     1. 仰角 >= 地上局の最小仰角
%     2. 月に隠されていない (h.Moon があるとき。月より遠い側にあるビークルの
%        視線が月面を通る区間を不可視とする。光行時は考慮しない)
%   シナリオの刻みで求めた時刻歴から、可視の開始・終了時刻を補間で求めます
%   (刻み 10 s のとき GMAT との差は 0.01 s 以下。validation 参照)。
%   時刻歴インポート型ビークルは、データのある時間範囲だけを対象にします。
%
%   See also mstudio.buildScenario, mstudio.findIntervals, aer

T = table(Size=[0 5], ...
    VariableTypes=["string","string","datetime","datetime","double"], ...
    VariableNames=["Source","Target","StartTime","EndTime","Duration"]);
T.StartTime.TimeZone = "UTC";  T.EndTime.TimeZone = "UTC";

for j = 1:numel(h.Stations)
    station = h.Stations{j};
    moon = [];
    if ~isempty(h.Moon)
        [moon.Az, moon.El, moon.Range] = aer(station, h.Moon);
    end
    for i = 1:numel(h.Assets)
        [az, el, range, t] = aer(station, h.Assets{i});
        margin = el - station.MinElevationAngle;
        if ~isempty(moon)
            margin = min(margin, moonClearance(az, el, range, moon));
        end
        margin(t < h.ValidRange(i,1) | t > h.ValidRange(i,2)) = NaN;

        [tStart, tEnd] = mstudio.findIntervals(seconds(t - t(1)), margin);
        n = numel(tStart);
        if n == 0, continue, end
        T = [T; table(repmat(h.AssetNames(i), n, 1), repmat(h.StationNames(j), n, 1), ...
            t(1) + seconds(tStart(:)), t(1) + seconds(tEnd(:)), tEnd(:) - tStart(:), ...
            VariableNames=T.Properties.VariableNames)]; %#ok<AGROW>
    end
end
T = sortrows(T, "StartTime");
end

function clearance = moonClearance(az, el, range, moon)
% 地上局から見たビークルと月面の縁との離角 [deg]。負なら月に隠れている。
% 視線上で月中心への最接近点より手前にあるビークルは隠れないので Inf とする
moonRadius = 1737.4e3;      % [m]
separation = acosd(min(1, sind(el).*sind(moon.El) ...
    + cosd(el).*cosd(moon.El).*cosd(az - moon.Az)));
clearance = separation - asind(moonRadius ./ moon.Range);
clearance(range < moon.Range .* cosd(separation)) = Inf;
end
