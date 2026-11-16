function result = designLunarTransfer(p, epoch)
%DESIGNLUNARTRANSFER  地球待機軌道から月周回軌道までの遷移軌道を設計する
%   result = mstudio.designLunarTransfer(p, epoch) は、時刻 epoch (UTC) に
%   月遷移投入 (TLI) を始め、指定の高度・傾斜角で月に最接近して月周回軌道に
%   入るまでの軌道を求めます。p は mstudio.defaultLunarTransfer 形式です。
%
%   手順
%     1. 初期推定: 遠地点が到着時の月の位置に向く遷移楕円 (二体問題) から、
%        TLI の増速量、待機軌道の昇交点赤経、TLI 位置を決める
%     2. ターゲティング (インパルス): 地球・月・太陽の重力で伝播し、月最接近時の
%        高度と傾斜角が目標に合うよう 3 変数 (増速量、昇交点赤経、TLI 位置)
%        を lsqnonlin で修正する
%     3. p.BurnModel = "finite" のとき: 2 の解を初期値に、進行方向へ一定推力で
%        燃焼する TLI について 3 変数 (燃焼時間、昇交点赤経、燃焼開始位置) を
%        同じ目標で解き直す
%     4. 月周回投入 (LOI): インパルスでは最接近点で円軌道速度まで減速。
%        有限燃焼では逆方向へ一定推力で燃焼する。燃焼が長いと最接近点を中心に
%        噴くだけでは円軌道にならないので、燃焼時間・燃焼の中心時刻・接近軌道の
%        最接近高度の 3 つを調整して、目標高度の円軌道に入れる。最接近高度を
%        変えた分は TLI のターゲティングをやり直して反映する
%     5. 月中心で p.LunarOrbits 周回ぶん伝播する
%
%   力モデル
%     地球・月・太陽の質点重力 (DE405)。p.IncludeSRP で太陽輻射圧、
%     p.MoonGravityDegree で月周回中の月重力場 (LP165P) を追加できます。
%
%   result のフィールド
%     Epoch          TLI 開始時刻
%     Time           TLI 開始からの経過時間 [s] (N×1)
%     PosEarth_km    地球中心 ICRF での位置 (N×3)
%     MoonPos_km     同時刻の月の位置 (地球中心、N×3)
%     Phase          1 = 遷移、2 = 月周回
%     Thrusting      燃焼中のサンプルなら true (有限燃焼のみ)
%     BurnModel      "impulsive" | "finite"
%     DeltaV_TLI, DeltaV_LOI   増速量 [km/s] (有限燃焼ではロケット方程式の値)
%     TLI, LOI       燃焼の詳細 (Duration_s, Propellant_kg, MassAfter_kg)
%     TransferDays   TLI 開始から月最接近までの日数
%     PeriluneAlt_km, LunarInc_deg   LOI をしない場合の月最接近高度と傾斜角。
%                    有限燃焼では円軌道化のため目標高度より少し高くなる
%     LunarOrbitAlt_km   LOI 直後の月周回軌道の [近月点, 遠月点] 高度
%     RAAN_deg, ArgLat_deg     待機軌道の昇交点赤経と TLI 開始位置 (緯度引数)
%     TLIState       TLI 直後 (有限燃焼では燃焼開始時) の状態 [km; km/s]
%     LOITime, LOIState  LOI 完了時刻 [s] と、その時の月中心 ICRF での状態
%     Converged      ターゲティングが収束したか
%
%   See also mstudio.defaultLunarTransfer, mstudio.propagateNBody, mstudio.nbodyModel

arguments
    p     (1,1) struct
    epoch (1,1) datetime
end

k = constants();
finite = string(p.BurnModel) == "finite";
r0  = k.EarthRadius + p.ParkingAlt_km;
inc = p.ParkingInc_deg;
forces = {};
if p.IncludeSRP
    forces = {"ReflectivityArea_m2", p.Cr * p.SRPArea_m2, "Mass_kg", p.ProbeMass_kg};
end

% --- 1. 初期推定 (遷移楕円の半周期で到着時刻を決め、数回反復)
tof = 5 * k.Day;
for iter = 1:4
    moonAtArrival = mstudio.ephemeris("Earth", "Moon", epoch, tof);
    sma = (r0 + norm(moonAtArrival)) / 2;
    tof = pi * sqrt(sma^3 / k.MuEarth);
end
dv0 = sqrt(k.MuEarth * (2/r0 - 1/sma)) - sqrt(k.MuEarth / r0);
[raan0, argLat0] = planeThrough(-moonAtArrival' / norm(moonAtArrival), inc);

% --- 2. ターゲティング (インパルス)
tMax   = tof + 2*k.Day;
model  = mstudio.nbodyModel("Earth", epoch, [0 tMax], forces{:});
moon   = moonInterpolants(epoch, tMax);
tGrid  = (0:120:tMax)';
target = [p.PeriluneAlt_km, p.LunarInc_deg];
options = optimoptions("lsqnonlin", Algorithm="levenberg-marquardt", Display="off", ...
    FunctionTolerance=1e-14, StepTolerance=1e-12, MaxIterations=60, ...
    FiniteDifferenceStepSize=1e-7);

impulsive = @(x) flyby(tliState(r0, inc, x(2), x(3), x(1), k.MuEarth), [], tGrid, model, moon, k);
x = lsqnonlin(@(x) residual(impulsive(x), target), [dv0, raan0, argLat0], [], [], options);
fb = impulsive(x);
tli = struct(Duration_s=0, Propellant_kg=NaN, MassAfter_kg=NaN);
dvTLI = x(1);

% --- 3. ターゲティング (有限燃焼)。変数は [燃焼時間/100 s, 昇交点赤経, 開始位置]
if finite
    thrust   = struct(Force_N=p.Thrust_kN*1e3, Isp_s=p.Isp_s, Direction="velocity");
    burnTime = burnDuration(x(1), p.Mass_kg, thrust, k);
    meanMotion = sqrt(k.MuEarth / r0^3);
    start    = [burnTime/100, x(2), x(3) - meanMotion*burnTime/2];   % 燃焼の中心を合わせる
    burning  = @(y) flyby([tliState(r0, inc, y(2), y(3), 0, k.MuEarth); p.Mass_kg], ...
        setfield(thrust, "Duration", 100*y(1)), tGrid, model, moon, k);
    x  = lsqnonlin(@(y) residual(burning(y), target), start, [], [], options);
    fb = burning(x);
end
assert(~isempty(fb.Event), "mstudio:lunar:noFlyby", "月への最接近が得られませんでした。");

% --- 4. 月周回投入
rp       = k.MoonRadius + p.PeriluneAlt_km;
period   = 2*pi * sqrt(rp^3 / k.MuMoon);
tPeri    = fb.Event.Time;
tLunarEnd = tPeri + p.LunarOrbits*period + 3600;
moonModel = mstudio.nbodyModel("Moon", epoch, [tPeri - 3*3600, tLunarEnd], ...
    forces{:}, MoonGravityDegree=p.MoonGravityDegree);

if finite
    retro = struct(Force_N=p.LOIThrust_N, Isp_s=p.LOIIsp_s, Direction="antivelocity");
    guess = burnDuration(norm(fb.VRel) - sqrt(k.MuMoon/norm(fb.Rel)), p.ProbeMass_kg, retro, k);
    burnLOI = @(perilune, z) insertionBurn(perilune, tPeri, 100*z(1), 100*z(2), ...
        p.ProbeMass_kg, retro, moonModel);
    lsqOpts = optimoptions(options, FiniteDifferenceStepSize=1e-5);

    % (a) 燃焼時間・中心時刻・最接近高度の補正量を、接近軌道を近似的に動かして求める
    shifted = @(dAlt) raisePerilune([fb.Rel; fb.VRel], dAlt, k);
    z = lsqnonlin(@(z) circularError(burnLOI(shifted(10*z(3)), z), rp, k), ...
        [guess/100, 0, 0], [], [], lsqOpts);

    % (b) 補正した最接近高度で TLI を解き直し、実際の接近軌道で燃焼を合わせ直す
    target(1) = p.PeriluneAlt_km + 10*z(3);
    x  = lsqnonlin(@(y) residual(burning(y), target), x, [], [], options);
    fb = burning(x);
    tPeri = fb.Event.Time;
    burnLOI = @(perilune, z) insertionBurn(perilune, tPeri, 100*z(1), 100*z(2), ...
        p.ProbeMass_kg, retro, moonModel);
    z = lsqnonlin(@(z) circularError(burnLOI([fb.Rel; fb.VRel], z), rp, k), ...
        z(1:2), [], [], lsqOpts);

    b    = burnLOI([fb.Rel; fb.VRel], z);
    tLOI = b.Time;  XLOI = b.X;                 % 燃焼区間 (月中心)
    loi  = struct(Duration_s=100*z(1), Propellant_kg=p.ProbeMass_kg - XLOI(end, 7), ...
        MassAfter_kg=XLOI(end, 7));
    dvLOI = p.LOIIsp_s * k.g0 * log(p.ProbeMass_kg / XLOI(end, 7)) / 1e3;
    orbitStart = XLOI(end, 1:6)';

    tli = struct(Duration_s=100*x(1), Propellant_kg=p.Mass_kg - fb.MassAfterBurn, ...
        MassAfter_kg=fb.MassAfterBurn);
    dvTLI = p.Isp_s * k.g0 * log(p.Mass_kg / fb.MassAfterBurn) / 1e3;
else
    vCirc = sqrt(k.MuMoon / norm(fb.Rel));
    dvLOI = norm(fb.VRel) - vCirc;
    tLOI  = tPeri;  XLOI = [fb.Rel; fb.VRel]';
    loi   = struct(Duration_s=0, Propellant_kg=NaN, MassAfter_kg=NaN);
    orbitStart = [fb.Rel; fb.VRel * vCirc / norm(fb.VRel)];
end
res = residual(fb, target);

% --- 5. 月周回
tOrbit = tLOI(end) + (0:30:p.LunarOrbits * period)';
[tL, XL] = mstudio.propagateNBody(orbitStart, tOrbit, moonModel);

% --- 出力 (遷移は LOI 開始まで、以降は月中心の結果を地球中心に直す)
keep  = fb.Time < tLOI(1);
tMoon = [tLOI; tL(2:end)];
relMoon = [XLOI(:, 1:3); XL(2:end, 1:3)];
moonDuring = mstudio.ephemeris("Earth", "Moon", epoch, tMoon);

result.Epoch       = epoch;
result.Time        = [fb.Time(keep); tMoon];
result.PosEarth_km = [fb.X(keep, 1:3); relMoon + moonDuring];
result.MoonPos_km  = mstudio.ephemeris("Earth", "Moon", epoch, result.Time);
result.Phase       = [ones(nnz(keep), 1); 2*ones(numel(tMoon), 1)];
result.Thrusting   = [fb.Time(keep) <= tli.Duration_s & finite; ...
    tMoon <= tLOI(end) & finite];
result.BurnModel   = string(p.BurnModel);
result.DeltaV_TLI  = dvTLI;
result.DeltaV_LOI  = dvLOI;
result.TLI         = tli;
result.LOI         = loi;
result.TransferDays   = tPeri / k.Day;
result.PeriluneAlt_km = fb.Alt;
result.LunarInc_deg   = fb.Inc;
result.LunarOrbitAlt_km = apsisAltitudes(orbitStart, k);
result.RAAN_deg    = mod(rad2deg(x(2)), 360);
result.ArgLat_deg  = mod(rad2deg(x(3)), 360);
result.TLIState    = fb.State0(1:6);
result.LOITime     = tLOI(end);
result.LOIState    = orbitStart;
result.Converged   = norm(res) < 1e-3;      % 高度 1 km、傾斜角 0.01 deg 以内
end

%% ------------------------------------------------------------ 遷移区間
function out = flyby(state, burn, tGrid, model, moon, k)
% 待機軌道上の状態から月最接近まで伝播する
%   burn が空ならインパルス後の状態 (6要素) から慣性飛行。
%   burn があれば、質量を含む状態 (7要素) で burn.Duration だけ燃焼してから慣性飛行
out = struct(Time=[], X=[], Event=[], Rel=[], VRel=[], State0=state, ...
    Alt=NaN, Inc=NaN, MassAfterBurn=NaN);
tb = zeros(0, 1);  Xb = zeros(0, 6);  tStart = 0;
if ~isempty(burn)
    tBurn = linspace(0, burn.Duration, max(3, ceil(burn.Duration/10) + 1))';
    [tb, Xb] = mstudio.propagateNBody(state, tBurn, model, [], burn);
    out.MassAfterBurn = Xb(end, 7);
    state  = Xb(end, 1:6)';  tStart = burn.Duration;
    tb = tb(1:end-1);  Xb = Xb(1:end-1, 1:6);
end
closest = @(t, s) closestApproach(t, s, moon, k.Day);
[tc, Xc, ev] = mstudio.propagateNBody(state, [tStart; tGrid(tGrid > tStart)], model, closest);
out.Time = [tb; tc];  out.X = [Xb; Xc];
if isempty(ev.Time), return, end

out.Event = ev;
out.Rel   = ev.State(1:3) - moon.Pos(ev.Time)';
out.VRel  = ev.State(4:6) - moon.Vel(ev.Time)';
h = cross(out.Rel, out.VRel);
out.Alt = norm(out.Rel) - k.MoonRadius;
out.Inc = acosd(h(3) / norm(h));
end

function res = residual(fb, target)
% 月最接近の高度 [1000 km 単位] と傾斜角 [10 deg 単位] の目標との差
if isempty(fb.Event)
    res = [1e3; 1e3];                       % 最接近が見つからない
else
    res = [(fb.Alt - target(1)) / 1000; (fb.Inc - target(2)) / 10];
end
end

function value = closestApproach(t, s, moon, day)
% 月に対する動径速度。負から正に変わる点が最接近 (出発直後の1日は対象外)
if t < day
    value = -1;
else
    value = dot(s(1:3) - moon.Pos(t)', s(4:6) - moon.Vel(t)');
end
end

%% ------------------------------------------------------------ 月周回投入
function b = insertionBurn(perilune, tPeri, tau, shift, mass, thrust, moonModel)
% 時刻 tPeri + shift を中心とする長さ tau の逆噴射。b.Time, b.X (月中心、7要素) を返す
%   perilune は噴射しない場合の最接近時 (tPeri) の状態。燃焼開始点は、その軌道を
%   開始時刻まで伝播して求める (最接近より前なら逆向きに伝播)
tStart = tPeri + shift - tau/2;
[~, coast] = mstudio.propagateNBody(perilune, tPeri + (tStart - tPeri)*[0; 0.5; 1], moonModel);
tBurn = tStart + linspace(0, tau, max(3, ceil(tau/10) + 1))';
[b.Time, b.X] = mstudio.propagateNBody([coast(end, :)'; mass], tBurn, moonModel, [], thrust);
end

function err = circularError(b, radius, k)
% 燃焼後の軌道と、半径 radius の円軌道との差: [エネルギー; 離心率ベクトルの2成分]
s = b.X(end, 1:6)';
r = s(1:3);  v = s(4:6);
energy = norm(v)^2/2 - k.MuMoon/norm(r);
target = -k.MuMoon / (2*radius);
eccVec = cross(v, cross(r, v))/k.MuMoon - r/norm(r);
radial = r / norm(r);
along  = cross(cross(r, v), r);  along = along / norm(along);
err = [(energy - target)/abs(target); dot(eccVec, radial); dot(eccVec, along)] * 100;
end

function s = raisePerilune(perilune, dAlt, k)
% 最接近高度を dAlt [km] だけ変えた近傍の接近軌道 (無限遠速度と向きは同じとみなす)
r = perilune(1:3);  v = perilune(4:6);
vInfSq = norm(v)^2 - 2*k.MuMoon/norm(r);
rNew = r * (1 + dAlt/norm(r));
s = [rNew; v/norm(v) * sqrt(vInfSq + 2*k.MuMoon/norm(rNew))];
end

%% ------------------------------------------------------------ 補助関数
function k = constants()
k.MuEarth = 398600.4415;  k.MuMoon = 4902.8005821478;      % [km^3/s^2]
k.EarthRadius = 6378.137;  k.MoonRadius = 1737.4;          % [km]
k.g0 = 9.80665;  k.Day = 86400;
end

function tau = burnDuration(dv_kmps, mass, thrust, k)
% 増速量 dv を得るのに必要な燃焼時間 (ロケット方程式、重力損失なし)
ve  = thrust.Isp_s * k.g0;
tau = mass * (1 - exp(-dv_kmps*1e3 / ve)) * ve / thrust.Force_N;
end

function alt = apsisAltitudes(state, k)
% 月中心の状態から、接触軌道の [近月点, 遠月点] 高度 [km]
r = state(1:3);  v = state(4:6);
energy = norm(v)^2/2 - k.MuMoon/norm(r);
ecc = norm(cross(v, cross(r, v))/k.MuMoon - r/norm(r));
sma = -k.MuMoon / (2*energy);
alt = sma * [1 - ecc, 1 + ecc] - k.MoonRadius;
end

function [raan, argLat] = planeThrough(d, incDeg)
% 単位ベクトル d を含み、傾斜角 incDeg の軌道面の昇交点赤経と、d の緯度引数 [rad]
amp = sind(incDeg) * hypot(d(1), d(2));
assert(abs(cosd(incDeg) * d(3)) <= amp, "mstudio:lunar:inclination", ...
    "待機軌道の傾斜角が小さすぎて、到着時の月の方向を軌道面に含められません。");
raan = atan2(d(2), d(1)) + asin(-cosd(incDeg) * d(3) / amp);
node = [cos(raan); sin(raan); 0];
normal = [sind(incDeg)*sin(raan); -sind(incDeg)*cos(raan); cosd(incDeg)];
argLat = atan2(dot(cross(node, d(:)), normal), dot(node, d(:)));
end

function x = tliState(r0, incDeg, raan, argLat, dv, mu)
% 円軌道上の緯度引数 argLat の点で、進行方向に dv を加えた直後の状態
node   = [cos(raan); sin(raan); 0];
normal = [sind(incDeg)*sin(raan); -sind(incDeg)*cos(raan); cosd(incDeg)];
inPlane = cross(normal, node);
rHat = cos(argLat)*node + sin(argLat)*inPlane;
vHat = -sin(argLat)*node + cos(argLat)*inPlane;
x = [r0 * rHat; (sqrt(mu / r0) + dv) * vHat];
end

function moon = moonInterpolants(epoch, tMax)
% 地球から見た月の位置・速度の補間関数
grid = (-600:600:tMax + 1200)';
[P, V] = mstudio.ephemeris("Earth", "Moon", epoch, grid);
moon.Pos = griddedInterpolant(grid, P, "spline");
moon.Vel = griddedInterpolant(grid, V, "spline");
end
