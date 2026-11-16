function [sc, h] = buildScenario(spec, cache)
%BUILDSCENARIO  シナリオ定義から satelliteScenario を構築する
%   [sc, h] = mstudio.buildScenario(spec)
%   [sc, h] = mstudio.buildScenario(spec, cache) は、計算済みの結果を再利用して
%   再計算を省きます。cache.Launch (h.Launch) と cache.LunarTransfer
%   (h.LunarTransfer) のうち、与えたものだけが使われます。
%
%   ビークルは次の順に登録されます。
%     1. spec.Satellites   ケプラー要素の衛星 (spec.Propagator で伝播)
%     2. spec.TLEFiles     TLEファイル内の衛星 (SGP4/SDP4)
%     3. spec.Trajectories インポートした飛行経路
%     4. spec.Launcher     3DoF質点モデルで計算したロケット (Enabled のとき)
%     5. spec.LunarTransfer 月遷移軌道の探査機 (Enabled のとき)
%
%   sc : satelliteScenario オブジェクト
%   h  : 生成したオブジェクトのハンドル
%        h.Assets       - ビークル (cell)
%        h.AssetNames   - その名前 (string)
%        h.AssetKinds   - 種別 "satellite" | "trajectory" (string)
%        h.ValidRange   - 各ビークルのデータが有効な時間範囲 [開始, 終了]
%        h.Stations     - 地上局 (cell)
%        h.StationNames - その名前 (string)
%        h.Launch       - mstudio.simulateAscent の結果 (ロケット無効時は [])
%        h.LunarTransfer - mstudio.designLunarTransfer の結果 (無効時は [])
%        h.Moon         - 月の位置を表すオブジェクト (月遷移が有効なときのみ)。
%                         月による掩蔽の判定とビューアでの表示に使う
%
%   See also mstudio.defaultSpec, mstudio.simulateAscent, satelliteScenario

maxTLESatellites = 100;     % 巨大なコンステレーションの誤読込を防ぐ上限

duration = hours(spec.DurationHours);
stopTime = spec.StartTime + duration;
sc = satelliteScenario(spec.StartTime, stopTime, spec.SampleTime);

h.Assets = {};
h.AssetKinds = strings(0, 1);
h.ValidRange = repmat(spec.StartTime, 0, 2);
h.Launch = [];
h.LunarTransfer = [];
h.Moon = [];
if nargin < 2, cache = struct(); end

% --- 1. ケプラー要素
propagatorArgs = configurePropagator(sc, spec.Propagator);
for k = 1:height(spec.Satellites)
    s = spec.Satellites(k, :);
    sat = satellite(sc, s.a_km*1e3, s.e, s.i_deg, ...
        s.RAAN_deg, s.ArgP_deg, s.Nu_deg, "Name", s.Name, propagatorArgs{:});
    if spec.Propagator.Method == "numerical"
        p = spec.Propagator;
        physicalProperties(sat, Mass=p.Mass_kg, DragArea=p.DragArea_m2, ...
            DragCoefficient=p.Cd, SRPArea=p.SRPArea_m2, ReflectivityCoefficient=p.Cr);
    end
    addAsset(sat);
end

% --- 2. TLE
for file = reshape(string(spec.TLEFiles), 1, [])
    assert(isfile(file), "mstudio:build:tleMissing", ...
        "TLEファイルが見つかりません: %s", file);
    sats = satellite(sc, file);
    assert(numel(sats) <= maxTLESatellites, "mstudio:build:tleTooMany", ...
        "%s には衛星が %d 機あります (上限 %d 機)。対象を絞ったTLEを使ってください。", ...
        file, numel(sats), maxTLESatellites);
    for k = 1:numel(sats), addAsset(sats(k)); end
end

% --- 3. インポートした飛行経路
for tr = reshape(spec.Trajectories, 1, [])
    addTrajectory(tr);
end

% --- 4. ロケット (3DoF)
if spec.Launcher.Enabled
    lv = spec.Launcher;
    if isfield(cache, "Launch") && ~isempty(cache.Launch)
        h.Launch = cache.Launch;
    else
        h.Launch = mstudio.simulateAscent(lv, seconds(duration) - lv.LiftoffTime);
    end
    addTrajectory(struct(Name=lv.Name, Time=h.Launch.Time + lv.LiftoffTime, LLA=h.Launch.LLA));
end

% --- 5. 月遷移軌道の探査機
if spec.LunarTransfer.Enabled
    lt = spec.LunarTransfer;
    if isfield(cache, "LunarTransfer") && ~isempty(cache.LunarTransfer)
        h.LunarTransfer = cache.LunarTransfer;
    else
        h.LunarTransfer = mstudio.designLunarTransfer(lt, spec.StartTime + seconds(lt.TLITime));
    end
    res = h.LunarTransfer;

    % 探査機と月の位置は、シナリオのサンプル時刻そのものに合わせて与える
    % (satelliteScenario 側での時刻歴の補間を避け、両者の相対位置を保つため)
    tSample = (0:spec.SampleTime:seconds(duration))';
    tProbe  = tSample - lt.TLITime;                      % TLI 開始からの経過時間
    inRange = tProbe >= res.Time(1) & tProbe <= res.Time(end);
    assert(nnz(inRange) >= 2, "mstudio:build:lunarOutside", ...
        "月遷移の開始時刻がシナリオ期間の外です。");
    probePos = resampleByPhase(res, tProbe(inRange)) * 1e3;
    tt = timetable(spec.StartTime + seconds(tSample(inRange)), probePos);
    addAsset(satellite(sc, tt, CoordinateFrame="inertial", Name=lt.Name), tt.Time([1 end])');

    % 月そのものもシナリオに置く (ビークルの一覧には入れない)
    moonPos = mstudio.ephemeris("Earth", "Moon", spec.StartTime, tSample) * 1e3;
    h.Moon  = satellite(sc, timetable(spec.StartTime + seconds(tSample), moonPos), ...
        CoordinateFrame="inertial", Name="Moon");
end

h.AssetNames = cellfun(@(a) string(a.Name), h.Assets);
h.AssetNames = reshape(h.AssetNames, [], 1);
[~, iu] = unique(h.AssetNames);
dup = h.AssetNames(setdiff(1:numel(h.AssetNames), iu));
assert(isempty(dup), "mstudio:build:duplicate", ...
    "ビークル名が重複しています: %s", strjoin(unique(dup), ", "));

% --- 地上局
h.Stations = {};
for k = 1:height(spec.Stations)
    g = spec.Stations(k, :);
    h.Stations{end+1} = groundStation(sc, g.Lat_deg, g.Lon_deg, ...
        Name=g.Name, MinElevationAngle=g.MinEl_deg);
end
h.StationNames = string(spec.Stations.Name);

    function addAsset(obj, range)
        kind = "trajectory";
        if nargin < 2
            range = [spec.StartTime, stopTime];  kind = "satellite";
        end
        h.Assets{end+1} = obj;
        h.AssetKinds(end+1, 1) = kind;
        h.ValidRange(end+1, :) = range;
    end

    function addTrajectory(tr)
        % 時刻歴 (経過秒 + LLA) を地球固定系の位置時刻歴として登録する
        tt = timetable(spec.StartTime + seconds(tr.Time), lla2ecef(tr.LLA));
        addAsset(satellite(sc, tt, CoordinateFrame="ecef", Name=tr.Name), tt.Time([1 end])');
    end
end

function args = configurePropagator(sc, p)
% 伝播設定をシナリオに反映し、satellite() に渡す名前/値引数を返す
switch string(p.Method)
    case "numerical"
        needsEphemeris = p.IncludeThirdBody || p.IncludeSRP;
        assert(~needsEphemeris || exist("ephConstants405.mat", "file") == 2, ...
            "mstudio:build:noEphemeris", ...
            "月・太陽の引力と太陽輻射圧にはエフェメリスデータが必要です。" + ...
            "MATLABで aeroDataPackage を実行してインストールしてください。");
        if p.GravityDegree >= 2
            gravity = {"GravitationalPotentialModel", "spherical-harmonics", ...
                "SphericalHarmonicModel", "EGM96", ...
                "SphericalHarmonicDegree", p.GravityDegree};
        else
            gravity = {"GravitationalPotentialModel", "point-mass"};
        end
        % 既定 (ode45, RelTol 1e-8) では低軌道24時間で約20 mの積分誤差が出るため、
        % 高次の積分器と厳しい許容誤差を使う (GMAT 比較で確認)
        numericalPropagator(sc, gravity{:}, ...
            ODESolver="ode89", ODESet=odeset(RelTol=1e-12, AbsTol=1e-9), ...
            IncludeAtmosDrag=logical(p.IncludeDrag), ...
            F107Average=p.F107, F107Daily=p.F107, ...
            IncludeThirdBodyGravity=logical(p.IncludeThirdBody), ...
            IncludeSRP=logical(p.IncludeSRP));
        args = {"OrbitPropagator", "numerical"};
    case "two-body-keplerian"
        args = {"OrbitPropagator", "two-body-keplerian"};
    case "sgp4"
        args = {};      % 周期に応じて SGP4 / SDP4 が自動選択される
    otherwise
        error("mstudio:build:propagator", "未対応の伝播方式です: %s", p.Method);
end
end

function pos = resampleByPhase(res, tQuery)
% 月遷移の位置時刻歴 [km] を tQuery に補間する。遷移区間と月周回区間は
% LOI で速度が不連続になるので、区間ごとにスプライン補間する
pos = nan(numel(tQuery), 3);
tSwitch = res.Time(find(res.Phase == 2, 1));
for phase = 1:2
    rows = res.Phase == phase;
    [t, iu] = unique(res.Time(rows));
    P = res.PosEarth_km(rows, :);
    if phase == 1, query = tQuery < tSwitch; else, query = tQuery >= tSwitch; end
    if nnz(query) > 0 && numel(t) >= 2
        pos(query, :) = interp1(t, P(iu, :), tQuery(query), "spline");
    end
end
end
