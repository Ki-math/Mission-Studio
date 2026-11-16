% 新しいMATLABプロセスで比較検証を実行し、結果をログに残す
here = fileparts(mfilename("fullpath"));
diary(fullfile(here, "validation_log.txt"));
try
    results = compareWithGmat();
    save(fullfile(here, "work", "results.mat"), "results");
    disp("VALIDATION_DONE")
catch err
    disp(getReport(err, "extended", hyperlinks="off"));
    disp("VALIDATION_FAILED")
end
diary off
