function [tStart, tEnd] = findIntervals(t, margin)
%FINDINTERVALS  時刻歴から margin >= 0 となる区間を求める
%   [tStart, tEnd] = mstudio.findIntervals(t, margin) は、サンプル時刻 t
%   (単調増加の数値ベクトル) と条件の余裕 margin から、margin >= 0 の区間の
%   開始・終了時刻を返します。区間の両端はサンプル間の零点を補間して求める
%   ため、サンプル刻みより細かい精度になります (前後4点で3次補間、端では線形)。
%
%   margin の NaN は「条件不成立」として扱い、NaN との境界ではデータのある側の
%   サンプル時刻を端とします。区間がデータの先頭・末尾にかかる場合は、
%   その時刻で打ち切ります。
%
%   可視 (仰角 - 最小仰角) と食 (影の境界からの角度) の両方で使います。
%
%   See also mstudio.computeAccess, mstudio.computeEclipse

t = reshape(t, 1, []);  margin = reshape(margin, 1, []);
inside = margin >= 0;
edges  = diff([false, inside, false]);
iStart = find(edges == 1);          % 条件成立の最初のサンプル
iEnd   = find(edges == -1) - 1;     % 条件成立の最後のサンプル

tStart = t(iStart);  tEnd = t(iEnd);
for k = 1:numel(iStart)
    if iStart(k) > 1
        tStart(k) = crossing(t, margin, iStart(k) - 1);
    end
    if iEnd(k) < numel(t)
        tEnd(k) = crossing(t, margin, iEnd(k));
    end
end
end

function tc = crossing(t, f, k)
% サンプル k と k+1 の間にある f の零点
if isnan(f(k)) || isnan(f(k+1))
    tc = t(k + isnan(f(k)));
    return
end
idx = max(k-1, 1):min(k+2, numel(t));
if numel(idx) == 4 && ~any(isnan(f(idx)))
    tc = fzero(@(x) interp1(t(idx), f(idx), x, "spline"), t([k k+1]));
else
    tc = t(k) - f(k) * (t(k+1) - t(k)) / (f(k+1) - f(k));
end
end
