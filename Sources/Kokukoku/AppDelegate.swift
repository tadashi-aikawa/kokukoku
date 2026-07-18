import AppKit
import KokukokuCore

/// 全体の配線(元 Kokukoku.spoon/init.lua の setup 相当)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "0.0.0-development"

    private var panel: PanelController?
    private var hotkey: Hotkey?
    private var engine: TimerEngine?
    private var alert: ContinuousWorkAlert?
    private var tickTask: Task<Void, Never>?

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

        let persistence = Persistence()
        let engine = TimerEngine(
            projects: config.projects,
            initialState: persistence.load(),
            onStateChange: { state in persistence.save(state) })

        let continuousWork = config.alert?.continuousWork
        let alert = ContinuousWorkAlert(
            thresholds: continuousWork?.thresholds ?? [],
            messageTemplate: continuousWork?.message ?? "%d分経過しました。休憩しましょう",
            notify: { message in Notifier.send(title: "刻刻", message: message) })

        let panel = PanelController(
            projects: config.projects,
            breakItem: config.breakItem,
            ui: ResolvedUIConfig(ui: config.ui),
            keymap: ResolvedKeymap(keymap: config.keymap),
            versionText: "v" + Self.version,
            callbacks: .init(
                onProjectSelect: { engine.startProject($0) },
                onBreak: { engine.startBreak() },
                onReset: { engine.reset() },
                onSetAccumulated: { engine.setAccumulated(projectId: $0, seconds: $1) },
                onSetContinuous: { engine.setContinuousElapsed($0) },
                getState: { engine.state }))
        self.panel = panel

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

        self.engine = engine
        self.alert = alert

        // --show-panel: 起動直後にパネルを表示する(動作確認用)
        if CommandLine.arguments.contains("--show-panel") {
            panel.show()
        }

        // 1秒tick: パネル表示の更新とアラート判定(元 timer_engine の tickTimer 相当)
        startTick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTask?.cancel()
        hotkey?.unregister()
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
