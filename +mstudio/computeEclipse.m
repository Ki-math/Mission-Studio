function T = computeEclipse(h)
%COMPUTEECLIPSE  全ビークルの地球による食 (日陰) の区間を求める
%   T = mstudio.computeEclipse(h) は Asset, Type, StartTime, EndTime,
%   Duration[s] を列に持つ table を返します。h は mstudio.buildScenario の出力。
%
%   Type
%     "Eclipse" : 半影を含む日陰全体 (太陽の一部でも地球に隠れている区間)
%     "Umbra"   : 本影 (太陽が完全に隠れている区間)
%
%   モデル
%     太陽と地球を円盤として見た二重円錐モデル。衛星から見た太陽と地球中心の
%     離角を、両者の視半径と比べます。地球の扁平は、極方向を 1/(1-f) 倍に
%     引き伸ばして球に直す近似で考慮します。太陽位置は DE405
%     (Aerospace Toolbox のエフェメリスデータ、aeroDataPackage が必要)。
%     光行時・光行差の補正はしません。
%   区間の両端は mstudio.findIntervals の補間で求めます。
%
%   See also mstudio.findIntervals, mstudio.buildScenario, planetEphemeris

assert(exist("ephConstants405.mat", "file") == 2, "mstudio:eclipse:noEphemeris", ...
    "食の計算にはエフェメリスデータが必要です。aeroDataPackage を実行してください。");

earthRadius = 6378.137e3;           % [m] 赤道半径
flattening  = 1/298.257223563;
sunRadius   = 695700e3;             % [m]
ttMinusUtc  = 69.184;               % [s] TT - UTC (2017年以降。TDB ≒ TT とみなす)

T = table(Size=[0 5], ...
    VariableTypes=["string","string","datetime","datetime","double"], ...
    VariableNames=["Asset","Type","StartTime","EndTime","Duration"]);
T.StartTime.TimeZone = "UTC";  T.EndTime.TimeZone = "UTC";

stretch = [1; 1; 1/(1 - flattening)];       % 扁平な地球を球に直す
for i = 1:numel(h.Assets)
    [r, ~, t] = states(h.Assets{i});         % GCRF [m]
    sun = planetEphemeris(juliandate(t(:)) + ttMinusUtc/86400, "Earth", "Sun", "405")' * 1e3;

    r   = r .* stretch;
    toSun = sun .* stretch - r;
    dist  = vecnorm(r);
    sunDist = vecnorm(toSun);

    separation = acos(dot(-r, toSun) ./ (dist .* sunDist));   % 地球中心と太陽の離角
    earthAngle = asin(min(1, earthRadius ./ dist));
    sunAngle   = asin(sunRadius ./ sunDist);

    outside = t < h.ValidRange(i,1) | t > h.ValidRange(i,2);
    margins = struct( ...
        Eclipse = (earthAngle + sunAngle) - separation, ...
        Umbra   = (earthAngle - sunAngle) - separation);
    for type = ["Eclipse","Umbra"]
        m = margins.(type);  m(outside) = NaN;
        [tStart, tEnd] = mstudio.findIntervals(seconds(t - t(1)), m);
        n = numel(tStart);
        if n == 0, continue, end
        T = [T; table(repmat(h.AssetNames(i), n, 1), repmat(type, n, 1), ...
            t(1) + seconds(tStart(:)), t(1) + seconds(tEnd(:)), tEnd(:) - tStart(:), ...
            VariableNames=T.Properties.VariableNames)]; %#ok<AGROW>
    end
end
T = sortrows(T, ["StartTime","Type"]);
end
