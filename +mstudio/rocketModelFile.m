function file = rocketModelFile()
%ROCKETMODELFILE  ビューア表示用のロケット形状 (STL) のファイル名を返す
%   file = mstudio.rocketModelFile() は、円筒の胴体・円錐のノーズ・4枚の
%   フィンからなる簡易ロケット形状の STL ファイルのフルパスを返します。
%   ファイルが無ければ assets フォルダに生成します。
%
%   形状は全長 60 m・直径 3.7 m、機軸は機体 +x 軸 (ノーズが +x 側) です。
%   satelliteScenario の既定姿勢では +x がほぼ進行方向を向きます。
%
%   See also mstudio.applyVisualModels

folder = fullfile(fileparts(fileparts(mfilename("fullpath"))), "assets");
file   = fullfile(folder, "rocket.stl");
if isfile(file), return, end
if ~isfolder(folder), mkdir(folder); end

len = 60;  radius = 3.7/2;  noseLen = 8;  nSides = 24;
ang  = (0:nSides-1)' * 2*pi/nSides;
ring = @(x) [repmat(x, nSides, 1), radius*cos(ang), radius*sin(ang)];

% 頂点: 後端リング、ノーズ付け根リング、後端中心、ノーズ先端
V = [ring(0); ring(len - noseLen); 0 0 0; len 0 0];
iAft = (1:nSides)';  iFwd = iAft + nSides;
iAftNext = circshift(iAft, -1);  iFwdNext = circshift(iFwd, -1);
iCenter = 2*nSides + 1;  iTip = 2*nSides + 2;

F = [iAft, iAftNext, iFwd                       % 胴体
     iAftNext, iFwdNext, iFwd
     iFwd, iFwdNext, repmat(iTip, nSides, 1)    % ノーズ
     iAftNext, iAft, repmat(iCenter, nSides, 1)];   % 後端面

% フィン (薄い三角板を表裏2枚)
finSpan = 3;  finChord = 8;
for a = (0:3) * pi/2
    out = [0, cos(a), sin(a)];
    P = [0 0 0; finChord 0 0; 0 0 0] + [radius; radius; radius + finSpan] .* out;
    n = size(V, 1);
    V = [V; P]; %#ok<AGROW>
    F = [F; n+1, n+2, n+3; n+1, n+3, n+2]; %#ok<AGROW>
end

stlwrite(triangulation(F, V), file);
end
