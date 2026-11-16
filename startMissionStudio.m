function app = startMissionStudio()
%STARTMISSIONSTUDIO  Mission Studio (宇宙ミッション解析GUI) を起動する
%   app = startMissionStudio() はパスを通してアプリを起動します。

addpath(fileparts(mfilename("fullpath")));
app = MissionStudioApp();
end
