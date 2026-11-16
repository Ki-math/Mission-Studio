classdef MissionStudioApp < handle
    %MISSIONSTUDIOAPP  宇宙ミッション解析GUI (衛星・ロケット・月探査機・地上局)
    %   app = MissionStudioApp() は既定シナリオでアプリを起動します。
    %   app = MissionStudioApp(spec) は指定したシナリオ定義で起動します。
    %
    %   左ペインでシナリオ (期間・衛星・地上局・TLE・飛行経路) を編集し、
    %   [Run] で以下を更新します。
    %     Ground Track : 地上軌跡と地上局
    %     Access       : 可視区間の一覧とタイムライン
    %     Eclipse      : 地球による食 (本影・半影) の区間
    %     Coverage     : 地表の格子点に対するカバレッジ (被覆率・再訪時間など)
    %     Proximity    : ビークル同士の距離と最接近
    %     Navigation   : 地上局から見た測位衛星の可視機数・最高仰角・DOP
    %     AER          : 方位・仰角・距離の時刻歴
    %     Force Model  : 衛星の軌道伝播方式と力モデル
    %     Launch       : ロケットの3DoF上昇計算 (諸元編集・時刻歴・到達軌道)
    %     Lunar        : 月遷移軌道の設計 (TLI → 月周回投入)
    %     Link Budget  : ダウンリンク Eb/No と回線マージン
    %   [3D Viewer] は satelliteScenarioViewer を別ウィンドウで開きます。
    %
    %   MissionStudioApp のメソッド:
    %     runAnalysis  - シナリオを再構築して全解析を更新
    %     open3DViewer - 3D地球儀ビューアを開く
    %     addTLE       - TLEファイルを追加
    %     selectDropdown - 表示対象 (地上局・指標など) をスクリプトから選ぶ
    %     saveSpec     - シナリオ定義を MAT に保存
    %     loadSpec     - シナリオ定義を MAT から読込
    %
    %   See also startMissionStudio, mstudio.defaultSpec, mstudio.buildScenario

    properties (SetAccess = private)
        Fig                 % uifigure
        Spec                % シナリオ定義 (mstudio.defaultSpec 参照)
        Scenario            % 直近に構築した satelliteScenario
        Objects             % mstudio.buildScenario が返すハンドル
        AccessTable         % 直近の可視区間
        EclipseTable        % 直近の食の区間 (エフェメリスデータが無ければ空)
        Coverage            % 直近のカバレッジ解析結果 (無効なら空)
        CloseApproaches     % 直近の最接近の一覧
        RangeHistory        % ビークル同士の距離の時刻歴
    end

    properties (Access = private)
        UI = struct()       % UI部品のハンドル
        LunarCacheKey = []  % 直近の月遷移設計に使った条件 (同じ条件なら再設計しない)
    end

    %% 公開メソッド
    methods
        function app = MissionStudioApp(spec)
            arguments
                spec (1,1) struct = mstudio.defaultSpec()
            end
            app.Spec = spec;
            app.buildUI();
            app.writeSpecToUI();
            app.runAnalysis();
        end

        function open3DViewerFromButton(app)
            app.open3DViewer();     % ボタンからは戻り値を表示しない
        end

        function runAnalysis(app)
            %RUNANALYSIS  UIの内容でシナリオを再構築し、全タブを更新する
            dlg = uiprogressdlg(app.Fig, Title="Mission Studio", ...
                Message="シナリオを解析中...", Indeterminate="on");
            cleanup = onCleanup(@() close(dlg));
            try
                app.readSpecFromUI();
                [app.Scenario, app.Objects] = mstudio.buildScenario(app.Spec, app.reusableResults());
                app.LunarCacheKey = app.lunarKey();
                app.AccessTable = mstudio.computeAccess(app.Objects);
                app.EclipseTable = app.computeEclipseIfAvailable();
                app.Coverage = [];
                if app.Spec.Coverage.Enabled
                    app.Coverage = mstudio.computeCoverage(app.Objects, app.Spec.Coverage);
                end
                [app.CloseApproaches, app.RangeHistory] = mstudio.computeCloseApproaches( ...
                    app.Objects, app.Spec.Proximity.Threshold_km);
                app.refreshPairSelectors();
                app.updateGroundTrack();
                app.updateAccess();
                app.updateEclipse();
                app.updateCoverage();
                app.updateProximity();
                app.updateNavigation();
                app.updateLaunch();
                app.updateLunar();
                app.updatePairPlots();
                app.UI.Status.Text = sprintf("解析完了 %s  (ビークル %d / 地上局 %d / 可視 %d 回 / 食 %d 回)", ...
                    string(datetime("now"), "HH:mm:ss"), numel(app.Objects.Assets), ...
                    numel(app.Objects.Stations), height(app.AccessTable), ...
                    nnz(string(app.eclipseTypes()) == "Eclipse"));
            catch err
                uialert(app.Fig, err.message, "解析エラー");
                app.UI.Status.Text = "エラー: " + err.message;
            end
        end

        function viewer = open3DViewer(app)
            %OPEN3DVIEWER  現在のシナリオを3D地球儀で表示する
            %   衛星とロケットは3Dモデルで表示されます。ツールバーの Model size で
            %   モデルの見かけの長さ [km] を変えられます (0 = 実寸)。
            if isempty(app.Scenario), app.runAnalysis(); end
            mstudio.applyVisualModels(app.Objects, app.UI.ModelSize.Value);
            viewer = satelliteScenarioViewer(app.Scenario);
        end

        function saveSpec(app, file)
            %SAVESPEC  シナリオ定義を MAT ファイルに保存する
            if nargin < 2
                [f, p] = uiputfile("*.mat", "シナリオを保存", "scenario.mat");
                if isequal(f, 0), return, end
                file = fullfile(p, f);
            end
            app.readSpecFromUI();
            spec = app.Spec;
            save(file, "spec");
        end

        function loadSpec(app, file)
            %LOADSPEC  シナリオ定義を MAT ファイルから読み込む
            if nargin < 2
                [f, p] = uigetfile("*.mat", "シナリオを開く");
                if isequal(f, 0), return, end
                file = fullfile(p, f);
            end
            S = load(file, "spec");
            app.Spec = S.spec;
            % 旧バージョンで保存した定義に無い項目は既定値で補う
            defaults = mstudio.defaultSpec();
            for f = setdiff(string(fieldnames(defaults)), string(fieldnames(app.Spec)))'
                app.Spec.(f) = defaults.(f);
            end
            for group = ["LunarTransfer","Link"]
                for f = setdiff(string(fieldnames(defaults.(group))), ...
                        string(fieldnames(app.Spec.(group))))'
                    app.Spec.(group).(f) = defaults.(group).(f);
                end
            end
            app.writeSpecToUI();
            app.runAnalysis();
        end

        function addTLE(app, file)
            %ADDTLE  TLEファイルをシナリオに追加して再解析する
            %   ファイル内の全衛星が SGP4/SDP4 で伝播されます。
            arguments
                app
                file (1,1) string {mustBeFile}
            end
            app.Spec.TLEFiles(end+1) = file;
            app.refreshImportList();
            app.runAnalysis();
        end

        function selectDropdown(app, control, value)
            %SELECTDROPDOWN  ドロップダウンの項目をスクリプトから選ぶ
            %   app.selectDropdown(control, value) は、画面で選んだときと同じように
            %   値を設定して表示を更新します。control は "NavStation"、
            %   "CoverageMetric"、"ProximityPair" など。
            dd = app.UI.(control);
            dd.Value = value;
            dd.ValueChangedFcn(dd, []);
        end

        function delete(app)
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end
    end

    %% UI構築
    methods (Access = private)
        function buildUI(app)
            % 画面に収まる大きさで中央に開く (タスクバーとタイトルバーの分を空ける)
            screen = get(groot, "ScreenSize");
            figSize = min([1400 820], screen(3:4) - [40 110]);
            figPos  = [(screen(3) - figSize(1))/2, 60, figSize];
            app.Fig = uifigure(Name="Mission Studio", Position=figPos);
            root = uigridlayout(app.Fig, [3 2], RowHeight={36,"1x",22}, ...
                ColumnWidth={520,"1x"}, Padding=[8 8 8 8]);

            app.buildToolbar(root);
            app.buildScenarioPane(root);
            app.buildAnalysisTabs(root);

            app.UI.Status = uilabel(root, Text="Ready");
            app.UI.Status.Layout.Row = 3;  app.UI.Status.Layout.Column = [1 2];
        end

        function buildToolbar(app, root)
            bar = uigridlayout(root, [1 7], Padding=[0 0 0 0], ...
                ColumnWidth={110,110,95,70,90,90,"1x"});
            bar.Layout.Row = 1;  bar.Layout.Column = [1 2];
            uibutton(bar, Text="▶ Run", FontWeight="bold", ...
                ButtonPushedFcn=@(~,~) app.runAnalysis());
            uibutton(bar, Text="3D Viewer", ButtonPushedFcn=@(~,~) app.open3DViewerFromButton());
            uilabel(bar, Text="Model size [km]", HorizontalAlignment="right");
            app.UI.ModelSize = uieditfield(bar, "numeric", Value=300, Limits=[0 1e4], ...
                Tooltip="ビューアでの3Dモデルの見かけの長さ (0 = 実寸)");
            uibutton(bar, Text="Save", ButtonPushedFcn=@(~,~) app.saveSpec());
            uibutton(bar, Text="Open", ButtonPushedFcn=@(~,~) app.loadSpec());
        end

        function buildScenarioPane(app, root)
            g = uigridlayout(root, [9 1], Padding=[0 0 0 0], RowSpacing=4, ...
                RowHeight={84,18,"1.2x",26,18,"1x",26,18,84});
            g.Layout.Row = 2;  g.Layout.Column = 1;

            % --- シナリオ期間
            p  = uipanel(g, Title="Scenario");
            pg = uigridlayout(p, [2 4], ColumnWidth={70,"1x",80,60}, ...
                RowHeight={22,22}, Padding=[6 4 6 4], RowSpacing=4);
            uilabel(pg, Text="Start (UTC)");
            app.UI.Start = uieditfield(pg, "text");
            app.UI.Start.Layout.Column = [2 4];
            uilabel(pg, Text="Duration [h]");
            app.UI.Duration = uieditfield(pg, "numeric", Limits=[0.1 720]);
            uilabel(pg, Text="Step [s]");
            app.UI.Step = uieditfield(pg, "numeric", Limits=[1 3600]);

            % --- 衛星
            uilabel(g, Text="Satellites (Keplerian elements)", FontWeight="bold");
            app.UI.SatTable = uitable(g, ColumnEditable=true, SelectionType="row");
            app.addRowButtons(g, app.UI.SatTable, ...
                {"NewSat", 7000, 0, 45, 0, 0, 0});

            % --- 地上局
            uilabel(g, Text="Ground Stations", FontWeight="bold");
            app.UI.GsTable = uitable(g, ColumnEditable=true, SelectionType="row");
            app.addRowButtons(g, app.UI.GsTable, {"NewStation", 35, 139, 5});

            % --- 飛行経路
            uilabel(g, Text="Imported (TLE files / trajectory time histories)", FontWeight="bold");
            tg = uigridlayout(g, [3 2], ColumnWidth={"1x",110}, RowHeight={"1x","1x","1x"}, ...
                Padding=[0 0 0 0], RowSpacing=4);
            app.UI.ImportList = uilistbox(tg, Items={});
            app.UI.ImportList.Layout.Row = [1 3];  app.UI.ImportList.Layout.Column = 1;
            b = uibutton(tg, Text="Import TLE...", ButtonPushedFcn=@(~,~) app.onImportTLE());
            b.Layout.Row = 1;  b.Layout.Column = 2;
            b = uibutton(tg, Text="Import Traj...", ButtonPushedFcn=@(~,~) app.onImportTrajectory());
            b.Layout.Row = 2;  b.Layout.Column = 2;
            b = uibutton(tg, Text="Remove", ButtonPushedFcn=@(~,~) app.onRemoveImport());
            b.Layout.Row = 3;  b.Layout.Column = 2;
        end

        function addRowButtons(~, parent, tbl, defaultRow)
            % テーブル直下に [+ Add] [- Remove] ボタンを置く
            bg = uigridlayout(parent, [1 3], ColumnWidth={80,80,"1x"}, Padding=[0 0 0 0]);
            uibutton(bg, Text="+ Add",    ButtonPushedFcn=@(~,~) addRow());
            uibutton(bg, Text="- Remove", ButtonPushedFcn=@(~,~) removeRow());

            function addRow()
                row = cell2table(defaultRow, VariableNames=tbl.Data.Properties.VariableNames);
                row.Name = string(row.Name) + (height(tbl.Data) + 1);
                tbl.Data = [tbl.Data; row];
            end
            function removeRow()
                if ~isempty(tbl.Selection), tbl.Data(tbl.Selection, :) = []; end
            end
        end

        function buildAnalysisTabs(app, root)
            tabs = uitabgroup(root);
            tabs.Layout.Row = 2;  tabs.Layout.Column = 2;

            % --- Ground Track
            t1 = uitab(tabs, Title="Ground Track");
            g1 = uigridlayout(t1, [1 1], Padding=[4 4 4 4]);
            app.UI.GeoAx = geoaxes(g1, Basemap="darkwater");

            % --- Access
            t2 = uitab(tabs, Title="Access");
            g2 = uigridlayout(t2, [2 1], RowHeight={"1x","1x"}, Padding=[4 4 4 4]);
            app.UI.AccessAx    = uiaxes(g2);
            app.UI.AccessTable = uitable(g2);

            % --- Eclipse
            t5 = uitab(tabs, Title="Eclipse");
            g5 = uigridlayout(t5, [2 1], RowHeight={"1x","1x"}, Padding=[4 4 4 4]);
            app.UI.EclipseAx    = uiaxes(g5);
            app.UI.EclipseTable = uitable(g5);

            % --- Coverage / Proximity
            app.buildCoverageTab(uitab(tabs, Title="Coverage"));
            app.buildProximityTab(uitab(tabs, Title="Proximity"));
            app.buildNavigationTab(uitab(tabs, Title="Navigation"));

            % --- ビークル/地上局ペアの選択 (AER と Link で共有)
            t3 = uitab(tabs, Title="AER");
            g3 = uigridlayout(t3, [3 1], RowHeight={26,"1x","1x"}, Padding=[4 4 4 4]);
            app.UI.PairAER = app.addPairSelector(g3);
            app.UI.ElAx    = uiaxes(g3);
            app.UI.RangeAx = uiaxes(g3);

            % --- Force Model
            app.buildForceModelTab(uitab(tabs, Title="Force Model"));

            % --- Launch (3DoF)
            app.buildLaunchTab(uitab(tabs, Title="Launch"));

            % --- Lunar transfer
            app.buildLunarTab(uitab(tabs, Title="Lunar"));

            % --- Link Budget
            t4 = uitab(tabs, Title="Link Budget");
            g4 = uigridlayout(t4, [2 2], RowHeight={26,"1x"}, ColumnWidth={290,"1x"}, ...
                Padding=[4 4 4 4]);
            app.UI.PairLink = app.addPairSelector(g4);
            app.UI.PairLink.Grid.Layout.Column = [1 2];
            app.buildLinkForm(g4);
            app.UI.LinkAx = uiaxes(g4);
        end

        function addNumericFields(app, grid, group, fields, labels)
            % ラベル + 数値入力欄を並べ、app.UI.(group).(field) に登録する
            for k = 1:numel(fields)
                uilabel(grid, Text=labels(k));
                app.UI.(group).(fields(k)) = uieditfield(grid, "numeric");
            end
        end

        function buildForceModelTab(app, tab)
            g = uigridlayout(tab, [1 2], ColumnWidth={360,"1x"}, Padding=[4 4 4 4]);
            p = uipanel(g, Title="Orbit propagation (Keplerian-element satellites)");
            fg = uigridlayout(p, [13 2], ColumnWidth={200,"1x"}, RowSpacing=3, ...
                RowHeight=[{26} repmat({22}, 1, 12)], Padding=[6 4 6 4], Scrollable="on");

            b = uibutton(fg, Text="Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            b.Layout.Column = [1 2];
            uilabel(fg, Text="Propagator");
            app.UI.Propagator.Method = uidropdown(fg, ...
                Items=["numerical","two-body-keplerian","sgp4"]);
            app.addNumericFields(fg, "Propagator", "GravityDegree", ...
                "Gravity degree (EGM96, 0=point mass)");
            app.UI.Propagator.IncludeDrag = uicheckbox(fg, Text="Atmospheric drag (NRLMSISE-00)");
            app.UI.Propagator.IncludeDrag.Layout.Column = [1 2];
            app.addNumericFields(fg, "Propagator", "F107", "F10.7 solar flux [sfu]");
            app.UI.Propagator.IncludeThirdBody = uicheckbox(fg, Text="Sun / Moon gravity *");
            app.UI.Propagator.IncludeThirdBody.Layout.Column = [1 2];
            app.UI.Propagator.IncludeSRP = uicheckbox(fg, Text="Solar radiation pressure *");
            app.UI.Propagator.IncludeSRP.Layout.Column = [1 2];
            app.addNumericFields(fg, "Propagator", ...
                ["Mass_kg","DragArea_m2","Cd","SRPArea_m2","Cr"], ...
                ["Mass [kg]","Drag area [m^2]","Drag coefficient [-]", ...
                 "SRP area [m^2]","Reflectivity coefficient [-]"]);
            note = uilabel(fg, Text="* requires ephemeris data (aeroDataPackage)", ...
                FontAngle="italic");
            note.Layout.Column = [1 2];

            app.UI.PropagatorInfo = uitextarea(g, Editable="off", Value=[ ...
                "numerical          : 数値積分。要素は接触軌道要素として扱われ、下の力モデルが有効"
                "two-body-keplerian : 二体問題の解析解 (摂動なし)"
                "sgp4               : SGP4/SDP4。要素を平均要素として解釈するため、"
                "                     同じ数値でも numerical とは別の軌道になる"
                ""
                "TLE から読み込んだ衛星は、この設定に関係なく常に SGP4/SDP4 で伝播します。"]);
        end

        function buildCoverageTab(app, tab)
            g = uigridlayout(tab, [2 2], ColumnWidth={270,"1x"}, RowHeight={"1x",120}, ...
                Padding=[4 4 4 4]);
            fields = ["LatMin_deg","LatMax_deg","LonMin_deg","LonMax_deg","GridStep_deg","MinEl_deg"];
            labels = ["Latitude min [deg]","Latitude max [deg]","Longitude min [deg]", ...
                      "Longitude max [deg]","Grid step [deg]","Min elevation [deg]"];
            p = uipanel(g, Title="Coverage (Keplerian + TLE satellites)");
            p.Layout.Row = [1 2];  p.Layout.Column = 1;
            fg = uigridlayout(p, [numel(fields)+5 2], ColumnWidth={150,"1x"}, RowSpacing=3, ...
                RowHeight=[{22,26} repmat({22}, 1, numel(fields)+3)], Padding=[6 4 6 4], ...
                Scrollable="on");
            app.UI.Coverage.Enabled = uicheckbox(fg, Text="Enable coverage analysis");
            app.UI.Coverage.Enabled.Layout.Column = [1 2];
            b = uibutton(fg, Text="Compute / Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            b.Layout.Column = [1 2];
            app.addNumericFields(fg, "Coverage", fields, labels);
            app.UI.Coverage.ComputeDOP = uicheckbox(fg, Text="Compute PDOP (navigation)");
            app.UI.Coverage.ComputeDOP.Layout.Column = [1 2];
            app.addNumericFields(fg, "Coverage", "PDOPLimit", "PDOP limit [-]");
            uilabel(fg, Text="Show");
            app.UI.CoverageMetric = uidropdown(fg, ...
                Items=["Percent time [%]","Max gap [min]","Mean gap [min]","Passes", ...
                       "Mean satellites","Max satellites","Min satellites", ...
                       "Median PDOP","PDOP availability [%]"], ...
                ValueChangedFcn=@(~,~) app.updateCoverage());

            app.UI.CoverageAx = geoaxes(g, Basemap="darkwater");
            app.UI.CoverageAx.Layout.Row = 1;  app.UI.CoverageAx.Layout.Column = 2;
            app.UI.CoverageSummary = uitextarea(g, Editable="off", FontName="Consolas");
            app.UI.CoverageSummary.Layout.Row = 2;  app.UI.CoverageSummary.Layout.Column = 2;
        end

        function buildNavigationTab(app, tab)
            g = uigridlayout(tab, [5 1], RowHeight={26,"1x","1x","1x",70}, Padding=[4 4 4 4]);
            top = uigridlayout(g, [1 3], ColumnWidth={60,220,"1x"}, Padding=[0 0 0 0]);
            uilabel(top, Text="Station");
            app.UI.NavStation = uidropdown(top, Items={}, ...
                ValueChangedFcn=@(~,~) app.updateNavigation());
            uilabel(top, FontAngle="italic", ...
                Text="Keplerian + TLE satellites above the station's minimum elevation");
            app.UI.NavCountAx = uiaxes(g);
            app.UI.NavElAx    = uiaxes(g);
            app.UI.NavDopAx   = uiaxes(g);
            app.UI.NavSummary = uitextarea(g, Editable="off", FontName="Consolas");
        end

        function buildProximityTab(app, tab)
            g = uigridlayout(tab, [3 1], RowHeight={26,"1x","1x"}, Padding=[4 4 4 4]);
            top = uigridlayout(g, [1 6], ColumnWidth={150,80,90,50,260,"1x"}, Padding=[0 0 0 0]);
            app.addNumericFields(top, "Proximity", "Threshold_km", "List approaches within [km]");
            uibutton(top, Text="Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            uilabel(top, Text="Pair", HorizontalAlignment="right");
            app.UI.ProximityPair = uidropdown(top, Items={}, ...
                ValueChangedFcn=@(~,~) app.plotRange());
            app.UI.ProximityAx    = uiaxes(g);
            app.UI.ProximityTable = uitable(g);
        end

        function buildLunarTab(app, tab)
            g = uigridlayout(tab, [2 3], ColumnWidth={300,"1x","1x"}, RowHeight={"1x",140}, ...
                Padding=[4 4 4 4]);

            fields = ["TLITime","ParkingAlt_km","ParkingInc_deg", ...
                      "PeriluneAlt_km","LunarInc_deg","LunarOrbits"];
            labels = ["TLI time [s]","Parking altitude [km]","Parking inclination [deg]", ...
                      "Perilune altitude [km]","Lunar inclination [deg]","Lunar orbits [-]"];
            p  = uipanel(g, Title="Lunar transfer (Earth-Moon-Sun point masses)");
            p.Layout.Row = [1 2];  p.Layout.Column = 1;
            burnFields = ["Mass_kg","Thrust_kN","Isp_s","ProbeMass_kg","LOIThrust_N","LOIIsp_s"];
            burnLabels = ["TLI initial mass [kg]","TLI thrust [kN]","TLI Isp [s]", ...
                          "Probe mass at LOI [kg]","LOI thrust [N]","LOI Isp [s]"];
            forceFields = ["SRPArea_m2","Cr","MoonGravityDegree"];
            forceLabels = ["SRP area [m^2]","Reflectivity Cr [-]","Moon gravity degree (0=point)"];
            nRows = numel(fields) + numel(burnFields) + numel(forceFields) + 6;
            fg = uigridlayout(p, [nRows 2], ColumnWidth={170,"1x"}, RowSpacing=3, ...
                RowHeight=[{22,26} repmat({22}, 1, nRows-3) {90}], ...
                Padding=[6 4 6 4], Scrollable="on");
            app.UI.Lunar.Enabled = uicheckbox(fg, Text="Enable lunar transfer");
            app.UI.Lunar.Enabled.Layout.Column = [1 2];
            b = uibutton(fg, Text="Design / Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            b.Layout.Column = [1 2];
            uilabel(fg, Text="Name");
            app.UI.Lunar.Name = uieditfield(fg, "text");
            app.addNumericFields(fg, "Lunar", fields, labels);
            uilabel(fg, Text="Burn model");
            app.UI.Lunar.BurnModel = uidropdown(fg, Items=["impulsive","finite"]);
            app.addNumericFields(fg, "Lunar", burnFields, burnLabels);
            app.UI.Lunar.IncludeSRP = uicheckbox(fg, Text="Solar radiation pressure");
            app.UI.Lunar.IncludeSRP.Layout.Column = [1 2];
            app.addNumericFields(fg, "Lunar", forceFields, forceLabels);
            note = uilabel(fg, WordWrap="on", VerticalAlignment="top", FontAngle="italic", ...
                Text="可視・回線解析に遷移全体を含めるには、Scenario の Duration を 120 h 以上にしてください。" + ...
                     "その場合は Force Model を two-body-keplerian にすると解析が速くなります。");
            note.Layout.Column = [1 2];

            app.UI.Lunar.EarthAx = uiaxes(g);
            app.UI.Lunar.EarthAx.Layout.Row = 1;  app.UI.Lunar.EarthAx.Layout.Column = 2;
            app.UI.Lunar.MoonAx  = uiaxes(g);
            app.UI.Lunar.MoonAx.Layout.Row = 1;   app.UI.Lunar.MoonAx.Layout.Column = 3;
            app.UI.LunarSummary  = uitextarea(g, Editable="off", FontName="Consolas");
            app.UI.LunarSummary.Layout.Row = 2;  app.UI.LunarSummary.Layout.Column = [2 3];
        end

        function buildLaunchTab(app, tab)
            g = uigridlayout(tab, [2 2], ColumnWidth={330,"1x"}, RowHeight={"1x",150}, ...
                Padding=[4 4 4 4]);

            % --- 諸元フォーム
            fields = ["LiftoffTime","SiteLat_deg","SiteLon_deg","Azimuth_deg", ...
                      "Payload_kg","Diameter_m","Cd","PitchoverAlt_m", ...
                      "KickAngle_deg","KickDuration_s","CutoffApogee_km"];
            labels = ["Liftoff time [s]","Site latitude [deg]","Site longitude [deg]", ...
                      "Launch azimuth [deg]","Payload [kg]","Diameter [m]","Cd [-]", ...
                      "Pitchover altitude [m]","Kick angle [deg]","Kick duration [s]", ...
                      "Cutoff apogee [km] (Inf=deplete)"];
            p  = uipanel(g, Title="Launch vehicle (3DoF point mass)");
            p.Layout.Row = 1;  p.Layout.Column = 1;
            % ボタンは先頭に置き、ウィンドウが低いときは欄をスクロールできるようにする
            fg = uigridlayout(p, [numel(fields)+3 2], ColumnWidth={190,"1x"}, RowSpacing=3, ...
                RowHeight=[{22,26} repmat({22}, 1, numel(fields)+1)], Padding=[6 4 6 4], ...
                Scrollable="on");
            app.UI.Launch.Enabled = uicheckbox(fg, Text="Enable launcher");
            app.UI.Launch.Enabled.Layout.Column = [1 2];
            uibutton(fg, Text="Auto-tune kick", Tooltip="近地点高度が最大になるキック角を探索", ...
                ButtonPushedFcn=@(~,~) app.onTuneKick());
            uibutton(fg, Text="Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            uilabel(fg, Text="Name");
            app.UI.Launch.Name = uieditfield(fg, "text");
            app.addNumericFields(fg, "Launch", fields, labels);

            % --- ステージ諸元 + 結果サマリ
            bg = uigridlayout(g, [1 2], ColumnWidth={"1.6x","1x"}, Padding=[0 0 0 0]);
            bg.Layout.Row = 2;  bg.Layout.Column = [1 2];
            app.UI.StageTable   = uitable(bg, ColumnEditable=true);
            app.UI.LaunchSummary = uitextarea(bg, Editable="off", FontName="Consolas");

            % --- 時刻歴プロット
            pg = uigridlayout(g, [2 2], Padding=[0 0 0 0]);
            pg.Layout.Row = 1;  pg.Layout.Column = 2;
            for name = ["AltAx","SpeedAx","ProfileAx","LoadAx"]
                app.UI.Launch.(name) = uiaxes(pg);
            end
        end

        function s = addPairSelector(app, parent)
            s.Grid = uigridlayout(parent, [1 5], ColumnWidth={60,180,60,180,"1x"}, ...
                Padding=[0 0 0 0]);
            uilabel(s.Grid, Text="Vehicle");
            s.Asset = uidropdown(s.Grid, Items={}, ...
                ValueChangedFcn=@(~,~) app.updatePairPlots());
            uilabel(s.Grid, Text="Station");
            s.Station = uidropdown(s.Grid, Items={}, ...
                ValueChangedFcn=@(~,~) app.updatePairPlots());
        end

        function buildLinkForm(app, parent)
            fields = ["FrequencyGHz","TxPowerdBW","TxDishM","RxDishM", ...
                      "RxGT","BitRateMbps","RequiredEbNo", ...
                      "TxLineLoss_dB","PointingLoss_dB","PolarizationLoss_dB","ImplementationLoss_dB"];
            labels = ["Frequency [GHz]","Tx power [dBW]","Tx dish [m]","Rx dish [m]", ...
                      "Rx G/T [dB/K]","Bit rate [Mbps]","Required Eb/No [dB]", ...
                      "Tx line loss [dB]","Pointing loss [dB]","Polarization loss [dB]", ...
                      "Implementation loss [dB]"];
            atmFields = ["Availability_pct","SystemNoiseTemp_K"];
            atmLabels = ["Availability [%]","System noise temp [K]"];
            p = uipanel(parent, Title="Downlink parameters");
            nRows = numel(fields) + numel(atmFields) + 2;
            g = uigridlayout(p, [nRows 2], ColumnWidth={145,"1x"}, RowSpacing=3, ...
                RowHeight=[{26} repmat({22}, 1, nRows-1)], Padding=[6 4 6 4], Scrollable="on");
            b = uibutton(g, Text="Update", ButtonPushedFcn=@(~,~) app.runAnalysis());
            b.Layout.Column = [1 2];
            app.addNumericFields(g, "Link", fields, labels);
            app.UI.Link.IncludeAtmosphere = uicheckbox(g, Text="Atmospheric loss (ITU-R P.618)");
            app.UI.Link.IncludeAtmosphere.Layout.Column = [1 2];
            app.addNumericFields(g, "Link", atmFields, atmLabels);
        end
    end

    %% UI <-> Spec
    methods (Access = private)
        function writeSpecToUI(app)
            s = app.Spec;
            app.UI.Start.Value    = string(s.StartTime, "yyyy-MM-dd HH:mm:ss");
            app.UI.Duration.Value = s.DurationHours;
            app.UI.Step.Value     = s.SampleTime;
            app.UI.SatTable.Data  = s.Satellites;
            app.UI.GsTable.Data   = s.Stations;
            app.refreshImportList();
            for group = app.formGroups()
                [ui, fields] = app.formFields(group);
                for f = fields, ui.(f).Value = s.(group).(f); end
            end
            app.UI.StageTable.Data = s.Launcher.Stages;
        end

        function readSpecFromUI(app)
            app.Spec.StartTime = datetime(app.UI.Start.Value, ...
                InputFormat="yyyy-MM-dd HH:mm:ss", TimeZone="UTC");
            app.Spec.DurationHours = app.UI.Duration.Value;
            app.Spec.SampleTime    = app.UI.Step.Value;
            app.Spec.Satellites    = app.UI.SatTable.Data;
            app.Spec.Stations      = app.UI.GsTable.Data;
            for group = app.formGroups()
                [ui, fields] = app.formFields(group);
                for f = fields, app.Spec.(group).(f) = ui.(f).Value; end
            end
            app.Spec.LunarTransfer.Name = string(app.Spec.LunarTransfer.Name);
            app.Spec.LunarTransfer.BurnModel = string(app.Spec.LunarTransfer.BurnModel);
            app.Spec.Launcher.Name     = string(app.Spec.Launcher.Name);
            app.Spec.Propagator.Method = string(app.Spec.Propagator.Method);
            app.Spec.Launcher.Stages = app.UI.StageTable.Data;
        end

        function groups = formGroups(~)
            % フォームで編集する spec のフィールド
            groups = ["Link","Launcher","Propagator","LunarTransfer","Coverage","Proximity"];
        end

        function [ui, fields] = formFields(app, group)
            % spec.(group) を編集するフォームの部品と、対応するフィールド名を返す
            uiNames = struct(Link="Link", Launcher="Launch", Propagator="Propagator", ...
                LunarTransfer="Lunar", Coverage="Coverage", Proximity="Proximity");
            ui = app.UI.(uiNames.(group));
            fields = intersect(string(fieldnames(ui)), ...
                string(fieldnames(app.Spec.(group))))';
        end

        function refreshImportList(app)
            % ItemsData は "tle:番号" / "traj:番号" (削除時に対象を特定する)
            tleNames = strings(1, 0);
            for file = reshape(string(app.Spec.TLEFiles), 1, [])
                [~, name, ext] = fileparts(file);
                tleNames(end+1) = name + ext; %#ok<AGROW>
            end
            trajNames = reshape(string({app.Spec.Trajectories.Name}), 1, []);
            app.UI.ImportList.Items = cellstr( ...
                ["[TLE]  " + tleNames, "[Traj] " + trajNames]);
            app.UI.ImportList.ItemsData = cellstr( ...
                ["tle:" + (1:numel(tleNames)), "traj:" + (1:numel(trajNames))]);
        end

        function refreshPairSelectors(app)
            % 選択中の項目を保ったままドロップダウンの候補を更新する
            for sel = [app.UI.PairAER, app.UI.PairLink]
                setItems(sel.Asset,   app.Objects.AssetNames);
                setItems(sel.Station, app.Objects.StationNames);
            end
            function setItems(dd, names)
                prev = dd.Value;
                dd.Items = cellstr(names);
                if ischar(prev) && any(strcmp(prev, names)), dd.Value = prev; end
            end
        end

        function onImportTrajectory(app)
            [f, p] = uigetfile({"*.csv;*.mat", "Trajectory (*.csv, *.mat)"}, ...
                "飛行経路を読み込む");
            if isequal(f, 0), return, end
            try
                traj = mstudio.importTrajectory(fullfile(p, f));
                app.Spec.Trajectories = [app.Spec.Trajectories, traj];
                app.refreshImportList();
                app.runAnalysis();
            catch err
                uialert(app.Fig, err.message, "読み込みエラー");
            end
        end

        function onImportTLE(app)
            [f, p] = uigetfile({"*.tle;*.txt", "TLE (*.tle, *.txt)"}, "TLEファイルを読み込む");
            if isequal(f, 0), return, end
            app.addTLE(fullfile(p, f));
        end

        function onRemoveImport(app)
            if isempty(app.UI.ImportList.Items), return, end
            key = split(string(app.UI.ImportList.Value), ":");
            idx = str2double(key(2));
            if key(1) == "tle"
                app.Spec.TLEFiles(idx) = [];
            else
                app.Spec.Trajectories(idx) = [];
            end
            app.refreshImportList();
        end

        function onTuneKick(app)
            dlg = uiprogressdlg(app.Fig, Title="Mission Studio", ...
                Message="キック角を探索中...", Indeterminate="on");
            try
                app.readSpecFromUI();
                kick = mstudio.tuneKickAngle(app.Spec.Launcher);
                app.UI.Launch.KickAngle_deg.Value = kick;
                close(dlg);
                app.runAnalysis();
            catch err
                close(dlg);
                uialert(app.Fig, err.message, "探索エラー");
            end
        end
    end

    %% 描画
    methods (Access = private)
        function updateGroundTrack(app)
            ax = app.UI.GeoAx;
            cla(ax);  hold(ax, "on");
            for k = 1:numel(app.Objects.Assets)
                [lat, lon] = mstudio.groundTrackLLA(app.Objects.Assets{k}, ...
                    app.Objects.ValidRange(k, :));
                geoplot(ax, lat, lon, LineWidth=1.5, ...
                    DisplayName=app.Objects.AssetNames(k));
            end
            gs = app.Spec.Stations;
            if ~isempty(gs)
                geoscatter(ax, gs.Lat_deg, gs.Lon_deg, 60, "w", "filled", "^", ...
                    MarkerEdgeColor="k", DisplayName="Ground stations");
                text(ax, gs.Lat_deg, gs.Lon_deg, "  " + string(gs.Name), Color="w");
            end
            hold(ax, "off");
            geolimits(ax, [-85 85], [-180 180]);
            legend(ax, Location="southwest", TextColor="w", Color=[0.15 0.15 0.15]);
        end

        function updateAccess(app)
            T = app.AccessTable;
            app.UI.AccessTable.Data = app.formatIntervalTable(T);
            app.plotTimeline(app.UI.AccessAx, T, T.Source + " → " + T.Target, ...
                "Access timeline (UTC)", "No access");
        end

        function T = computeEclipseIfAvailable(app)
            % エフェメリスデータが無い環境では、食の解析だけを省略する
            try
                T = mstudio.computeEclipse(app.Objects);
            catch err
                if err.identifier ~= "mstudio:eclipse:noEphemeris", rethrow(err), end
                T = [];
            end
        end

        function updateCoverage(app)
            % Coverage タブ: 選択した指標を格子点ごとに色で示す
            ax = app.UI.CoverageAx;
            cla(ax);
            C = app.Coverage;
            if isempty(C)
                app.UI.CoverageSummary.Value = "Coverage analysis disabled";
                return
            end
            metric = string(app.UI.CoverageMetric.Value);
            values = struct( ...
                PercentTime=C.PercentTime, MaxGap=C.MaxGap_s/60, MeanGap=C.MeanGap_s/60, ...
                Passes=C.NumAccess, MeanSats=C.MeanSats, MaxSats=C.MaxSats, MinSats=C.MinSats);
            keys = ["PercentTime","MaxGap","MeanGap","Passes","MeanSats","MaxSats","MinSats", ...
                    "MedianPDOP","PctPDOPBelow"];
            key = keys(app.UI.CoverageMetric.Items == metric);
            if ismember(key, ["MedianPDOP","PctPDOPBelow"])
                if ~isfield(C, "PDOP")
                    title(ax, "Enable 'Compute PDOP' and update");
                    return
                end
                values.(key) = C.(key);
            end
            v = values.(key);
            v(isinf(v)) = NaN;                              % 一度も見えない点は描かない

            half = app.Spec.Coverage.GridStep_deg / 2;
            markerSize = max(8, 5000 / max(numel(unique(C.Lat)), numel(unique(C.Lon)))^1.2);
            geoscatter(ax, C.Lat, C.Lon, markerSize, v, "filled", Marker="s", MarkerFaceAlpha=0.75);
            geolimits(ax, [max(-85, min(C.Lat)-half), min(85, max(C.Lat)+half)], ...
                [min(C.Lon)-half, max(C.Lon)+half]);         % 東経 180 度をまたぐ領域も可
            if key == "MedianPDOP"
                % 少数の極端に悪い点で色が潰れないよう、上位 10% は同じ色にする
                sorted = sort(v(~isnan(v)));
                if numel(sorted) > 1
                    upper = sorted(ceil(0.9 * numel(sorted)));
                    clim(ax, [sorted(1), max(upper, sorted(1) + eps)]);
                end
            end
            cb = colorbar(ax);  cb.Label.String = metric;
            title(ax, metric);

            S = C.Summary;
            app.UI.CoverageSummary.Value = [ ...
                sprintf("Grid points            : %d  (step %.1f deg, min elevation %.0f deg)", ...
                    numel(C.Lat), app.Spec.Coverage.GridStep_deg, app.Spec.Coverage.MinEl_deg)
                sprintf("Area ever covered      : %6.2f %%", S.AreaEverCovered_pct)
                sprintf("Mean area covered      : %6.2f %%  (instantaneous, time average)", S.MeanAreaCovered_pct)
                sprintf("Mean percent of time   : %6.2f %%", S.MeanPercentTime)
                sprintf("Max revisit gap, worst : %6.1f min", S.WorstMaxGap_s/60)
                sprintf("Max revisit gap, mean  : %6.1f min  (covered points only)", S.MeanMaxGap_s/60)];
        end

        function updateNavigation(app)
            % Navigation タブ: 選択した地上局から見た可視機数・最高仰角・DOP
            dd = app.UI.NavStation;
            prev = dd.Value;
            dd.Items = cellstr(app.Objects.StationNames);
            if ischar(prev) && any(strcmp(prev, dd.Items)), dd.Value = prev; end
            axes3 = [app.UI.NavCountAx, app.UI.NavElAx, app.UI.NavDopAx];
            arrayfun(@cla, axes3);

            sats = app.Objects.Assets(app.Objects.AssetKinds == "satellite");
            if isempty(sats) || isempty(dd.Items)
                app.UI.NavSummary.Value = "No satellite or ground station";
                return
            end
            station = app.Objects.Stations{app.Objects.StationNames == string(dd.Value)};
            az = [];  el = [];
            for k = 1:numel(sats)
                [az(k, :), el(k, :), ~, t] = aer(station, sats{k}); %#ok<AGROW>
            end
            minEl = station.MinElevationAngle;
            dop = mstudio.dilutionOfPrecision(az, el, minEl);

            stairs(app.UI.NavCountAx, t, dop.NumSats, LineWidth=1.3);
            yline(app.UI.NavCountAx, 4, "--k", "4 satellites");
            ylabel(app.UI.NavCountAx, sprintf("Satellites above %.0f deg", minEl));
            ylim(app.UI.NavCountAx, [0 numel(sats) + 0.5]);  grid(app.UI.NavCountAx, "on");

            plot(app.UI.NavElAx, t, max(el, [], 1), LineWidth=1.3);
            ylabel(app.UI.NavElAx, "Highest elevation [deg]");
            ylim(app.UI.NavElAx, [0 90]);  grid(app.UI.NavElAx, "on");

            semilogy(app.UI.NavDopAx, t, [dop.PDOP; dop.HDOP; dop.VDOP]', LineWidth=1.3);
            ylabel(app.UI.NavDopAx, "DOP");  grid(app.UI.NavDopAx, "on");
            legend(app.UI.NavDopAx, ["PDOP","HDOP","VDOP"], Location="best");

            solvable = ~isnan(dop.PDOP);
            app.UI.NavSummary.Value = [ ...
                sprintf("Satellites visible : min %d, mean %.2f, max %d", ...
                    min(dop.NumSats), mean(dop.NumSats), max(dop.NumSats))
                sprintf("Highest elevation  : min %.1f deg", min(max(el, [], 1)))
                sprintf("PDOP               : median %.2f, max %.2f   (solvable %.1f%% of the time)", ...
                    median(dop.PDOP, "omitnan"), max(dop.PDOP), 100*mean(solvable))];
        end

        function updateProximity(app)
            % Proximity タブ: 最接近の一覧と、選択した組の距離の時刻歴
            T = app.CloseApproaches;
            D = T;
            D.TCA = string(T.TCA, "yyyy-MM-dd HH:mm:ss.SSS");
            D.MissDistance_km = round(T.MissDistance_km, 3);
            D.RelSpeed_kmps   = round(T.RelSpeed_kmps, 3);
            app.UI.ProximityTable.Data = D;

            pairs = app.RangeHistory.Pairs;
            dd = app.UI.ProximityPair;
            prev = dd.Value;
            dd.Items = cellstr(pairs(:, 1) + " - " + pairs(:, 2));
            if ischar(prev) && any(strcmp(prev, dd.Items)), dd.Value = prev; end
            app.plotRange();
        end

        function plotRange(app)
            ax = app.UI.ProximityAx;
            cla(ax);
            R = app.RangeHistory;
            if isempty(R) || isempty(R.Pairs), return, end
            k = find(strcmp(app.UI.ProximityPair.Value, app.UI.ProximityPair.Items), 1);
            semilogy(ax, R.Time, R.Distance_km(k, :), LineWidth=1.2);
            hold(ax, "on");
            T = app.CloseApproaches;
            mine = T(T.ObjectA == R.Pairs(k, 1) & T.ObjectB == R.Pairs(k, 2), :);
            plot(ax, mine.TCA, mine.MissDistance_km, "rv", MarkerFaceColor="r");
            hold(ax, "off");
            grid(ax, "on");  ylabel(ax, "Range [km]");
            title(ax, R.Pairs(k, 1) + " - " + R.Pairs(k, 2) + ...
                sprintf("   (minimum %.3f km)", min([R.Distance_km(k, :), mine.MissDistance_km'])));
        end

        function types = eclipseTypes(app)
            types = strings(0, 1);
            if istable(app.EclipseTable), types = app.EclipseTable.Type; end
        end

        function updateEclipse(app)
            T = app.EclipseTable;
            if isempty(T) && ~istable(T)
                cla(app.UI.EclipseAx);
                title(app.UI.EclipseAx, "Ephemeris data required (run aeroDataPackage)");
                app.UI.EclipseTable.Data = table;
                return
            end
            app.UI.EclipseTable.Data = app.formatIntervalTable(T);
            app.plotTimeline(app.UI.EclipseAx, T, T.Asset + " (" + lower(T.Type) + ")", ...
                "Eclipse timeline (UTC)", "No eclipse");
        end

        function D = formatIntervalTable(~, T)
            % 区間の table を表示用に整形する (時刻は秒の小数1桁まで)
            D = T;
            D.StartTime = string(T.StartTime, "yyyy-MM-dd HH:mm:ss.S");
            D.EndTime   = string(T.EndTime,   "yyyy-MM-dd HH:mm:ss.S");
            D.Duration  = round(T.Duration);
            D = renamevars(D, "Duration", "Duration_s");
        end

        function plotTimeline(app, ax, T, rowLabels, titleText, emptyText)
            % 区間 (StartTime, EndTime) を、rowLabels ごとに1行のガントチャートで描く
            cla(ax);
            if isempty(T)
                title(ax, emptyText);  return
            end
            [labels, ~, row] = unique(rowLabels, "stable");
            colors = lines(numel(labels));
            hold(ax, "on");
            for k = 1:height(T)
                plot(ax, [T.StartTime(k) T.EndTime(k)], [row(k) row(k)], ...
                    LineWidth=8, Color=colors(row(k), :));
            end
            hold(ax, "off");
            ax.YTick = 1:numel(labels);  ax.YTickLabel = labels;
            ax.YLim  = [0.5 numel(labels) + 0.5];  ax.YDir = "reverse";
            ax.XLim  = [app.Spec.StartTime, ...
                app.Spec.StartTime + hours(app.Spec.DurationHours)];
            grid(ax, "on");  title(ax, titleText);
        end

        function updateLaunch(app)
            % Launch タブ: 上昇計算の時刻歴と到達軌道のサマリ
            L  = app.Objects.Launch;
            ax = app.UI.Launch;
            if isempty(L)
                for name = ["AltAx","SpeedAx","ProfileAx","LoadAx"], cla(ax.(name)); end
                app.UI.LaunchSummary.Value = "Launcher disabled";
                return
            end
            % 動力飛行 + 少しの慣性飛行までを表示する
            tShow = min(L.Time(end), 1.3 * L.Events.Time_s(end) + 60);
            D = L.Telemetry(L.Time <= tShow, :);
            tEvents = L.Events.Time_s(2:end);

            plot(ax.AltAx, D.Time_s, D.Alt_km, LineWidth=1.5);
            xline(ax.AltAx, tEvents, ":");
            xlabel(ax.AltAx, "Time [s]");  ylabel(ax.AltAx, "Altitude [km]");  grid(ax.AltAx, "on");

            plot(ax.SpeedAx, D.Time_s, D.Speed_mps/1e3, LineWidth=1.5);
            xline(ax.SpeedAx, tEvents, ":");
            xlabel(ax.SpeedAx, "Time [s]");  ylabel(ax.SpeedAx, "Inertial speed [km/s]");
            grid(ax.SpeedAx, "on");

            plot(ax.ProfileAx, D.Downrange_km, D.Alt_km, LineWidth=1.5);
            xlabel(ax.ProfileAx, "Downrange [km]");  ylabel(ax.ProfileAx, "Altitude [km]");
            grid(ax.ProfileAx, "on");

            yyaxis(ax.LoadAx, "left");
            plot(ax.LoadAx, D.Time_s, D.Q_kPa, LineWidth=1.5);
            ylabel(ax.LoadAx, "Dynamic pressure [kPa]");
            yyaxis(ax.LoadAx, "right");
            plot(ax.LoadAx, D.Time_s, D.Accel_g, LineWidth=1.5);
            ylabel(ax.LoadAx, "Sensed accel [g]");
            xlabel(ax.LoadAx, "Time [s]");  grid(ax.LoadAx, "on");

            o = L.Orbit;
            txt = [ ...
                sprintf("Result      : %s", upper(L.Reached))
                sprintf("Perigee alt : %8.1f km", o.PerigeeAlt_km)
                sprintf("Apogee alt  : %8.1f km", o.ApogeeAlt_km)
                sprintf("Inclination : %8.2f deg", o.Inc_deg)
                sprintf("Max Q       : %8.1f kPa", max(L.Telemetry.Q_kPa))
                sprintf("Max accel   : %8.1f g", max(L.Telemetry.Accel_g))
                ""
                compose("%-16s t=%7.1f s  h=%6.1f km  v=%5.0f m/s", L.Events.Name, ...
                    L.Events.Time_s, L.Events.Alt_km, L.Events.Speed_mps)];
            app.UI.LaunchSummary.Value = txt;
        end

        function key = lunarKey(app)
            % 月遷移の設計結果を決める条件 (設計パラメータと TLI 時刻)
            key = {app.Spec.LunarTransfer, app.Spec.StartTime};
        end

        function cache = reusableResults(app)
            % 条件が変わっていなければ、前回の月遷移設計 (約20秒かかる) を再利用する
            cache = struct();
            if ~isempty(app.Objects) && ~isempty(app.Objects.LunarTransfer) ...
                    && isequal(app.LunarCacheKey, app.lunarKey())
                cache.LunarTransfer = app.Objects.LunarTransfer;
            end
        end

        function updateLunar(app)
            % Lunar タブ: 地球中心・月中心の軌道と設計結果
            R = app.Objects.LunarTransfer;
            axE = app.UI.Lunar.EarthAx;  axM = app.UI.Lunar.MoonAx;
            cla(axE);  cla(axM);
            if isempty(R)
                app.UI.LunarSummary.Value = "Lunar transfer disabled";
                return
            end

            % --- 地球中心
            plot3(axE, R.PosEarth_km(:,1), R.PosEarth_km(:,2), R.PosEarth_km(:,3), LineWidth=1.5);
            hold(axE, "on");
            plot3(axE, R.MoonPos_km(:,1), R.MoonPos_km(:,2), R.MoonPos_km(:,3), "--", ...
                Color=[0.5 0.5 0.5]);
            plot3(axE, 0, 0, 0, "o", MarkerFaceColor=[0.2 0.4 0.9], MarkerEdgeColor="none", ...
                MarkerSize=8);
            burn = R.Thrusting & R.Phase == 1;
            plot3(axE, R.PosEarth_km(burn,1), R.PosEarth_km(burn,2), R.PosEarth_km(burn,3), ...
                "r", LineWidth=3);
            plot3(axE, R.MoonPos_km(end,1), R.MoonPos_km(end,2), R.MoonPos_km(end,3), "o", ...
                MarkerFaceColor=[0.6 0.6 0.6], MarkerEdgeColor="none", MarkerSize=6);
            hold(axE, "off");
            axis(axE, "equal");  grid(axE, "on");  view(axE, 3);
            title(axE, "Earth-centered (ICRF) [km]");
            legend(axE, ["Probe","Moon","Earth"], Location="northeast");
            % 凡例は先頭3本のみ (燃焼区間は月中心の図で示す)

            % --- 月中心 (月の近傍のみ)
            rel  = R.PosEarth_km - R.MoonPos_km;
            near = vecnorm(rel, 2, 2) < 15000;
            [sx, sy, sz] = sphere(30);
            surf(axM, 1737.4*sx, 1737.4*sy, 1737.4*sz, FaceColor=[0.7 0.7 0.7], ...
                EdgeColor="none", FaceAlpha=0.9);
            hold(axM, "on");
            arrive = near & R.Phase == 1;  orbit = near & R.Phase == 2;
            plot3(axM, rel(arrive,1), rel(arrive,2), rel(arrive,3), LineWidth=1.5);
            plot3(axM, rel(orbit,1), rel(orbit,2), rel(orbit,3), LineWidth=1.2);
            burn = near & R.Thrusting;
            plot3(axM, rel(burn,1), rel(burn,2), rel(burn,3), "r", LineWidth=3);
            hold(axM, "off");
            axis(axM, "equal");  grid(axM, "on");  view(axM, 3);
            title(axM, "Moon-centered (ICRF) [km]");
            legend(axM, ["Moon","Approach","Lunar orbit","Burn"], Location="northeast");

            app.UI.LunarSummary.Value = [ ...
                sprintf("Targeting      : %s", string(R.Converged).replace(["true","false"], ["converged","NOT converged"]))
                sprintf("TLI epoch      : %s UTC", string(R.Epoch, "yyyy-MM-dd HH:mm:ss"))
                sprintf("Burn model     : %s", R.BurnModel)
                sprintf("TLI delta-V    : %7.4f km/s   (burn %.0f s, propellant %.0f kg)", ...
                    R.DeltaV_TLI, R.TLI.Duration_s, R.TLI.Propellant_kg)
                sprintf("LOI delta-V    : %7.4f km/s   (burn %.0f s, propellant %.0f kg)", ...
                    R.DeltaV_LOI, R.LOI.Duration_s, R.LOI.Propellant_kg)
                sprintf("Transfer time  : %7.3f days", R.TransferDays)
                sprintf("Approach       : perilune %.2f km, inclination %.2f deg", ...
                    R.PeriluneAlt_km, R.LunarInc_deg)
                sprintf("Orbit after LOI: %.1f x %.1f km", R.LunarOrbitAlt_km)
                sprintf("Parking RAAN   : %7.2f deg,  TLI arg. of latitude %.2f deg", ...
                    R.RAAN_deg, R.ArgLat_deg)];
        end

        function updatePairPlots(app)
            % AER と Link Budget を、それぞれのタブで選択中のペアについて描画する
            if isempty(app.Objects) || isempty(app.Objects.Assets) ...
                    || isempty(app.Objects.Stations)
                return
            end
            try
                [asset, station, label, valid] = app.selectedPair(app.UI.PairAER);
                app.plotAER(asset, station, label, valid);
                [asset, station, label, valid] = app.selectedPair(app.UI.PairLink);
                app.plotLink(asset, station, label, valid);
            catch err
                uialert(app.Fig, err.message, "解析エラー");
            end
        end

        function [asset, station, label, valid] = selectedPair(app, sel)
            % valid はビークルのデータが有効な時間範囲 [開始, 終了]
            iAsset  = app.Objects.AssetNames == string(sel.Asset.Value);
            asset   = app.Objects.Assets{iAsset};
            valid   = app.Objects.ValidRange(iAsset, :);
            station = app.Objects.Stations{app.Objects.StationNames == string(sel.Station.Value)};
            label   = string(sel.Asset.Value) + " → " + string(sel.Station.Value);
        end

        function plotAER(app, asset, station, label, valid)
            [~, el, rng, t] = aer(station, asset);
            outside = t < valid(1) | t > valid(2);
            el(outside) = NaN;  rng(outside) = NaN;
            minEl = station.MinElevationAngle;

            ax = app.UI.ElAx;
            plot(ax, t, el, LineWidth=1.5);
            yline(ax, minEl, "--r", "Min elevation");
            ylabel(ax, "Elevation [deg]");  grid(ax, "on");
            title(ax, label);

            ax = app.UI.RangeAx;
            plot(ax, t, rng/1e3, LineWidth=1.5);
            ylabel(ax, "Range [km]");  grid(ax, "on");
        end

        function plotLink(app, asset, station, label, valid)
            link = app.Spec.Link;
            noMaps = link.IncludeAtmosphere && ~mstudio.hasItuMaps();
            if noMaps, link.IncludeAtmosphere = false; end      % マップが無ければ晴天時のみ
            r = mstudio.computeLinkBudget(asset, station, link);
            if noMaps, label = label + "  [no ITU-R maps: clear sky only]"; end
            outside = r.Time < valid(1) | r.Time > valid(2);
            r.EbNo(outside) = NaN;  r.Margin(outside) = NaN;

            ax = app.UI.LinkAx;
            plot(ax, r.Time, r.EbNoClear, ":", LineWidth=1.2, DisplayName="Clear sky");
            hold(ax, "on");
            plot(ax, r.Time, r.EbNo, LineWidth=1.5, DisplayName=sprintf( ...
                "With atmosphere (%.3g%% availability)", app.Spec.Link.Availability_pct));
            hold(ax, "off");
            yline(ax, app.Spec.Link.RequiredEbNo, "--r", "Required Eb/No", HandleVisibility="off");
            ylabel(ax, "Eb/No [dB]");  grid(ax, "on");
            legend(ax, Location="best");
            if all(isnan(r.Margin))
                title(ax, label + "  (no link)");
            else
                title(ax, sprintf("%s   min margin %.1f dB / max %.1f dB", ...
                    label, min(r.Margin), max(r.Margin)));
            end
        end
    end
end
