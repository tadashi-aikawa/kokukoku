import AppKit
import KokukokuCore

/// 全体の配線(元 Kokukoku.spoon/init.lua の setup 相当)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?
    private var panel: PanelController?
    private var hotkey: Hotkey?
    private var engine: TimerEngine?
    private var alert: ContinuousWorkAlert?
    private var calendarService: CalendarService?
    private var tickTask: Task<Void, Never>?
    private let persistence = Persistence()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: KokukokuConfig
        do {
            config = try ConfigLoader.load()
        } catch {
            FileHandle.standardError.write(
                Data("Kokukoku: failed to load config: \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }

        let statusItem = StatusItem()
        statusItem.onReloadConfig = { [weak self] in self?.reloadConfig() }
        self.statusItem = statusItem

        // 通知クリックでパネルを開く(バンドル実行時のみ有効)
        Notifier.setUp(onClick: { [weak self] in self?.panel?.show() })

        setUp(config: config)

        // --test-notification: 通知の表示とクリック挙動の動作確認用
        if CommandLine.arguments.contains("--test-notification") {
            Notifier.send("テスト通知です。クリックするとパネルが開きます")
        }

        // --show-panel: 起動直後にパネルを表示する(動作確認用)
        if CommandLine.arguments.contains("--show-panel") {
            panel?.show()
        }

        // 1秒tick: パネル表示の更新とアラート判定(元 timer_engine の tickTimer 相当)
        startTick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTask?.cancel()
        hotkey?.unregister()
        calendarService?.stop()
    }

    /// 設定から各コンポーネントを組み立てる(起動時・設定再読込時の共通経路)
    private func setUp(config: KokukokuConfig) {
        // 旧アダプタを止めてから新アダプタを起こす(多重購読・二重通知の防止)
        calendarService?.stop()
        calendarService = nil

        let engine = TimerEngine(
            projects: config.projects,
            initialState: persistence.load(),
            onStateChange: { [persistence] state in persistence.save(state) })

        let continuousWork = config.alert?.continuousWork
        let alert = ContinuousWorkAlert(
            thresholds: continuousWork?.thresholds ?? [],
            messageTemplate: continuousWork?.message ?? "%d分経過しました。休憩しましょう",
            notify: { message in Notifier.send(message) })

        let panel = PanelController(
            projects: config.projects,
            alertThresholds: continuousWork?.thresholds ?? [],
            ui: ResolvedUIConfig(ui: config.ui),
            keymap: ResolvedKeymap(keymap: config.keymap),
            callbacks: .init(
                onProjectSelect: { engine.startProject($0) },
                onBreak: { engine.startBreak() },
                onReset: { engine.reset() },
                onSetAccumulated: { engine.setAccumulated(projectId: $0, seconds: $1) },
                onSetContinuous: { engine.setContinuousElapsed($0) },
                getState: { engine.state },
                getCalendarState: { [weak self] in
                    guard let service = self?.calendarService else { return nil }
                    return CalendarPanelState(
                        events: service.snapshot.visibleEvents(now: Date()),
                        error: service.snapshot.lastError,
                        maxAttendees: service.maxAttendees,
                        maxVisibleEvents: service.maxVisibleEvents,
                        lastSuccessAt: service.snapshot.lastSuccessAt,
                        notices: service.notices,
                        selfEmail: service.selfEmail,
                        gapRailMinutes: service.gapRailMinutes,
                        upcomingCountdownMaxMinutes: service.upcomingCountdownMaxMinutes,
                        ongoingCountdownMaxMinutes: service.ongoingCountdownMaxMinutes)
                }))

        self.engine = engine
        self.alert = alert
        self.panel = panel

        // [calendar] 設定がない場合はカレンダー連携を完全に無効にする(権限要求もしない)
        if let calendarConfig = config.calendar {
            let service = CalendarService(config: ResolvedCalendarConfig(calendar: calendarConfig))
            // 開始前通知: パネルを自動表示して該当予定を強調する
            service.onNotification = { [weak self] keys in
                self?.panel?.showCalendarNotification(keys: keys)
            }
            panel.onNotificationClosed = { [weak service] in service?.clearNotices() }
            service.start()
            calendarService = service

            // --test-calendar-notification: 次の未開始予定で開始前通知の見た目
            // (対象の点のハロー・入場パルス)を実際の通知時刻を待たずに確認する
            if CommandLine.arguments.contains("--test-calendar-notification") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, let service = self.calendarService else { return }
                    let upcoming = service.snapshot.visibleEvents(now: Date())
                        .filter { $0.start > Date() }
                    guard let first = upcoming.first else { return }
                    self.panel?.showCalendarNotification(keys: [first.key])
                }
            }
        }

        if let hotkeyConfig = config.hotkey {
            hotkey = Hotkey(
                modifiers: hotkeyConfig.modifiers,
                key: hotkeyConfig.key,
                handler: { panel.toggle() })
            if hotkey == nil {
                FileHandle.standardError.write(
                    Data("Kokukoku: failed to register hotkey: \(hotkeyConfig.key)\n".utf8))
            }
        }
    }

    /// ステータスバーメニューからの設定再読込。
    /// 読込失敗時は現行設定のまま動き続ける(起動時と違い終了しない)
    private func reloadConfig() {
        let config: KokukokuConfig
        do {
            config = try ConfigLoader.load()
        } catch {
            FileHandle.standardError.write(
                Data("Kokukoku: failed to reload config: \(error)\n".utf8))
            Notifier.send("設定の再読込に失敗しました。現在の設定のまま動作します")
            return
        }

        panel?.hide()
        hotkey?.unregister()
        hotkey = nil
        setUp(config: config)
        // 既に超過している閾値を通知済み扱いにし、再読込直後の再通知を防ぐ
        if let engine {
            alert?.prime(engine.state)
        }
        Notifier.send("設定を再読込しました")
    }

    private func startTick() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.panel?.update()
                if let engine = self.engine {
                    self.alert?.check(engine.state)
                }
            }
        }
    }
}
