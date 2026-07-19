import Testing

@testable import KokukokuCore

@Suite("PanelSelection")
struct PanelSelectionTests {
    private let eventRow = CalendarEventRow(startText: "01:00", endText: "02:00", title: "MTG")

    @Test("巡回順は予定行→トグル行→プロジェクト行(選択できない行は含めない)")
    func targets() {
        let rows: [CalendarSectionRow] = [
            .notice(text: "中止"),
            .event(eventRow),
            .attendees(.init(othersText: "a, b")),
            .event(eventRow),
            .overflow(hiddenCount: 2),
            .freshness(text: "6分前時点の情報"),
        ]
        #expect(
            PanelSelection.targets(calendarRows: rows, projectCount: 2) == [
                .calendarEvent(eventIndex: 0),
                .calendarEvent(eventIndex: 1),
                .calendarOverflow,
                .project(index: 1),
                .project(index: 2),
            ])
    }

    @Test("展開中は「畳む」行が巡回に入る")
    func targetsExpanded() {
        let rows: [CalendarSectionRow] = [.event(eventRow), .collapse]
        #expect(
            PanelSelection.targets(calendarRows: rows, projectCount: 1) == [
                .calendarEvent(eventIndex: 0),
                .calendarCollapse,
                .project(index: 1),
            ])
    }

    @Test("予定なし・プロジェクトなしでも壊れない")
    func targetsEmpty() {
        #expect(PanelSelection.targets(calendarRows: [], projectCount: 0) == [])
        #expect(
            PanelSelection.targets(calendarRows: [], projectCount: 2)
                == [.project(index: 1), .project(index: 2)])
    }

    @Test("次へ移動して末尾から先頭へ折り返す(予定行とプロジェクト行をまたぐ)")
    func next() {
        let targets: [PanelSelectionTarget] = [
            .calendarEvent(eventIndex: 0), .project(index: 1), .project(index: 2),
        ]
        #expect(
            PanelSelection.next(current: nil, in: targets) == .calendarEvent(eventIndex: 0))
        #expect(
            PanelSelection.next(current: .calendarEvent(eventIndex: 0), in: targets)
                == .project(index: 1))
        #expect(
            PanelSelection.next(current: .project(index: 2), in: targets)
                == .calendarEvent(eventIndex: 0))
    }

    @Test("前へ移動して先頭から末尾へ折り返す")
    func previous() {
        let targets: [PanelSelectionTarget] = [
            .calendarEvent(eventIndex: 0), .project(index: 1), .project(index: 2),
        ]
        #expect(PanelSelection.previous(current: nil, in: targets) == .project(index: 2))
        #expect(
            PanelSelection.previous(current: .calendarEvent(eventIndex: 0), in: targets)
                == .project(index: 2))
        #expect(
            PanelSelection.previous(current: .project(index: 1), in: targets)
                == .calendarEvent(eventIndex: 0))
    }

    @Test("選択対象が巡回から消えていたら先頭/末尾へ戻る")
    func missingCurrent() {
        let targets: [PanelSelectionTarget] = [.project(index: 1), .project(index: 2)]
        #expect(
            PanelSelection.next(current: .calendarEvent(eventIndex: 3), in: targets)
                == .project(index: 1))
        #expect(
            PanelSelection.previous(current: .calendarOverflow, in: targets)
                == .project(index: 2))
    }

    @Test("巡回対象が空ならnil")
    func emptyTargets() {
        #expect(PanelSelection.next(current: nil, in: []) == nil)
        #expect(PanelSelection.previous(current: .project(index: 1), in: []) == nil)
    }
}
