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
    }

    private let projects: [KokukokuConfig.Project]
    private let breakItem: KokukokuConfig.BreakItem?
    private let ui: ResolvedUIConfig
    private let keymap: ResolvedKeymap
    private let versionText: String
    private let callbacks: Callbacks
    private let iconStore = IconStore()
    private let now: () -> Int = { Int(Date().timeIntervalSince1970) }

    private var window: PanelWindow?
    private var panelView: PanelView?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private(set) var visible = false
    private var isVersionVisible: Bool
    private var selectedIndex: Int?  // 1-origin (Luaと同じ)
    private var hoveredId: String?
    private var isClosing = false
    private var resetConfirming = false
    private var feedbackWorkItem: DispatchWorkItem?
    private var inlineEditor: InlineTimeEditor?
    private var editingTarget: PanelEditingTarget?

    private static let feedbackDelay: TimeInterval = 0.4
    private static let fadeDuration: TimeInterval = 0.3

    init(
        projects: [KokukokuConfig.Project],
        breakItem: KokukokuConfig.BreakItem?,
        ui: ResolvedUIConfig,
        keymap: ResolvedKeymap,
        versionText: String,
        callbacks: Callbacks
    ) {
        self.projects = projects
        self.breakItem = breakItem
        self.ui = ui
        self.keymap = keymap
        self.versionText = versionText
        self.callbacks = callbacks
        self.isVersionVisible = ui.showVersionByDefault
        iconStore.onLoad = { [weak self] in self?.rebuildPanel() }
    }

    // MARK: - 公開操作 (show / hide / toggle / update)

    func show() {
        if visible, window != nil { return }

        isVersionVisible = ui.showVersionByDefault
        resetConfirming = false

        // カーソル初期位置をアクティブプロジェクトに設定
        let state = callbacks.getState()
        selectedIndex = state.activeProjectId.flatMap { activeId in
            projects.firstIndex { $0.id == activeId }.map { $0 + 1 }
        }

        let panelSize = NSSize(
            width: PanelLayout.panelWidth,
            height: PanelLayout.panelHeight(projectCount: projects.count))

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
            guard let self, !self.isClosing else { return }
            self.hoveredId = id
            self.rebuildPanel()
        }
        window.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }

        self.window = window
        self.panelView = panelView
        visible = true
        rebuildPanel()
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
        feedbackWorkItem?.cancel()
        feedbackWorkItem = nil
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
        isVersionVisible = ui.showVersionByDefault
        selectedIndex = nil
        hoveredId = nil
        isClosing = false
        resetConfirming = false
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

    private func rebuildPanel() {
        guard visible, let panelView else { return }

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
            resolveIcon: { [iconStore] icon in iconStore.resolve(icon) },
            hasLogoImage: iconStore.logoImage != nil
        )
        panelView.elements = builder.build(
            .init(
                projects: projects,
                breakItem: breakItem,
                state: callbacks.getState(),
                selectedIndex: selectedIndex,
                hoveredId: hoveredId,
                isVersionVisible: isVersionVisible,
                resetConfirming: resetConfirming,
                versionText: versionText,
                editingTarget: editingTarget,
                ui: ui))
    }

    // MARK: - 操作の実行

    private func selectProject(_ projectId: String) {
        resetConfirming = false
        let isAlreadyActive = callbacks.getState().activeProjectId == projectId
        callbacks.onProjectSelect(projectId)
        if !isAlreadyActive, ui.closeOnSwitch {
            hideWithFeedback(projectId: projectId)
        } else {
            rebuildPanel()
        }
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

    private func executeSelectedAction() {
        guard let selectedIndex else { return }
        if selectedIndex <= projects.count {
            selectProject(projects[selectedIndex - 1].id)
        } else if selectedIndex == projects.count + 1 {
            resetConfirming = false
            callbacks.onBreak()
            rebuildPanel()
        } else if selectedIndex == projects.count + 2 {
            handleResetAction()
        }
    }

    /// 選択行をハイライトし、少し置いてからフェードアウトして閉じる
    private func hideWithFeedback(projectId: String) {
        guard let window, let panelView, visible else { return }

        isClosing = true
        panelView.elements = panelView.elements.map { element in
            if case .rectangle(let frame, _, let radius, _, _, let id, let tracks) = element,
                id == "row_\(projectId)"
            {
                return .rectangle(
                    frame: frame, fillColor: PanelLayout.colors.switchSuccessBg,
                    cornerRadius: radius, id: id, tracksMouse: tracks)
            }
            return element
        }

        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                window.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    // フェード中に閉じて再表示された場合、新しいパネルを巻き込まない
                    guard let self, self.window === window else { return }
                    self.hide()
                }
            }
        }
        feedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedbackDelay, execute: workItem)
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
            frame = PanelLayout.continuousTimeFrame
            fontSize = 16
            alignment = .left
            // ヘッダーの時刻テキストは枠の上寄りに描かれるため、
            // 枠中心やなくヘッダーの見た目の中心に合わせる
            centerY = PanelLayout.clockSectionHeight + PanelLayout.headerHeight / 2
        case .project(let id):
            guard let offset = projects.firstIndex(where: { $0.id == id }) else { return }
            frame = PanelLayout.accumulatedTimeFrame(rowOffset: offset)
            fontSize = 14
            alignment = .right
            centerY = frame.y + frame.h / 2
        }
        let editorHeight = fontSize + 8
        let rect = NSRect(
            x: frame.x - 4, y: centerY - editorHeight / 2,
            width: frame.w + 8, height: editorHeight)

        let editor = InlineTimeEditor(
            frame: rect,
            text: TimerEngine.formatTime(initialSeconds),
            fontName: ui.monoFontName,
            fontSize: fontSize,
            alignment: alignment)
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
            separator: ui.copyTextSeparator,
            now: now)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
    }

    // MARK: - イベントハンドリング

    private func handleClick(elementId: String) {
        guard !isClosing else { return }
        if editingTarget != nil { endInlineEdit() }

        if elementId.hasPrefix("row_") {
            selectProject(String(elementId.dropFirst(4)))
            return
        } else if elementId == "btn_break" {
            resetConfirming = false
            callbacks.onBreak()
        } else if elementId == "btn_reset" {
            handleResetAction()
            return
        }
        rebuildPanel()
    }

    /// 処理したらtrue(イベントを飲む)。Luaのeventtap返値と同じ意味
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if isClosing { return true }
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
        case .toggleVersion:
            isVersionVisible.toggle()
            rebuildPanel()
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

    private func screenForMousePosition() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
