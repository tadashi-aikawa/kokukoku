import Foundation

public final class ContinuousWorkAlert {
    private let thresholds: [Int]
    private let messageTemplate: String
    private let now: () -> Int
    private let notify: (String) -> Void
    private var notifiedThresholds = Set<Int>()

    public init(
        thresholds: [Int],
        messageTemplate: String = "%d分経過しました。休憩しましょう",
        now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
        notify: @escaping (String) -> Void
    ) {
        self.thresholds = thresholds
        self.messageTemplate = messageTemplate
        self.now = now
        self.notify = notify
    }

    public func check(_ state: TimerState) {
        guard state.activeProjectId != nil, let continuousStartedAt = state.continuousStartedAt else {
            resetNotifications()
            return
        }

        let elapsed = state.continuousElapsedBase + now() - continuousStartedAt
        for threshold in thresholds
        where elapsed >= threshold && !notifiedThresholds.contains(threshold) {
            notifiedThresholds.insert(threshold)
            let division = threshold.quotientAndRemainder(dividingBy: 60)
            let minutes = division.quotient - (division.remainder < 0 ? 1 : 0)
            notify(String(format: messageTemplate, minutes))
        }
    }

    public func resetNotifications() {
        notifiedThresholds.removeAll()
    }
}
