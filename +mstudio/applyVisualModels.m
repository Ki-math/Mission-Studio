function applyVisualModels(h, apparentLength_km)
%APPLYVISUALMODELS  ビューアに表示する3Dモデルを各ビークルに設定する
%   mstudio.applyVisualModels(h) は、衛星に小型衛星モデル (SmallSat.glb)、
%   飛行経路ビークルとロケットに簡易ロケット形状を実寸で割り当てます。
%   h は mstudio.buildScenario の出力です。
%   mstudio.applyVisualModels(h, apparentLength_km) は、モデルの見かけの長さが
%   指定値 [km] になるよう拡大します。実寸では地球に対して小さすぎるため、
%   全体を眺めるときは数百 km にすると形が見えます。0 は実寸です。
%
%   See also mstudio.rocketModelFile, satelliteScenarioViewer

arguments
    h                 (1,1) struct
    apparentLength_km (1,1) double {mustBeNonnegative} = 0
end

% モデルごとの実寸の長さ [m]
models = struct( ...
    satellite  = struct(File="SmallSat.glb",            Length=11.4), ...
    trajectory = struct(File=mstudio.rocketModelFile(), Length=60));

for k = 1:numel(h.Assets)
    m = models.(h.AssetKinds(k));
    h.Assets{k}.Visual3DModel = m.File;
    if apparentLength_km > 0
        h.Assets{k}.Visual3DModelScale = apparentLength_km*1e3 / m.Length;
    else
        h.Assets{k}.Visual3DModelScale = 1;
    end
end
end
