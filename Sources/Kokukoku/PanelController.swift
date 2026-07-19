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
    /// キーボード選択の対象(予定行・トグル行・プロジェクト行の統一ループ)
    private var selectedTarget: PanelSelectionTarget?
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
    /// 「他◯件」クリックでの全件展開中(パネルを閉じると畳んだ状態に戻る)
    private var calendarExpanded = false

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
            // 表示中のパネルへの合流も新しい通知の到着なので、署名をもう一撃打つ
            playNotificationPulse()
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
        selectedTarget = notificationMode
            ? nil
            : state.activeProjectId.flatMap { activeId in
                projects.firstIndex { $0.id == activeId }.map { .project(index: $0 + 1) }
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
            // (閉じるのはパネルをクリックしてキーにした後のEscか、既存のパネルトグルホットキー。
            // 閉じるボタンは1クリック目がキー化に消費されて2クリック要る体験になるため廃止)
            window.orderFrontRegardless()
            playNotificationPulse()
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

    /// 登場の署名: 通知としての自動表示の瞬間だけ、パネル輪郭を生成りのグローで
    /// 3回明滅させて静止する(周辺視野は動きに反応するため、音を使わずに気づかせる。
    /// 常時脈動はしない。2026-07-19 タダシ決定: 音・macOS通知併送は不採用で演出一本)
    private func playNotificationPulse() {
        guard let panelView else { return }
        panelView.wantsLayer = true
        guard let hostLayer = panelView.layer else { return }

        let cream = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.83, alpha: 1).cgColor
        let pulse = CAShapeLayer()
        pulse.path = CGPath(
            roundedRect: panelView.bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: 10, cornerHeight: 10, transform: nil)
        pulse.fillColor = nil
        pulse.strokeColor = cream
        pulse.lineWidth = 2.5
        pulse.shadowColor = cream
        pulse.shadowOpacity = 0.9
        pulse.shadowRadius = 10
        pulse.shadowOffset = .zero
        pulse.opacity = 0
        hostLayer.addSublayer(pulse)

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 0.1, 1, 0.1, 1, 0]
        animation.duration = 1.6
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak pulse] in pulse?.removeFromSuperlayer() }
        pulse.add(animation, forKey: "notificationPulse")
        CATransaction.commit()
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
        selectedTarget = nil
        hoveredId = nil
        resetConfirming = false
        calendarExpanded = false
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
            state: state, now: Date(), includeFreshness: notificationMode,
            expanded: calendarExpanded)
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

        // 予定の増減で選択対象の行が消えた場合は選択を外す(幽霊選択の防止)
        if let target = selectedTarget, !selectionTargets().contains(target) {
            selectedTarget = nil
        }

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
            metrics: metrics
        )
        panelView.elements = builder.build(
            .init(
                projects: projects,
                state: callbacks.getState(),
                selectedTarget: selectedTarget,
                hoveredId: hoveredId,
                resetConfirming: resetConfirming,
                editingTarget: editingTarget,
                alertThresholds: alertThresholds,
                calendarRows: calendarRows,
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

    /// 現在の表示内容から選択ループの巡回順を組み立てる(予定セクション→プロジェクト行)
    private func selectionTargets() -> [PanelSelectionTarget] {
        PanelSelection.targets(calendarRows: calendarRows, projectCount: projects.count)
    }

    /// Enterの確定動作は選択対象で分岐する。プロジェクト行=計測切替、
    /// 予定行=詳細ページを開いてパネルを閉じる(クリックと同じ)、トグル行=展開/畳む
    private func executeSelectedAction() {
        switch selectedTarget {
        case .project(let index):
            guard index <= projects.count else { return }
            selectProject(projects[index - 1].id)
        case .calendarEvent(let eventIndex):
            openCalendarDetail(eventIndex: eventIndex)
        case .calendarOverflow:
            // キーボードで展開したときは、カーソルを展開で現れた先頭の予定へ進める
            let shownEventCount = calendarRows.reduce(0) {
                if case .event = $1 { return $0 + 1 } else { return $0 }
            }
            calendarExpanded = true
            selectedTarget = .calendarEvent(eventIndex: shownEventCount)
            rebuildPanel()
        case .calendarCollapse:
            // 畳んだ後もループ内の同じ場所(「他◯件」行)にカーソルを留める
            calendarExpanded = false
            selectedTarget = .calendarOverflow
            rebuildPanel()
        case nil:
            break
        }
    }

    /// 予定の展開/畳むをキー1発でトグルする。「他◯件/畳む」行がない(全件表示済み)ときは何もしない
    private func toggleCalendarExpansion() {
        let hasToggleRow = calendarRows.contains {
            if case .overflow = $0 { return true }
            if case .collapse = $0 { return true }
            return false
        }
        guard hasToggleRow else { return }
        calendarExpanded.toggle()
        rebuildPanel()
    }

    private func editSelectedProjectTime() {
        guard case .project(let index)? = selectedTarget, index <= projects.count else { return }
        let project = projects[index - 1]
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
        // 連続稼働はラベルが実測幅の中央寄せ描画になったため、編集フィールドも枠中央へ置く
        let editorX: Double
        if case .continuous = target {
            editorX = frame.x + (frame.w - editorWidth) / 2
        } else if alignment == .right {
            editorX = frame.x + frame.w - editorWidth + 3
        } else {
            editorX = frame.x - 3
        }
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
        } else if elementId == "cal_overflow" {
            calendarExpanded = true
            rebuildPanel()
            return
        } else if elementId == "cal_collapse" {
            calendarExpanded = false
            rebuildPanel()
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
            executeSelectedAction()
        case .moveDown:
            selectedTarget = PanelSelection.next(
                current: selectedTarget, in: selectionTargets())
            rebuildPanel()
        case .moveUp:
            selectedTarget = PanelSelection.previous(
                current: selectedTarget, in: selectionTargets())
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
        case .toggleCalendar:
            toggleCalendarExpansion()
        case .selectProject(let index):
            if index <= projects.count {
                selectProject(projects[index - 1].id)
            }
        case .passthrough:
            return false
        }
        return true
    }

    /// 予定行のクリック・Enterでカレンダーの詳細ページをブラウザで開く。
    /// フォーカスがブラウザへ移るためパネルは閉じる(戻すよりホットキー再表示のほうが楽。
    /// 2026-07-19 タダシ決定)
    private func openCalendarDetail(eventIndex: Int) {
        let eventRows: [CalendarEventRow] = calendarRows.compactMap {
            if case .event(let row) = $0 { return row } else { return nil }
        }
        guard eventIndex >= 0, eventIndex < eventRows.count,
            let url = eventRows[eventIndex].detailURL
        else { return }
        NSWorkspace.shared.open(url)
        hide()
    }

    private func screenForMousePosition() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
