import Testing

@testable import KokukokuCore

@Suite("TimerEngine")
struct TimerEngineTests {
    private let projects: [KokukokuConfig.Project] = [
        .init(id: "proj-a", name: "Project A", icon: "🔵"),
        .init(id: "proj-b", name: "Project B", icon: "🟢"),
    ]

    @Test("秒数をHH:MM:SS形式に変換できる")
    func formatTime() {
        #expect(TimerEngine.formatTime(0) == "00:00:00")
        #expect(TimerEngine.formatTime(3661) == "01:01:01")
        #expect(TimerEngine.formatTime(nil) == "00:00:00")
        #expect(TimerEngine.formatTime(-1) == "00:00:00")
    }

    @Test("初期状態ではアクティブなプロジェクトがない")
    func initialState() {
        let engine = TimerEngine(projects: projects, now: { 100 })

        #expect(engine.state == TimerState(lastResetAt: 100))
    }

    @Test("プロジェクトを開始できる")
    func startProject() {
        let engine = TimerEngine(projects: projects, now: { 100 })

        engine.startProject("proj-a")

        #expect(engine.state.activeProjectId == "proj-a")
        #expect(engine.state.activeStartedAt == 100)
        #expect(engine.state.continuousStartedAt == 100)
    }

    @Test("切り替え時に前プロジェクトの時間を積み上げる")
    func switchProject() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        clock.value = 200

        engine.startProject("proj-b")

        #expect(engine.state.accumulated["proj-a"] == 100)
        #expect(engine.state.activeProjectId == "proj-b")
        #expect(engine.state.activeStartedAt == 200)
        #expect(engine.state.continuousStartedAt == 100)
    }

    @Test("存在しないプロジェクトIDは無視する")
    func ignoreUnknownProject() {
        var callbackCount = 0
        let engine = TimerEngine(
            projects: projects, now: { 100 }, onStateChange: { _ in callbackCount += 1 })

        engine.startProject("unknown")

        #expect(engine.state.activeProjectId == nil)
        #expect(callbackCount == 0)
    }

    @Test("状態変更時にコールバックを呼ぶ")
    func callStateChange() {
        var states: [TimerState] = []
        let engine = TimerEngine(
            projects: projects, now: { 100 }, onStateChange: { states.append($0) })

        engine.startProject("proj-a")

        #expect(states == [engine.state])
    }

    @Test("休憩開始時に計測を停止して連続作業時間をリセットする")
    func startBreak() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        clock.value = 160

        engine.startBreak()

        #expect(engine.state.activeProjectId == nil)
        #expect(engine.state.accumulated["proj-a"] == 60)
        #expect(engine.state.continuousElapsedBase == 0)
        #expect(engine.state.continuousStartedAt == nil)
    }

    @Test("休憩中に編集した連続作業時間を再開時に引き継ぐ")
    func resumeEditedContinuousElapsed() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        engine.startBreak()
        engine.setContinuousElapsed(600)
        clock.value = 200

        engine.startProject("proj-b")

        #expect(engine.state.continuousElapsedBase == 600)
        #expect(engine.state.continuousStartedAt == 200)
        #expect(engine.snapshot().continuousElapsed == 600)
    }

    @Test("リセットで全データをクリアする")
    func reset() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        clock.value = 200

        engine.reset()

        #expect(engine.state == TimerState(lastResetAt: 200))
    }

    @Test("プロジェクトのスナップショットを取得できる")
    func snapshot() {
        let engine = TimerEngine(
            projects: projects,
            initialState: TimerState(
                accumulated: ["proj-a": 3600, "proj-b": 30],
                activeProjectId: "proj-a",
                activeStartedAt: 900,
                continuousElapsedBase: 120,
                continuousStartedAt: 800,
                lastResetAt: 1),
            now: { 1000 })

        let snapshot = engine.snapshot()

        #expect(
            snapshot.projects == [
                .init(
                    id: "proj-a", name: "Project A", icon: "🔵", accumulated: 3700,
                    isActive: true),
                .init(
                    id: "proj-b", name: "Project B", icon: "🟢", accumulated: 30,
                    isActive: false),
            ])
        #expect(snapshot.activeProjectId == "proj-a")
        #expect(snapshot.currentElapsed == 100)
        #expect(snapshot.continuousElapsed == 320)
        #expect(snapshot.isRunning)
    }

    @Test("初期状態を復元できる")
    func restoreInitialState() {
        let initial = TimerState(
            accumulated: ["proj-a": 3600],
            activeProjectId: "proj-a",
            activeStartedAt: 900,
            continuousElapsedBase: 120,
            continuousStartedAt: 800,
            lastResetAt: 700)

        let engine = TimerEngine(projects: projects, initialState: initial, now: { 1000 })

        #expect(engine.state == initial)
    }

    @Test("初期状態の負の連続作業時間は0に補正する")
    func normalizeNegativeInitialContinuousElapsed() {
        let engine = TimerEngine(
            projects: projects,
            initialState: TimerState(continuousElapsedBase: -1, lastResetAt: 50),
            now: { 100 })

        #expect(engine.state.continuousElapsedBase == 0)
        #expect(engine.state.lastResetAt == 50)
    }

    @Test("累積時間を設定できる")
    func setAccumulated() {
        let engine = TimerEngine(projects: projects, now: { 100 })

        #expect(engine.setAccumulated(projectId: "proj-a", seconds: 3600))
        #expect(engine.state.accumulated["proj-a"] == 3600)
        #expect(engine.setAccumulated(projectId: "proj-a", seconds: 0))
        #expect(engine.state.accumulated["proj-a"] == 0)
    }

    @Test("不正な累積時間設定を拒否する")
    func rejectInvalidAccumulated() {
        let engine = TimerEngine(projects: projects, now: { 100 })

        #expect(!engine.setAccumulated(projectId: "unknown", seconds: 100))
        #expect(!engine.setAccumulated(projectId: "proj-a", seconds: -1))
        #expect(engine.state.accumulated.isEmpty)
    }

    @Test("計測中プロジェクトの累積時間設定時に開始時刻をリセットする")
    func setActiveAccumulated() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        clock.value = 200

        engine.setAccumulated(projectId: "proj-a", seconds: 7200)

        #expect(engine.state.accumulated["proj-a"] == 7200)
        #expect(engine.state.activeStartedAt == 200)
    }

    @Test("累積時間設定時にコールバックを呼ぶ")
    func setAccumulatedCallsStateChange() {
        var callbackCount = 0
        let engine = TimerEngine(
            projects: projects, now: { 100 }, onStateChange: { _ in callbackCount += 1 })

        engine.setAccumulated(projectId: "proj-a", seconds: 1000)

        #expect(callbackCount == 1)
    }

    @Test("稼働中の連続作業時間を設定できる")
    func setRunningContinuousElapsed() {
        let clock = TestClock(100)
        let engine = TimerEngine(projects: projects, now: { clock.value })
        engine.startProject("proj-a")
        clock.value = 200

        #expect(engine.setContinuousElapsed(3600))
        #expect(engine.state.continuousElapsedBase == 3600)
        #expect(engine.state.continuousStartedAt == 200)
    }

    @Test("停止中の連続作業時間を設定できる")
    func setStoppedContinuousElapsed() {
        let engine = TimerEngine(projects: projects, now: { 100 })

        #expect(engine.setContinuousElapsed(100))
        #expect(engine.state.continuousElapsedBase == 100)
        #expect(engine.state.continuousStartedAt == nil)
    }

    @Test("負の連続作業時間を拒否する")
    func rejectNegativeContinuousElapsed() {
        let engine = TimerEngine(projects: projects, now: { 100 })
        engine.startProject("proj-a")

        #expect(!engine.setContinuousElapsed(-1))
        #expect(engine.state.continuousElapsedBase == 0)
    }

    @Test("連続作業時間は0秒にも設定できる")
    func setContinuousElapsedToZero() {
        let engine = TimerEngine(projects: projects, now: { 100 })
        engine.startProject("proj-a")

        #expect(engine.setContinuousElapsed(0))
        #expect(engine.state.continuousElapsedBase == 0)
        #expect(engine.state.continuousStartedAt == 100)
    }

    @Test("連続作業時間設定時にコールバックを呼ぶ")
    func setContinuousElapsedCallsStateChange() {
        var callbackCount = 0
        let engine = TimerEngine(
            projects: projects, now: { 100 }, onStateChange: { _ in callbackCount += 1 })

        engine.setContinuousElapsed(1000)

        #expect(callbackCount == 1)
    }
}

private final class TestClock {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}
