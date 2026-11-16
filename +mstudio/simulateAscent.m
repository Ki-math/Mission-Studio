function result = simulateAscent(lv, tEnd, dtCoast)
%SIMULATEASCENT  多段ロケットの上昇〜軌道を3DoF質点モデルで計算する
%   result = mstudio.simulateAscent(lv, tEnd) は、リフトオフから tEnd [s]
%   (リフトオフ基準) までの飛行を計算します。lv は mstudio.defaultLauncher
%   と同じフィールドを持つ構造体です。
%   result = mstudio.simulateAscent(lv, tEnd, dtCoast) は最終燃焼終了後の
%   出力刻み [s] を指定します (既定 10)。動力飛行中は 1 s 刻みです。
%
%   モデル
%     運動   : 慣性系の質点 (位置3・速度3・質量)。地球は自転する球対称重力場
%     推力   : 真空推力を大気圧で補正 (IspVac -> IspSL を気圧比で線形補間)
%     空気力 : 指数大気 + 一定 Cd の抗力 (揚力なし)
%     誘導   : 垂直上昇 -> ピッチキック -> 重力ターン (推力 = 対気速度方向)
%     燃焼停止: 最終段は接触軌道の遠地点高度が lv.CutoffApogee_km に達したら
%              停止 (Inf なら推進剤を使い切るまで燃焼)
%     終了   : tEnd 到達、または地表到達
%
%   result のフィールド
%     Time      : リフトオフからの経過時間 [s] (列ベクトル)
%     LLA       : [緯度deg, 経度deg, 高度m]
%     Telemetry : 時刻歴 table (Alt_km, Speed_mps, Mass_kg, Q_kPa,
%                 Gamma_deg, Downrange_km, Accel_g, Stage)
%     Events    : イベント table (Name, Time_s, Alt_km, Speed_mps)
%     Orbit     : 最終燃焼終了時の接触軌道 (PerigeeAlt_km, ApogeeAlt_km,
%                 Inc_deg, Ecc, SMA_km)
%     Reached   : "orbit" | "impact" | "flying"
%
%   See also mstudio.defaultLauncher, mstudio.tuneKickAngle

arguments
    lv      (1,1) struct
    tEnd    (1,1) double {mustBePositive}
    dtCoast (1,1) double {mustBePositive} = 10
end

c = earthConstants();
area = pi/4 * lv.Diameter_m^2;

% --- 初期状態 (慣性系 = リフトオフ時刻の地球固定系)
r0 = lla2ecef([lv.SiteLat_deg, lv.SiteLon_deg, 0])';
v0 = cross(c.Omega, r0);
h0 = altitude(r0, c);
m  = lv.Payload_kg + sum(lv.Stages.Prop_kg) + sum(lv.Stages.Dry_kg);
x  = [r0; v0; m];
t  = 0;

opts   = odeset(RelTol=1e-8, AbsTol=1e-6);
tPitch = Inf;                       % ピッチキック開始時刻 (未到達は Inf)
T = [];  X = [];  stageId = [];
events = table(Size=[0 2], VariableTypes=["string","double"], ...
    VariableNames=["Name","Time_s"]);
events(end+1, :) = {"Liftoff", 0};
impacted = false;

% --- 動力飛行 (ステージごと)
for k = 1:height(lv.Stages)
    st    = lv.Stages(k, :);
    mdot  = st.ThrustVac_kN*1e3 / (c.g0 * st.IspVac_s);
    tBurn = st.Prop_kg / mdot;
    tStop = min(t + tBurn, tEnd);
    rhs   = @(t, x) dynamics(t, x, st, mdot, area, lv, c, tPitch);
    cutoff = false;
    apoTarget = Inf;                % 遠地点による燃焼停止は最終段のみ
    if k == height(lv.Stages) && isfield(lv, "CutoffApogee_km")
        apoTarget = lv.CutoffApogee_km * 1e3;
    end

    % ピッチキック高度の到達を検出して誘導フェーズを切り替える
    if isinf(tPitch)
        ev = odeset(opts, Events=@(~, x) pitchoverEvent(x, h0 + lv.PitchoverAlt_m, c));
        [ts, xs, te] = ode45(rhs, gridTimes(t, tStop, 1), x, ev);
        append(ts, xs, k);
        if ~isempty(te)
            tPitch = te(end);
            events(end+1, :) = {"Pitchover", tPitch}; %#ok<AGROW>
            rhs = @(t, x) dynamics(t, x, st, mdot, area, lv, c, tPitch);
        end
    end
    if t < tStop
        ev = odeset(opts, Events=@(~, x) stageEvents(x, c, apoTarget));
        [ts, xs, ~, ~, ie] = ode45(rhs, gridTimes(t, tStop, 1), x, ev);
        append(ts, xs, k);
        impacted = any(ie == 1);
        cutoff   = any(ie == 2);
    end
    if impacted || (t >= tEnd && ~cutoff), break, end

    if cutoff
        events(end+1, :) = {st.Name + " cutoff", t}; %#ok<AGROW>
    else
        events(end+1, :) = {st.Name + " burnout", t}; %#ok<AGROW>
    end
    x(7) = x(7) - st.Dry_kg;                    % 空になったステージを分離

    if st.CoastAfter_s > 0 && k < height(lv.Stages)
        impacted = coast(min(t + st.CoastAfter_s, tEnd), 1, k);
        if impacted || t >= tEnd, break, end
    end
end
xBurnout = x;

% --- 最終燃焼終了後の慣性飛行 (軌道 or 弾道)
if ~impacted && t < tEnd
    impacted = coast(tEnd, dtCoast, 0);
end
if impacted, events(end+1, :) = {"Impact", t}; end

% --- 出力整形
[T, iu] = unique(T);  X = X(iu, :);  stageId = stageId(iu);
result = packResult(T, X, stageId, events, xBurnout, impacted, t >= tEnd, r0, lv, area, c);

    % ---- 入れ子関数: 時刻歴の追記と慣性飛行
    function append(ts, xs, id)
        T = [T; ts];  X = [X; xs];  stageId = [stageId; repmat(id, numel(ts), 1)];
        t = ts(end);  x = xs(end, :)';
    end

    function hit = coast(tStop, dt, id)
        rhsCoast = @(t, x) dynamics(t, x, [], 0, area, lv, c, tPitch);
        evCoast  = odeset(opts, Events=@(~, x) impactEvent(x, c));
        [ts, xs, te] = ode45(rhsCoast, gridTimes(t, tStop, dt), x, evCoast);
        append(ts, xs, id);
        hit = ~isempty(te);
    end
end

%% ---------------------------------------------------------------- 力学
function dx = dynamics(t, x, st, mdot, area, lv, c, tPitch)
% 質点の運動方程式。st が空なら推力なし (慣性飛行)。
r = x(1:3);  v = x(4:6);  m = x(7);
rn = norm(r);  up = r/rn;
h  = altitude(r, c);

% 大気 (指数モデル)
pRatio = exp(-h / c.ScaleHeight);
rho    = c.Rho0 * pRatio;
vRel   = v - cross(c.Omega, r);
drag   = -0.5 * rho * lv.Cd * area * norm(vRel) * vRel;

thrust = [0; 0; 0];
if ~isempty(st)
    isp    = st.IspVac_s - (st.IspVac_s - st.IspSL_s) * pRatio;
    thrust = mdot * c.g0 * isp * thrustDirection(t, up, vRel, lv, tPitch);
end

dx = [v; -c.Mu/rn^3 * r + (thrust + drag)/m; -mdot];
end

function d = thrustDirection(t, up, vRel, lv, tPitch)
% 誘導則: 垂直上昇 -> ピッチキック -> 重力ターン
if t < tPitch
    d = up;
elseif t < tPitch + lv.KickDuration_s
    east  = cross([0; 0; 1], up);  east = east/norm(east);
    north = cross(up, east);
    horiz = cosd(lv.Azimuth_deg)*north + sind(lv.Azimuth_deg)*east;
    d = cosd(lv.KickAngle_deg)*up + sind(lv.KickAngle_deg)*horiz;
else
    d = vRel / norm(vRel);
end
end

function h = altitude(r, c)
% 楕円体高度の近似 (地心緯度による半径補正)
rn = norm(r);
h  = rn - c.Re * (1 - c.Flattening * (r(3)/rn)^2);
end

function [value, isterminal, direction] = pitchoverEvent(x, hPitch, c)
value = altitude(x(1:3), c) - hPitch;  isterminal = 1;  direction = 1;
end

function [value, isterminal, direction] = impactEvent(x, c)
value = altitude(x(1:3), c);  isterminal = 1;  direction = -1;
end

function [value, isterminal, direction] = stageEvents(x, c, apoTarget)
% (1) 地表到達  (2) 接触軌道の遠地点高度が目標に到達
value = [altitude(x(1:3), c); -1];
if isfinite(apoTarget)
    [~, apoAlt] = apsides(x(1:3), x(4:6), c);
    value(2) = apoAlt - apoTarget;
end
isterminal = [1; 1];  direction = [-1; 1];
end

function [periAlt, apoAlt, sma, ecc, hvec] = apsides(r, v, c)
% 接触軌道の近地点・遠地点高度 [m] (双曲線軌道の遠地点は Inf)
energy = norm(v)^2/2 - c.Mu/norm(r);
hvec   = cross(r, v);
sma    = -c.Mu / (2*energy);
ecc    = sqrt(max(0, 1 + 2*energy*norm(hvec)^2 / c.Mu^2));
periAlt = norm(hvec)^2/c.Mu / (1 + ecc) - c.Re;
if energy < 0, apoAlt = sma*(1 + ecc) - c.Re; else, apoAlt = Inf; end
end

function tt = gridTimes(t0, t1, dt)
% 出力時刻 (ode45 は3点以上のベクトルを要求する)
tt = unique([t0:dt:t1, t1]);
if numel(tt) < 3, tt = linspace(t0, t1, 3); end
end

function c = earthConstants()
c.Mu          = 3.986004418e14;      % [m^3/s^2]
c.Re          = 6378137;             % [m]
c.Flattening  = 1/298.257223563;
c.Omega       = [0; 0; 7.292115e-5]; % [rad/s]
c.g0          = 9.80665;
c.Rho0        = 1.225;               % [kg/m^3]
c.ScaleHeight = 7200;                % [m]
end

%% ---------------------------------------------------------------- 出力
function result = packResult(T, X, stageId, events, xBurnout, impacted, timedOut, r0, lv, area, c)
R = X(:, 1:3);  V = X(:, 4:6);  M = X(:, 7);

% 慣性系 -> 地球固定系 (z軸まわりに -Omega*t 回転)
th   = c.Omega(3) * T;
Recf = [ cos(th).*R(:,1) + sin(th).*R(:,2), ...
        -sin(th).*R(:,1) + cos(th).*R(:,2), R(:,3)];
lla  = ecef2lla(Recf);

Vrel  = V - cross(repmat(c.Omega', numel(T), 1), R, 2);
rn    = vecnorm(R, 2, 2);
speed = vecnorm(V, 2, 2);
rho   = c.Rho0 * exp(-lla(:,3) / c.ScaleHeight);
q     = 0.5 * rho .* vecnorm(Vrel, 2, 2).^2;
gamma = asind(dot(R, V, 2) ./ (rn .* speed));          % 慣性飛行経路角
downrange = c.Re * acos(min(1, Recf * r0 ./ (vecnorm(Recf, 2, 2) * norm(r0))));

% 非重力加速度 [g] (推力 + 抗力)
accel = zeros(numel(T), 1);
for i = 1:numel(T)
    k = stageId(i);
    if k > 0
        st = lv.Stages(k, :);  mdot = st.ThrustVac_kN*1e3 / (c.g0*st.IspVac_s);
    else
        st = [];  mdot = 0;
    end
    dx = dynamics(T(i), X(i,:)', st, mdot, area, lv, c, -Inf);
    grav = -c.Mu / rn(i)^3 * R(i,:)';
    accel(i) = norm(dx(4:6) - grav) / c.g0;
end

result.Time = T;
result.LLA  = lla;
result.Telemetry = table(T, lla(:,3)/1e3, speed, M, q/1e3, gamma, downrange/1e3, ...
    accel, stageId, VariableNames=["Time_s","Alt_km","Speed_mps","Mass_kg", ...
    "Q_kPa","Gamma_deg","Downrange_km","Accel_g","Stage"]);

events.Alt_km    = interp1(T, lla(:,3)/1e3, events.Time_s);
events.Speed_mps = interp1(T, speed, events.Time_s);
result.Events = events;

% 最終燃焼終了時の接触軌道
[periAlt, apoAlt, sma, ecc, hvec] = apsides(xBurnout(1:3), xBurnout(4:6), c);
result.Orbit = struct( ...
    PerigeeAlt_km = periAlt/1e3, ...
    ApogeeAlt_km  = apoAlt/1e3, ...
    Inc_deg       = acosd(hvec(3)/norm(hvec)), ...
    Ecc = ecc, SMA_km = sma/1e3);

if impacted
    result.Reached = "impact";
elseif timedOut && result.Orbit.PerigeeAlt_km > 100 && isfinite(apoAlt)
    result.Reached = "orbit";
else
    result.Reached = "flying";
end
end
