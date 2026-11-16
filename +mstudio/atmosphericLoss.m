function loss = atmosphericLoss(frequencyGHz, lat, lon, elevation, availability_pct, antennaDiameter)
%ATMOSPHERICLOSS  地球局と衛星の間の大気による損失 (ITU-R P.618) を求める
%   loss = mstudio.atmosphericLoss(frequencyGHz, lat, lon, elevation, ...
%              availability_pct, antennaDiameter)
%   は、緯度 lat・経度 lon [deg] の地球局について、仰角 elevation [deg]
%   (ベクトル可) ごとの損失 [dB] を返します。
%
%   availability_pct は年間の稼働率 [%] です。例えば 99 なら、年間の 1% の時間
%   だけ超える損失 (= 99% の時間はこれ以下) を返します。範囲は 95〜99.999。
%   antennaDiameter [m] はシンチレーションの計算に使う地球局アンテナ径です。
%
%   loss のフィールド (いずれも elevation と同じ大きさ)
%     Gas, Cloud, Rain, Scintillation   成分ごとの損失
%     Total    合成した損失 (P.618 の合成式。単純な和ではない)
%
%   p618PropagationLosses (Satellite Communications Toolbox) を仰角 5〜90 度の
%   格子で評価し、線形補間します。P.618 は仰角 5 度未満を対象にしていないので、
%   それより低い仰角には 5 度の値を使います。
%   ITU-R のデジタルマップが必要です (data/ITURDigitalMaps。README 参照)。
%
%   See also p618PropagationLosses, p618Config, mstudio.computeLinkBudget

arguments
    frequencyGHz     (1,1) double {mustBePositive}
    lat              (1,1) double
    lon              (1,1) double
    elevation        double
    availability_pct (1,1) double {mustBeInRange(availability_pct, 95, 99.999)}
    antennaDiameter  (1,1) double {mustBePositive}
end
assert(mstudio.hasItuMaps(), "mstudio:link:noItuMaps", ...
    "ITU-R のデジタルマップが見つかりません。data/ITURDigitalMaps に展開してください。");

cfg = p618Config;
cfg.Frequency = frequencyGHz * 1e9;
cfg.Latitude  = lat;
cfg.Longitude = lon;
cfg.AntennaDiameter = antennaDiameter;
exceedance = 100 - availability_pct;
for name = ["Gas","Cloud","Rain","Scintillation","Total"]
    cfg.(name + "AnnualExceedance") = exceedance;
end

grid  = [5:1:20, 22.5:2.5:90];
table = zeros(5, numel(grid));
for k = 1:numel(grid)
    cfg.ElevationAngle = grid(k);
    pl = p618PropagationLosses(cfg);
    table(:, k) = [pl.Ag; pl.Ac; pl.Ar; pl.As; pl.At];
end

el = min(max(elevation, grid(1)), grid(end));
names = ["Gas","Cloud","Rain","Scintillation","Total"];
for k = 1:5
    loss.(names(k)) = reshape(interp1(grid, table(k, :), el(:)), size(elevation));
end
end
