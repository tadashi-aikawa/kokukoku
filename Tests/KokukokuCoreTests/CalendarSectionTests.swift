import Foundation
import Testing

@testable import KokukokuCore

private let calendar = Foundation.Calendar(identifier: .gregorian)
private let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_752_800_000))

private func at(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
    dayStart.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second))
}

private func makeEvent(
    id: String = "ext-1@google.com",
    title: String = "MTG",
    start: Date,
    end: Date,
    location: String? = nil,
    meetURL: URL? = nil,
    attendees: [CalendarEvent.Attendee] = [],
    organizerEmail: String? = nil
) -> CalendarEvent {
    CalendarEvent(
        key: .init(externalIdentifier: id, occurrenceDate: start),
        title: title,
        start: start,
        end: end,
        location: location,
        meetURL: meetURL,
        attendees: attendees,
        organizerEmail: organizerEmail)
}

private func eventRow(_ row: CalendarSectionRow) -> CalendarEventRow? {
    if case .event(let event) = row { return event } else { return nil }
}

@Suite("CalendarSectionModel")
struct CalendarSectionModelTests {
    @Test("予定行は開始・終了の分離テキストと場所・詳細URLの表示データになる")
    func eventRowData() {
        let event = makeEvent(
            id: "abc123@google.com",
            title: "定例",
            start: at(hour: 14), end: at(hour: 15, minute: 30),
            location: "会議室A",
            organizerEmail: "cal-id@group.calendar.google.com")

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        // eid = base64url("abc123 cal-id@group.calendar.google.com")
        let expectedEid = Data("abc123 cal-id@group.calendar.google.com".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(
            rows == [
                .event(
                    .init(
                        startText: "14:00",
                        endText: "-15:30",
                        title: "定例",
                        locationText: "会議室A",
                        detailURL: URL(
                            string: "https://calendar.google.com/calendar/event?eid=\(expectedEid)"),
                        countdownText: "あと2時間",
                        countdownUrgency: .distant))
            ])
    }

    @Test("主催者情報が無い予定の詳細URLは日ビューへフォールバックする")
    func detailURLFallsBackToDayView() {
        let event = makeEvent(start: at(hour: 14), end: at(hour: 15))

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        let parts = calendar.dateComponents([.year, .month, .day], from: at(hour: 14))
        #expect(
            eventRow(rows[0])?.detailURL
                == URL(
                    string:
                    "https://calendar.google.com/calendar/r/day/\(parts.year!)/\(parts.month!)/\(parts.day!)"
                ))
    }

    @Test("進行中の先頭予定は「終了まで◯分」になる(切り上げ)")
    func countdownOngoing() {
        let event = makeEvent(start: at(hour: 11), end: at(hour: 12, minute: 30, second: 30))

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[0])?.countdownText == "終了まで31分")
    }

    @Test("未開始の先頭予定は「あと◯分」になる(切り上げ)")
    func countdownUpcoming() {
        let event = makeEvent(start: at(hour: 12, minute: 0, second: 30), end: at(hour: 13))

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[0])?.countdownText == "あと1分")
    }

    @Test("2件目以降は間隔を持ち、先頭はカウントダウンだけを持つ")
    func gapOnSecondEvent() {
        let events = [
            makeEvent(id: "a@google.com", start: at(hour: 13), end: at(hour: 14)),
            makeEvent(id: "b@google.com", start: at(hour: 14, minute: 10), end: at(hour: 15)),
        ]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        let first = eventRow(rows[0])
        let second = eventRow(rows[1])
        #expect(first?.countdownText == "あと1時間")
        #expect(first?.gapText == nil)
        #expect(second?.countdownText == nil)
        #expect(second?.gapText == "10分")
        #expect(second?.gapIsWarning == false)
    }

    @Test("間隔10分未満は警告になる(表示は切り捨て)")
    func gapWarning() {
        let events = [
            makeEvent(id: "a@google.com", start: at(hour: 13), end: at(hour: 14)),
            makeEvent(
                id: "b@google.com", start: at(hour: 14, minute: 9, second: 59), end: at(hour: 15)),
        ]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[1])?.gapText == "9分")
        #expect(eventRow(rows[1])?.gapIsWarning == true)
    }

    @Test("back-to-backは「0分」として警告になる")
    func backToBackGap() {
        let events = [
            makeEvent(id: "a@google.com", start: at(hour: 13), end: at(hour: 14)),
            makeEvent(id: "b@google.com", start: at(hour: 14), end: at(hour: 15)),
        ]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[1])?.gapText == "0分")
        #expect(eventRow(rows[1])?.gapIsWarning == true)
    }

    @Test("時間帯が重なる場合は「◯分重複」として警告になる(切り上げ)")
    func overlappingGap() {
        let events = [
            makeEvent(id: "a@google.com", start: at(hour: 13), end: at(hour: 14, minute: 30)),
            makeEvent(
                id: "b@google.com", start: at(hour: 14, minute: 0, second: 30), end: at(hour: 15)),
        ]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[1])?.gapText == "30分重複")
        #expect(eventRow(rows[1])?.gapIsWarning == true)
    }

    @Test("参加者は2行目になり、メールアドレスはローカル部だけ表示される")
    func attendeesRow() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [
                .init(name: "syou.maman@gmail.com", email: "syou.maman@gmail.com", status: .pending),
                .init(name: nil, email: "alice@example.com", status: .accepted),
            ])

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(rows[1] == .attendees(.init(organizerName: nil, othersText: "syou.maman, alice")))
    }

    @Test("招待されたMTGでは主催者が分離され先頭で強調される")
    func organizerEmphasis() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [
                .init(name: nil, email: "member@example.com", status: .accepted),
                .init(name: nil, email: "boss@example.com", status: .accepted),
            ],
            organizerEmail: "boss@example.com")

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(rows[1] == .attendees(.init(organizerName: "boss", othersText: "member")))
    }

    @Test("カレンダー自身が主催者の予定では主催者強調をしない")
    func calendarSelfOrganizerIsNotEmphasized() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [.init(name: nil, email: "me@example.com", status: .accepted)],
            organizerEmail: "cal-id@group.calendar.google.com")

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(rows[1] == .attendees(.init(organizerName: nil, othersText: "me")))
    }

    @Test("参加者がmaxAttendees(主催者込み)を超えたら他◯人に畳まれる")
    func attendeeOverflow() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: (1...5).map {
                .init(name: "user\($0)", email: "user\($0)@example.com", status: .accepted)
            },
            organizerEmail: "user3@example.com")

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event], maxAttendees: 3),
            now: at(hour: 12), calendar: calendar)

        #expect(
            rows[1]
                == .attendees(.init(organizerName: "user3", othersText: "user1, user2 他2人")))
    }

    @Test("参加者一覧は次の予定(先頭)だけに付く")
    func attendeesOnlyOnFirstEvent() {
        let attendees: [CalendarEvent.Attendee] = [.init(name: "alice", status: .accepted)]
        let events = [
            makeEvent(id: "a@google.com", start: at(hour: 13), end: at(hour: 14), attendees: attendees),
            makeEvent(id: "b@google.com", start: at(hour: 15), end: at(hour: 16), attendees: attendees),
        ]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        let attendeeRowCount = rows.filter {
            if case .attendees = $0 { return true } else { return false }
        }.count
        #expect(attendeeRowCount == 1)
        #expect(rows[1] == .attendees(.init(othersText: "alice")))
    }

    @Test("自分自身(selfEmail)は参加者一覧から除外される")
    func selfIsExcludedFromAttendees() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [
                .init(name: nil, email: "me@example.com", status: .pending),
                .init(name: nil, email: "alice@example.com", status: .accepted),
            ])

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event], selfEmail: "Me@example.com"),
            now: at(hour: 12), calendar: calendar)

        #expect(rows[1] == .attendees(.init(othersText: "alice")))
    }

    @Test("自分しか参加者が居ない予定には2行目が付かない")
    func selfOnlyAttendeesYieldsNoRow() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [.init(name: nil, email: "me@example.com", status: .pending)])

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event], selfEmail: "me@example.com"),
            now: at(hour: 12), calendar: calendar)

        #expect(rows.count == 1)
    }

    @Test("自分が主催者の場合は主催者強調をしない")
    func selfOrganizerIsNotEmphasized() {
        let event = makeEvent(
            start: at(hour: 14), end: at(hour: 15),
            attendees: [.init(name: nil, email: "alice@example.com", status: .accepted)],
            organizerEmail: "me@example.com")

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event], selfEmail: "me@example.com"),
            now: at(hour: 12), calendar: calendar)

        #expect(rows[1] == .attendees(.init(organizerName: nil, othersText: "alice")))
    }

    @Test("参加者情報が無い予定には2行目が付かない")
    func noAttendeesRow() {
        let event = makeEvent(start: at(hour: 14), end: at(hour: 15))

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event]), now: at(hour: 12), calendar: calendar)

        #expect(rows.count == 1)
    }

    @Test("上限(既定3件)超過分は「他◯件」に畳まれる")
    func overflowRow() {
        let events = (0..<7).map { i in
            makeEvent(
                id: "e\(i)@google.com",
                start: at(hour: 13 + i), end: at(hour: 13 + i, minute: 30))
        }

        let rows = CalendarSectionModel.rows(
            state: .init(events: events), now: at(hour: 12), calendar: calendar)

        let eventCount = rows.filter { eventRow($0) != nil }.count
        #expect(eventCount == 3)
        #expect(rows.last == .overflow(hiddenCount: 4))
    }

    @Test("表示上限はmaxVisibleEventsで変えられる")
    func customMaxVisibleEvents() {
        let events = (0..<4).map { i in
            makeEvent(
                id: "e\(i)@google.com",
                start: at(hour: 13 + i), end: at(hour: 13 + i, minute: 30))
        }

        let rows = CalendarSectionModel.rows(
            state: .init(events: events, maxVisibleEvents: 2),
            now: at(hour: 12), calendar: calendar)

        let eventCount = rows.filter { eventRow($0) != nil }.count
        #expect(eventCount == 2)
        #expect(rows.last == .overflow(hiddenCount: 2))
    }

    @Test("展開中は全件表示され末尾が「畳む」になる")
    func expandedShowsAll() {
        let events = (0..<7).map { i in
            makeEvent(
                id: "e\(i)@google.com",
                start: at(hour: 13 + i), end: at(hour: 13 + i, minute: 30))
        }

        let rows = CalendarSectionModel.rows(
            state: .init(events: events),
            now: at(hour: 12), calendar: calendar,
            expanded: true)

        let eventCount = rows.filter { eventRow($0) != nil }.count
        #expect(eventCount == 7)
        #expect(rows.last == .collapse)
    }

    @Test("上限以内なら展開中でも「畳む」は出ない")
    func noCollapseWithinLimit() {
        let events = [makeEvent(start: at(hour: 13), end: at(hour: 14))]

        let rows = CalendarSectionModel.rows(
            state: .init(events: events),
            now: at(hour: 12), calendar: calendar,
            expanded: true)

        #expect(rows.last != .collapse)
    }

    @Test("予定0件なら行なし(セクション非表示)")
    func emptyEvents() {
        let rows = CalendarSectionModel.rows(
            state: .init(events: []), now: at(hour: 12), calendar: calendar)

        #expect(rows.isEmpty)
    }

    @Test("エラー状態はエラー行のみになる")
    func errorRow() {
        let rows = CalendarSectionModel.rows(
            state: .init(
                events: [makeEvent(start: at(hour: 13), end: at(hour: 14))],
                error: .calendarNotFound(name: "一般")),
            now: at(hour: 12), calendar: calendar)

        #expect(rows == [.error(message: "カレンダー『一般』が見つかりません")])
    }

    @Test("強調キーに一致する予定行はisHighlightedになる")
    func highlightedEvent() {
        let event = makeEvent(start: at(hour: 14), end: at(hour: 15))

        let rows = CalendarSectionModel.rows(
            state: .init(events: [event], highlightedKeys: [event.key]),
            now: at(hour: 12), calendar: calendar)

        #expect(eventRow(rows[0])?.isHighlighted == true)
    }

    @Test("中止告知は先頭にnotice行として並ぶ")
    func noticeRows() {
        let rows = CalendarSectionModel.rows(
            state: .init(
                events: [makeEvent(start: at(hour: 14), end: at(hour: 15))],
                notices: ["『定例』は中止になりました"]),
            now: at(hour: 12), calendar: calendar)

        #expect(rows.first == .notice(text: "『定例』は中止になりました"))
        #expect(eventRow(rows[1]) != nil)
    }

    @Test("予定0件でも中止告知だけは表示される")
    func noticeWithoutEvents() {
        let rows = CalendarSectionModel.rows(
            state: .init(events: [], notices: ["『定例』は中止になりました"]),
            now: at(hour: 12), calendar: calendar)

        #expect(rows == [.notice(text: "『定例』は中止になりました")])
    }

    @Test("通知モードでも取得から5分未満なら鮮度表示は出ない")
    func freshnessHiddenWhenFresh() {
        let rows = CalendarSectionModel.rows(
            state: .init(
                events: [makeEvent(start: at(hour: 14), end: at(hour: 15))],
                lastSuccessAt: at(hour: 11, minute: 57)),
            now: at(hour: 12), calendar: calendar,
            includeFreshness: true)

        #expect(rows.last != .freshness(text: "3分前時点の情報"))
        #expect(eventRow(rows[0]) != nil)
    }

    @Test("取得から5分以上経つと鮮度表示が末尾に付く")
    func freshnessShownWhenStale() {
        let rows = CalendarSectionModel.rows(
            state: .init(
                events: [makeEvent(start: at(hour: 14), end: at(hour: 15))],
                lastSuccessAt: at(hour: 11, minute: 53)),
            now: at(hour: 12), calendar: calendar,
            includeFreshness: true)

        #expect(rows.last == .freshness(text: "7分前時点の情報"))
        #expect(CalendarSectionModel.freshnessText(lastSuccessAt: nil, now: at(hour: 12)) == nil)
    }

    @Test("カウントダウンの緊急度は10分/30分の閾値で切り替わる")
    func countdownUrgencyThresholds() {
        func urgencyAt(minute: Int, second: Int = 0) -> CalendarCountdownUrgency? {
            let event = makeEvent(
                start: at(hour: 12, minute: minute, second: second), end: at(hour: 13))
            let rows = CalendarSectionModel.rows(
                state: .init(events: [event]), now: at(hour: 12), calendar: calendar)
            return eventRow(rows[0])?.countdownUrgency
        }

        #expect(urgencyAt(minute: 10) == .imminent)
        #expect(urgencyAt(minute: 10, second: 30) == .near)
        #expect(urgencyAt(minute: 30) == .near)
        #expect(urgencyAt(minute: 30, second: 30) == .distant)
    }

    @Test("60分超のカウントダウンは時間表記になる")
    func countdownHourFormat() {
        #expect(CalendarSectionModel.durationText(minutes: 59) == "59分")
        #expect(CalendarSectionModel.durationText(minutes: 60) == "1時間")
        #expect(CalendarSectionModel.durationText(minutes: 70) == "1時間10分")
        #expect(CalendarSectionModel.durationText(minutes: 135) == "2時間15分")
    }

    @Test("複数一致エラーは候補一覧を含む")
    func multipleCalendarsMessage() {
        let error = CalendarFetchError.multipleCalendars(
            name: "一般", candidates: ["Google/一般", "iCloud/一般"])

        #expect(error.userMessage == "カレンダー『一般』が複数あります: Google/一般, iCloud/一般")
    }
}

@Suite("PanelLayout calendar section")
struct PanelLayoutCalendarTests {
    @Test("行なしならセクション高は0(パネル高は従来どおり)")
    func emptySectionHeight() {
        #expect(PanelLayout.calendarSectionHeight(rows: []) == 0)
        #expect(
            PanelLayout.panelHeight(projectCount: 3)
                == PanelLayout.panelHeight(projectCount: 3, calendarSectionHeight: 0))
    }

    @Test("セクション高は行種別ごとの高さ+上下パディングになる")
    func sectionHeight() {
        let rows: [CalendarSectionRow] = [
            .event(.init(startText: "13:00", endText: "-14:00", title: "a")),
            .attendees(.init(othersText: "x, y")),
            .overflow(hiddenCount: 2),
        ]

        let expected = PanelLayout.calendarEventRowHeight
            + PanelLayout.calendarAttendeeRowHeight
            + PanelLayout.calendarOverflowRowHeight
            + PanelLayout.calendarSectionPaddingTop
            + PanelLayout.calendarSectionPaddingBottom
        #expect(PanelLayout.calendarSectionHeight(rows: rows) == expected)
        #expect(
            PanelLayout.panelHeight(projectCount: 2, calendarSectionHeight: expected)
                == PanelLayout.panelHeight(projectCount: 2) + expected)
    }
}
