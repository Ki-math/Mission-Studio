function writeGmatScript(scriptFile, c, cfg)
%WRITEGMATSCRIPT  比較ケースを GMAT スクリプトとして書き出す
%   writeGmatScript(scriptFile, c, cfg)
%     c   : gmatCases の1要素
%     cfg : Epoch (datetime, UTC), DurationHours, Step_s, Stations (table),
%           StateFile, ContactFile, EclipseFile (GMAT の出力先)
%
%   Mission Studio 側と条件をそろえるため、次のように設定します。
%     座標系   ICRF 軸 (satelliteScenario の慣性系 GCRF に対応)
%     重力     EGM96、次数 = 位数
%     大気     MSISE90 (このGMAT配布物では NRLMSISE-00 が使えないため。
%              Mission Studio 側は NRLMSISE-00 なので密度に数%の差が出る)、
%              F10.7 一定、地磁気は静穏 (Kp = 1 ≒ Ap 4)
%     太陽輻射圧 球モデル。太陽定数は satelliteScenario の既定の輻射圧
%              4.5344e-6 N/m^2 (1 AU) に合わせる
%     可視・食 光行時補正・光行差補正なしの幾何学的な判定
%
%   See also compareWithGmat, gmatCases

p = c.Propagator;
L = strings(0, 1);
add = @(varargin) sprintf(varargin{:});

% --- 宇宙機
% EarthICRF は GMAT の組み込み座標系
L(end+1) = "Create Spacecraft Sat;";
L(end+1) = "Sat.DateFormat = UTCGregorian;";
L(end+1) = add("Sat.Epoch = '%s';", string(cfg.Epoch, "dd MMM yyyy HH:mm:ss.SSS", "en_US"));
L(end+1) = "Sat.CoordinateSystem = EarthICRF;";
L(end+1) = "Sat.DisplayStateType = Keplerian;";
names = ["SMA","ECC","INC","RAAN","AOP","TA"];
for k = 1:6
    L(end+1) = add("Sat.%s = %.15g;", names(k), c.Elements(k)); %#ok<AGROW>
end
L(end+1) = add("Sat.DryMass = %.15g;", p.Mass_kg);
L(end+1) = add("Sat.Cd = %.15g;", p.Cd);
L(end+1) = add("Sat.DragArea = %.15g;", p.DragArea_m2);
L(end+1) = add("Sat.Cr = %.15g;", p.Cr);
L(end+1) = add("Sat.SRPArea = %.15g;", p.SRPArea_m2);

% --- 力モデル
L(end+1) = "Create ForceModel FM;";
L(end+1) = "FM.CentralBody = Earth;";
L(end+1) = "FM.PrimaryBodies = {Earth};";
L(end+1) = "FM.GravityField.Earth.PotentialFile = 'EGM96.cof';";
L(end+1) = add("FM.GravityField.Earth.Degree = %d;", p.GravityDegree);
L(end+1) = add("FM.GravityField.Earth.Order = %d;", p.GravityDegree);
L(end+1) = "FM.GravityField.Earth.TideModel = 'None';";
L(end+1) = "FM.RelativisticCorrection = Off;";
L(end+1) = "FM.ErrorControl = RSSStep;";
if p.IncludeDrag
    L(end+1) = "FM.Drag.AtmosphereModel = MSISE90;";
    L(end+1) = "FM.Drag.HistoricWeatherSource = 'ConstantFluxAndGeoMag';";
    L(end+1) = "FM.Drag.PredictedWeatherSource = 'ConstantFluxAndGeoMag';";
    L(end+1) = add("FM.Drag.F107 = %.15g;", p.F107);
    L(end+1) = add("FM.Drag.F107A = %.15g;", p.F107);
    L(end+1) = "FM.Drag.MagneticIndex = 1;";
else
    L(end+1) = "FM.Drag = None;";
end
if p.IncludeThirdBody
    L(end+1) = "FM.PointMasses = {Sun, Luna};";
end
L(end+1) = add("FM.SRP = %s;", string(onOff(p.IncludeSRP)));
if p.IncludeSRP
    L(end+1) = add("FM.SRP.Flux = %.15g;", 4.5344e-6 * 299792458);
    L(end+1) = "FM.SRP.SRPModel = Spherical;";
end

L(end+1) = "Create Propagator Prop;";
L(end+1) = "Prop.FM = FM;";
L(end+1) = "Prop.Type = RungeKutta89;";
L(end+1) = "Prop.InitialStepSize = 10;";
L(end+1) = "Prop.Accuracy = 1e-13;";
L(end+1) = "Prop.MinStep = 0.001;";
L(end+1) = add("Prop.MaxStep = %.15g;", cfg.Step_s);

% --- 地上局と可視
gsNames = strings(1, height(cfg.Stations));
for k = 1:height(cfg.Stations)
    g = cfg.Stations(k, :);
    gsNames(k) = "GS" + k;
    L(end+1) = add("Create GroundStation %s;", gsNames(k)); %#ok<AGROW>
    L(end+1) = add("%s.CentralBody = Earth;", gsNames(k)); %#ok<AGROW>
    L(end+1) = add("%s.StateType = Spherical;", gsNames(k)); %#ok<AGROW>
    L(end+1) = add("%s.HorizonReference = Ellipsoid;", gsNames(k)); %#ok<AGROW>
    L(end+1) = add("%s.Location1 = %.15g;", gsNames(k), g.Lat_deg); %#ok<AGROW>
    L(end+1) = add("%s.Location2 = %.15g;", gsNames(k), g.Lon_deg); %#ok<AGROW>
    L(end+1) = add("%s.Location3 = 0;", gsNames(k)); %#ok<AGROW>
    L(end+1) = add("%s.MinimumElevationAngle = %.15g;", gsNames(k), g.MinEl_deg); %#ok<AGROW>
end
L(end+1) = "Create ContactLocator CL;";
L(end+1) = "CL.Target = Sat;";
L(end+1) = add("CL.Filename = '%s';", cfg.ContactFile);
L(end+1) = add("CL.Observers = {%s};", strjoin(gsNames, ", "));
L(end+1) = "CL.UseLightTimeDelay = false;";
L(end+1) = "CL.UseStellarAberration = false;";
L(end+1) = "CL.UseEntireInterval = true;";
L(end+1) = "CL.StepSize = 10;";
L(end+1) = "CL.WriteReport = true;";
L(end+1) = "CL.RunMode = Automatic;";

L(end+1) = "Create EclipseLocator EL;";
L(end+1) = "EL.Spacecraft = Sat;";
L(end+1) = add("EL.Filename = '%s';", cfg.EclipseFile);
L(end+1) = "EL.OccultingBodies = {Earth};";
L(end+1) = "EL.EclipseTypes = {'Umbra', 'Penumbra'};";
L(end+1) = "EL.UseLightTimeDelay = false;";
L(end+1) = "EL.UseStellarAberration = false;";
L(end+1) = "EL.UseEntireInterval = true;";
L(end+1) = "EL.StepSize = 2;";      % 半影の通過 (低軌道で約8 s) より短くする
L(end+1) = "EL.WriteReport = true;";
L(end+1) = "EL.RunMode = Automatic;";

% --- 出力と実行
L(end+1) = "Create ReportFile RF;";
L(end+1) = add("RF.Filename = '%s';", cfg.StateFile);
L(end+1) = "RF.Precision = 16;";
L(end+1) = "RF.ColumnWidth = 26;";
L(end+1) = "RF.WriteHeaders = false;";
L(end+1) = "Create Variable i n;";
L(end+1) = "BeginMissionSequence;";
L(end+1) = add("n = %d;", round(cfg.DurationHours*3600 / cfg.Step_s));
report = "Report RF Sat.ElapsedSecs Sat.EarthICRF.X Sat.EarthICRF.Y Sat.EarthICRF.Z;";
L(end+1) = report;
L(end+1) = "For i = 1:n;";
L(end+1) = add("   Propagate Prop(Sat) {Sat.ElapsedSecs = %.15g};", cfg.Step_s);
L(end+1) = "   " + report;
L(end+1) = "EndFor;";

writelines(L, scriptFile);
end

function s = onOff(tf)
if tf, s = "On"; else, s = "Off"; end
end
