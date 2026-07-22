import Foundation
import Testing

@testable import KokukokuCore

@Suite("CalendarEventRowLookup")
struct CalendarEventRowLookupTests {
    private let firstKey = CalendarEvent.EventKey(
        externalIdentifier: "first", occurrenceDate: .distantPast)
    private let secondKey = CalendarEvent.EventKey(
        externalIdentifier: "second", occurrenceDate: .distantFuture)

    @Test("予定以外の行を除外して表示インデックスで予定を引く")
    func rowAtEventIndex() {
        let rows = rowsWithTwoEvents()

        #expect(CalendarEventRowLookup.row(atEventIndex: -1, in: rows) == nil)
        #expect(CalendarEventRowLookup.row(atEventIndex: 0, in: rows)?.eventKey == firstKey)
        #expect(CalendarEventRowLookup.row(atEventIndex: 1, in: rows)?.eventKey == secondKey)
        #expect(CalendarEventRowLookup.row(atEventIndex: 2, in: rows) == nil)
    }

    @Test("安定IDで予定と現在の表示インデックスを引く")
    func matchByEventKey() {
        let rows = rowsWithTwoEvents()

        #expect(
            CalendarEventRowLookup.match(eventKey: secondKey, in: rows)
                == .init(eventIndex: 1, eventRow: eventRow(key: secondKey, title: "次の予定")))
        #expect(
            CalendarEventRowLookup.match(
                eventKey: .init(externalIdentifier: "missing", occurrenceDate: .distantPast),
                in: rows) == nil)
    }

    private func rowsWithTwoEvents() -> [CalendarSectionRow] {
        [
            .notice(text: "お知らせ"),
            .event(eventRow(key: firstKey, title: "最初の予定")),
            .freshness(text: "5分前時点の情報"),
            .event(eventRow(key: secondKey, title: "次の予定")),
            .collapse,
        ]
    }

    private func eventRow(key: CalendarEvent.EventKey, title: String) -> CalendarEventRow {
        CalendarEventRow(eventKey: key, startText: "10:00", endText: "11:00", title: title)
    }
}
