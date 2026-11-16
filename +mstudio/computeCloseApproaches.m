function [T, range] = computeCloseApproaches(h, threshold_km)
%COMPUTECLOSEAPPROACHES  ビークル同士の最接近 (距離が極小になる時刻) を求める
%   T = mstudio.computeCloseApproaches(h, threshold_km) は、シナリオ内の全ての
%   ビークルの組について距離の極小点を探し、最接近距離が threshold_km 以下の
%   ものを table で返します。h は mstudio.buildScenario の出力です。
%
%   T の列
%     ObjectA, ObjectB   ビークル名
%     TCA                最接近時刻 (UTC)
%     MissDistance_km    最接近距離
%     RelSpeed_kmps      その時の相対速度の大きさ
%
%   [T, range] = mstudio.computeCloseApproaches(___) は、距離の時刻歴も返します。
%     range.Time         サンプル時刻 (1×Nt)
%     range.Pairs        組の名前 (Np×2 string)
%     range.Distance_km  距離 (Np×Nt)。データの無い時刻は NaN
%
%   方法
%     シナリオの刻みで求めた相対位置から距離が極小になるサンプルを見つけ、
%     その前後の相対位置を 3 次スプラインで補間して最接近時刻を絞り込みます。
%     低軌道同士の交差は相対速度が 10 km/s を超えるので、刻みが粗いままでは
%     最接近距離を大きく見積もります。補間後の誤差は、刻み 30 s で 1 m 未満
%     です (validation/checkCloseApproach 参照)。
%
%   衝突確率は求めません (位置の誤差共分散が必要です)。
%
%   See also mstudio.buildScenario, states

arguments
    h            (1,1) struct
    threshold_km (1,1) double {mustBePositive} = Inf
end

T = table(Size=[0 5], VariableTypes=["string","string","datetime","double","double"], ...
    VariableNames=["ObjectA","ObjectB","TCA","MissDistance_km","RelSpeed_kmps"]);
T.TCA.TimeZone = "UTC";
range = struct(Time=[], Pairs=strings(0, 2), Distance_km=zeros(0, 0));

n = numel(h.Assets);
if n < 2, return, end

% --- 全ビークルの位置 (慣性系 [km])。データ範囲外は NaN
pos = cell(1, n);
for i = 1:n
    [p, ~, t] = states(h.Assets{i});
    p(:, t < h.ValidRange(i,1) | t > h.ValidRange(i,2)) = NaN;
    pos{i} = p / 1e3;
end
tSec = seconds(t - t(1));
range.Time = t;

for i = 1:n-1
    for j = i+1:n
        rel  = pos{j} - pos{i};                         % 3×Nt
        dist = vecnorm(rel);
        range.Pairs(end+1, :) = [h.AssetNames(i), h.AssetNames(j)];
        range.Distance_km(end+1, :) = dist;

        % 距離が両隣より小さいサンプル (極小の候補)
        k = find(dist(2:end-1) <= dist(1:end-2) & dist(2:end-1) < dist(3:end)) + 1;
        for m = k
            [tca, miss, speed] = refineMinimum(tSec, rel, m);
            if miss <= threshold_km
                T(end+1, :) = {h.AssetNames(i), h.AssetNames(j), ...
                    t(1) + seconds(tca), miss, speed}; %#ok<AGROW>
            end
        end
    end
end
T = sortrows(T, "MissDistance_km");
end

function [tca, miss, speed] = refineMinimum(t, rel, m)
% サンプル m 付近の相対位置をスプライン補間し、距離が最小になる時刻を求める
idx = max(m-3, 1):min(m+3, numel(t));
idx = idx(~any(isnan(rel(:, idx)), 1));
if numel(idx) < 4 || ~ismember(m, idx)
    tca = t(m);  miss = norm(rel(:, m));  speed = NaN;      % 補間できないときは標本値
    return
end
pp   = spline(t(idx), rel(:, idx));
dpp  = fnderLocal(pp);
lo   = t(max(m-1, idx(1)));  hi = t(min(m+1, idx(end)));
tca  = fminbnd(@(x) sum(ppval(pp, x).^2), lo, hi, optimset(TolX=1e-6));
miss  = norm(ppval(pp, tca));
speed = norm(ppval(dpp, tca));
end

function dpp = fnderLocal(pp)
% 区分多項式の微分 (Curve Fitting Toolbox の fnder に頼らない)
[breaks, coefs, pieces, order, dim] = unmkpp(pp);
dcoefs = coefs(:, 1:order-1) .* (order-1:-1:1);
dpp = mkpp(breaks, dcoefs, dim);
assert(pieces >= 1);
end
