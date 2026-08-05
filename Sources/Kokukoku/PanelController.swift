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
    /// パネル操作として扱わない修飾キー(Cmd-Q等のOS標準ショートカットを妨げないための判定)。
    /// 矢印キーはOSが常に .function (と .numericPad) を立てて送ってくるため、
    /// ここに .function を含めると矢印単押しまで「修飾キー付き」になってしまう。
    /// ShiftはGなど大文字の固定キー入力に使うため、修飾キーとして扱わない
    private static let navigationModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

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
    /// show()のmakeKeyAndOrderFront直後のキー化ではフォーカスグローを出さない(表示自体がフィードバック)
    private var suppressFocusGlow = false
    /// 通知で強調する予定(開始前通知の対象)
    private var highlightedKeys: Set<CalendarEvent.EventKey> = []
    /// 通知で強調する予定(終了前通知の対象。進行中の間だけハローが灯る)
    private var endHighlightedKeys: Set<CalendarEvent.EventKey> = []
    /// 通知パネルが閉じたときに呼ばれる(中止告知のクリア用)
    var onNotificationClosed: (() -> Void)?
    /// 「他◯件」クリックでの全件展開中(パネルを閉じると畳んだ状態に戻る)
    private var calendarExpanded = false
    /// パネル固定(Pin): onのとき外クリックでパネルが閉じない
    private var pinned = false
    /// 予定詳細ポップオーバー(表示中のみ保持)
    private var eventPopover: EventDetailPopover?
    /// 通知モードでループ再生中のパルスレイヤー(キー化で停止・除去する)
    private var notificationPulseLayer: CAShapeLayer?
    /// 連続稼働の蝋燭のうち動く部分(動かすためだけに本体と分けたレイヤー)
    private var candleFlameLayer: CALayer?
    private var candleFlameKey: String?
    /// 前回描画時に炎があったか。点火・吹き消しの遷移演出の判定に使う。
    /// nilは「不明」(パネルを開いた直後・蝋燭ごと非表示)で、遷移とは扱わない。
    /// レイヤーの生死だけで判定すると、計測中にパネルを開いた瞬間まで点火に見えてしまう
    private var candleFlameWasPresent: Bool?
    /// 煙は枠(マスク付き)と、その中を上へ流れる絵の二段構え
    private var candleSmokeLayer: CALayer?
    private var candleSmokeArtLayer: CALayer?
    private var candleSmokeKey: String?
    /// パネルがフォーカスを得る直前に前面だったアプリ(Pin中のESC/q・ホットキーで戻す先)。
    /// パネルは.nonactivatingPanelでアプリ自体をアクティブ化しないため、
    /// キー化の時点でもfrontmostApplicationは直前のアプリのまま残っている
    private var previousApplication: NSRunningApplication?

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
            },
            minWidth: ui.panelMinWidth,
            maxWidth: ui.panelMaxWidth)
        iconStore.onLoad = { [weak self] in self?.rebuildPanel() }
    }

    // MARK: - 公開操作 (show / hide / toggle / update)

    /// 開始前・終了前通知としてパネルを自動表示する(該当予定を強調)。
    /// 既に通知パネル表示中なら同じパネルにまとめて強調を足す。
    /// 通常パネル表示中なら畳んで通知パネルとして出し直す
    func showCalendarNotification(
        keys: Set<CalendarEvent.EventKey>,
        endKeys: Set<CalendarEvent.EventKey> = []
    ) {
        if visible, notificationMode {
            highlightedKeys.formUnion(keys)
            endHighlightedKeys.formUnion(endKeys)
            rebuildPanel()
            // 表示中のパネルへの合流も新しい通知の到着なので、署名をもう一撃打つ
            playNotificationPulse()
            return
        }
        if visible { hide() }
        notificationMode = true
        highlightedKeys = keys
        endHighlightedKeys = endKeys
        show()
    }

    func show() {
        if visible, window != nil { return }

        resetConfirming = false

        // カーソル初期位置をアクティブプロジェクトに設定(通知モードはカーソルなし)
        selectedTarget = initialSelectedTarget()

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

        window.onBecomeKey = { [weak self] in self?.handleBecomeKey() }
        window.onResignKey = { [weak self] in self?.handleResignKey() }

        if notificationMode {
            // 通知パネルはキーボードフォーカスを奪わず、キー化前は外クリックでも閉じない
            // (気づく前に誤クリックで消えるのを防ぐ。パネルをクリックしてキーにした後は
            // 通常パネルと同じく外クリックで閉じる。閉じるボタンは1クリック目が
            // キー化に消費されて2クリック要る体験になるため廃止)
            window.orderFrontRegardless()
            playNotificationPulse()
            return
        }
        suppressFocusGlow = true
        window.makeKeyAndOrderFront(nil)
        suppressFocusGlow = false
        installOutsideClickMonitors()
    }

    /// パネル外クリックで閉じる(他アプリ宛はグローバル、自アプリ宛はローカルの両モニタで拾う)。
    /// ローカルモニタはpopover表示中のESCも拾う: NSPopoverが自分だけアニメーション付きで
    /// 閉じる前に横取りし、パネルごと即時に一発で閉じる
    private func installOutsideClickMonitors() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] _ in
            self?.hideIfClickedOutside()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown])
        { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if self.eventPopover != nil,
                    event.modifierFlags.intersection(Self.navigationModifiers).isEmpty,
                    event.keyCode == 53 || event.charactersIgnoringModifiers == "q"
                {  // ESC or q(Cmd-Q等の修飾キー付きはOS標準ショートカットへ通す)
                    // Pin中はホットキーと同じく閉じ抑止: パネルは維持したまま
                    // popoverを閉じてフォーカスを直前のアプリへ返す
                    if self.pinned {
                        self.returnFocusToPreviousApp()
                    } else {
                        self.hide()
                    }
                    return nil
                }
                return event
            }
            self.hideIfClickedOutside()
            return event
        }
    }

    /// キー化(フォーカス獲得)の統一ハンドラ。マウスクリック・ホットキーを問わず
    /// becomeKeyで発火する。通知モードのパルス停止・外クリック監視導入もここに統合
    private func handleBecomeKey() {
        rememberPreviousApplication()
        if notificationMode {
            notificationPulseLayer?.removeFromSuperlayer()
            notificationPulseLayer = nil
            installOutsideClickMonitors()
        }
        if selectedTarget == nil {
            selectedTarget = initialSelectedTarget()
        }
        guard !suppressFocusGlow else { return }
        rebuildPanel()
        playFocusGlow()
    }

    private func handleResignKey() {
        guard visible else { return }
        selectedTarget = nil
        rebuildPanel()
    }

    /// フォーカスを返す先を控える。通知クリック起動などで自アプリが前面のときは
    /// 戻り先にならないため、先に控えた相手をそのまま維持する
    private func rememberPreviousApplication() {
        guard let front = NSWorkspace.shared.frontmostApplication,
            front != NSRunningApplication.current
        else { return }
        previousApplication = front
    }

    /// パネルは残したまま、フォーカスだけ直前のアプリへ返す(popover表示中なら先に閉じる)。
    /// Pin中のESC/q・ホットキーで使う。戻り先を控えていない・既に終了しているときは
    /// 何もしない(パネルはフォーカスを保持したまま)
    private func returnFocusToPreviousApp() {
        guard let window, let target = previousApplication, !target.isTerminated,
            target != NSRunningApplication.current
        else { return }
        dismissEventPopover()
        // パネルは.nonactivatingPanelで相手アプリをアクティブにしたまま奪キーするため、
        // activate()だけでは(相手が既にアクティブで no-op になり)キーの座を明け渡せない。
        // いったんorderOutしてキーを相手へ返し、キー化を伴わないorderFrontRegardlessで出し直す
        let targetWasActive = target.isActive
        window.orderOut(nil)
        window.orderFrontRegardless()
        // 相手が非アクティブなとき(パネル表示中にアプリが切り替わった等)だけ明示的に戻す
        if !targetWasActive {
            target.activate(options: [])
        }
        // 控えた相手は消さない(次のESC/qで再試行でき、パネルへフォーカスが戻れば
        // handleBecomeKeyが最新の相手で上書きする)
    }

    /// 登場の署名: 通知としての自動表示中、パネル輪郭を生成りのグローで
    /// 「3回明滅→ひと呼吸」のリズムで繰り返す(周辺視野は動きに反応するため、
    /// 音を使わずに気づかせる。2026-07-19 タダシ決定: 音・macOS通知併送は不採用で演出一本)。
    /// ユーザーがパネルをクリックしてキー化するまで続け、キー化で止まる。
    /// キー化後の合流通知は署名を1周だけ打つ
    private func playNotificationPulse() {
        guard let panelView else { return }
        panelView.wantsLayer = true
        guard let hostLayer = panelView.layer else { return }

        notificationPulseLayer?.removeFromSuperlayer()
        notificationPulseLayer = nil

        let cream = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.83, alpha: 1).cgColor
        let pulse = CAShapeLayer()
        pulse.path = CGPath(
            roundedRect: panelView.bounds.insetBy(dx: 4, dy: 4),
            cornerWidth: 8, cornerHeight: 8, transform: nil)
        pulse.fillColor = nil
        pulse.strokeColor = cream
        pulse.lineWidth = 6
        pulse.shadowColor = cream
        pulse.shadowOpacity = 0.9
        pulse.shadowRadius = 10
        pulse.shadowOffset = .zero
        pulse.opacity = 0
        hostLayer.addSublayer(pulse)

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        // 前半1.6秒で3回明滅し、後半1秒は消灯(休符)。休符があることで
        // ループしても「点きっぱなし」にならず、動きとしての気づきやすさを保つ
        animation.values = [0, 1, 0.1, 1, 0.1, 1, 0, 0]
        animation.keyTimes = [0, 0.103, 0.205, 0.308, 0.41, 0.513, 0.615, 1]
        animation.duration = 2.6

        if window?.isKeyWindow != true {
            animation.repeatCount = .greatestFiniteMagnitude
            notificationPulseLayer = pulse
            pulse.add(animation, forKey: "notificationPulse")
        } else {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak pulse] in pulse?.removeFromSuperlayer() }
            pulse.add(animation, forKey: "notificationPulse")
            CATransaction.commit()
        }
    }

    /// フォーカス獲得の合図: 「非フォーカス→フォーカス」の遷移が起きた瞬間だけ、
    /// パネル外周を金茶系(panelBorderFocusedと同系色)のグローで一撃だけ光らせて消す
    /// (300〜400ms)。通知パルスと違いループせず、完了後に自身を取り除く単発演出
    private func playFocusGlow() {
        guard let panelView else { return }
        panelView.wantsLayer = true
        guard let hostLayer = panelView.layer else { return }

        let amber = NSColor(srgbRed: 0.67, green: 0.54, blue: 0.33, alpha: 1).cgColor
        let glow = CAShapeLayer()
        glow.path = CGPath(
            roundedRect: panelView.bounds.insetBy(dx: 4, dy: 4),
            cornerWidth: 8, cornerHeight: 8, transform: nil)
        glow.fillColor = nil
        glow.strokeColor = amber
        glow.lineWidth = 6
        glow.shadowColor = amber
        glow.shadowOpacity = 0.9
        glow.shadowRadius = 10
        glow.shadowOffset = .zero
        glow.opacity = 0
        hostLayer.addSublayer(glow)

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 0]
        animation.keyTimes = [0, 0.3, 1]
        animation.duration = 0.35

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak glow] in glow?.removeFromSuperlayer() }
        glow.add(animation, forKey: "focusGlow")
        CATransaction.commit()
    }

    private func hideIfClickedOutside() {
        guard !pinned else { return }
        guard let window else { return }
        let location = NSEvent.mouseLocation
        if window.frame.contains(location) { return }
        // 予定詳細popover内のクリックはパネル外扱いにしない
        if let popoverWindow = eventPopover?.contentViewController?.view.window,
            popoverWindow.frame.contains(location)
        {
            return
        }
        hide()
    }

    func hide() {
        dismissEventPopover()
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
        notificationPulseLayer?.removeFromSuperlayer()
        notificationPulseLayer = nil
        // 再表示ではPanelViewごと作り直されるため、古いホストに紐づいたままの
        // 蝋燭レイヤーを持ち越すと次に火が点かない
        candleFlameLayer?.removeFromSuperlayer()
        candleFlameLayer = nil
        candleFlameKey = nil
        candleFlameWasPresent = nil
        discardSmokeLayer()
        window?.orderOut(nil)
        window?.alphaValue = 1
        window = nil
        panelView = nil
        visible = false
        selectedTarget = nil
        hoveredId = nil
        resetConfirming = false
        calendarExpanded = false
        pinned = false
        previousApplication = nil
        if notificationMode {
            notificationMode = false
            highlightedKeys = []
            endHighlightedKeys = []
            onNotificationClosed?()
        }
    }

    /// ホットキー押下時の分岐(表示・フォーカス・Pinの状態から一意に決まる)。
    /// 判定は KokukokuCore の PanelHotkeyDecision に委譲し、ここでは実行するだけ
    func toggle() {
        let action = PanelHotkeyDecision.decide(
            visible: visible, focused: window?.isKeyWindow == true, pinned: pinned)
        switch action {
        case .show:
            show()
        case .focus:
            focus()
        case .returnFocus:
            returnFocusToPreviousApp()
        case .hide:
            hide()
        }
    }

    /// 表示中だが非フォーカスのパネルへキーボードでフォーカスを移す(閉じない)。
    /// makeKeyAndOrderFrontによりbecomeKey → handleBecomeKeyが発火し、
    /// 枠色の切替とフォーカスグローが自動で走る。通知モード中はパルス停止・
    /// 外クリック監視の導入も同じハンドラで処理される
    private func focus() {
        guard let window else { return }
        // キーボード操作でのフォーカス移動が目的なので、カーソル無しでは着地させない
        if selectedTarget == nil {
            selectedTarget = initialSelectedTarget()
        }
        window.makeKeyAndOrderFront(nil)
        rebuildPanel()
    }

    /// show() / focus() で使う初期カーソル位置(アクティブプロジェクト行。通知モードはカーソルなし)
    private func initialSelectedTarget() -> PanelSelectionTarget? {
        notificationMode
            ? nil
            : callbacks.getState().activeProjectId.flatMap { activeId in
                projects.firstIndex { $0.id == activeId }.map { .project(index: $0 + 1) }
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
            state.endHighlightedKeys = endHighlightedKeys
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
        refreshEventPopoverIfNeeded()

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
        let state = callbacks.getState()
        panelView.elements = builder.build(
            .init(
                projects: projects,
                state: state,
                selectedTarget: selectedTarget,
                hoveredId: hoveredId,
                resetConfirming: resetConfirming,
                editingTarget: editingTarget,
                alertThresholds: alertThresholds,
                calendarRows: calendarRows,
                ui: ui,
                pinned: pinned,
                focused: window?.isKeyWindow == true))
        updateCandleFlame(state: state, metrics: metrics)
    }

    /// 蝋燭の動く部分(炎と、燃え尽きた後の煙)。本体(蝋・台)と違って動かしたいため、
    /// 要素描画ではなくレイヤーで重ねる。SVGの<animate>はNSImageでは効かないが、
    /// CoreAnimationに乗せればGPU側で回り、1秒tickとは無関係に動き続けてCPUを食わない。
    /// 遊び心の表示なので動きは控えめにし、他の情報から視線を奪わないようにする
    private func updateCandleFlame(state: TimerState, metrics: PanelMetrics) {
        guard let panelView else { return }

        var continuousElapsed = state.continuousElapsedBase
        if let startedAt = state.continuousStartedAt {
            continuousElapsed += now() - startedAt
        }
        let candle = editingTarget == .continuous
            ? nil
            : CandleArt.state(
                continuousElapsed: continuousElapsed,
                thresholds: alertThresholds,
                isRunning: state.continuousStartedAt != nil)
        let candleFrame = metrics.candleFrame(
            projectCount: projects.count,
            calendarSectionHeight: PanelLayout.calendarSectionHeight(rows: calendarRows))

        let flamePresent = candle.map { $0.lit && $0.remain > 0 } ?? false

        // 計測終了で火が消えるときは即座に消さず、レイヤーを手放して
        // 「風に吹かれて消える」退場に託す(手放した後のsyncCandleLayerは素通りする)。
        // 燃え尽きは風やなく蝋が尽きた結果なので対象外(従来どおり即座に熾火と煙へ)
        if candleFlameWasPresent == true, !flamePresent, let candle, !candle.isBurntOut,
            let layer = candleFlameLayer
        {
            candleFlameLayer = nil
            candleFlameKey = nil
            blowOutFlame(layer, candle: candle, frame: candleFrame)
        }

        // 炎と煙は排他(燃えている間は炎だけ、燃え尽きた後は煙だけ)
        syncCandleLayer(
            &candleFlameLayer, key: &candleFlameKey,
            svg: candle.flatMap(CandleArt.flameSVG),
            box: candle.flatMap { CandleArt.flameBox($0, in: candleFrame) },
            cacheKey: candle?.cacheKey ?? "",
            anchorY: CandleArt.flameAnchorY,
            in: panelView,
            configure: addFlameAnimations)
        syncSmokeLayer(
            svg: candle.flatMap(CandleArt.smokeSVG),
            box: candle.flatMap { CandleArt.smokeBox($0, in: candleFrame) },
            cacheKey: (candle?.cacheKey ?? "") + ":smoke",
            in: panelView)

        // 計測開始で火が灯るときは、生成されたばかりのレイヤーに点火の演出を一度だけ仕込む
        if candleFlameWasPresent == false, flamePresent, let layer = candleFlameLayer {
            addIgnitionAnimation(to: layer)
        }
        // 蝋燭ごと非表示(連続稼働の編集中)は「不明」へ戻す。
        // falseのまま持ち越すと、編集を終えて蝋燭が戻った瞬間に点火演出が走ってしまう
        candleFlameWasPresent = candle == nil ? nil : flamePresent
    }

    /// 燃え尽きた後の煙。周期パターンの絵を1周期ぶん上へ流し続けてループさせる。
    ///
    /// 「上ほど薄れる」濃淡は絵に焼かず、**マスクレイヤーに持たせて静止**させる。
    /// 絵に焼くと濃淡ごと流れて根本の濃さが上下し、先端から煙が絶える瞬間ができるため
    /// (実物の蝋燭は芯がくすぶる間は煙が絶えない)。
    /// 絵は枠より下に1周期ぶん長く、流れた分を下から供給し続ける
    private func syncSmokeLayer(
        svg: String?, box: PanelFrame?, cacheKey: String, in panelView: PanelView
    ) {
        guard let svg, let box else {
            discardSmokeLayer()
            return
        }

        panelView.wantsLayer = true
        guard let hostLayer = panelView.layer else { return }

        // 閉じて開き直すとPanelViewごと作り直されるため、ホストが変わっていたら作り直す
        let container: CALayer
        let art: CALayer
        if let existing = candleSmokeLayer, existing.superlayer === hostLayer,
            let existingArt = candleSmokeArtLayer
        {
            container = existing
            art = existingArt
        } else {
            discardSmokeLayer()
            let created = CALayer()
            created.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let createdArt = CALayer()
            createdArt.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            created.addSublayer(createdArt)
            created.mask = smokeMaskLayer()
            hostLayer.addSublayer(created)
            candleSmokeLayer = created
            candleSmokeArtLayer = createdArt
            addSmokeAnimations(to: created, art: createdArt)
            container = created
            art = createdArt
        }

        let backingScale = window?.backingScaleFactor ?? 2
        let scroll = CandleArt.smokeScroll
        let artHeight = scroll.artHeight
        let newKey = "\(cacheKey)|\(box.w)x\(box.h)@\(backingScale)"
        // 位置とcontentsの差し替えで暗黙アニメーションが走ると、
        // 1分ごとに絵がぬるりと移動して落ち着かないため切っておく
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.bounds = CGRect(x: 0, y: 0, width: box.w, height: box.h)
        container.position = CGPoint(x: box.x + box.w / 2, y: box.y + box.h / 2)
        container.mask?.bounds = container.bounds
        container.mask?.position = CGPoint(x: box.w / 2, y: box.h / 2)
        // 絵は枠の上端に揃えて置く。余りは枠の下(マスクの外)へはみ出させる
        art.bounds = CGRect(x: 0, y: 0, width: box.w, height: artHeight)
        art.position = CGPoint(x: box.w / 2, y: scroll.artTopOffset + artHeight / 2)
        art.contentsScale = backingScale
        if candleSmokeKey != newKey {
            var proposed = CGRect(
                x: 0, y: 0, width: box.w * backingScale * 2, height: artHeight * backingScale * 2)
            let image = NSImage(data: Data(svg.utf8))
            art.contents = image?.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
            art.contentsGravity = .resizeAspect
            candleSmokeKey = newKey
        }
        CATransaction.commit()
    }

    /// 煙のレイヤーを捨てる。枠を外せばマスクも絵も一緒に消える
    private func discardSmokeLayer() {
        candleSmokeLayer?.removeFromSuperlayer()
        candleSmokeLayer = nil
        candleSmokeArtLayer = nil
        candleSmokeKey = nil
    }

    /// 煙の濃淡を作るマスク。ホストレイヤーがisGeometryFlippedのため単位座標の
    /// y=1側が視覚的な下端になる。根本(下端)から先端(上端)へ向けて薄れさせる
    private func smokeMaskLayer() -> CAGradientLayer {
        let mask = CAGradientLayer()
        mask.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        mask.startPoint = CGPoint(x: 0.5, y: 1)
        mask.endPoint = CGPoint(x: 0.5, y: 0)
        mask.colors = CandleArt.smokeMaskStops.map {
            NSColor(white: 1, alpha: $0.opacity).cgColor
        }
        mask.locations = CandleArt.smokeMaskStops.map { NSNumber(value: $0.location) }
        return mask
    }

    /// SVGを載せたレイヤーを枠へ同期する。描くものが無ければ破棄する。
    /// アニメーションはレイヤーの生成時にだけ仕込む(毎秒付け直すと動きが巻き戻る)
    private func syncCandleLayer(
        _ stored: inout CALayer?,
        key: inout String?,
        svg: String?,
        box: PanelFrame?,
        cacheKey: String,
        anchorY: Double,
        in panelView: PanelView,
        configure: (CALayer) -> Void
    ) {
        guard let svg, let box else {
            stored?.removeFromSuperlayer()
            stored = nil
            key = nil
            return
        }

        panelView.wantsLayer = true
        guard let hostLayer = panelView.layer else { return }

        // panelViewはisFlippedのため、AppKitがホストレイヤーのisGeometryFlippedを立てる。
        // つまりサブレイヤーの座標も左上原点で、PanelElementの座標をそのまま渡せばよい
        // (手で反転すると二重反転になる)。同じ理由でanchorPointの上下も反転して読まれるため、
        // 根本(視覚的な下端)を軸にするにはy=1側を指定する。
        // 閉じて開き直すとPanelViewごと作り直されるため、レイヤーを持ち越すと
        // 古いホストに付いたままになり何も見えない。hide()でも破棄しているが、
        // ホストが変わっていたら作り直す形にして経路の取りこぼしを塞ぐ
        let layer: CALayer
        if let existing = stored, existing.superlayer === hostLayer {
            layer = existing
        } else {
            stored?.removeFromSuperlayer()
            let created = CALayer()
            created.anchorPoint = CGPoint(x: 0.5, y: anchorY)
            hostLayer.addSublayer(created)
            stored = created
            key = nil
            configure(created)
            layer = created
        }

        let backingScale = window?.backingScaleFactor ?? 2
        // 解像度が変わったディスプレイへ移した場合も焼き直せるよう、倍率をキーに含める
        let newKey = "\(cacheKey)|\(box.w)x\(box.h)@\(backingScale)"
        // 位置とcontentsの差し替えで暗黙アニメーションが走ると、
        // 1分ごとに絵がぬるりと移動して落ち着かないため切っておく
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: box.w, height: box.h)
        layer.position = CGPoint(x: box.x + box.w / 2, y: box.y + box.h * anchorY)
        layer.contentsScale = backingScale
        if key != newKey {
            var proposed = CGRect(
                x: 0, y: 0, width: box.w * backingScale * 2, height: box.h * backingScale * 2)
            let image = NSImage(data: Data(svg.utf8))
            layer.contents = image?.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
            layer.contentsGravity = .resizeAspect
            key = newKey
        }
        CATransaction.commit()
    }

    /// 燃え尽きた後の煙の動き。絵を1周期ぶん**等速で**上へ流し、動かした先で元の位置へ
    /// 戻す。くねりが周期的なので継ぎ目が一致し、無限に立ち上り続けて見える。
    /// 実物の煙は上へ流れる速さがほぼ一定なので、緩急(easing)は付けない
    private func addSmokeAnimations(to container: CALayer, art: CALayer) {
        let scroll = CABasicAnimation(keyPath: "transform.translation.y")
        scroll.fromValue = 0
        // 進む向き(視覚的な上方向が負)はKokukokuCore側の値に従う
        scroll.toValue = CandleArt.smokeScroll.translation
        scroll.duration = smokeScrollDuration
        scroll.repeatCount = .greatestFiniteMagnitude
        scroll.timingFunction = CAMediaTimingFunction(name: .linear)
        art.add(scroll, forKey: "smokeScroll")

        // 全体の横揺れ。くねりの反復が機械的に見えないよう、スクロールと無関係な周期にする
        let waver = CABasicAnimation(keyPath: "transform.translation.x")
        waver.fromValue = -1.3
        waver.toValue = 1.3
        waver.duration = 2.9
        waver.autoreverses = true
        waver.repeatCount = .greatestFiniteMagnitude
        waver.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.add(waver, forKey: "smokeWaver")
    }

    /// くねり1周期ぶんを上るのにかける時間。実物の蝋燭の煙はそれなりの速さで上がるため、
    /// 13pt毎秒あたりに置く(遅すぎると幽玄になり、煙に見えない。2026-07-25 タダシ選択)
    private var smokeScrollDuration: Double { 3.0 }

    /// 炎の揺らぎ。和ろうそくは芯が太く空気を多く食うため、丈の伸び縮みより
    /// **左右へたなびく**動きが姿の特徴になる(2026-07-25 タダシ指摘)。
    /// そこで首振りを主役に据え、横流れを**わざと違う周期**で重ねて
    /// 反復が機械的に見えないようにする(単一周期だと点滅のように読めてしまう)
    private func addFlameAnimations(to layer: CALayer) {
        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -0.10
        sway.toValue = 0.10
        sway.duration = 1.3
        sway.autoreverses = true
        sway.repeatCount = .greatestFiniteMagnitude
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(sway, forKey: "candleSway")

        let drift = CABasicAnimation(keyPath: "transform.translation.x")
        drift.fromValue = -0.7
        drift.toValue = 0.7
        drift.duration = 0.83
        drift.autoreverses = true
        drift.repeatCount = .greatestFiniteMagnitude
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(drift, forKey: "candleDrift")
    }

    /// 計測開始の点火。芯先で小さく灯った火が一度大きくあおられ、揺り戻しながら
    /// 定位置へ落ち着く(マッチで点けた直後の暴れを模す)。根本anchor基準の拡縮なので
    /// 火は芯先から上へ育つ。常時の揺らぎ(sway/drift)とは軸が違うため同居できる
    private func addIgnitionAnimation(to layer: CALayer) {
        let catchFire = CAKeyframeAnimation(keyPath: "transform.scale")
        catchFire.values = [0.05, 0.4, 1.26, 0.84, 1.1, 1.0]
        catchFire.keyTimes = [0, 0.18, 0.42, 0.62, 0.82, 1]
        catchFire.calculationMode = .cubic
        catchFire.duration = 0.85
        layer.add(catchFire, forKey: "flameIgnite")

        // 灯りはじめの一瞬だけ透かして、無から滲み出るように見せる
        let emerge = CABasicAnimation(keyPath: "opacity")
        emerge.fromValue = 0
        emerge.toValue = 1
        emerge.duration = 0.18
        layer.add(emerge, forKey: "flameIgniteEmerge")
    }

    /// 計測終了の吹き消し。突風にちぎられた火が斜め上(約50度)の風下へ、細く小さく
    /// 吹っ飛んで消える。消えた芯先からは一筋の煙が立ち、漂いながらフェードして消える
    /// (2026-08-05 タダシ指定)。根本を軸に傾けるだけの初案は、形の変わらない炎が
    /// 綺麗に斜めへ倒れるだけで嘘くさかった(同日タダシ指摘)ため、傾きは飛ぶ向きへ
    /// 揃える程度にとどめ、消える仕事は移動と痩せ細りにさせる。
    /// 位置は消えた瞬間に立つ真新しい蝋燭の芯先へ移す
    /// (本体の絵は即座に新品の丈へ替わるため、古い丈のまま消すと胴の中で火が燃えて見える)。
    /// 消え終わったレイヤーはここで破棄する(呼び出し元は参照を手放し済み)
    private func blowOutFlame(_ layer: CALayer, candle: CandleArt.State, frame: PanelFrame) {
        guard let box = CandleArt.flameBox(.init(remain: candle.remain, lit: true), in: frame)
        else {
            layer.removeFromSuperlayer()
            return
        }
        // 常時の揺らぎは傾きの軸を取り合うため先に外す。外した瞬間の角度から
        // 滑らかに繋ぎ、揺れの途中で始まっても角が飛ばないようにする
        let tilt =
            (layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
        layer.removeAnimation(forKey: "candleSway")
        layer.removeAnimation(forKey: "candleDrift")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: box.x + box.w / 2, y: box.y + box.h * CandleArt.flameAnchorY)
        CATransaction.commit()

        let duration = 0.4

        // 傾きは飛ぶ向きへ揃えるだけの脇役(その場で回すと「綺麗に倒れる」に戻ってしまう)
        let align = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        align.values = [tilt, -0.9, -1.0]
        align.keyTimes = [0, 0.35, 1]

        // 吹っ飛び: 出足は芯先に粘り、後半で一気に加速して飛び去る(突風の質感)。
        // 行き先は斜め上約50度の風下(煙が流れる向きと同じ側)
        let flyX = CAKeyframeAnimation(keyPath: "transform.translation.x")
        flyX.values = [0, -2.5, -18]
        flyX.keyTimes = [0, 0.3, 1]

        let flyY = CAKeyframeAnimation(keyPath: "transform.translation.y")
        flyY.values = [0, -3, -22]
        flyY.keyTimes = [0, 0.3, 1]

        // 細く(幅)・小さく(丈)。ちぎれた直後だけ丈がわずかに伸び、風に千切れた布のように痩せる
        let thin = CAKeyframeAnimation(keyPath: "transform.scale.x")
        thin.values = [1.0, 0.55, 0.1]
        thin.keyTimes = [0, 0.4, 1]

        let shrink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        shrink.values = [1.0, 1.12, 0.18]
        shrink.keyTimes = [0, 0.3, 1]

        let vanish = CAKeyframeAnimation(keyPath: "opacity")
        vanish.values = [1.0, 0.95, 0]
        vanish.keyTimes = [0, 0.5, 1]

        // 消えた瞬間に芯先から煙を立てるため、行き先をアニメーション開始前に決めておく
        let wispBox = CandleArt.blowOutWispBox(remain: candle.remain, in: frame)
        let host = layer.superlayer
        let backingScale = window?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            layer.removeFromSuperlayer()
            // パネルが閉じられていたらホストごと外れているので煙は立てない
            guard let self, let host, host === self.panelView?.layer else { return }
            self.spawnBlowOutWisp(on: host, at: wispBox, backingScale: backingScale)
        }
        for animation in [align, flyX, flyY, thin, shrink, vanish] {
            animation.calculationMode = .cubic
            animation.duration = duration
            // 終わり姿(消えた状態)で止め、除去までの一瞬に元の姿へ戻るちらつきを防ぐ
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: nil)
        }
        CATransaction.commit()
    }

    /// 吹き消し直後の一筋の煙。芯先から立ちのぼり、風下へ流れながらフェードで消える。
    /// 燃え尽きの煙(ループ)とは別物の一発ものなので、レイヤーもここで作ってここで捨てる
    private func spawnBlowOutWisp(on host: CALayer, at box: PanelFrame, backingScale: CGFloat) {
        let wisp = CALayer()
        wisp.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wisp.bounds = CGRect(x: 0, y: 0, width: box.w, height: box.h)
        wisp.position = CGPoint(x: box.x + box.w / 2, y: box.y + box.h / 2)
        wisp.contentsScale = backingScale
        var proposed = CGRect(
            x: 0, y: 0, width: box.w * backingScale * 2, height: box.h * backingScale * 2)
        let image = NSImage(data: Data(CandleArt.blowOutWispSVG().utf8))
        wisp.contents = image?.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        wisp.contentsGravity = .resizeAspect
        // 先端ほど薄れる濃淡は燃え尽きの煙と同じくマスクで作る(ホストがisGeometryFlippedの
        // ため、単位座標のy=1側が視覚的な下端=根本になる)
        let mask = CAGradientLayer()
        mask.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        mask.startPoint = CGPoint(x: 0.5, y: 1)
        mask.endPoint = CGPoint(x: 0.5, y: 0)
        mask.colors = [0.95, 0.55, 0].map { NSColor(white: 1, alpha: $0).cgColor }
        mask.locations = [0, 0.55, 1]
        mask.bounds = wisp.bounds
        mask.position = CGPoint(x: box.w / 2, y: box.h / 2)
        wisp.mask = mask
        // ベースは透明にしておき、姿はアニメーションだけに語らせる
        // (不透明で置くと、フェードが始まる前の1フレームに濃い煙がちらつく)
        wisp.opacity = 0
        host.addSublayer(wisp)

        let duration = 1.2

        // 立ちのぼってすぐが最も濃く、あとは薄れていくだけ(一瞬の儚さ)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.9, 0.7, 0]
        fade.keyTimes = [0, 0.12, 0.45, 1]

        // 上りながら風下(なびいた側)へ流れる。実物の煙の等速に合わせ緩急は付けない
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 0
        rise.toValue = -10
        rise.timingFunction = CAMediaTimingFunction(name: .linear)

        let drift = CABasicAnimation(keyPath: "transform.translation.x")
        drift.fromValue = 0
        drift.toValue = -3
        drift.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setCompletionBlock { wisp.removeFromSuperlayer() }
        for animation in [fade, rise, drift] {
            animation.duration = duration
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            wisp.add(animation, forKey: nil)
        }
        CATransaction.commit()
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
    /// 予定行=詳細ポップオーバー、トグル行=展開/畳む
    private func executeSelectedAction() {
        switch selectedTarget {
        case .project(let index):
            guard index <= projects.count else { return }
            selectProject(projects[index - 1].id)
        case .calendarEvent(let eventIndex):
            showEventDetailPopover(eventIndex: eventIndex)
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
        } else if elementId == "btn_pin" {
            pinned.toggle()
            rebuildPanel()
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
            guard let eventIndex = Int(elementId.dropFirst("cal_event_".count)) else { return }
            selectedTarget = .calendarEvent(eventIndex: eventIndex)
            rebuildPanel()
            showEventDetailPopover(eventIndex: eventIndex)
            return
        }
        rebuildPanel()
    }

    /// 処理したらtrue(イベントを飲む)。Luaのeventtap返値と同じ意味
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 編集中のキーはフィールド側が処理する(こぼれたキーでパネル操作が走らないよう飲む)
        if editingTarget != nil { return true }

        let hasModifiers = !event.modifierFlags.intersection(Self.navigationModifiers).isEmpty
        var isCalendarEventSelected = false
        var isPopoverForSelectedEvent = false
        if case .calendarEvent(let selectedIndex)? = selectedTarget {
            isCalendarEventSelected = true
            if let eventPopover,
                let selectedRow = CalendarEventRowLookup.row(
                    atEventIndex: selectedIndex, in: calendarRows)
            {
                isPopoverForSelectedEvent = selectedRow.eventKey == eventPopover.eventKey
            }
        }
        let action = PanelKeyInterpreter.interpret(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            hasModifiers: hasModifiers,
            context: .init(
                isEventPopoverVisible: eventPopover != nil,
                isCalendarEventSelected: isCalendarEventSelected,
                isPopoverForSelectedEvent: isPopoverForSelectedEvent,
                isPinned: pinned),
            keymap: keymap)

        switch action {
        case .dismiss:
            hide()
        case .returnFocus:
            returnFocusToPreviousApp()
        case .confirm:
            if eventPopover?.activateFocusedButton() != true {
                executeSelectedAction()
            }
        case .moveDown:
            selectedTarget = PanelSelection.next(
                current: selectedTarget, in: selectionTargets())
            rebuildPanel()
        case .moveUp:
            selectedTarget = PanelSelection.previous(
                current: selectedTarget, in: selectionTargets())
            rebuildPanel()
        case .moveToTop:
            selectedTarget = PanelSelection.first(in: selectionTargets())
            rebuildPanel()
        case .moveToBottom:
            selectedTarget = PanelSelection.last(in: selectionTargets())
            rebuildPanel()
        case .moveToFirstProject:
            selectedTarget = PanelSelection.firstProject(in: selectionTargets())
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
        case .togglePin:
            pinned.toggle()
            rebuildPanel()
        case .toggleCalendar:
            toggleCalendarExpansion()
        case .selectProject(let index):
            if index <= projects.count {
                selectProject(projects[index - 1].id)
            }
        case .moveEventPopoverFocus(let delta):
            if delta < 0, eventPopover?.moveButtonFocus(delta) == .closePopover {
                eventPopover?.close()
            } else if delta > 0 {
                _ = eventPopover?.moveButtonFocus(delta)
            }
        case .showEventPopover:
            if case .calendarEvent(let eventIndex)? = selectedTarget {
                showEventDetailPopover(eventIndex: eventIndex)
            }
        case .reserved:
            break
        case .passthrough:
            return false
        }
        return true
    }

    /// 予定行のクリック・Enterで詳細ポップオーバーを表示する。
    /// 同じ予定を再度決定したときはトグルとして閉じる。
    /// ポップオーバー内のボタンからカレンダー詳細ページやMeetを開ける
    private func showEventDetailPopover(eventIndex: Int) {
        guard let eventRow = CalendarEventRowLookup.row(
            atEventIndex: eventIndex, in: calendarRows),
            let panelView
        else { return }
        if let eventPopover, eventPopover.eventKey == eventRow.eventKey {
            eventPopover.close()
            return
        }

        dismissEventPopover()

        let rect = eventRowRect(eventIndex: eventIndex)
        guard rect != .zero else { return }

        // 外クリック監視は止めない(popover内クリックはhideIfClickedOutsideが除外する)。
        // パネル外クリックはpopoverだけでなくパネルごと閉じる
        let popover = EventDetailPopover(
            eventRow: eventRow,
            eventIndex: eventIndex,
            maximumContentHeight: eventPopoverMaximumContentHeight())
        popover.onDismiss = { [weak self] in
            self?.eventPopover = nil
        }
        popover.onActionPerformed = { [weak self] in
            guard let self else { return true }
            // カレンダー・Meetを開いたら他アプリへ移る意思表示とみなし、パネルごと畳む
            // (パネルは.floatingで開いた先に被り続けるうえ、外クリックするまで閉じない)。
            // Pin中は「出したままにする」意思表示なのでpopoverだけ閉じる。
            // close処理中の再入を避けるためhideは次のrunloopで実行する
            guard !self.pinned else { return true }
            DispatchQueue.main.async { self.hide() }
            return false
        }
        popover.onUserCloseRequest = { [weak self] in
            guard let self, let event = NSApp.currentEvent else { return true }
            // ESC・パネル外クリック起因の閉じ要求は、popover単体のフェードを走らせず
            // パネルごと即時に閉じる(2段階の直列アニメーション防止)。
            // close処理中の再入を避けるためhideは次のrunloopで実行する。
            // Pin中は閉じ抑止: パネルは閉じずpopover単体のクローズ(return true)に任せる
            // (Pin中のESC/qはローカルモニタが横取りするため、ここへは外クリックだけが来る)
            let isEsc =
                event.type == .keyDown
                && event.modifierFlags.intersection(Self.navigationModifiers).isEmpty
                && (event.keyCode == 53 || event.charactersIgnoringModifiers == "q")
            let isOutsidePanelClick =
                event.type == .leftMouseDown
                && self.window.map { !$0.frame.contains(NSEvent.mouseLocation) } == true
            if (isEsc || isOutsidePanelClick), !self.pinned {
                DispatchQueue.main.async { self.hide() }
                return false
            }
            return true
        }
        eventPopover = popover
        popover.show(relativeTo: rect, of: panelView, preferredEdge: .maxX)
    }

    /// 毎秒のパネル再構築後も、安定IDが一致する予定へpopoverを追従させる
    private func refreshEventPopoverIfNeeded() {
        guard let eventPopover else { return }
        guard let match = CalendarEventRowLookup.match(
            eventKey: eventPopover.eventKey, in: calendarRows)
        else {
            if selectedTarget == .calendarEvent(eventIndex: eventPopover.eventIndex) {
                selectedTarget = nil
            }
            dismissEventPopover()
            return
        }

        let previousEventIndex = eventPopover.eventIndex
        if selectedTarget == .calendarEvent(eventIndex: previousEventIndex) {
            selectedTarget = .calendarEvent(eventIndex: match.eventIndex)
        }
        let rect = eventRowRect(eventIndex: match.eventIndex)
        guard rect != .zero else {
            dismissEventPopover()
            return
        }
        eventPopover.update(
            eventRow: match.eventRow,
            eventIndex: match.eventIndex,
            maximumContentHeight: eventPopoverMaximumContentHeight())
        eventPopover.positioningRect = rect
    }

    /// popover本体の枠と画面端の余白を残し、内容高を表示中スクリーン内へ制限する
    private func eventPopoverMaximumContentHeight() -> CGFloat {
        let visibleHeight = panelView?.window?.screen?.visibleFrame.height
            ?? screenForMousePosition().visibleFrame.height
        return max(160, visibleHeight - 64)
    }

    private func dismissEventPopover() {
        guard let eventPopover else { return }
        eventPopover.onDismiss = nil
        eventPopover.close()
        self.eventPopover = nil
    }

    /// 予定セクション内の指定eventIndexの行の矩形(PanelView座標系)
    private func eventRowRect(eventIndex: Int) -> NSRect {
        let startY = PanelLayout.clockSectionHeight
        var y = startY + PanelLayout.calendarSectionPaddingTop
        let hasNowBand = PanelLayout.hasNowMarkerBand(rows: calendarRows)
        var insertedNowBand = false
        var currentEventIndex = 0
        for row in calendarRows {
            if hasNowBand, !insertedNowBand, case .event = row {
                y += PanelLayout.calendarNowMarkerHeight
                insertedNowBand = true
            }
            let rowHeight = PanelLayout.calendarRowHeight(row)
            if case .event = row {
                if currentEventIndex == eventIndex {
                    return NSRect(x: 0, y: y, width: metrics.panelWidth, height: rowHeight)
                }
                currentEventIndex += 1
            }
            y += rowHeight
        }
        return .zero
    }

    private func screenForMousePosition() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
