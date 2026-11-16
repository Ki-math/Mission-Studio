function p = defaultPropagator()
%DEFAULTPROPAGATOR  既定の軌道伝播設定を返す
%   p = mstudio.defaultPropagator() は spec.Propagator に入れる構造体を返します。
%   ケプラー要素で定義した衛星に適用されます (TLE の衛星は常に SGP4/SDP4)。
%
%   p.Method
%     "numerical"          数値積分 (下記の力モデル)。要素は接触軌道要素として扱う
%     "two-body-keplerian" 二体問題の解析解
%     "sgp4"               SGP4/SDP4 (要素を平均要素として扱う点に注意)
%
%   数値積分の力モデル
%     GravityDegree  地球重力場 EGM96 の次数 (0 = 質点、2 以上 = 球面調和)
%     IncludeDrag    大気抵抗 (NRLMSISE-00)。F107 は太陽電波フラックス
%     IncludeThirdBody / IncludeSRP
%                    月・太陽の引力 / 太陽輻射圧。Aerospace Toolbox の
%                    エフェメリスデータ (aeroDataPackage) が必要
%     Mass_kg, DragArea_m2, Cd, SRPArea_m2, Cr  衛星の物理特性 (全衛星共通)
%
%   See also mstudio.buildScenario, numericalPropagator, physicalProperties

p.Method           = "numerical";
p.GravityDegree    = 20;
p.IncludeDrag      = true;
p.F107             = 150;
p.IncludeThirdBody = false;
p.IncludeSRP       = false;
p.Mass_kg          = 500;
p.DragArea_m2      = 2;
p.Cd               = 2.2;
p.SRPArea_m2       = 2;
p.Cr               = 1.8;
end
