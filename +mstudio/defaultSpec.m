function spec = defaultSpec()
%DEFAULTSPEC  Mission Studio の既定シナリオ定義を返す
%   spec = mstudio.defaultSpec() は衛星3機・地上局3局・2段式ロケット1機を
%   含むシナリオ定義 (構造体) を返します。spec は mstudio.buildScenario に渡します。
%
%   See also mstudio.buildScenario, MissionStudioApp

spec.StartTime     = datetime(2026,11,14,0,0,0,TimeZone="UTC");
spec.DurationHours = 6;
spec.SampleTime    = 30;   % [s]

% 衛星: ケプラー要素 (長半径[km], 離心率, 角度は[deg])
spec.Satellites = table( ...
    ["LEO-ISS"; "LEO-SSO"; "GEO-140E"], ...
    [6793; 6978; 42164], [0.0005; 0.001; 0], [51.6; 97.8; 0.05], ...
    [30; 120; 0], [0; 0; 0], [0; 45; 193], ...
    VariableNames=["Name","a_km","e","i_deg","RAAN_deg","ArgP_deg","Nu_deg"]);

% 軌道伝播 (ケプラー要素の衛星に適用)
spec.Propagator = mstudio.defaultPropagator();

% 地上局
spec.Stations = table( ...
    ["Tanegashima"; "Katsuura"; "Svalbard"], ...
    [30.40; 35.20; 78.23], [130.97; 140.30; 15.39], [5; 5; 5], ...
    VariableNames=["Name","Lat_deg","Lon_deg","MinEl_deg"]);

% TLEファイル (フルパスの string 配列)
spec.TLEFiles = strings(1, 0);

% インポートした飛行経路 (mstudio.importTrajectory の出力の配列)
spec.Trajectories = struct(Name={}, Time={}, LLA={});

% ロケット (3DoF質点モデル)
spec.Launcher = mstudio.defaultLauncher();

% 月遷移ミッション (既定は無効)
spec.LunarTransfer = mstudio.defaultLunarTransfer();

% カバレッジ解析 (既定は無効)
spec.Coverage = mstudio.defaultCoverage();

% 接近解析: この距離以下の最接近を一覧に載せる
spec.Proximity = struct(Threshold_km=500);

% 回線設計パラメータ
spec.Link = struct( ...
    FrequencyGHz = 8.2, ...   % ダウンリンク周波数
    TxPowerdBW   = 10, ...    % 送信電力
    TxDishM      = 0.3, ...   % 送信アンテナ径
    RxDishM      = 3.0, ...   % 受信アンテナ径
    RxGT         = 20, ...    % 受信 G/T [dB/K]
    BitRateMbps  = 10, ...
    RequiredEbNo = 10, ...    % 所要 Eb/No [dB]
    TxLineLoss_dB         = 1.0, ...  % 送信系 (給電線など) の損失
    PointingLoss_dB       = 0.5, ...  % アンテナ指向誤差による損失
    PolarizationLoss_dB   = 0.2, ...  % 偏波不整合による損失
    ImplementationLoss_dB = 1.0, ...  % 復調器などの実装損失
    IncludeAtmosphere     = true, ... % ITU-R P.618 の大気損失を入れる
    Availability_pct      = 99, ...   % 大気損失を評価する年間稼働率 [%]
    SystemNoiseTemp_K     = 150);     % 受信系の雑音温度 (降雨による G/T 低下の計算用)
end
