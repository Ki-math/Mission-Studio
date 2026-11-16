function r = computeCoverage(h, c)
%COMPUTECOVERAGE  地表の格子点に対する衛星群のカバレッジを求める
%   r = mstudio.computeCoverage(h, c) は、c (mstudio.defaultCoverage 形式) で
%   指定した緯度・経度の格子点それぞれについて、シナリオ内の衛星
%   (ケプラー要素と TLE の衛星) が最小仰角以上で見える時間を調べます。
%   h は mstudio.buildScenario の出力です。
%
%   格子点は等間隔の緯度・経度セルの中心 (高度 0) です。領域全体の集計には
%   セルの面積 (cos 緯度) を重みに使います。判定はシナリオの刻みごとで、
%   時刻の補間はしません (刻みより短い通過は数え落とすことがあります)。
%
%   r のフィールド
%     Lat, Lon        格子点の緯度・経度 [deg] (Ng×1)
%     Weight          面積の重み (合計 1)
%     Time            サンプル時刻 (1×Nt)
%     PercentTime     見えている時間の割合 [%]
%     NumAccess       通過回数
%     MaxGap_s        最大の空白時間 (再訪時間) [s]。一度も見えない点は Inf
%     MeanGap_s       空白時間の平均 [s]
%     MeanSats        同時に見える衛星数の平均
%     MaxSats         同時に見える衛星数の最大
%     MinSats         同時に見える衛星数の最小 (測位では 4 機以上が目安)
%     AreaCovered     各時刻に領域のうち見えている面積の割合 [%] (1×Nt)
%     PDOP            c.ComputeDOP が true のとき。位置精度劣化係数 (Ng×Nt)。
%                     4 機未満、または配置が悪く 1000 を超える時刻は NaN
%     MedianPDOP      PDOP の中央値 (NaN を除く)
%     PctPDOPBelow    PDOP が c.PDOPLimit 以下の時間の割合 [%]
%     Summary         領域全体の集計 (下記)
%       AreaEverCovered_pct   一度でも見えた面積の割合
%       MeanAreaCovered_pct   AreaCovered の時間平均
%       MeanPercentTime       PercentTime の面積平均
%       WorstMaxGap_s         MaxGap_s の最大 (最も条件の悪い点)
%       MeanMaxGap_s          MaxGap_s の面積平均 (見えた点のみ)
%
%   空白時間は、解析期間の先頭・末尾の見えていない区間も含めます。
%
%   See also mstudio.defaultCoverage, mstudio.buildScenario

arguments
    h (1,1) struct
    c (1,1) struct
end

sats = h.Assets(h.AssetKinds == "satellite");
assert(~isempty(sats), "mstudio:coverage:noSatellite", ...
    "カバレッジ解析の対象になる衛星がありません。");

% --- 格子点 (セル中心) と、その地球固定系での位置・天頂方向
lat = (c.LatMin_deg + c.GridStep_deg/2 : c.GridStep_deg : c.LatMax_deg)';
lon = (c.LonMin_deg + c.GridStep_deg/2 : c.GridStep_deg : c.LonMax_deg)';
assert(~isempty(lat) && ~isempty(lon), "mstudio:coverage:emptyGrid", ...
    "格子点がありません。領域と格子間隔を確認してください。");
[LAT, LON] = ndgrid(lat, lon);
LAT = LAT(:);  LON = LON(:);
point  = lla2ecef([LAT, LON, zeros(size(LAT))]);                       % Ng×3 [m]
zenith = [cosd(LAT).*cosd(LON), cosd(LAT).*sind(LON), sind(LAT)];      % Ng×3

% --- 各時刻に見えている衛星の数 (Ng×Nt)
sinMinEl = sind(c.MinEl_deg);
count = [];
satPos = cell(1, numel(sats));
for k = 1:numel(sats)
    [pos, ~, t] = states(sats{k}, CoordinateFrame="ecef");            % 3×Nt
    satPos{k} = pos;
    if isempty(count), count = zeros(numel(LAT), numel(t), "uint8"); end
    % sin(仰角) = (視線ベクトル・天頂) / 距離
    along = zenith * pos - sum(zenith .* point, 2);                    % Ng×Nt
    distSq = sum(point.^2, 2) - 2 * (point * pos) + sum(pos.^2, 1);
    count = count + uint8(along ./ sqrt(distSq) >= sinMinEl);
end
visible = count > 0;
dt = seconds(t(2) - t(1));

% --- 格子点ごとの指標
nPoint = numel(LAT);
r.Lat = LAT;  r.Lon = LON;
r.Weight = cosd(LAT) / sum(cosd(LAT));
r.Time = t;
r.PercentTime = 100 * mean(visible, 2);
r.MeanSats = mean(count, 2);
r.MaxSats  = double(max(count, [], 2));
r.MinSats  = double(min(count, [], 2));
r.NumAccess = zeros(nPoint, 1);
r.MaxGap_s  = inf(nPoint, 1);
r.MeanGap_s = inf(nPoint, 1);
for i = 1:nPoint
    edges = diff([false, visible(i, :), false]);
    r.NumAccess(i) = nnz(edges == 1);
    if r.NumAccess(i) == 0, continue, end
    gapEdges = diff([false, ~visible(i, :), false]);
    gaps = (find(gapEdges == -1) - find(gapEdges == 1)) * dt;
    if isempty(gaps), gaps = 0; end
    r.MaxGap_s(i)  = max(gaps);
    r.MeanGap_s(i) = mean(gaps);
end

% --- 測位精度の劣化係数 (求める場合のみ)
if isfield(c, "ComputeDOP") && c.ComputeDOP
    r.PDOP = positionDOP(point, zenith, satPos, sinMinEl);
    r.MedianPDOP   = median(r.PDOP, 2, "omitnan");
    r.PctPDOPBelow = 100 * mean(r.PDOP <= c.PDOPLimit, 2);
end

% --- 領域全体
r.AreaCovered = 100 * (r.Weight' * visible);
seen = r.NumAccess > 0;
r.Summary = struct( ...
    AreaEverCovered_pct = 100 * sum(r.Weight(seen)), ...
    MeanAreaCovered_pct = mean(r.AreaCovered), ...
    MeanPercentTime     = r.Weight' * r.PercentTime, ...
    WorstMaxGap_s       = max(r.MaxGap_s), ...
    MeanMaxGap_s        = sum(r.Weight(seen) .* r.MaxGap_s(seen)) / max(sum(r.Weight(seen)), eps));
end

function pdop = positionDOP(point, zenith, satPos, sinMinEl)
% 全格子点・全時刻の PDOP (Ng×Nt)。見えている衛星への視線の単位ベクトルと
% 時計誤差の列からなる観測行列 G について、inv(G'G) の位置成分の和の平方根。
% 位置成分の和は座標系の回転によらないので、地球固定系のまま計算する
nPoint = size(point, 1);  nTime = size(satPos{1}, 2);  nSat = numel(satPos);
pdop = nan(nPoint, nTime);
chunk = 200;                                             % メモリを抑えるため時刻を分割
state = warning("off", "MATLAB:nearlySingularMatrix");
restore = onCleanup(@() warning(state));
warning("off", "MATLAB:singularMatrix");

for first = 1:chunk:nTime
    idx = first:min(first + chunk - 1, nTime);
    nPage = nPoint * numel(idx);
    G = zeros(nSat, 4, nPage);
    for k = 1:nSat
        los  = reshape(satPos{k}(:, idx)', 1, [], 3) - reshape(point, nPoint, 1, 3);
        los  = los ./ vecnorm(los, 2, 3);                % Ng×Nc×3 の単位ベクトル
        seen = sum(los .* reshape(zenith, nPoint, 1, 3), 3) >= sinMinEl;
        G(k, 1:3, :) = reshape(permute(los .* seen, [3 1 2]), 3, nPage);
        G(k, 4, :)   = seen(:);
    end
    enough = reshape(sum(G(:, 4, :), 1), 1, []) >= 4;
    N = pagemtimes(G, "transpose", G, "none");
    N(:, :, ~enough) = repmat(eye(4), 1, 1, nnz(~enough));
    Q = pageinv(N);
    value = sqrt(reshape(Q(1,1,:) + Q(2,2,:) + Q(3,3,:), 1, []));
    value(~enough | ~isreal(value) | ~isfinite(value) | value > 1000) = NaN;
    pdop(:, idx) = reshape(real(value), nPoint, numel(idx));
end
end
