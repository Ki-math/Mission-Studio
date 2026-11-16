function tf = hasItuMaps()
%HASITUMAPS  ITU-R のデジタルマップが使えるかを返す (必要ならパスに追加する)
%   tf = mstudio.hasItuMaps() は、p618PropagationLosses が使うデジタルマップ
%   (maps.mat など) が MATLAB パス上にあれば true を返します。無ければ
%   Mission Studio の data/ITURDigitalMaps を探し、あればパスに追加します。
%
%   See also mstudio.atmosphericLoss

tf = exist("p837.mat", "file") == 2;
if tf, return, end
folder = fullfile(fileparts(fileparts(mfilename("fullpath"))), "data", "ITURDigitalMaps");
if isfile(fullfile(folder, "p837.mat"))
    addpath(folder);
    tf = true;
end
end
