function [t, X, event] = propagateNBody(x0, tOut, model, eventFcn, thrust)
%PROPAGATENBODY  N体問題の力モデルで軌道を数値積分する
%   [t, X] = mstudio.propagateNBody(x0, tOut, model) は、初期状態 x0 を
%   時刻 tOut (epoch からの経過秒、単調増加) について伝播します。
%   model は mstudio.nbodyModel の出力です。
%
%   状態量 x0 は model の中心天体・ICRF軸で
%     6 要素: [位置 km; 速度 km/s]
%     7 要素: [位置 km; 速度 km/s; 質量 kg]  (推力を使うときは必須)
%   X は N×6 または N×7。
%
%   [t, X, event] = mstudio.propagateNBody(x0, tOut, model, eventFcn) は、
%   value = eventFcn(t, x) が負から正に変わった時点で積分を打ち切ります。
%   event.Time, event.State にその時刻と状態が入ります (起きなければ空)。
%   打ち切った場合、t と X の最終行はイベント時点です。
%
%   [...] = mstudio.propagateNBody(x0, tOut, model, eventFcn, thrust) は、
%   全区間で一定推力をかけます (有限燃焼)。thrust は構造体で
%     Force_N    推力 [N]
%     Isp_s      比推力 [s]
%     Direction  "velocity" (進行方向) | "antivelocity" (逆方向)。
%                速度は中心天体に対する慣性速度
%   イベントが不要なら eventFcn に [] を渡します。
%
%   運動方程式
%     a = (中心天体の重力) + sum_k mu_k [ (r_k - r)/|r_k - r|^3 - r_k/|r_k|^3 ]
%         + (太陽輻射圧) + (推力)/m,    dm/dt = -(推力)/(Isp g0)
%   積分は ode113 (RelTol 1e-12, AbsTol 1e-9 km)。
%
%   See also mstudio.nbodyModel, mstudio.designLunarTransfer

arguments
    x0       (:,1) double {mustBeVector}
    tOut     (:,1) double
    model    (1,1) struct
    eventFcn = []
    thrust   = []
end
assert(ismember(numel(x0), [6 7]), "mstudio:nbody:state", "状態量は 6 または 7 要素です。");
assert(isempty(thrust) || numel(x0) == 7, "mstudio:nbody:mass", ...
    "推力を使うときは状態量に質量を含めてください (7 要素)。");

absTol = [1e-9*ones(6, 1); 1e-6];
opts   = odeset(RelTol=1e-12, AbsTol=absTol(1:numel(x0)));
rhs    = @(t, x) dynamics(t, x, model, thrust);
event  = struct(Time=[], State=[]);
if isempty(eventFcn)
    [t, X] = ode113(rhs, tOut, x0, opts);
    return
end

opts = odeset(opts, Events=@(t, x) terminalEvent(eventFcn(t, x)));
[t, X, te, xe] = ode113(rhs, tOut, x0, opts);
if ~isempty(te)
    event = struct(Time=te(end), State=xe(end, :)');
    if t(end) < te(end)
        t(end+1) = te(end);  X(end+1, :) = xe(end, :);
    end
end
end

%% ---------------------------------------------------------------- 力学
function dx = dynamics(t, x, model, thrust)
r = x(1:3);  v = x(4:6);
if numel(x) == 7, mass = x(7); else, mass = model.Mass_kg; end

a = centralGravity(t, r, model);

% 第三天体の質点重力
sunPos = [];
for k = 1:numel(model.Bodies)
    rk = model.Position{k}(t)';
    d  = rk - r;
    a  = a + model.MuThird(k) * (d / norm(d)^3 - rk / norm(rk)^3);
    if k == model.SunIndex, sunPos = rk; end
end

% 太陽輻射圧 (球モデル、太陽から遠ざかる向き)
if model.ReflectivityArea_m2 > 0
    pressureAt1AU = 1367 / 299792458;       % [N/m^2]
    au = 149597870.691;                     % [km]
    fromSun = r - sunPos;
    dist = norm(fromSun);
    a = a + pressureAt1AU * (au/dist)^2 * model.ReflectivityArea_m2 / mass / 1e3 ...
        * fromSun / dist;
end

% 推力
massRate = 0;
if ~isempty(thrust)
    direction = v / norm(v);
    if thrust.Direction == "antivelocity", direction = -direction; end
    a = a + thrust.Force_N / mass / 1e3 * direction;
    massRate = -thrust.Force_N / (thrust.Isp_s * 9.80665);
end

dx = [v; a];
if numel(x) == 7, dx(7) = massRate; end
end

function a = centralGravity(t, r, model)
% 中心天体の重力加速度 [km/s^2]。月は球面調和 (LP165P) に切り替えられる
if model.MoonGravityDegree < 2
    a = -model.Mu * r / norm(r)^3;
    return
end
ang = model.Libration(t);
toFixed = angle2dcm(ang(1), ang(2), ang(3), "ZXZ");     % ICRF -> 月主軸系
[gx, gy, gz] = gravitysphericalharmonic((toFixed * r)' * 1e3, "LP165P", ...
    model.MoonGravityDegree, "None");
a = toFixed' * [gx; gy; gz] / 1e3;
end

function [value, isterminal, direction] = terminalEvent(value)
isterminal = 1;  direction = 1;
end
