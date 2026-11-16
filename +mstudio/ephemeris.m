function [pos, vel] = ephemeris(center, target, epoch, t)
%EPHEMERIS  天体の位置・速度 (DE405、ICRF軸) を返す
%   [pos, vel] = mstudio.ephemeris(center, target, epoch, t) は、center から
%   見た target の位置 [km] と速度 [km/s] を、時刻 epoch + t [s] について
%   返します (N×3)。天体名は planetEphemeris と同じ ("Earth","Moon","Sun" など)。
%   epoch は UTC の datetime。TDB ≒ TT = UTC + 69.184 s として換算します
%   (2017年以降のうるう秒)。
%
%   エフェメリスデータ (aeroDataPackage) が必要です。
%
%   See also planetEphemeris, mstudio.nbodyModel

jd = juliandate(epoch) + (69.184 + t(:)) / 86400;
[pos, vel] = planetEphemeris(jd, center, target, "405");
end
