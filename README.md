# Mission Studio

MATLAB上で動くSTK風のミッション解析GUI。Aerospace Toolbox / Satellite Communications Toolbox の
`satelliteScenario` を解析エンジンとして使用します (R2024b で確認)。

## 起動
```matlab
cd C:\Work\MissionStudio
app = startMissionStudio;
```

## 機能
| タブ | 内容 |
|---|---|
| Ground Track | 衛星・飛行経路ビークルの地上軌跡と地上局 |
| Access | 全ビークル×全地上局の可視区間 (一覧とタイムライン) |
| AER | 選択ペアの仰角・距離の時刻歴 |
| Launch | ロケットの3DoF質点モデル上昇計算 (諸元編集、時刻歴、到達軌道) |
| Link Budget | 選択ペアのダウンリンク Eb/No と回線マージン |

`3D Viewer` で satelliteScenarioViewer (3D地球儀) を開きます。`Save` / `Open` でシナリオ定義を MAT 保存・読込。

## ロケット (3DoF質点モデル)
`Launch` タブで射点・方位・ステージ諸元を編集します。計算結果は衛星と同じシナリオに登録され、
地上軌跡・可視・回線解析の対象になります。

- 運動: 慣性系の質点、自転する球対称重力場、指数大気 + 一定Cd抗力
- 誘導: 垂直上昇 → ピッチキック → 重力ターン
- 最終段は遠地点高度が `Cutoff apogee` に達したら燃焼停止 (Inf で使い切り)
- `Auto-tune kick` は近地点高度が最大になるキック角を探索 (`mstudio.tuneKickAngle`)

スクリプトからは `r = mstudio.simulateAscent(mstudio.defaultLauncher, 3600)`。

## TLE
`Import TLE...` でTLEファイル (2行/3行形式) を追加すると、ファイル内の全衛星 (上限100機) を
SGP4/SDP4 で伝播します。TLEの元期から離れた日時では精度が落ちるので、シナリオ開始時刻を
元期の近くに設定してください。スクリプトからは `app.addTLE(file)`。

## 飛行経路の取り込み
ロケット等のシミュレーション結果は、列 `t_s, lat_deg, lon_deg, alt_m` を持つ CSV
(または同じ列の table / timetable を含む MAT) にして `Import...` から読み込みます。
時刻はシナリオ開始時刻からの経過秒です。データ範囲外の時間は解析・表示から除外されます。

## 構成
```
startMissionStudio.m     起動関数
MissionStudioApp.m       GUI本体 (クラス)
+mstudio/
  defaultSpec.m          既定シナリオ定義
  buildScenario.m        定義 -> satelliteScenario
  computeAccess.m        可視区間
  computeLinkBudget.m    回線解析
  groundTrackLLA.m       地上軌跡
  importTrajectory.m     飛行経路の読込
  sampleTrajectory.m     表示確認用のダミー経路
  defaultLauncher.m      既定のロケット諸元
  simulateAscent.m       3DoF上昇計算
  tuneKickAngle.m        キック角の探索
tests/smokeTest.m        動作確認
```
GUIを使わずに `spec = mstudio.defaultSpec; [sc,h] = mstudio.buildScenario(spec); T = mstudio.computeAccess(h)`
のようにスクリプトからも利用できます。

## 軌道伝播 (Force Model タブ)
ケプラー要素の衛星は `numerical` (数値積分、EGM96 重力場 + NRLMSISE-00 大気抵抗、ode89 / RelTol 1e-12)
が既定です。`two-body-keplerian`、`sgp4` も選べます。月・太陽の引力と太陽輻射圧は
エフェメリスデータ (`aeroDataPackage`) のインストールが必要です。

## 食 (Eclipse タブ)
`mstudio.computeEclipse` が地球による本影 (Umbra) と、半影を含む日陰全体 (Eclipse) の区間を求めます。
二重円錐モデル、太陽位置は DE405。エフェメリスデータ (`aeroDataPackage`) が必要です。

## GMAT との比較検証
`validation/compareWithGmat` が同じ初期軌道を Mission Studio と NASA GMAT R2025a で 24 時間伝播し、
位置差、可視区間 (AOS/LOS)、食の区間の差を調べます (約10分)。
GMAT は `C:\Work\GMAT\GMAT_R2025a` (または環境変数 `GMAT_ROOT`)。

2026-11-15 の結果 (エポック 2024-06-01、刻み 10 s、地上局: 種子島・スバールバル):

| ケース | 最大位置差 | パス数 (MS/GMAT) | AOS/LOS 最大差 | 食の区間数 | 食の時刻 最大差 |
|---|---|---|---|---|---|
| LEO 質点重力 | 0.25 m | 4 / 4 | 0.003 s | 32 / 32 | 0.03 s |
| LEO EGM96 20x20 | 3.4 m | 4 / 4 | 0.003 s | 32 / 32 | 0.03 s |
| SSO EGM96 20x20 | 4.1 m | 19 / 19 | 0.009 s | 30 / 30 | 0.02 s |
| GEO EGM96 20x20 | 0.10 m | 0 / 0 | - | 0 / 0 | - |
| LEO EGM96 + 大気抵抗 | 47 m | 4 / 4 | 0.003 s | 32 / 32 | 0.03 s |
| LEO + 月・太陽 | 3.4 m | 4 / 4 | 0.003 s | 32 / 32 | 0.03 s |
| GEO + 月・太陽 | 0.10 m | 0 / 0 | - | 0 / 0 | - |
| GEO + 月・太陽 + 輻射圧 | 0.11 m | 0 / 0 | - | 0 / 0 | - |
| SSO + 月・太陽 + 輻射圧 | 4.1 m | 19 / 19 | 0.009 s | 30 / 30 | 0.56 s |

注意
- 大気抵抗ケースは大気モデルが異なります (Mission Studio: NRLMSISE-00、GMAT: MSISE90)。
- GEO ケースはこの地上局・時期では可視パスも食も無く、GEO の可視と食は比較できていません。
- 24 時間・9 ケースのみ。長期伝播、高離心率軌道、TLE (SGP4) は未検証です。

## 月遷移軌道 (Lunar タブ)
`mstudio.designLunarTransfer` が、地球待機軌道からの月遷移投入 (TLI) と月周回投入 (LOI) を設計します。
設計した探査機はシナリオに載り、地上局からの可視や回線解析の対象になります
(Scenario の Duration を 120 h 以上に)。

- 増速: インパルス、または有限燃焼 (一定推力・進行方向 / 逆方向、質量変化あり)。
  有限燃焼の LOI は、燃焼時間・燃焼の中心時刻・接近軌道の最接近高度を調整して目標高度の円軌道に入れる
- 力モデル: 地球・月・太陽の質点重力 (DE405)。任意で太陽輻射圧、月周回中の月重力場 (LP165P)
- 可視解析は、探査機が月の裏側に隠れる区間を除く (`mstudio.computeAccess`)
- `mstudio.nbodyModel` / `mstudio.propagateNBody` : 中心天体を選べる N体伝播
- `mstudio.ephemeris` : 天体の位置・速度 (DE405)

GMAT R2025a との比較 (2026-11-15、エポック 2024-06-01):

| 検証 | スクリプト | 結果 |
|---|---|---|
| 月遷移 (TLI 後 4.67 日、月最接近まで) | `validation/compareLunarWithGmat` | 位置差 77 m |
| 有限燃焼 (60 kN で 500 s 燃焼 + 2 日) | `validation/compareForcesWithGmat` | 位置差 7.3 m |
| 太陽輻射圧 (3 日。効果 950 m) | 同上 | 位置差 1.0 m |
| 月重力場 LP165P 20x20 (6 時間。効果 22.7 km) | 同上 | 位置差 6 mm |
| 月による掩蔽 (月周回 3 周、臼田局) | `validation/compareOccultationWithGmat` | 掩蔽の出入り時刻の差 0.005 s 以下 |

未対応: 推力方向の最適化、低推力、打上げ可能時間帯の探索、月以外の天体、スイングバイ、
輻射圧での影 (食) の考慮、遷移中 (地球中心で伝播する区間) の月重力場。

## カバレッジ解析 (Coverage タブ)
`mstudio.computeCoverage` が、緯度・経度の格子点ごとに衛星群 (ケプラー要素と TLE の衛星) の
被覆率、通過回数、再訪時間 (最大・平均の空白時間)、同時可視衛星数を求め、領域全体を面積で重み付けして集計します。
判定はシナリオの刻みごとです。

確認 (`validation/checkCoverage`、2026-11-15): 静止衛星の可視面積率は球の解析解と 0.03 ポイント以内
(最小仰角 0/5/10/20 度)。低軌道 2 機の格子点 4 か所で、同じ場所に地上局を置いた可視解析と
通過回数が一致、被覆率の差は 0.12 ポイント以内。GMAT にカバレッジ機能が無いため外部ツールとの比較はしていません。

## 接近解析 (Proximity タブ)
`mstudio.computeCloseApproaches` が、全ビークルの組について距離の時刻歴と最接近
(時刻、最接近距離、相対速度) を求めます。最接近は相対位置のスプライン補間で絞り込みます。
衝突確率は求めません (誤差共分散が必要)。

確認 (`validation/checkCloseApproach`、2026-11-15): 約 1 km まで近づく低軌道 2 機 (相対速度 7.6 km/s) で、
刻み 30 s の結果が刻み 1 s の結果と時刻 0.1 ms・距離 1 mm 未満で一致。補間しない場合の標本最小値は 2.0 km。

## 回線解析 (Link Budget タブ)
`mstudio.computeLinkBudget` がダウンリンクの Eb/No を、晴天時と大気損失込みの両方で求めます。

- 損失はすべて明示: 送信系損失、指向損失、偏波損失、実装損失
  (satelliteScenario の送受信機に既定で入っている計 13 dB は 0 にしている)
- 大気損失: ITU-R P.618 (大気ガス・雲・降雨・シンチレーション) を稼働率 [%] と仰角に応じて適用
  (`mstudio.atmosphericLoss`)。降雨・雲による雑音増加 (G/T の低下) も含む
- ITU-R のデジタルマップが必要: `data/ITURDigitalMaps`
  (https://www.mathworks.com/supportfiles/spc/P618/ITURDigitalMaps.tar.gz を展開)。
  無い場合は晴天時のみ計算し、図の題にその旨を表示

確認 (`validation/checkLinkBudget`、2026-11-15): 回線が最も良い時刻で、式による手計算
(EIRP・自由空間損失・G/T) および p618PropagationLosses の直接呼び出しと 0.003 dB 以内で一致。
P.618 の実装そのもの (MathWorks の関数) の検証は対象外。

未対応: アップリンク、衛星間回線、干渉、変調・符号化方式ごとの所要 Eb/No、アンテナパターン、
降雨の時系列 (統計値のみ)、仰角 5 度未満の大気損失 (5 度の値で代用)。

## 解析例: みちびき (examples/)
`examples/michibikiAnalysis` が、準天頂衛星システムの公称軌道 (`michibikiSpec`) について、
現行 5 機と 7 号機を加えた 6 機の可視機数・最高仰角・PDOP・カバレッジを 24 時間解析し、
図と集計を `examples/michibiki_out` に保存します。軌道は公称値による近似で、実際の軌道暦ではありません。
`mstudio.dilutionOfPrecision` は方位・仰角から DOP を求めます。

## 測位衛星の解析 (Navigation タブ)
選択した地上局について、最小仰角以上に見える衛星 (ケプラー要素と TLE) の機数、最高仰角、
DOP (PDOP / HDOP / VDOP) の時刻歴と集計を表示します (`mstudio.dilutionOfPrecision`)。
Coverage タブで「Compute PDOP」を有効にすると、格子点ごとの PDOP の中央値と、PDOP が上限以下の時間率を
地図に表示できます。

確認 (tests/smokeTest、2026-11-15): 天頂 1 機 + 水平 3 機の配置で解析解
(PDOP = sqrt(8/3)、HDOP = VDOP = sqrt(4/3)、GDOP = sqrt(3)) と一致。
カバレッジの PDOP は、同じ場所に置いた地上局の PDOP と相対差 1e-9 で一致。
DOP は全衛星の測距誤差が等しく独立という仮定で、他の測位システムとの併用は扱いません。
