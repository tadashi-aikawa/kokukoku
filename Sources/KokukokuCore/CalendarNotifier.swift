import Foundation

/// 開始前・終了前通知の通知済み管理とcatch-up判定(docs/calendar-integration.md「開始前通知」「終了前通知」)。
/// 通知済みは「通知回 = (種別, EventKey, 基準時刻)」の単位で持つ:
/// 後ろ倒しは新しい通知回として再通知され、前倒しで通知時刻を過ぎていれば即時通知される。
/// プロセス内のみで保持し、再起動時はcatch-up規則でやり直す(永続化しない)
public struct CalendarNotifier: Sendable {
    /// 通知回。予定の同一性(EventKey)と通知の回を分離するためのキー
    public struct NotificationKey: Hashable, Sendable {
        /// 通知の種別。開始前と終了前は独立した通知回として管理する
        public enum Kind: Hashable, Sendable {
            case start
            case end
        }

        public var kind: Kind
        public var eventKey: CalendarEvent.EventKey
        /// 通知回を区切る基準時刻(開始前=開始時刻、終了前=終了時刻)
        public var time: Date

        public init(kind: Kind, eventKey: CalendarEvent.EventKey, time: Date) {
            self.kind = kind
            self.eventKey = eventKey
            self.time = time
        }
    }

    private var notified: Set<NotificationKey> = []

    public init() {}

    /// 開始前通知の判定の一般規則: すべてのスナップショット更新時(と通知タイマー発火時)に呼ぶ。
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
            let key = NotificationKey(kind: .start, eventKey: event.key, time: event.start)
            return notified.insert(key).inserted
        }
    }

    /// 終了前通知の判定: 開始前と同じ一般規則で呼ぶ。
    /// 「通知時刻 ≤ 現在 < 終了時刻 かつ 進行中 かつ 未通知の通知回」を通知対象として返し、
    /// 通知済みに記録する。開始前は対象にしない(予定の長さがリード時間以下の場合は
    /// 開始した時点でcatch-up規則により即時通知される)
    public mutating func dueEndingEvents(
        in events: [CalendarEvent], now: Date, leadMinutes: Int
    ) -> [CalendarEvent] {
        prune(now: now)
        let lead = TimeInterval(leadMinutes * 60)
        return events.filter { event in
            guard event.end.addingTimeInterval(-lead) <= now,
                event.start <= now, now < event.end
            else {
                return false
            }
            let key = NotificationKey(kind: .end, eventKey: event.key, time: event.end)
            return notified.insert(key).inserted
        }
    }

    /// 次にタイマーを仕掛けるべき通知時刻(未通知の通知回のうち最も早いもの)。
    /// 開始前は「開始-リード時間」、終了前は「終了-リード時間」(開始前には出さないため
    /// 開始時刻を下回らない)。endLeadMinutes が nil(終了前通知が無効)なら終了前は
    /// 候補にしない。すべて通知済み・対象なしなら nil
    public func nextFireDate(
        in events: [CalendarEvent], now: Date, leadMinutes: Int, endLeadMinutes: Int?
    ) -> Date? {
        let lead = TimeInterval(leadMinutes * 60)
        let startDates = events.compactMap { event -> Date? in
            let fireDate = event.start.addingTimeInterval(-lead)
            guard fireDate > now,
                !notified.contains(
                    NotificationKey(kind: .start, eventKey: event.key, time: event.start))
            else { return nil }
            return fireDate
        }
        let endDates = endLeadMinutes.map { endLeadMinutes -> [Date] in
            let endLead = TimeInterval(endLeadMinutes * 60)
            return events.compactMap { event -> Date? in
                let fireDate = max(event.end.addingTimeInterval(-endLead), event.start)
                guard fireDate > now,
                    !notified.contains(
                        NotificationKey(kind: .end, eventKey: event.key, time: event.end))
                else { return nil }
                return fireDate
            }
        } ?? []
        return (startDates + endDates).min()
    }

    /// この予定(開始前の通知回)が通知済みか。中止の明示表示の対象判定に使う
    public func hasNotified(eventKey: CalendarEvent.EventKey, start: Date) -> Bool {
        notified.contains(NotificationKey(kind: .start, eventKey: eventKey, time: start))
    }

    /// 過去の通知回を掃除する(常駐プロセスで無限に増やさない)
    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        notified = notified.filter { $0.time >= cutoff }
    }
}
