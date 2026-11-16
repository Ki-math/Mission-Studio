function [kick, result] = tuneKickAngle(lv, range)
%TUNEKICKANGLE  近地点高度が最大になるピッチキック角を探索する
%   kick = mstudio.tuneKickAngle(lv) は、重力ターンのキック角 [deg] を
%   1〜12 deg の範囲で探索し、最終燃焼終了時の近地点高度が最大となる値を
%   返します。lv.CutoffApogee_km を設定していれば、遠地点がその高度の
%   ほぼ円軌道になるキック角が得られます。
%   kick = mstudio.tuneKickAngle(lv, [lo hi]) は探索範囲を指定します。
%   [kick, result] = ... は、そのキック角での計算結果も返します。
%
%   重力ターンは解が1パラメータで決まるため、粗い走査で山を見つけてから
%   fminbnd で絞り込みます。
%
%   See also mstudio.simulateAscent

arguments
    lv    (1,1) struct
    range (1,2) double = [1 12]
end

% 動力飛行の終了まで計算すれば十分
c = 9.80665;
tBurn = sum(lv.Stages.Prop_kg ./ (lv.Stages.ThrustVac_kN*1e3 ./ (c*lv.Stages.IspVac_s)));
tEnd  = tBurn + sum(lv.Stages.CoastAfter_s) + 5;

grid = linspace(range(1), range(2), 23);
cost = arrayfun(@negPerigee, grid);
[~, i] = min(cost);
lo = grid(max(i-1, 1));  hi = grid(min(i+1, numel(grid)));
kick = fminbnd(@negPerigee, lo, hi, optimset(TolX=1e-3));

if nargout > 1
    lv.KickAngle_deg = kick;
    result = mstudio.simulateAscent(lv, tEnd);
end

    function J = negPerigee(k)
        trial = lv;  trial.KickAngle_deg = k;
        r = mstudio.simulateAscent(trial, tEnd);
        J = -r.Orbit.PerigeeAlt_km;
    end
end
