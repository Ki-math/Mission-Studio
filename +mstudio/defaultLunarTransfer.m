function p = defaultLunarTransfer()
%DEFAULTLUNARTRANSFER  既定の月遷移ミッション定義を返す
%   p = mstudio.defaultLunarTransfer() は mstudio.designLunarTransfer に渡す
%   構造体を返します (spec.LunarTransfer)。
%
%   See also mstudio.designLunarTransfer

p.Enabled        = false;
p.Name           = "LunarProbe";
p.TLITime        = 0;       % シナリオ開始から月遷移投入 (TLI) までの時間 [s]

% 軌道の目標
p.ParkingAlt_km  = 200;     % 地球待機軌道 (円軌道) の高度
p.ParkingInc_deg = 30.4;    % 待機軌道の傾斜角 (ICRF 赤道面基準)
p.PeriluneAlt_km = 100;     % 月最接近高度 = 月周回軌道の高度
p.LunarInc_deg   = 90;      % 月周回軌道の傾斜角 (月中心 ICRF 軸基準)
p.LunarOrbits    = 3;       % 月周回投入後に伝播する周回数

% 増速のモデル
p.BurnModel      = "impulsive";   % "impulsive" (瞬時) | "finite" (有限燃焼)
p.Mass_kg        = 15000;   % TLI 開始時の全質量 (上段 + 探査機)
p.Thrust_kN      = 60;      % TLI の推力
p.Isp_s          = 450;     % TLI の比推力
p.ProbeMass_kg   = 2000;    % TLI 後に分離した探査機の質量 (LOI 開始時)
p.LOIThrust_N    = 2000;    % LOI の推力
p.LOIIsp_s       = 320;     % LOI の比推力

% 追加の力
p.IncludeSRP        = false;  % 太陽輻射圧 (質量は ProbeMass_kg を使用)
p.SRPArea_m2        = 10;
p.Cr                = 1.5;
p.MoonGravityDegree = 0;      % 月周回中の月重力場 LP165P の次数 (0 = 質点)
end
