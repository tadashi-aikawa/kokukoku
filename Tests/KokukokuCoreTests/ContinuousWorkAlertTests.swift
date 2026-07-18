import Testing

@testable import KokukokuCore

@Suite("ContinuousWorkAlert")
struct ContinuousWorkAlertTests {
    @Test("閾値を超えると通知する")
    func notifyAtThreshold() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], messageTemplate: "%d分経過", now: { 100 },
            notify: { messages.append($0) })

        alert.check(runningState(continuousStartedAt: 85))

        #expect(messages == ["0分経過"])
    }

    @Test("閾値に達していない場合は通知しない")
    func doNotNotifyBeforeThreshold() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [100], now: { 100 }, notify: { messages.append($0) })

        alert.check(runningState(continuousStartedAt: 90))

        #expect(messages.isEmpty)
    }

    @Test("同じ閾値では重複通知しない")
    func doNotNotifyTwice() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], now: { 100 }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)

        alert.check(state)
        alert.check(state)

        #expect(messages.count == 1)
    }

    @Test("連続作業停止時に通知フラグをリセットする")
    func resetWhenStopped() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], now: { 100 }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)
        alert.check(state)

        alert.check(TimerState())
        alert.check(state)

        #expect(messages.count == 2)
    }

    @Test("continuousStartedAtがない場合も通知フラグをリセットする")
    func resetWhenContinuousStartIsMissing() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], now: { 100 }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)
        alert.check(state)

        alert.check(TimerState(activeProjectId: "proj-a"))
        alert.check(state)

        #expect(messages.count == 2)
    }

    @Test("複数閾値に対応する")
    func notifyMultipleThresholds() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10, 20], messageTemplate: "%d分経過", now: { 100 },
            notify: { messages.append($0) })

        alert.check(runningState(continuousStartedAt: 75))

        #expect(messages == ["0分経過", "0分経過"])
    }

    @Test("連続作業時間の基準秒数を加味する")
    func includeElapsedBase() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [600], now: { 100 }, notify: { messages.append($0) })

        alert.check(runningState(base: 590, continuousStartedAt: 85))

        #expect(messages.count == 1)
    }

    @Test("通知フラグを明示的にリセットできる")
    func resetNotifications() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], now: { 100 }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)
        alert.check(state)

        alert.resetNotifications()
        alert.check(state)

        #expect(messages.count == 2)
    }

    @Test("既定メッセージに閾値の分数を埋め込む")
    func defaultMessage() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [3600], now: { 4000 }, notify: { messages.append($0) })

        alert.check(runningState(continuousStartedAt: 0))

        #expect(messages == ["60分経過しました。休憩しましょう"])
    }

    @Test("primeで超過済みの閾値を通知済み扱いにする")
    func primeMarksExceededThresholds() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10, 100], now: { 100 }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)

        alert.prime(state)
        alert.check(state)

        #expect(messages.isEmpty)
    }

    @Test("prime後も未超過の閾値は超過時に通知する")
    func primeKeepsFutureThresholds() {
        var messages: [String] = []
        var currentTime = 100
        let alert = ContinuousWorkAlert(
            thresholds: [10, 100], now: { currentTime }, notify: { messages.append($0) })
        let state = runningState(continuousStartedAt: 85)
        alert.prime(state)

        currentTime = 200
        alert.check(state)

        #expect(messages.count == 1)
    }

    @Test("停止中のstateではprimeは何もしない")
    func primeIgnoresStoppedState() {
        var messages: [String] = []
        let alert = ContinuousWorkAlert(
            thresholds: [10], now: { 100 }, notify: { messages.append($0) })

        alert.prime(TimerState())
        alert.check(runningState(continuousStartedAt: 85))

        #expect(messages.count == 1)
    }

    private func runningState(base: Int = 0, continuousStartedAt: Int) -> TimerState {
        TimerState(
            activeProjectId: "proj-a",
            activeStartedAt: continuousStartedAt,
            continuousElapsedBase: base,
            continuousStartedAt: continuousStartedAt)
    }
}
