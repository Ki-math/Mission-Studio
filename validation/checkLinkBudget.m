function r = checkLinkBudget()
%CHECKLINKBUDGET  回線計算を手計算の回線設計と照らして確認する
%   r = checkLinkBudget() は、低軌道衛星から地上局へのダウンリンクについて、
%   mstudio.computeLinkBudget の結果を、同じ時刻の距離と仰角から式で求めた
%   値と比べます。
%
%     EIRP   = 送信電力 + 10log10(0.65 (pi D f / c)^2) - 送信系損失
%     FSPL   = 20log10(4 pi d f / c)
%     Eb/No  = EIRP - FSPL + G/T + 228.6 - 10log10(ビットレート) - 固定損失
%   大気損失は p618PropagationLosses をその仰角で直接呼んだ値と比べます
%   (仰角の格子で補間していることの確認)。
%
%   GMAT に回線解析が無いため、この確認は式との照合です。P.618 の実装そのもの
%   (MathWorks の関数) の正しさは確認の対象外です。
%
%   See also mstudio.computeLinkBudget, mstudio.atmosphericLoss

addpath(fileparts(fileparts(mfilename("fullpath"))));

spec = mstudio.defaultSpec();
spec.Launcher.Enabled = false;
spec.Propagator.Method = "two-body-keplerian";
spec.Satellites = spec.Satellites(1, :);
spec.Stations   = spec.Stations(1, :);
[~, h] = mstudio.buildScenario(spec);
p = spec.Link;
link = mstudio.computeLinkBudget(h.Assets{1}, h.Stations{1}, p);

[~, el, range] = aer(h.Stations{1}, h.Assets{1});
[~, k] = max(link.EbNo);                       % 回線が最も良い時刻で比べる
c = 299792458;  f = p.FrequencyGHz * 1e9;
eirp = p.TxPowerdBW + 10*log10(0.65 * (pi * p.TxDishM * f / c)^2) - p.TxLineLoss_dB;
fspl = 20*log10(4*pi * range(k) * f / c);
fixed = p.PointingLoss_dB + p.PolarizationLoss_dB + p.ImplementationLoss_dB;
handClear = eirp - fspl + p.RxGT + 228.6 - 10*log10(p.BitRateMbps*1e6) - fixed;

cfg = p618Config;
cfg.Frequency = f;  cfg.ElevationAngle = el(k);
cfg.Latitude = spec.Stations.Lat_deg;  cfg.Longitude = spec.Stations.Lon_deg;
cfg.AntennaDiameter = p.RxDishM;
for name = ["Gas","Cloud","Rain","Scintillation","Total"]
    cfg.(name + "AnnualExceedance") = 100 - p.Availability_pct;
end
pl = p618PropagationLosses(cfg);
noise = 10*log10(1 + 275 * (1 - 10^(-(pl.Ar + pl.Ac)/10)) / p.SystemNoiseTemp_K);

r = table(["Clear-sky Eb/No"; "Atmospheric loss"; "Noise increase"; "Final Eb/No"], ...
    [link.EbNoClear(k); link.AtmLoss(k); link.NoiseIncrease(k); link.EbNo(k)], ...
    [handClear; pl.At; noise; handClear - pl.At - noise], ...
    VariableNames=["Quantity","MissionStudio_dB","Hand_dB"]);
r.Diff_dB = r.MissionStudio_dB - r.Hand_dB;
fprintf("elevation %.2f deg, range %.1f km\n", el(k), range(k)/1e3);
disp(r)
end
