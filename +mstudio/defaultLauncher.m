function lv = defaultLauncher()
%DEFAULTLAUNCHER  既定の2段式ロケット定義 (3DoF質点モデル用) を返す
%   lv = mstudio.defaultLauncher() は mstudio.simulateAscent に渡す構造体を返します。
%   諸元は液体2段式の中型ロケットを想定した代表値です。
%
%   See also mstudio.simulateAscent

lv.Enabled      = true;
lv.Name         = "Launcher";
lv.LiftoffTime  = 0;        % シナリオ開始からのリフトオフ時刻 [s]

% 射点と飛行方位
lv.SiteLat_deg  = 30.40;
lv.SiteLon_deg  = 130.97;
lv.Azimuth_deg  = 90;       % 射点での飛行方位角 (北から東回り)

% 機体
lv.Payload_kg   = 10000;
lv.Diameter_m   = 3.7;      % 抗力の基準面積 = pi*d^2/4
lv.Cd           = 0.3;

% ステージ諸元
lv.Stages = table( ...
    ["Stage1"; "Stage2"], [395700; 92670], [25600; 4000], ...
    [8227; 934], [311; 348], [282; 100], [3; 0], ...
    VariableNames=["Name","Prop_kg","Dry_kg","ThrustVac_kN", ...
                   "IspVac_s","IspSL_s","CoastAfter_s"]);

% 誘導 (重力ターン): 垂直上昇 -> ピッチキック -> 対気速度方向に推力
lv.PitchoverAlt_m = 300;    % ピッチキック開始高度 (射点からの上昇量)
lv.KickAngle_deg  = 5.67;   % キック角 (鉛直からの傾き)
lv.KickDuration_s = 10;
lv.CutoffApogee_km = 300;   % 最終段の燃焼停止条件: 遠地点高度 (Inf = 使い切り)
end
