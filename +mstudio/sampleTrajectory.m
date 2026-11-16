function traj = sampleTrajectory()
%SAMPLETRAJECTORY  表示確認用のサンプル飛行経路 (幾何学的な弧) を返す
%   traj = mstudio.sampleTrajectory() は種子島付近から東向きに伸びる滑らかな
%   弧を時刻歴として返します。運動方程式は解いておらず、インポート機能の
%   動作確認用のダミーデータです。実データは mstudio.importTrajectory で読み込みます。
%
%   traj.Name : 名前
%   traj.Time : 経過時間 [s] (シナリオ開始時刻基準)
%   traj.LLA  : [緯度deg, 経度deg, 高度m]

T = 600;  t = (0:5:T)';  s = t/T;
lat = 30.40 - 2.0*s;
lon = 130.97 + 15.0*s;
alt = 4*200e3*s.*(1-s) + 100;
traj = struct(Name="SampleArc", Time=t, LLA=[lat lon alt]);
end
