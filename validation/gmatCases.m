function cases = gmatCases()
%GMATCASES  GMAT との比較検証ケースを返す
%   cases = gmatCases() は構造体配列を返します。各ケースは同じ初期軌道を
%   Mission Studio と GMAT の両方で伝播し、位置差と可視区間の差を調べます。
%
%   エポックは両ツールの地球姿勢パラメータ (EOP) が実測値でそろう
%   2024-06-01 とし、24時間伝播します。
%
%   フィールド
%     Name        ケース名
%     Elements    [a_km e i RAAN ArgP Nu] (ICRF、接触軌道要素)
%     Propagator  mstudio.defaultPropagator 形式の伝播設定
%     PosTol_m    位置差の許容値 [m]
%
%   See also compareWithGmat

leo = [6793 0.0005 51.6 30 0 0];
sso = [6978 0.001 97.8 120 0 45];
geo = [42164 0.0002 0.05 0 0 193];

base = mstudio.defaultPropagator();
base.IncludeDrag = false;  base.IncludeThirdBody = false;  base.IncludeSRP = false;

pointMass = base;  pointMass.GravityDegree = 0;
gravity20 = base;  gravity20.GravityDegree = 20;
drag      = gravity20;  drag.IncludeDrag = true;
sunMoon   = gravity20;  sunMoon.IncludeThirdBody = true;
full      = sunMoon;    full.IncludeSRP = true;

cases = [ ...
    struct(Name="LEO point mass",      Elements=leo, Propagator=pointMass, PosTol_m=5)
    struct(Name="LEO EGM96 20x20",     Elements=leo, Propagator=gravity20, PosTol_m=5)
    struct(Name="SSO EGM96 20x20",     Elements=sso, Propagator=gravity20, PosTol_m=5)
    struct(Name="GEO EGM96 20x20",     Elements=geo, Propagator=gravity20, PosTol_m=5)
    struct(Name="LEO EGM96 + drag",    Elements=leo, Propagator=drag,      PosTol_m=500)
    struct(Name="LEO + Sun/Moon",      Elements=leo, Propagator=sunMoon,   PosTol_m=5)
    struct(Name="GEO + Sun/Moon",      Elements=geo, Propagator=sunMoon,   PosTol_m=5)
    struct(Name="GEO + Sun/Moon + SRP", Elements=geo, Propagator=full,     PosTol_m=5)
    struct(Name="SSO + Sun/Moon + SRP", Elements=sso, Propagator=full,     PosTol_m=5)];
end
