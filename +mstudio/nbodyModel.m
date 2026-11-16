function model = nbodyModel(center, epoch, tRange, opts)
%NBODYMODEL  N体問題の力モデルを作る
%   model = mstudio.nbodyModel(center, epoch, tRange) は、center を中心天体、
%   地球・月・太陽のうち残りを第三天体 (質点重力) とする力モデルを返します。
%   tRange = [t0 t1] は epoch (UTC の datetime) からの経過秒で、この範囲の
%   天体位置を DE405 から前もって求め、スプライン補間で使います
%   (600 s 刻み。月の位置の補間誤差は 1 mm 未満)。
%
%   model = mstudio.nbodyModel(___, Name=Value) で力を追加します。
%     ThirdBodies         第三天体 (既定: 中心天体以外の地球・月・太陽)
%     MoonGravityDegree   月の重力場 LP165P の次数 (既定 0 = 質点)。
%                         center = "Moon" のときだけ有効。月固定座標への変換は
%                         DE405 の秤動角 (主軸系) を使う
%     ReflectivityArea_m2 太陽輻射圧の Cr×面積 [m^2] (既定 0 = なし)。
%                         球モデル、影は考慮しない。太陽が第三天体に必要
%     Mass_kg             状態量に質量を含まないときに輻射圧で使う質量
%
%   座標系は center を原点とする ICRF 軸、単位は km, km/s。
%   重力定数と太陽定数は GMAT の既定値に合わせています。
%
%   See also mstudio.propagateNBody, mstudio.ephemeris

arguments
    center (1,1) string {mustBeMember(center, ["Earth","Moon","Sun"])}
    epoch  (1,1) datetime
    tRange (1,2) double
    opts.ThirdBodies         (1,:) string = setdiff(["Earth","Moon","Sun"], center, "stable")
    opts.MoonGravityDegree   (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.ReflectivityArea_m2 (1,1) double {mustBeNonnegative} = 0
    opts.Mass_kg             (1,1) double {mustBePositive} = 1000
end

mu = struct(Earth=398600.4415, Moon=4902.8005821478, Sun=132712440017.99);  % [km^3/s^2]

step = 600;
grid = (tRange(1) - step : step : tRange(2) + 2*step)';

model.Center  = center;
model.Epoch   = epoch;
model.Mu      = mu.(center);
model.Bodies  = opts.ThirdBodies;
model.MuThird = arrayfun(@(b) mu.(b), opts.ThirdBodies);
model.Position = cell(1, numel(opts.ThirdBodies));     % 補間関数: t [s] -> 位置 [km]
for k = 1:numel(opts.ThirdBodies)
    pos = mstudio.ephemeris(center, opts.ThirdBodies(k), epoch, grid);
    model.Position{k} = griddedInterpolant(grid, pos, "spline");
end

% --- 太陽輻射圧
model.ReflectivityArea_m2 = opts.ReflectivityArea_m2;
model.Mass_kg  = opts.Mass_kg;
model.SunIndex = find(opts.ThirdBodies == "Sun", 1);
assert(opts.ReflectivityArea_m2 == 0 || ~isempty(model.SunIndex), ...
    "mstudio:nbody:srpNeedsSun", "太陽輻射圧を使うには太陽を第三天体に含めてください。");

% --- 月の重力場 (月固定座標への回転に使う秤動角を補間)
model.MoonGravityDegree = 0;
model.Libration = [];
if center == "Moon" && opts.MoonGravityDegree >= 2
    jd = juliandate(epoch) + (69.184 + grid) / 86400;
    angles = unwrap(moonLibration(jd, "405"));          % [phi theta psi] (3-1-3 オイラー角)
    model.MoonGravityDegree = opts.MoonGravityDegree;
    model.Libration = griddedInterpolant(grid, angles, "spline");
end
end
