function r = compareOccultationWithGmat()
%COMPAREOCCULTATIONWITHGMAT  月による掩蔽を含む可視区間を GMAT と比較する
%   r = compareOccultationWithGmat() は、月周回軌道 (高度 100 km の極軌道、
%   3 周回) の探査機と臼田局との可視区間を、Mission Studio と GMAT
%   (ContactLocator、OccultingBodies = Luna) で求めて比べます。
%   探査機が月の裏側に入るたびに可視が途切れるので、その時刻が合うかを見ます。
%
%   r のフィールド
%     Counts        区間数 (Mission Studio / GMAT)
%     MaxDiff_s     対応する開始・終了時刻の最大差 [s]
%     MissionStudio, Gmat   比較に使った区間 (StartTime, EndTime)
%
%   See also mstudio.computeAccess, compareLunarWithGmat

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
work = fullfile(here, "work");
if ~isfolder(work), mkdir(work); end

% --- Mission Studio: 月遷移を含むシナリオを作り、月周回中の可視を取り出す
spec = mstudio.defaultSpec();
spec.StartTime     = datetime(2024, 6, 1, 0, 0, 0, TimeZone="UTC");
spec.DurationHours = 120;
spec.SampleTime    = 30;
spec.Satellites    = spec.Satellites([], :);
spec.Stations      = table("Usuda", 36.13, 138.36, 5, ...
    VariableNames=["Name","Lat_deg","Lon_deg","MinEl_deg"]);
spec.Launcher.Enabled      = false;
spec.LunarTransfer.Enabled = true;
[~, h] = mstudio.buildScenario(spec);
design = h.LunarTransfer;
access = mstudio.computeAccess(h);

orbitStart = spec.StartTime + seconds(design.LOITime);
orbitEnd   = spec.StartTime + seconds(design.Time(end));
ms = access(access.EndTime > orbitStart & access.StartTime < orbitEnd, ["StartTime","EndTime"]);

% --- GMAT: LOI 完了時の状態から同じ力モデルで月周回を伝播し、可視を求める
contactFile = fullfile(work, "Occultation_contact.txt");
script      = fullfile(work, "Occultation.script");
duration    = seconds(orbitEnd - orbitStart);
L = [ ...
    "Create CoordinateSystem LunaICRF;"
    "LunaICRF.Origin = Luna;"
    "LunaICRF.Axes = ICRF;"
    "Create Spacecraft Sat;"
    "Sat.DateFormat = UTCGregorian;"
    sprintf("Sat.Epoch = '%s';", string(orbitStart, "dd MMM yyyy HH:mm:ss.SSS", "en_US"))
    "Sat.CoordinateSystem = LunaICRF;"
    "Sat.DisplayStateType = Cartesian;"
    compose("Sat.%s = %.15g;", ["X";"Y";"Z";"VX";"VY";"VZ"], design.LOIState)
    "Create ForceModel FM;"
    "FM.CentralBody = Luna;"
    "FM.PrimaryBodies = {Luna};"
    "FM.GravityField.Luna.Degree = 0;"       % 月は質点 (既定は 4 次の重力場になる)
    "FM.GravityField.Luna.Order = 0;"
    "FM.PointMasses = {Earth, Sun};"
    "FM.Drag = None;"
    "FM.SRP = Off;"
    "FM.RelativisticCorrection = Off;"
    "FM.ErrorControl = RSSStep;"
    "Create Propagator Prop;"
    "Prop.FM = FM;"
    "Prop.Type = RungeKutta89;"
    "Prop.InitialStepSize = 5;"
    "Prop.Accuracy = 1e-13;"
    "Prop.MinStep = 0.001;"
    "Prop.MaxStep = 30;"
    "Create GroundStation GS1;"
    "GS1.CentralBody = Earth;"
    "GS1.StateType = Spherical;"
    "GS1.HorizonReference = Ellipsoid;"
    sprintf("GS1.Location1 = %.15g;", spec.Stations.Lat_deg)
    sprintf("GS1.Location2 = %.15g;", spec.Stations.Lon_deg)
    "GS1.Location3 = 0;"
    sprintf("GS1.MinimumElevationAngle = %.15g;", spec.Stations.MinEl_deg)
    "Create ContactLocator CL;"
    "CL.Target = Sat;"
    sprintf("CL.Filename = '%s';", contactFile)
    "CL.Observers = {GS1};"
    "CL.OccultingBodies = {Luna};"
    "CL.UseLightTimeDelay = false;"
    "CL.UseStellarAberration = false;"
    "CL.UseEntireInterval = true;"
    "CL.StepSize = 10;"
    "CL.WriteReport = true;"
    "CL.RunMode = Automatic;"
    "BeginMissionSequence;"
    sprintf("Propagate Prop(Sat) {Sat.ElapsedSecs = %.6f};", duration)];
writelines(L, script);

root = getenv("GMAT_ROOT");
if isempty(root), root = "C:\Work\GMAT\GMAT_R2025a"; end
if isfile(contactFile), delete(contactFile); end
[status, log] = system(sprintf('"%s" --run "%s"', fullfile(root, "bin", "GmatConsole.exe"), script));
assert(status == 0 && isfile(contactFile), "GMAT の実行に失敗しました:\n%s", log);

pattern = "\d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2}\.\d{3}";
tok = regexp(fileread(contactFile), "(" + pattern + ")\s+(" + pattern + ")", "tokens");
tok = vertcat(tok{:});
toTime = @(c) datetime(c, InputFormat="dd MMM yyyy HH:mm:ss.SSS", Locale="en_US", TimeZone="UTC");
gm = table(toTime(tok(:, 1)), toTime(tok(:, 2)), VariableNames=["StartTime","EndTime"]);

% --- 比較 (解析区間の端で切れた時刻は除き、最も近い時刻同士を比べる)
margin = seconds(60);
inner  = @(t) t(t > orbitStart + margin & t < orbitEnd - margin);
msEdges = [inner(ms.StartTime); inner(ms.EndTime)];
gmEdges = [inner(gm.StartTime); inner(gm.EndTime)];
diffs = arrayfun(@(t) min(abs(seconds(t - gmEdges))), msEdges);

r.Counts    = sprintf("%d / %d", height(ms), height(gm));
r.MaxDiff_s = max(diffs);
r.MissionStudio = ms;
r.Gmat = gm;
fprintf("intervals %s, edges compared %d / %d, max difference %.3f s\n", ...
    r.Counts, numel(msEdges), numel(gmEdges), r.MaxDiff_s);
end
