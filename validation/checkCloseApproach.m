function r = checkCloseApproach()
%CHECKCLOSEAPPROACH  最接近の絞り込み精度を、細かい刻みの結果と比べて確認する
%   r = checkCloseApproach() は、二体問題 (解析解なので刻みによらず正確) の
%   低軌道衛星 2 機が約 2 km まで近づく場面を作り、刻み 30 s で求めた最接近と、
%   刻み 1 s で求めた最接近を比べます。両者の最接近時刻・距離の差が補間の誤差です。
%   参考として、補間しない場合 (刻み 30 s の標本の最小値) の距離も出します。
%
%   See also mstudio.computeCloseApproaches

addpath(fileparts(fileparts(mfilename("fullpath"))));

spec = mstudio.defaultSpec();
spec.DurationHours = 6;
spec.Launcher.Enabled = false;
spec.Propagator.Method = "two-body-keplerian";
spec.Stations = spec.Stations(1, :);
spec.Satellites = spec.Satellites(1, :);
spec.Satellites{1, 2:end} = [6978 0.001 97.8 120 0 45];

% 衛星 B は、3 時間後に衛星 A の約 2 km 横を、軌道面が 60 度違う向きで通る軌道にする
tEncounter = 3 * 3600;
spec.SampleTime = 60;
[~, h] = mstudio.buildScenario(spec);
[pos, vel, t] = states(h.Assets{1});
k = find(seconds(t - t(1)) == tEncounter);
rA = pos(:, k);  vA = vel(:, k);
axis = rA / norm(rA);
vB = vA*cosd(60) + cross(axis, vA)*sind(60);            % 動径まわりに 60 度回す
rB = rA + 2e3 * cross(axis, vA) / norm(vA);
spec.Satellites(2, :) = spec.Satellites(1, :);
spec.Satellites.Name(2) = "B";
spec.Satellites{2, 2:end} = elementsAtEpoch(rB, vB, tEncounter);

results = cell(1, 2);  rawMin = NaN;
steps = [30 1];
for k = 1:2
    spec.SampleTime = steps(k);
    [~, h] = mstudio.buildScenario(spec);
    [T, range] = mstudio.computeCloseApproaches(h);
    results{k} = T(1, :);                       % 最も近い接近
    if k == 1, rawMin = min(range.Distance_km); end
end

r.Coarse = results{1};  r.Fine = results{2};
r.TimeDiff_s = abs(seconds(r.Coarse.TCA - r.Fine.TCA));
r.MissDiff_m = abs(r.Coarse.MissDistance_km - r.Fine.MissDistance_km) * 1e3;
r.SampledMin_km = rawMin;
fprintf("30 s step: miss %.4f km at %s, rel speed %.3f km/s\n", ...
    r.Coarse.MissDistance_km, string(r.Coarse.TCA, "HH:mm:ss.SSS"), r.Coarse.RelSpeed_kmps);
fprintf(" 1 s step: miss %.4f km at %s\n", r.Fine.MissDistance_km, string(r.Fine.TCA, "HH:mm:ss.SSS"));
fprintf("difference: %.4f s, %.2f m   (unrefined 30 s minimum: %.1f km)\n", ...
    r.TimeDiff_s, r.MissDiff_m, r.SampledMin_km);
end


function el = elementsAtEpoch(r, v, dt)
% 時刻 dt [s] の状態 (慣性系 [m], [m/s]) を通る二体問題の軌道の、時刻 0 の軌道要素
%   [a_km e i RAAN ArgP Nu] (角度は deg)
mu = 398600.4418e9;                                     % satelliteScenario の値 [m^3/s^2]
[a, e, inc, raan, argp, nu] = ijk2keplerian(r, v);
E  = 2 * atan(sqrt((1-e)/(1+e)) * tand(nu/2));          % 離心近点角
M  = E - e*sin(E) - sqrt(mu/a^3) * dt;                   % dt だけ戻した平均近点角
E0 = M;
for iter = 1:50, E0 = E0 - (E0 - e*sin(E0) - M) / (1 - e*cos(E0)); end
nu0 = 2 * atand(sqrt((1+e)/(1-e)) * tan(E0/2));
el = [a/1e3, e, inc, raan, argp, mod(nu0, 360)];
end
