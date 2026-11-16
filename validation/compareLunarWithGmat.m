function r = compareLunarWithGmat()
%COMPARELUNARWITHGMAT  月遷移軌道の N体伝播を GMAT と比較する
%   r = compareLunarWithGmat() は、mstudio.designLunarTransfer が求めた
%   TLI 直後の状態を GMAT (地球・月・太陽の質点重力、DE405) で月最接近まで
%   伝播し、mstudio.propagateNBody の結果と比べます。
%
%   月の近くでは軌道が初期値に敏感なので、最接近時の差が全体の指標になります。
%
%   r のフィールド
%     MaxPosDiff_km      全区間の最大位置差
%     PeriluneDiff_km    月最接近時刻での位置差
%     MoonDistDiff_km    同時刻の月中心距離の差 (天体暦と時刻換算の確認)
%     Design             mstudio.designLunarTransfer の結果
%
%   See also mstudio.designLunarTransfer, mstudio.propagateNBody, compareWithGmat

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
work = fullfile(here, "work");
if ~isfolder(work), mkdir(work); end

epoch  = datetime(2024, 6, 1, 0, 0, 0, TimeZone="UTC");
design = mstudio.designLunarTransfer(mstudio.defaultLunarTransfer(), epoch);
tPeri  = design.TransferDays * 86400;
step   = 600;
nSteps = floor(tPeri / step);

% --- GMAT
stateFile = fullfile(work, "LunarTransfer_state.txt");
script    = fullfile(work, "LunarTransfer.script");
report = "Report RF Sat.ElapsedSecs Sat.EarthICRF.X Sat.EarthICRF.Y Sat.EarthICRF.Z Sat.Luna.RMAG;";
L = [ ...
    "Create Spacecraft Sat;"
    "Sat.DateFormat = UTCGregorian;"
    sprintf("Sat.Epoch = '%s';", string(epoch, "dd MMM yyyy HH:mm:ss.SSS", "en_US"))
    "Sat.CoordinateSystem = EarthICRF;"
    "Sat.DisplayStateType = Cartesian;"
    compose("Sat.%s = %.15g;", ["X";"Y";"Z";"VX";"VY";"VZ"], design.TLIState)
    "Create ForceModel FM;"
    "FM.CentralBody = Earth;"
    "FM.PrimaryBodies = {Earth};"
    "FM.GravityField.Earth.PotentialFile = 'EGM96.cof';"
    "FM.GravityField.Earth.Degree = 0;"
    "FM.GravityField.Earth.Order = 0;"
    "FM.GravityField.Earth.TideModel = 'None';"
    "FM.PointMasses = {Luna, Sun};"
    "FM.Drag = None;"
    "FM.SRP = Off;"
    "FM.RelativisticCorrection = Off;"
    "FM.ErrorControl = RSSStep;"
    "Create Propagator Prop;"
    "Prop.FM = FM;"
    "Prop.Type = RungeKutta89;"
    "Prop.InitialStepSize = 10;"
    "Prop.Accuracy = 1e-13;"
    "Prop.MinStep = 0.001;"
    sprintf("Prop.MaxStep = %d;", step)
    "Create ReportFile RF;"
    sprintf("RF.Filename = '%s';", stateFile)
    "RF.Precision = 16;"
    "RF.ColumnWidth = 26;"
    "RF.WriteHeaders = false;"
    "Create Variable i n;"
    "BeginMissionSequence;"
    sprintf("n = %d;", nSteps)
    report
    "For i = 1:n;"
    sprintf("   Propagate Prop(Sat) {Sat.ElapsedSecs = %d};", step)
    "   " + report
    "EndFor;"
    sprintf("Propagate Prop(Sat) {Sat.ElapsedSecs = %.9f};", tPeri - nSteps*step)
    report];
writelines(L, script);

root = getenv("GMAT_ROOT");
if isempty(root), root = "C:\Work\GMAT\GMAT_R2025a"; end
if isfile(stateFile), delete(stateFile); end
[status, log] = system(sprintf('"%s" --run "%s"', fullfile(root, "bin", "GmatConsole.exe"), script));
assert(status == 0 && isfile(stateFile), "GMAT の実行に失敗しました:\n%s", log);
gmat = readmatrix(stateFile, FileType="text");

% --- Mission Studio (同じ初期状態・同じ出力時刻)
tOut  = [(0:nSteps)' * step; tPeri];
model = mstudio.nbodyModel("Earth", epoch, [0 tPeri]);
[~, X] = mstudio.propagateNBody(design.TLIState, tOut, model);
moon  = mstudio.ephemeris("Earth", "Moon", epoch, tOut);

diff = vecnorm(X(:, 1:3) - gmat(:, 2:4), 2, 2);
r.MaxPosDiff_km   = max(diff);
r.PeriluneDiff_km = diff(end);
r.MoonDistDiff_km = abs(norm(X(end, 1:3) - moon(end, :)) - gmat(end, 5));
r.Design = design;

fprintf("TLI %.4f km/s, LOI %.4f km/s, transfer %.3f days\n", ...
    design.DeltaV_TLI, design.DeltaV_LOI, design.TransferDays);
fprintf("max position diff %.4f km, at perilune %.4f km, lunar distance diff %.4f km\n", ...
    r.MaxPosDiff_km, r.PeriluneDiff_km, r.MoonDistDiff_km);
end
