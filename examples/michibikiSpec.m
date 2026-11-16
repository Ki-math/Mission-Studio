function spec = michibikiSpec(includeQZS7)
%MICHIBIKISPEC  準天頂衛星システム「みちびき」の公称軌道によるシナリオ定義を返す
%   spec = michibikiSpec() は、2026年11月時点で運用中の 5 機 (初号機後継機、
%   2・3・4・6 号機) のシナリオ定義を返します。
%   spec = michibikiSpec(true) は、2026年8月に打ち上げられ機能確認中の 7 号機を
%   加えた 6 機にします。
%
%   軌道は公開されている公称値に基づく近似で、実際の軌道暦ではありません。
%     準天頂軌道 (1R, 2, 4): 周期 1 恒星日、離心率 0.075、傾斜角 41 度、
%                            近地点引数 270 度、直下軌跡の中心 東経 136 度。
%                            3 機は同じ 8 の字の軌跡を 8 時間間隔で通る
%     静止軌道   (3, 6)    : 東経 127 度、東経 90.5 度
%     準静止軌道 (7)       : 東経 185 度 (西経 175 度) 付近。ここでは静止として扱う
%   実際の軌道で解析するには、TLE を取得して app.addTLE を使ってください。
%
%   See also michibikiAnalysis, mstudio.defaultSpec

arguments
    includeQZS7 (1,1) logical = false
end

spec = mstudio.defaultSpec();
spec.StartTime     = datetime(2026, 11, 15, 0, 0, 0, TimeZone="UTC");
spec.DurationHours = 24;
spec.SampleTime    = 60;
spec.Launcher.Enabled = false;

% 静止高度の摂動に合わせた力モデル (大気抵抗なし、月・太陽の引力あり)
spec.Propagator.GravityDegree    = 8;
spec.Propagator.IncludeDrag      = false;
spec.Propagator.IncludeThirdBody = exist("ephConstants405.mat", "file") == 2;

% --- 衛星: [名前, 傾斜角, 離心率, 昇交点赤経, 近地点引数, 直下軌跡の中心経度]
sma = (398600.4418 * (86164.0905 / (2*pi))^2)^(1/3);        % 1 恒星日の軌道 [km]
def = {"QZS-1R (QZO)", 41, 0.075,   0, 270, 136
       "QZS-2 (QZO)",  41, 0.075, 120, 270, 136
       "QZS-4 (QZO)",  41, 0.075, 240, 270, 136
       "QZS-3 (GEO)",   0, 0,       0,   0, 127
       "QZS-6 (GEO)",   0, 0,       0,   0, 90.5};
if includeQZS7
    def(end+1, :) = {"QZS-7 (QGEO)", 0, 0, 0, 0, 185};
end

siderealAngle = greenwichAngle(spec.StartTime);
n = size(def, 1);
spec.Satellites = table(strings(n,1), zeros(n,1), zeros(n,1), zeros(n,1), zeros(n,1), ...
    zeros(n,1), zeros(n,1), VariableNames=spec.Satellites.Properties.VariableNames);
for k = 1:n
    [name, inc, ecc, raan, argp, centerLon] = def{k, :};
    % 対地同期軌道では (昇交点赤経 + 近地点引数 + 平均近点角 - グリニッジ恒星時) が
    % 直下軌跡の中心経度になる
    meanAnomaly = centerLon + siderealAngle - raan - argp;
    spec.Satellites(k, :) = {name, sma, ecc, inc, raan, argp, trueAnomaly(meanAnomaly, ecc)};
end

% --- 地上の評価点 (最小仰角 10 度)
spec.Stations = table(["Sapporo"; "Tokyo"; "Naha"; "Sydney"; "Bangkok"], ...
    [43.06; 35.68; 26.21; -33.87; 13.76], [141.35; 139.77; 127.68; 151.21; 100.50], ...
    repmat(10, 5, 1), VariableNames=spec.Stations.Properties.VariableNames);

% --- カバレッジ: アジア・オセアニア、最小仰角 10 度
spec.Coverage.Enabled      = true;
spec.Coverage.LatMin_deg   = -60;   spec.Coverage.LatMax_deg = 70;
spec.Coverage.LonMin_deg   = 60;    spec.Coverage.LonMax_deg = 215;
spec.Coverage.GridStep_deg = 5;
spec.Coverage.MinEl_deg    = 10;
spec.Coverage.ComputeDOP   = true;
end

function angle = greenwichAngle(epoch)
% epoch でのグリニッジ恒星時 [deg]。satelliteScenario の座標変換と整合させるため、
% 赤経 0 度の静止衛星の経度から求める
sc  = satelliteScenario(epoch, epoch + minutes(1), 60);
sat = satellite(sc, 42164e3, 0, 0, 0, 0, 0, OrbitPropagator="two-body-keplerian");
pos = states(sat, epoch, CoordinateFrame="geographic");
angle = -pos(2);
end

function nu = trueAnomaly(meanAnomalyDeg, ecc)
% 平均近点角 [deg] から真近点角 [deg] (ケプラー方程式をニュートン法で解く)
M = deg2rad(mod(meanAnomalyDeg, 360));
E = M;
for iter = 1:50
    E = E - (E - ecc*sin(E) - M) / (1 - ecc*cos(E));
end
nu = mod(rad2deg(2 * atan2(sqrt(1+ecc)*sin(E/2), sqrt(1-ecc)*cos(E/2))), 360);
end
