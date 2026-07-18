import AppKit
import KokukokuCore

/// UI Panelの表示・操作(元 ui_panel.lua の M.new が返すオブジェクト相当)。
/// 描画要素の構築はKokukokuCoreのPanelElementsBuilderに任せ、
/// ここではウィンドウ・イベント・状態遷移だけを扱う。
@MainActor
final class PanelController {
    struct Callbacks {
        var onProjectSelect: (String) -> Void
        var onBreak: () -> Void
        var onReset: () -> Void
        var onSetAccumulated: (String, Int) -> Void
        var onSetContinuous: (Int) -> Void
        var getState: () -> TimerState
        /// カレンダー連携の現在状態。nil = 連携無効(セクション非表示)
        var getCalendarState: () -> CalendarPanelState?
    }

    private let projects: [KokukokuConfig.Project]
    private let alertThresholds: [Int]
    private let ui: ResolvedUIConfig
    private let keymap: ResolvedKeymap
    private let callbacks: Callbacks
    private let iconStore = IconStore()
    private let metrics: PanelMetrics
    private let now: () -> Int = { Int(Date().timeIntervalSince1970) }

    private var window: PanelWindow?
    private var panelView: PanelView?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private(set) var visible = false
    private var selectedIndex: Int?  // 1-origin (Luaと同じ)
    private var hoveredId: String?
    private var resetConfirming = false
    private var inlineEditor: InlineTimeEditor?
    private var editingTarget: PanelEditingTarget?
    /// 現在表示中の予定セクション行(クリック時のMeet URL解決とパネル高計算に使う)
    private var calendarRows: [CalendarSectionRow] = []
    /// 通知モード: 開始前通知としての自動表示中(フォーカス非奪取・外クリックで閉じない)
    private(set) var notificationMode = false
    /// 通知で強調する予定
    private var highlightedKeys: Set<CalendarEvent.EventKey> = []
    /// 通知パネルが閉じたときに呼ばれる(中止告知のクリア用)
    var onNotificationClosed: (() -> Void)?

    init(
        projects: [KokukokuConfig.Project],
        alertThresholds: [Int],
        ui: ResolvedUIConfig,
        keymap: ResolvedKeymap,
        callbacks: Callbacks
    ) {
        self.projects = projects
        self.alertThresholds = alertThresholds
        self.ui = ui
        self.keymap = keymap
        self.callbacks = callbacks
        // パネル幅は最長プロジェクト名の実測幅で決める(プロジェクトは設定再読込まで不変)
        let nameFont = NSFont(name: ui.fontName, size: 16) ?? NSFont.systemFont(ofSize: 16)
        self.metrics = PanelMetrics.compute(
            projectNames: projects.map(\.name),
            measureNameWidth: { name in
                Double((name as NSString).size(withAttributes: [.font: nameFont]).width)
            })
        iconStore.onLoad = { [weak self] in self?.rebuildPanel() }
    }

    // MARK: - 公開操作 (show / hide / toggle / update)

    /// 開始前通知としてパネルを自動表示する(該当予定を強調)。
    /// 既に通知パネル表示中なら同じパネルにまとめて強調を足す。
    /// 通常パネル表示中なら畳んで通知パネルとして出し直す
    func showCalendarNotification(keys: Set<CalendarEvent.EventKey>) {
        if visible, notificationMode {
            highlightedKeys.formUnion(keys)
            rebuildPanel()
            return
        }
        if visible { hide() }
        notificationMode = true
        highlightedKeys = keys
        show()
    }

    func show() {
        if visible, window != nil { return }

        resetConfirming = false

        // カーソル初期位置をアクティブプロジェクトに設定(通知モードはカーソルなし)
        let state = callbacks.getState()
        selectedIndex = notificationMode
            ? nil
            : state.activeProjectId.flatMap { activeId in
                projects.firstIndex { $0.id == activeId }.map { $0 + 1 }
            }

        calendarRows = currentCalendarRows()
        let panelSize = NSSize(
            width: metrics.panelWidth,
            height: PanelLayout.panelHeight(
                projectCount: projects.count,
                calendarSectionHeight: PanelLayout.calendarSectionHeight(rows: calendarRows)))

        // アクティブモニタ(マウスカーソルのあるスクリーン)の中央に表示
        let screen = screenForMousePosition()
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2)

        let window = PanelWindow(contentRect: NSRect(origin: origin, size: panelSize))
        let panelView = PanelView(frame: NSRect(origin: .zero, size: panelSize))
        window.contentView = panelView

        panelView.imageProvider = { [weak self] key in self?.iconStore.image(forKey: key) }
        panelView.onMouseDown = { [weak self] id in self?.handleClick(elementId: id) }
        panelView.onHoverChange = { [weak self] id in
            guard let self else { return }
            self.hoveredId = id
            self.rebuildPanel()
        }
        window.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }

        self.window = window
        self.panelView = panelView
        visible = true
        rebuildPanel()

        if notificationMode {
            // 通知パネルはキーボードフォーカスも奪わず、外クリックでは閉じない
            // (閉じるのはパネル上の閉じるボタンか既存のパネルトグルホットキー)
            window.orderFrontRegardless()
            return
        }
        window.makeKeyAndOrderFront(nil)

        // パネル外クリックで閉じる(他アプリ宛はグローバル、自アプリ宛はローカルの両モニタで拾う)
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] _ in
            self?.hideIfClickedOutside()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] event in
            self?.hideIfClickedOutside()
            return event
        }
    }

    private func hideIfClickedOutside() {
        guard let window else { return }
        if !window.frame.contains(NSEvent.mouseLocation) {
            hide()
        }
    }

    func hide() {
        inlineEditor?.field.removeFromSuperview()
        inlineEditor = nil
        editingTarget = nil
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        window?.orderOut(nil)
        window?.alphaValue = 1
        window = nil
        panelView = nil
        visible = false
        selectedIndex = nil
        hoveredId = nil
        resetConfirming = false
        if notificationMode {
            notificationMode = false
            highlightedKeys = []
            onNotificationClosed?()
        }
    }

    func toggle() {
        if visible {
            hide()
        } else {
            show()
        }
    }

    func update() {
        rebuildPanel()
    }

    // MARK: - 描画

    /// 予定セクションの行データ列を最新のカレンダー状態から組み立てる。
    /// 強調・中止告知・鮮度表示は通知モードのときだけ乗せる
    private func currentCalendarRows() -> [CalendarSectionRow] {
        guard var state = callbacks.getCalendarState() else { return [] }
        if notificationMode {
            state.highlightedKeys = highlightedKeys
        } else {
            state.notices = []
        }
        return CalendarSectionModel.rows(
            state: state, now: Date(), includeFreshness: notificationMode)
    }

    /// 表示中に予定の行数が変わった場合、画面中央位置を維持したままウィンドウ高を追従させる
    private func resizeWindowIfNeeded() {
        guard let window else { return }
        let height = PanelLayout.panelHeight(
            projectCount: projects.count,
            calendarSectionHeight: PanelLayout.calendarSectionHeight(rows: calendarRows))
        guard abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        let centerY = frame.midY
        frame.size.height = height
        frame.origin.y = centerY - height / 2
        window.setFrame(frame, display: true)
    }

    private func rebuildPanel() {
        guard visible, let panelView else { return }

        calendarRows = currentCalendarRows()
        resizeWindowIfNeeded()

        let builder = PanelElementsBuilder(
            now: now,
            localTime: {
                let parts = Calendar.current.dateComponents(
                    [.hour, .minute, .second], from: Date())
                return ClockTime(
                    hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0)
            },
            measureTextHeight: { text, fontName, size in
                let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
                let measured = (text.isEmpty ? " " : text as NSString).size(
                    withAttributes: [.font: font])
                let height = Double(measured.height.rounded(.up))
                return height > 0 ? height : max(size + 8, size)
            },
            measureTextWidth: { text, fontName, size in
                let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
                return Double((text as NSString).size(withAttributes: [.font: font]).width)
            },
            resolveIcon: { [iconStore] icon in iconStore.resolve(icon) },
            hasLogoImage: iconStore.logoImage != nil,
            metrics: metrics
        )
        panelView.elements = builder.build(
            .init(
                projects: projects,
                state: callbacks.getState(),
                selectedIndex: selectedIndex,
                hoveredId: hoveredId,
                resetConfirming: resetConfirming,
                editingTarget: editingTarget,
                alertThresholds: alertThresholds,
                calendarRows: calendarRows,
                showsCalendarCloseButton: notificationMode,
                ui: ui))
    }

    // MARK: - 操作の実行

    /// 切替後もパネルは開いたまま(閉じるのはESC)。計測中行のネオンが切替成功の合図になる。
    /// 計測中のプロジェクトを再選択した場合はトグルとして休憩に入る
    private func selectProject(_ projectId: String) {
        resetConfirming = false
        if callbacks.getState().activeProjectId == projectId {
            callbacks.onBreak()
        } else {
            callbacks.onProjectSelect(projectId)
        }
        rebuildPanel()
    }

    private func handleResetAction() {
        if resetConfirming {
            resetConfirming = false
            callbacks.onReset()
        } else {
            resetConfirming = true
        }
        rebuildPanel()
    }

    /// キーボード選択はプロジェクト行のみ(休憩は再選択トグル、リセットはキー・クリックで行う)
    private func executeSelectedAction() {
        guard let selectedIndex, selectedIndex <= projects.count else { return }
        selectProject(projects[selectedIndex - 1].id)
    }

    private func editSelectedProjectTime() {
        guard let selectedIndex, selectedIndex <= projects.count else { return }
        let project = projects[selectedIndex - 1]
        let state = callbacks.getState()

        var currentAccumulated = state.accumulated[project.id] ?? 0
        if state.activeProjectId == project.id, let startedAt = state.activeStartedAt {
            currentAccumulated += now() - startedAt
        }
        beginInlineEdit(.project(id: project.id), initialSeconds: currentAccumulated)
    }

    private func editContinuousTime() {
        let state = callbacks.getState()
        var continuousElapsed = state.continuousElapsedBase
        if let startedAt = state.continuousStartedAt {
            continuousElapsed += now() - startedAt
        }
        beginInlineEdit(.continuous, initialSeconds: continuousElapsed)
    }

    // MARK: - インライン時間編集

    /// 時刻表示の位置に編集フィールドを重ねる。編集中は下の時刻テキストを描画しない
    private func beginInlineEdit(_ target: PanelEditingTarget, initialSeconds: Int) {
        guard let window, let panelView else { return }
        endInlineEdit()

        let frame: PanelFrame
        let fontSize: Double
        let alignment: NSTextAlignment
        let centerY: Double
        switch target {
        case .continuous:
            let calendarHeight = PanelLayout.calendarSectionHeight(rows: calendarRows)
            frame = metrics.continuousTimeFrame(
                projectCount: projects.count, calendarSectionHeight: calendarHeight)
            fontSize = 16
            alignment = .left
            // フッターの時刻テキストは枠の上寄りに描かれるため、
            // 枠中心やなくフッターの見た目の中心に合わせる
            let footerY =
                PanelLayout.clockSectionHeight
                + Double(projects.count) * PanelLayout.rowHeight
                + calendarHeight
            centerY = footerY + PanelLayout.footerHeight / 2
        case .project(let id):
            guard let offset = projects.firstIndex(where: { $0.id == id }) else { return }
            frame = metrics.accumulatedTimeFrame(
                rowOffset: offset,
                calendarSectionHeight: PanelLayout.calendarSectionHeight(rows: calendarRows))
            fontSize = 16
            alignment = .right
            centerY = frame.y + frame.h / 2
        }
        let editorHeight = fontSize + 8
        let editor = InlineTimeEditor(
            frame: .zero,
            text: TimerEngine.formatTime(initialSeconds),
            fontName: ui.monoFontName,
            fontSize: fontSize,
            alignment: alignment)
        // 入力欄の幅はフィールド自身の実測(sizeToFit=セル内側余白込み)に任せ、
        // 時刻文字列へぴったり重ねる。列幅基準やと右寄せ時刻の左に空白が余る。
        // ±3はセル内側余白+枠線の分で、フィールド内の文字を元の描画位置に揃える補正
        editor.field.sizeToFit()
        let editorWidth = editor.field.frame.width.rounded(.up)
        let editorX = alignment == .right ? frame.x + frame.w - editorWidth + 3 : frame.x - 3
        editor.field.frame = NSRect(
            x: editorX, y: centerY - editorHeight / 2,
            width: editorWidth, height: editorHeight)
        editor.onCommit = { [weak self] text in self?.commitInlineEdit(text) }
        editor.onCancel = { [weak self] in self?.endInlineEdit() }

        panelView.addSubview(editor.field)
        inlineEditor = editor
        editingTarget = target
        rebuildPanel()

        editor.activate(in: window)
    }

    private func commitInlineEdit(_ text: String) {
        guard let editingTarget else { return }
        guard let seconds = TimeInput.parse(text), seconds >= 0 else {
            inlineEditor?.markInvalid()
            return
        }
        switch editingTarget {
        case .project(let id):
            callbacks.onSetAccumulated(id, seconds)
        case .continuous:
            callbacks.onSetContinuous(seconds)
        }
        endInlineEdit()
    }

    private func endInlineEdit() {
        guard editingTarget != nil else { return }
        window?.makeFirstResponder(nil)
        inlineEditor?.field.removeFromSuperview()
        inlineEditor = nil
        editingTarget = nil
        rebuildPanel()
    }

    private func copyToClipboard() {
        let text = CopyText.build(
            projects: projects,
            state: callbacks.getState(),
            lineFormat: ui.copyTextFormat,
            separator: "\n",
            now: now)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
    }

    // MARK: - イベントハンドリング

    private func handleClick(elementId: String) {
        if editingTarget != nil { endInlineEdit() }

        if elementId.hasPrefix("row_") {
            selectProject(String(elementId.dropFirst(4)))
            return
        } else if elementId == "btn_reset" {
            handleResetAction()
            return
        } else if elementId == "btn_cal_close" {
            hide()
            return
        } else if elementId.hasPrefix("cal_event_") {
            openCalendarDetail(eventIndex: Int(elementId.dropFirst("cal_event_".count)) ?? -1)
            return
        }
        rebuildPanel()
    }

    /// 処理したらtrue(イベントを飲む)。Luaのeventtap返値と同じ意味
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 編集中のキーはフィールド側が処理する(こぼれたキーでパネル操作が走らないよう飲む)
        if editingTarget != nil { return true }

        let action = PanelKeyInterpreter.interpret(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            keymap: keymap)

        switch action {
        case .dismiss:
            hide()
        case .confirm:
            if selectedIndex != nil {
                executeSelectedAction()
            }
        case .moveDown:
            selectedIndex = PanelSelection.nextIndex(
                current: selectedIndex, projectCount: projects.count)
            rebuildPanel()
        case .moveUp:
            selectedIndex = PanelSelection.previousIndex(
                current: selectedIndex, projectCount: projects.count)
            rebuildPanel()
        case .startBreak:
            resetConfirming = false
            callbacks.onBreak()
            rebuildPanel()
        case .reset:
            handleResetAction()
        case .editTime:
            editSelectedProjectTime()
        case .editContinuousTime:
            editContinuousTime()
        case .copyToClipboard:
            copyToClipboard()
        case .selectProject(let index):
            if index <= projects.count {
                selectProject(projects[index - 1].id)
            }
        case .passthrough:
            return false
        }
        return true
    }

    /// 予定行クリックでカレンダーの詳細ページをブラウザで開く(初期仕様の操作はマウスのみ)
    private func openCalendarDetail(eventIndex: Int) {
        let eventRows: [CalendarEventRow] = calendarRows.compactMap {
            if case .event(let row) = $0 { return row } else { return nil }
        }
        guard eventIndex >= 0, eventIndex < eventRows.count,
            let url = eventRows[eventIndex].detailURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func screenForMousePosition() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
