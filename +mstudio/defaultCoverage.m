function c = defaultCoverage()
%DEFAULTCOVERAGE  既定のカバレッジ解析設定を返す
%   c = mstudio.defaultCoverage() は spec.Coverage に入れる構造体を返します。
%
%   See also mstudio.computeCoverage

c.Enabled      = false;
c.LatMin_deg   = -90;      % 解析領域 (緯度・経度の範囲)
c.LatMax_deg   = 90;
c.LonMin_deg   = -180;
c.LonMax_deg   = 180;
c.GridStep_deg = 5;        % 格子の間隔 (緯度・経度とも)
c.MinEl_deg    = 10;       % 地表の点から衛星を見る最小仰角
c.ComputeDOP   = false;    % 測位精度の劣化係数 (PDOP) も求める (測位衛星向け)
c.PDOPLimit    = 6;        % この値以下を「測位可能」として時間率を集計する
end
