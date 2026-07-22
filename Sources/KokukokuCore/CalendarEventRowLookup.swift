/// 予定セクション行から予定行を安定IDで解決する純ロジック。
public enum CalendarEventRowLookup {
    /// eventIndex は予定行だけを数えた0-originで、クリックIDの cal_event_N と一致する
    public struct Match: Equatable, Sendable {
        public var eventIndex: Int
        public var eventRow: CalendarEventRow

        public init(eventIndex: Int, eventRow: CalendarEventRow) {
            self.eventIndex = eventIndex
            self.eventRow = eventRow
        }
    }

    /// 指定した表示インデックスの予定行を返す
    public static func row(
        atEventIndex targetIndex: Int,
        in rows: [CalendarSectionRow]
    ) -> CalendarEventRow? {
        guard targetIndex >= 0 else { return nil }
        var eventIndex = 0
        for row in rows {
            guard case .event(let eventRow) = row else { continue }
            if eventIndex == targetIndex { return eventRow }
            eventIndex += 1
        }
        return nil
    }

    /// 指定した安定IDの予定行と現在の表示インデックスを返す
    public static func match(
        eventKey: CalendarEvent.EventKey,
        in rows: [CalendarSectionRow]
    ) -> Match? {
        var eventIndex = 0
        for row in rows {
            guard case .event(let eventRow) = row else { continue }
            if eventRow.eventKey == eventKey {
                return Match(eventIndex: eventIndex, eventRow: eventRow)
            }
            eventIndex += 1
        }
        return nil
    }
}
