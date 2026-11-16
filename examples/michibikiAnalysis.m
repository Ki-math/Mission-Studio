function out = michibikiAnalysis()
%MICHIBIKIANALYSIS  「みちびき」の可視性とカバレッジを解析する
%   out = michibikiAnalysis() は、michibikiSpec の公称軌道について、
%   現行 5 機と、7 号機を加えた 6 機の 2 構成を 24 時間解析し、結果の図と
%   集計を examples/michibiki_out に保存します。
%
%   調べること
%     1. 直下軌跡 (準天頂軌道の 8 の字と静止衛星の位置)
%     2. 各都市で同時に見える機数 (仰角 10 度以上) と、最も高い衛星の仰角
%     3. みちびきだけで測位した場合の精度劣化係数 (PDOP)
%     4. アジア・オセアニアで常に見えている最小機数の分布
%     5. 食の有無
%
%   out.Summary は都市ごとの集計 (table)、out.Spec は構成ごとのシナリオ定義。
%   GUI で見るには  app = MissionStudioApp(out.Spec{2})  とします。
%
%   See also michibikiSpec, mstudio.computeCoverage, mstudio.computeAccess

here = fileparts(mfilename("fullpath"));
addpath(fileparts(here));
outDir = fullfile(here, "michibiki_out");
if ~isfolder(outDir), mkdir(outDir); end

labels = ["5 satellites (operational)", "6 satellites (with QZS-7)"];
out.Spec = {michibikiSpec(false), michibikiSpec(true)};
out.Summary = table;
coverage = cell(1, 2);

for c = 1:2
    spec = out.Spec{c};
    [~, h] = mstudio.buildScenario(spec);
    coverage{c} = mstudio.computeCoverage(h, spec.Coverage);

    % 都市ごと: 同時可視機数と最高仰角の時刻歴
    [count, topEl, pdop, t] = visibility(h, spec.Coverage.MinEl_deg);
    for s = 1:numel(h.Stations)
        out.Summary(end+1, :) = {labels(c), h.StationNames(s), min(count(s,:)), ...
            mean(count(s,:)), max(count(s,:)), ...
            min(topEl(s,:)), 100*mean(topEl(s,:) >= 60), ...
            median(pdop(s,:), "omitnan"), max(pdop(s,:)), 100*mean(pdop(s,:) <= 6)};
    end
    if c == 2
        plotGroundTracks(h, spec, fullfile(outDir, "ground_tracks.png"));
        plotCities(h, count, topEl, pdop, t, fullfile(outDir, "cities_6sat.png"));
        eclipses = mstudio.computeEclipse(h);
        out.EclipseCount = nnz(eclipses.Type == "Eclipse");
    end
end
out.Summary.Properties.VariableNames = ["Constellation","City","MinSats","MeanSats", ...
    "MaxSats","MinTopElevation_deg","PctTopAbove60deg","MedianPDOP","MaxPDOP","PctPDOPbelow6"];
out.Coverage = coverage;

plotCoverage(coverage, labels, fullfile(outDir, "min_satellites_map.png"));
writetable(out.Summary, fullfile(outDir, "city_summary.csv"));
spec = out.Spec{2}; %#ok<NASGU>
save(fullfile(outDir, "michibiki_scenario.mat"), "spec");      % GUI の Open で読める
disp(out.Summary)
end

%% ------------------------------------------------------------------
function [count, topEl, pdop, t] = visibility(h, minEl)
% 地上局ごとの、仰角 minEl 以上の機数、最も高い衛星の仰角、PDOP (局×時刻)
for s = numel(h.Stations):-1:1
    az = [];  el = [];
    for a = 1:numel(h.Assets)
        [az(a, :), el(a, :), ~, t] = aer(h.Stations{s}, h.Assets{a}); %#ok<AGROW>
    end
    dop = mstudio.dilutionOfPrecision(az, el, minEl);
    count(s, :) = dop.NumSats;
    topEl(s, :) = max(el, [], 1);
    pdop(s, :)  = dop.PDOP;
end
end

function plotGroundTracks(h, spec, file)
fig = figure(Visible="off", Position=[100 100 900 620]);
gx = geoaxes(fig, Basemap="darkwater");  hold(gx, "on");
for k = 1:numel(h.Assets)
    [lat, lon] = mstudio.groundTrackLLA(h.Assets{k});
    lon(lon < 0) = lon(lon < 0) + 360;                  % 太平洋側を続けて描く
    if spec.Satellites.i_deg(k) > 1
        geoplot(gx, lat, lon, LineWidth=1.8, DisplayName=h.AssetNames(k));
    else
        geoscatter(gx, mean(lat, "omitnan"), mean(lon, "omitnan"), 90, "filled", "d", ...
            DisplayName=h.AssetNames(k));
    end
end
geoscatter(gx, spec.Stations.Lat_deg, spec.Stations.Lon_deg, 40, "w", "filled", "^", ...
    MarkerEdgeColor="k", DisplayName="Cities");
geolimits(gx, [-60 65], [70 215]);
legend(gx, Location="southwest", TextColor="w", Color=[0.15 0.15 0.15]);
title(gx, "Michibiki (QZSS) nominal ground tracks, 24 h");
exportgraphics(fig, file, Resolution=130);  close(fig);
end

function plotCities(h, count, topEl, pdop, t, file)
fig = figure(Visible="off", Position=[100 100 900 820]);
tl = tiledlayout(fig, 3, 1, TileSpacing="compact");
ax = nexttile(tl);
stairs(ax, t, count', LineWidth=1.3);
yline(ax, 4, "--k", "4 satellites");
ylabel(ax, "Satellites above 10 deg");  grid(ax, "on");  ylim(ax, [0 numel(h.Assets) + 0.5]);
legend(ax, h.StationNames, Location="eastoutside");
title(ax, "Visible Michibiki satellites (6-satellite constellation)");
ax = nexttile(tl);
plot(ax, t, topEl', LineWidth=1.3);
yline(ax, 60, "--k", "60 deg");
ylabel(ax, "Highest elevation [deg]");  grid(ax, "on");  ylim(ax, [0 90]);
legend(ax, h.StationNames, Location="eastoutside");
ax = nexttile(tl);
semilogy(ax, t, pdop', LineWidth=1.3);
yline(ax, 6, "--k", "PDOP 6");
ylabel(ax, "PDOP (Michibiki only)");  grid(ax, "on");
legend(ax, h.StationNames, Location="eastoutside");
exportgraphics(fig, file, Resolution=130);  close(fig);
end

function plotCoverage(coverage, labels, file)
fig = figure(Visible="off", Position=[100 100 1200 520]);
tl = tiledlayout(fig, 1, 2, TileSpacing="compact");
for c = 1:2
    C = coverage{c};
    gx = geoaxes(tl, Basemap="darkwater");  gx.Layout.Tile = c;
    geoscatter(gx, C.Lat, C.Lon, 60, C.MinSats, "filled", Marker="s", MarkerFaceAlpha=0.8);
    geolimits(gx, [-60 70], [60 215]);
    clim(gx, [0 6]);  colormap(gx, parula(7));
    cb = colorbar(gx);  cb.Label.String = "Minimum satellites above 10 deg";
    title(gx, labels(c));
end
exportgraphics(fig, file, Resolution=130);  close(fig);
end
