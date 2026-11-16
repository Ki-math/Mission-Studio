function smokeTest()
%SMOKETEST  Mission Studio の起動と主要機能の動作確認
%   正常終了すると "SMOKE_OK" を表示します。

addpath(fileparts(fileparts(mfilename("fullpath"))));

% --- 上昇計算 (GUIなし): 既定ロケットは約 200 x 300 km の軌道に入る
r = mstudio.simulateAscent(mstudio.defaultLauncher(), 3600);
assert(r.Reached == "orbit", "既定ロケットが軌道に到達していません");
assert(abs(r.Orbit.ApogeeAlt_km - 300) < 1 && r.Orbit.PerigeeAlt_km > 150);
assert(all(diff(r.Telemetry.Mass_kg) <= 0), "質量が増加しています");

% --- GUI
spec = mstudio.defaultSpec();
spec.DurationHours = 2;
app = MissionStudioApp(spec);
assertAnalysisOK(app);
assert(ismember("Launcher", app.Objects.AssetNames));
assert(height(app.AccessTable) > 0, "可視区間が計算されていません");
assert(any(app.EclipseTable.Type == "Umbra"), "食が計算されていません");

% --- 伝播方式: 数値積分 (既定) と二体問題では軌道が変わる
p1 = states(app.Objects.Assets{1});
spec.Propagator.Method = "two-body-keplerian";
[~, h2] = mstudio.buildScenario(spec, struct(Launch=app.Objects.Launch));
p2 = states(h2.Assets{1});
assert(max(vecnorm(p1 - p2)) > 1e3, "伝播方式の切り替えが反映されていません");

% --- カバレッジと接近解析
cov = mstudio.defaultCoverage();  cov.GridStep_deg = 15;
C = mstudio.computeCoverage(app.Objects, cov);
assert(abs(sum(C.Weight) - 1) < 1e-12 && all(C.PercentTime >= 0 & C.PercentTime <= 100));
% 静止衛星 1 機だけで地表の約 34% (最小仰角 10 度) が常に見える
assert(C.Summary.MeanAreaCovered_pct > 34 && C.Summary.AreaEverCovered_pct <= 100 + 1e-9, ...
    "カバレッジの面積率が静止衛星の可視範囲より小さくなっています");
[CA, range] = mstudio.computeCloseApproaches(app.Objects);
assert(size(range.Distance_km, 1) == nchoosek(numel(app.Objects.Assets), 2));
assert(all(CA.MissDistance_km > 0) && issorted(CA.MissDistance_km));
assert(istable(app.CloseApproaches), "GUI で接近解析が実行されていません");

% --- DOP: 天頂 1 機 + 水平 3 機 (120 度間隔) の解析解
%     PDOP = sqrt(8/3), HDOP = VDOP = sqrt(4/3), GDOP = sqrt(3)
d = mstudio.dilutionOfPrecision([0; 0; 120; 240], [90; 0; 0; 0]);
assert(abs(d.PDOP - sqrt(8/3)) < 1e-12 && abs(d.GDOP - sqrt(3)) < 1e-12 ...
    && abs(d.HDOP - sqrt(4/3)) < 1e-12 && abs(d.VDOP - sqrt(4/3)) < 1e-12, "DOP が解析解と合いません");
assert(isnan(mstudio.dilutionOfPrecision([0; 90; 180], [30; 40; 50]).PDOP), "3 機では解けないはずです");

% --- カバレッジの PDOP は、同じ場所の地上局で求めた PDOP と一致する
navSpec = spec;  navSpec.Launcher.Enabled = false;  navSpec.Propagator.Method = "two-body-keplerian";
nSat = 10;                                  % 中高度 (GPS 相当) の衛星を散らして置く
navSpec.Satellites = navSpec.Satellites(ones(nSat, 1), :);
navSpec.Satellites.Name = "S" + (1:nSat)';
navSpec.Satellites.a_km(:) = 26560;  navSpec.Satellites.e(:) = 0;  navSpec.Satellites.i_deg(:) = 55;
navSpec.Satellites.RAAN_deg = (0:nSat-1)' * 36;
navSpec.Satellites.Nu_deg   = mod((0:nSat-1)' * 97, 360);
navSpec.Stations = navSpec.Stations(1, :);
navSpec.Stations.Lat_deg = 35;  navSpec.Stations.Lon_deg = 135;  navSpec.Stations.MinEl_deg = 10;
[~, hN] = mstudio.buildScenario(navSpec);
covN = mstudio.defaultCoverage();  covN.GridStep_deg = 10;  covN.ComputeDOP = true;
CN = mstudio.computeCoverage(hN, covN);
azN = [];  elN = [];
for kN = 1:nSat, [azN(kN,:), elN(kN,:)] = aer(hN.Stations{1}, hN.Assets{kN}); end %#ok<AGROW>
dN = mstudio.dilutionOfPrecision(azN, elN, 10);
pN = CN.PDOP(CN.Lat == 35 & CN.Lon == 135, :);
both = ~isnan(pN) & ~isnan(dN.PDOP);
% 可視の境目の時刻では使う衛星が 1 機ずれることがあるので、大半の時刻で合うことを見る
agree = abs(pN(both) - dN.PDOP(both)) ./ dN.PDOP(both) < 1e-3;
assert(nnz(both) > 20 && mean(agree) > 0.97, "カバレッジの PDOP が地上局の PDOP と合いません");

% --- 月遷移: 設計が収束し、探査機がシナリオに載る
lunar = mstudio.defaultLunarTransfer();  lunar.Enabled = true;
specL = spec;  specL.LunarTransfer = lunar;  specL.Propagator.Method = "two-body-keplerian";
[~, hL] = mstudio.buildScenario(specL, struct(Launch=app.Objects.Launch));
assert(hL.LunarTransfer.Converged, "月遷移のターゲティングが収束していません");
assert(abs(hL.LunarTransfer.PeriluneAlt_km - lunar.PeriluneAlt_km) < 1);
assert(ismember("LunarProbe", hL.AssetNames));
assert(~isempty(hL.Moon), "月が掩蔽判定用にシナリオへ載っていません");

% --- 月遷移 (有限燃焼): 月周回軌道が目標高度の円軌道になる
lunar.BurnModel = "finite";
rF = mstudio.designLunarTransfer(lunar, spec.StartTime);
assert(rF.Converged && all(abs(rF.LunarOrbitAlt_km - lunar.PeriluneAlt_km) < 1), ...
    "有限燃焼の月周回投入が目標の円軌道になっていません");
assert(rF.DeltaV_TLI > hL.LunarTransfer.DeltaV_TLI, "有限燃焼の TLI に重力損失が出ていません");

% --- TLE (ツールボックス同梱のサンプル)
nBefore = numel(app.Objects.Assets);
app.addTLE(which("threeSatelliteConstellation.tle"));
assertAnalysisOK(app);
assert(numel(app.Objects.Assets) == nBefore + 3, "TLEの衛星が追加されていません");

% --- 保存/読込
file = [tempname '.mat'];
app.saveSpec(file);  app.loadSpec(file);  delete(file);
assertAnalysisOK(app);
drawnow
disp("SMOKE_OK")
end

function assertAnalysisOK(app)
labels = string({findobj(app.Fig, "Type", "uilabel").Text});
assert(any(startsWith(labels, "解析完了")), ...
    "解析がエラー終了: " + strjoin(labels(startsWith(labels, "エラー"))));
end
