import Foundation

/// 開始前通知の通知済み管理とcatch-up判定(docs/calendar-integration.md「開始前通知」)。
/// 通知済みは「通知回 = (EventKey, 開始時刻)」の単位で持つ:
/// 後ろ倒しは新しい通知回として再通知され、前倒しで通知時刻を過ぎていれば即時通知される。
/// プロセス内のみで保持し、再起動時はcatch-up規則でやり直す(永続化しない)
public struct CalendarNotifier: Sendable {
    /// 通知回。予定の同一性(EventKey)と通知の回を分離するためのキー
    public struct NotificationKey: Hashable, Sendable {
        public var eventKey: CalendarEvent.EventKey
        public var start: Date

        public init(eventKey: CalendarEvent.EventKey, start: Date) {
            self.eventKey = eventKey
            self.start = start
        }
    }

    private var notified: Set<NotificationKey> = []

    public init() {}

    /// 通知判定の一般規則: すべてのスナップショット更新時(と通知タイマー発火時)に呼ぶ。
    /// 「通知時刻 ≤ 現在 < 開始時刻 かつ 未通知の通知回」を通知対象として返し、通知済みに記録する。
    /// 開始時刻を過ぎた予定には通知しない(一覧の進行中表示で足りる)
    public mutating func dueEvents(
        in events: [CalendarEvent], now: Date, leadMinutes: Int
    ) -> [CalendarEvent] {
        prune(now: now)
        let lead = TimeInterval(leadMinutes * 60)
        return events.filter { event in
            guard event.start.addingTimeInterval(-lead) <= now, now < event.start else {
                return false
            }
            let key = NotificationKey(eventKey: event.key, start: event.start)
            return notified.insert(key).inserted
        }
    }

    /// 次にタイマーを仕掛けるべき通知時刻(未通知の通知回のうち最も早い「開始-リード時間」)。
    /// すべて通知済み・対象なしなら nil
    public func nextFireDate(
        in events: [CalendarEvent], now: Date, leadMinutes: Int
    ) -> Date? {
        let lead = TimeInterval(leadMinutes * 60)
        return events.compactMap { event -> Date? in
            let fireDate = event.start.addingTimeInterval(-lead)
            guard fireDate > now,
                !notified.contains(NotificationKey(eventKey: event.key, start: event.start))
            else { return nil }
            return fireDate
        }.min()
    }

    /// この予定(通知回)が通知済みか。中止の明示表示の対象判定に使う
    public func hasNotified(eventKey: CalendarEvent.EventKey, start: Date) -> Bool {
        notified.contains(NotificationKey(eventKey: eventKey, start: start))
    }

    /// 過去の通知回を掃除する(常駐プロセスで無限に増やさない)
    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        notified = notified.filter { $0.start >= cutoff }
    }
}
