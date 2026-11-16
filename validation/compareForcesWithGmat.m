function results = compareForcesWithGmat()
%COMPAREFORCESWITHGMAT  N体伝播の追加の力 (有限燃焼・輻射圧・月重力場) を GMAT と比較する
%   results = compareForcesWithGmat() は、力を1つずつ有効にした3ケースを
%   mstudio.propagateNBody と GMAT の両方で伝播し、位置差をまとめた table を
%   返します。
%
%   ケース
%     Finite burn  : 地球待機軌道から 60 kN・Isp 450 s で 500 s 燃焼し、2日間慣性飛行
%     SRP          : 月遷移軌道を 3 日間。Cr×面積 15 m^2、質量 2000 kg
%     Lunar gravity: 高度 100 km の月極軌道を 6 時間。LP165P 20×20
%
%   results の列
%     Case         ケース名
%     MaxDiff_km   GMAT との最大位置差
%     Effect_km    その力を外したときとの最大位置差 (力の効果の大きさ)
%   MaxDiff_km が Effect_km より十分小さければ、その力の実装が合っています。
%
%   See also compareLunarWithGmat, mstudio.propagateNBody, mstudio.nbodyModel

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
work = fullfile(here, "work");
if ~isfolder(work), mkdir(work); end

epoch = datetime(2024, 6, 1, 0, 0, 0, TimeZone="UTC");
results = table;

% --- 1. 有限燃焼 (地球中心)
muEarth = 398600.4415;  r0 = 6378.137 + 200;
c.Name = "Finite burn";  c.Center = "Earth";
c.State = [r0; 0; 0; 0; sqrt(muEarth/r0)*cosd(30); sqrt(muEarth/r0)*sind(30)];
c.Mass = 15000;  c.Burn = struct(Force_N=60e3, Isp_s=450, Duration=500);
c.CoastTimes = (0:600:2*86400)';
c.ModelArgs = {};  c.GmatForces = "";
results = [results; runCase(c, epoch, work)];

% --- 2. 太陽輻射圧 (地球中心、月遷移軌道)
c.Name = "SRP";
c.State = [r0; 0; 0; 0; (sqrt(muEarth/r0) + 3.13)*cosd(30); (sqrt(muEarth/r0) + 3.13)*sind(30)];
c.Mass = 2000;  c.Burn = [];
c.CoastTimes = (0:600:3*86400)';
c.ModelArgs = {"ReflectivityArea_m2", 15, "Mass_kg", 2000};
c.GmatForces = ["FM.SRP = On;"; "FM.SRP.Flux = 1367;"; "FM.SRP.SRPModel = Spherical;"; ...
    "FM.SRP.Nominal_Sun = 149597870.691;"; "Sat.Cr = 1.5;"; "Sat.SRPArea = 10;"];
results = [results; runCase(c, epoch, work)];

% --- 3. 月の重力場 (月中心)
muMoon = 4902.8005821478;  rm = 1737.4 + 100;
c.Name = "Lunar gravity";  c.Center = "Moon";
c.State = [rm; 0; 0; 0; 0; sqrt(muMoon/rm)];
c.CoastTimes = (0:60:6*3600)';
c.ModelArgs = {"MoonGravityDegree", 20};
c.GmatForces = ["FM.GravityField.Luna.PotentialFile = 'LP165P.cof';"; ...
    "FM.GravityField.Luna.Degree = 20;"; "FM.GravityField.Luna.Order = 20;"; ...
    "FM.GravityField.Luna.TideModel = 'None';"];
results = [results; runCase(c, epoch, work)];

disp(results)
end

function row = runCase(c, epoch, work)
% 1ケースを両ツールで計算して比較する
tag    = matlab.lang.makeValidName(c.Name);
[gmat] = runGmatCase(c, epoch, work, tag);

withForce    = propagate(c, epoch, c.ModelArgs, true);
withoutForce = propagate(c, epoch, {}, false);
row = table(string(c.Name), max(vecnorm(withForce - gmat, 2, 2)), ...
    max(vecnorm(withForce - withoutForce, 2, 2)), ...
    VariableNames=["Case","MaxDiff_km","Effect_km"]);
fprintf("%-14s diff %.5f km, effect %.3f km\n", c.Name, row.MaxDiff_km, row.Effect_km);
end

function pos = propagate(c, epoch, modelArgs, useBurn)
% Mission Studio 側。出力は慣性飛行区間の位置 (燃焼があれば燃焼終了を t = 0 とする)
tEnd  = c.CoastTimes(end) + 1000;
model = mstudio.nbodyModel(c.Center, epoch, [0 tEnd], modelArgs{:});
x = [c.State; c.Mass];
t0 = 0;
if ~isempty(c.Burn) && useBurn
    thrust = struct(Force_N=c.Burn.Force_N, Isp_s=c.Burn.Isp_s, Direction="velocity");
    [~, Xb] = mstudio.propagateNBody(x, [0 c.Burn.Duration/2 c.Burn.Duration], model, [], thrust);
    x = Xb(end, :)';  t0 = c.Burn.Duration;
elseif ~isempty(c.Burn)
    t0 = c.Burn.Duration;                    % 燃焼なしで同じ時刻系にそろえる
    [~, Xb] = mstudio.propagateNBody(x, [0 t0/2 t0], model);
    x = Xb(end, :)';
end
[~, X] = mstudio.propagateNBody(x, t0 + c.CoastTimes, model);
pos = X(:, 1:3);
end

function pos = runGmatCase(c, epoch, work, tag)
% GMAT 側。同じ初期状態・力モデルのスクリプトを書いて実行する
stateFile = fullfile(work, tag + "_state.txt");
script    = fullfile(work, tag + ".script");
isMoon    = c.Center == "Moon";
frame     = "EarthICRF";  body = "Earth";  others = "{Luna, Sun}";
if isMoon, frame = "LunaICRF";  body = "Luna";  others = "{Earth, Sun}"; end
report = sprintf("Report RF Sat.ElapsedSecs Sat.%1$s.X Sat.%1$s.Y Sat.%1$s.Z;", frame);
step   = c.CoastTimes(2) - c.CoastTimes(1);

L = strings(0, 1);
if isMoon
    L = [L; "Create CoordinateSystem LunaICRF;"; "LunaICRF.Origin = Luna;"; "LunaICRF.Axes = ICRF;"];
end
L = [L
    "Create Spacecraft Sat;"
    "Sat.DateFormat = UTCGregorian;"
    sprintf("Sat.Epoch = '%s';", string(epoch, "dd MMM yyyy HH:mm:ss.SSS", "en_US"))
    "Sat.CoordinateSystem = " + frame + ";"
    "Sat.DisplayStateType = Cartesian;"
    compose("Sat.%s = %.15g;", ["X";"Y";"Z";"VX";"VY";"VZ"], c.State)];
if isempty(c.Burn)
    L = [L; sprintf("Sat.DryMass = %.15g;", c.Mass)];
else
    fuel = 0.8 * c.Mass;
    L = [L
        sprintf("Sat.DryMass = %.15g;", c.Mass - fuel)
        "Create ChemicalTank Tank;"
        sprintf("Tank.FuelMass = %.15g;", fuel)
        "Tank.Volume = 100;"
        "Create ChemicalThruster Thr;"
        "Thr.CoordinateSystem = Local;"
        "Thr.Origin = Earth;"
        "Thr.Axes = VNB;"
        "Thr.ThrustDirection1 = 1;"
        "Thr.ThrustDirection2 = 0;"
        "Thr.ThrustDirection3 = 0;"
        "Thr.DecrementMass = true;"
        "Thr.Tank = {Tank};"
        "Thr.GravitationalAccel = 9.80665;"
        sprintf("Thr.C1 = %.15g;", c.Burn.Force_N)
        sprintf("Thr.K1 = %.15g;", c.Burn.Isp_s)
        "Sat.Tanks = {Tank};"
        "Sat.Thrusters = {Thr};"
        "Create FiniteBurn FB;"
        "FB.Thrusters = {Thr};"];
end
L = [L
    "Create ForceModel FM;"
    "FM.CentralBody = " + body + ";"
    "FM.PrimaryBodies = {" + body + "};"
    "FM.PointMasses = " + others + ";"
    "FM.Drag = None;"
    "FM.SRP = Off;"
    "FM.RelativisticCorrection = Off;"
    "FM.ErrorControl = RSSStep;"];
if ~isMoon
    L = [L; "FM.GravityField.Earth.PotentialFile = 'EGM96.cof';"; ...
        "FM.GravityField.Earth.Degree = 0;"; "FM.GravityField.Earth.Order = 0;"; ...
        "FM.GravityField.Earth.TideModel = 'None';"];
end
L = [L
    c.GmatForces(c.GmatForces ~= "")
    "Create Propagator Prop;"
    "Prop.FM = FM;"
    "Prop.Type = RungeKutta89;"
    "Prop.InitialStepSize = 5;"
    "Prop.Accuracy = 1e-13;"
    "Prop.MinStep = 0.001;"
    sprintf("Prop.MaxStep = %d;", step)
    "Create ReportFile RF;"
    sprintf("RF.Filename = '%s';", stateFile)
    "RF.Precision = 16;"
    "RF.ColumnWidth = 26;"
    "RF.WriteHeaders = false;"
    "Create Variable i n;"
    "BeginMissionSequence;"];
if ~isempty(c.Burn)
    L = [L
        "BeginFiniteBurn FB(Sat);"
        sprintf("Propagate Prop(Sat) {Sat.ElapsedSecs = %.15g};", c.Burn.Duration)
        "EndFiniteBurn FB(Sat);"];
end
L = [L
    sprintf("n = %d;", numel(c.CoastTimes) - 1)
    report
    "For i = 1:n;"
    sprintf("   Propagate Prop(Sat) {Sat.ElapsedSecs = %d};", step)
    "   " + report
    "EndFor;"];
writelines(L, script);

root = getenv("GMAT_ROOT");
if isempty(root), root = "C:\Work\GMAT\GMAT_R2025a"; end
if isfile(stateFile), delete(stateFile); end
[status, log] = system(sprintf('"%s" --run "%s"', fullfile(root, "bin", "GmatConsole.exe"), script));
assert(status == 0 && isfile(stateFile), "GMAT の実行に失敗しました (%s):\n%s", c.Name, log);
data = readmatrix(stateFile, FileType="text");
pos  = data(:, 2:4);
end
