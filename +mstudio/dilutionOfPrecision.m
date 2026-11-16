function dop = dilutionOfPrecision(az, el, minEl)
%DILUTIONOFPRECISION  衛星の方位・仰角から測位精度の劣化係数 (DOP) を求める
%   dop = mstudio.dilutionOfPrecision(az, el, minEl) は、ある地点から見た
%   各衛星の方位 az・仰角 el [deg] (衛星数×時刻数) について、仰角 minEl 以上の
%   衛星だけを使った DOP の時刻歴を返します。
%
%   dop のフィールド (いずれも 1×時刻数)
%     GDOP, PDOP, HDOP, VDOP, TDOP   幾何・位置・水平・垂直・時刻の DOP
%     NumSats                        使った衛星数
%   衛星が 4 機未満、または配置が悪く解けない時刻は NaN です。
%
%   視線の単位ベクトル (東・北・上) と時計誤差の列からなる観測行列 G について
%   Q = inv(G'G) の対角成分から求めます。全衛星の測距誤差が同じで独立という
%   標準的な仮定です。
%
%   See also aer, mstudio.computeAccess

arguments
    az    double
    el    double
    minEl (1,1) double = 0
end

nTime = size(el, 2);
names = ["GDOP","PDOP","HDOP","VDOP","TDOP"];
for name = names, dop.(name) = nan(1, nTime); end
dop.NumSats = sum(el >= minEl, 1);

for k = 1:nTime
    use = el(:, k) >= minEl;
    if nnz(use) < 4, continue, end
    a = az(use, k);  e = el(use, k);
    G = [cosd(e).*sind(a), cosd(e).*cosd(a), sind(e), ones(nnz(use), 1)];
    N = G' * G;
    if rcond(N) < 1e-12, continue, end
    q = diag(inv(N));
    dop.GDOP(k) = sqrt(sum(q));
    dop.PDOP(k) = sqrt(sum(q(1:3)));
    dop.HDOP(k) = sqrt(sum(q(1:2)));
    dop.VDOP(k) = sqrt(q(3));
    dop.TDOP(k) = sqrt(q(4));
end
end
