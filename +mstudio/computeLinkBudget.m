function r = computeLinkBudget(asset, station, p)
%COMPUTELINKBUDGET  ビークル→地上局ダウンリンクの Eb/No 時刻歴を求める
%   r = mstudio.computeLinkBudget(asset, station, p)
%
%   p は spec.Link と同じフィールドを持つ構造体です (mstudio.defaultSpec 参照)。
%
%   計算の内訳
%     Eb/No = EIRP - 自由空間損失 + G/T + 228.6 - 10log10(ビットレート)
%             - 固定損失 - 大気損失 - 降雨による雑音増加
%     EIRP        送信電力 + 送信アンテナ利得 (開口効率 0.65 のパラボラ) - 送信系損失
%     固定損失    指向損失 + 偏波損失 + 復調などの実装損失
%     大気損失    ITU-R P.618 (大気ガス・雲・降雨・シンチレーション)。
%                 p.Availability_pct の稼働率に対応する値を、仰角ごとに適用
%     雑音増加    降雨と雲が放射する雑音で G/T が下がる分。
%                 dT = 275 (1 - 10^(-A/10)) [K]、低下量 = 10log10(1 + dT/Tsys)
%   送受信アンテナは互いを追尾するジンバルに載っているものとします。
%   satelliteScenario の送受信機に既定で入っている損失 (合計 13 dB) は 0 にし、
%   損失はすべて p の項目として明示します。
%
%   元のシナリオには何も追加しません。ビークルの位置時刻歴を写した回線解析
%   専用のシナリオを内部で作るため、軌道の再伝播も発生しません。
%
%   r のフィールド (いずれも 1×Nt、見通し外は NaN)
%     Time          時刻
%     Elevation     仰角 [deg]
%     EbNoClear     大気を除いた Eb/No [dB] (固定損失は含む)
%     AtmLoss       大気損失 [dB] (P.618 の合成値)
%     NoiseIncrease 降雨による雑音増加 [dB]
%     EbNo          最終的な Eb/No [dB]
%     Margin        回線マージン [dB] = EbNo - 所要 Eb/No
%     Atmosphere    大気損失の成分 (Gas, Cloud, Rain, Scintillation, Total)
%
%   See also mstudio.atmosphericLoss, mstudio.defaultSpec, link, ebno

% --- 位置時刻歴を写した専用シナリオ
[pos, ~, t] = states(asset, CoordinateFrame="ecef");
sc  = satelliteScenario(t(1), t(end), seconds(t(2) - t(1)));
veh = satellite(sc, timetable(t(:), pos'), CoordinateFrame="ecef", Name=asset.Name);
gs  = groundStation(sc, station.Latitude, station.Longitude, ...
    Altitude=station.Altitude, MinElevationAngle=station.MinElevationAngle, ...
    Name=station.Name);

% --- 送受信系 (損失は下で明示的に引くので、ここでは 0 にする)
gTx = gimbal(veh);  pointAt(gTx, gs);
gRx = gimbal(gs);   pointAt(gRx, veh);

tx = transmitter(gTx, Frequency=p.FrequencyGHz*1e9, Power=p.TxPowerdBW, ...
    BitRate=p.BitRateMbps, SystemLoss=0);
gaussianAntenna(tx, DishDiameter=p.TxDishM);

rx = receiver(gRx, GainToNoiseTemperatureRatio=p.RxGT, RequiredEbNo=p.RequiredEbNo, ...
    SystemLoss=0, PreReceiverLoss=0);
gaussianAntenna(rx, DishDiameter=p.RxDishM);

[e, t] = ebno(link(tx, rx));
e(~isfinite(e)) = NaN;
[~, el] = aer(gs, veh);

% --- 損失
fixedLoss = p.TxLineLoss_dB + p.PointingLoss_dB + p.PolarizationLoss_dB + p.ImplementationLoss_dB;
r.Time      = t;
r.Elevation = el;
r.EbNoClear = e - fixedLoss;
r.AtmLoss   = zeros(size(e));
r.NoiseIncrease = zeros(size(e));
r.Atmosphere = [];
if p.IncludeAtmosphere
    atm = mstudio.atmosphericLoss(p.FrequencyGHz, station.Latitude, station.Longitude, ...
        el, p.Availability_pct, p.RxDishM);
    mediumTemp = 275;                                   % 降雨媒質の実効温度 [K]
    noiseTemp  = mediumTemp * (1 - 10.^(-(atm.Rain + atm.Cloud)/10));
    r.AtmLoss       = atm.Total;
    r.NoiseIncrease = 10*log10(1 + noiseTemp / p.SystemNoiseTemp_K);
    r.Atmosphere    = atm;
end
r.EbNo   = r.EbNoClear - r.AtmLoss - r.NoiseIncrease;
r.Margin = r.EbNo - p.RequiredEbNo;
end
