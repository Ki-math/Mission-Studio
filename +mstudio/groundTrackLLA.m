function [lat, lon, alt, t] = groundTrackLLA(asset, validRange)
%GROUNDTRACKLLA  地上軌跡 (緯度・経度・高度の時刻歴) を返す
%   [lat, lon, alt, t] = mstudio.groundTrackLLA(asset)
%   [...] = mstudio.groundTrackLLA(asset, validRange) は [開始, 終了] の外側を
%   NaN にします (時刻歴インポート型ビークルのデータ範囲外を描かないため)。
%   経度が ±180° をまたぐ点には NaN を挿入し、そのまま geoplot できます。

[pos, ~, t] = states(asset, CoordinateFrame="geographic");
if nargin > 1
    pos(:, t < validRange(1) | t > validRange(2)) = NaN;
end
lat = pos(1,:);  lon = pos(2,:);  alt = pos(3,:);

wrap = find(abs(diff(lon)) > 180);
for k = numel(wrap):-1:1
    i = wrap(k);
    lat = [lat(1:i) NaN lat(i+1:end)];
    lon = [lon(1:i) NaN lon(i+1:end)];
    alt = [alt(1:i) NaN alt(i+1:end)];
    t   = [t(1:i) NaT(TimeZone=t.TimeZone) t(i+1:end)];
end
end
