import Foundation
import Testing

@testable import KokukokuCore

private let base = Date(timeIntervalSince1970: 1_752_800_000)

private func at(minute: Int) -> Date {
    base.addingTimeInterval(TimeInterval(minute * 60))
}

private func makeEvent(
    id: String = "ext-1",
    start: Date,
    end: Date? = nil
) -> CalendarEvent {
    CalendarEvent(
        key: .init(externalIdentifier: id, occurrenceDate: start),
        title: "MTG",
        start: start,
        end: end ?? start.addingTimeInterval(1800))
}

@Suite("CalendarNotifier")
struct CalendarNotifierTests {
    @Test("通知時刻を迎えた未通知の予定が通知対象になる")
    func dueAtLeadTime() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))

        let due = notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5)

        #expect(due == [event])
    }

    @Test("通知時刻前の予定は通知対象にならない")
    func notDueBeforeLeadTime() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 6))

        let due = notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5)

        #expect(due.isEmpty)
    }

    @Test("同じ通知回への通知は1回まで")
    func notifiesOncePerOccasion() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))

        #expect(notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5) == [event])
        #expect(notifier.dueEvents(in: [event], now: at(minute: 1), leadMinutes: 5).isEmpty)
    }

    @Test("開始時刻を過ぎた予定には通知しない")
    func noNotificationAfterStart() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))

        let due = notifier.dueEvents(in: [event], now: at(minute: 5), leadMinutes: 5)

        #expect(due.isEmpty)
    }

    @Test("catch-up: 通知時刻を過ぎて初めて取得された予定も開始前なら即時通知される")
    func catchUpLateFetch() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))

        // 通知時刻(0分)を過ぎた4分時点で初めてスナップショットに現れた
        let due = notifier.dueEvents(in: [event], now: at(minute: 4), leadMinutes: 5)

        #expect(due == [event])
    }

    @Test("後ろ倒しは新しい通知回として再通知される")
    func rescheduleLater() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))
        _ = notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5)

        var moved = event
        moved.start = at(minute: 20)
        moved.end = at(minute: 50)
        #expect(notifier.dueEvents(in: [moved], now: at(minute: 10), leadMinutes: 5).isEmpty)
        #expect(notifier.dueEvents(in: [moved], now: at(minute: 15), leadMinutes: 5) == [moved])
    }

    @Test("前倒しで通知時刻を過ぎていれば即時通知される")
    func rescheduleEarlier() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 30))
        #expect(notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5).isEmpty)

        var moved = event
        moved.start = at(minute: 3)
        #expect(notifier.dueEvents(in: [moved], now: at(minute: 0), leadMinutes: 5) == [moved])
    }

    @Test("同時刻に複数の予定が該当したらまとめて通知対象になる")
    func multipleDueAtOnce() {
        var notifier = CalendarNotifier()
        let events = [
            makeEvent(id: "a", start: at(minute: 5)),
            makeEvent(id: "b", start: at(minute: 5)),
        ]

        let due = notifier.dueEvents(in: events, now: at(minute: 0), leadMinutes: 5)

        #expect(due.count == 2)
    }

    @Test("nextFireDateは未通知の通知回のうち最も早い通知時刻を返す")
    func nextFireDate() {
        var notifier = CalendarNotifier()
        let first = makeEvent(id: "a", start: at(minute: 10))
        let second = makeEvent(id: "b", start: at(minute: 30))

        #expect(
            notifier.nextFireDate(
                in: [first, second], now: at(minute: 0), leadMinutes: 5, endLeadMinutes: 5)
                == at(minute: 5))

        // 先頭を通知済みにしたら次の通知回に切り替わる
        _ = notifier.dueEvents(in: [first], now: at(minute: 5), leadMinutes: 5)
        #expect(
            notifier.nextFireDate(
                in: [first, second], now: at(minute: 6), leadMinutes: 5, endLeadMinutes: 5)
                == at(minute: 25))
    }

    @Test("nextFireDateは対象がなければnilを返す")
    func nextFireDateEmpty() {
        let notifier = CalendarNotifier()

        #expect(
            notifier.nextFireDate(in: [], now: at(minute: 0), leadMinutes: 5, endLeadMinutes: 5)
                == nil)
    }

    @Test("通知済みの予定はhasNotifiedで判定できる(中止告知の対象判定)")
    func hasNotified() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5))
        _ = notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5)

        #expect(notifier.hasNotified(eventKey: event.key, start: event.start))
        #expect(!notifier.hasNotified(eventKey: event.key, start: at(minute: 6)))
    }

    // MARK: - 終了前通知

    @Test("終了前: 通知時刻を迎えた進行中の予定が通知対象になる")
    func endDueAtLeadTime() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 0), end: at(minute: 30))

        let due = notifier.dueEndingEvents(in: [event], now: at(minute: 25), leadMinutes: 5)

        #expect(due == [event])
    }

    @Test("終了前: 通知時刻前の予定は通知対象にならない")
    func endNotDueBeforeLeadTime() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 0), end: at(minute: 30))

        let due = notifier.dueEndingEvents(in: [event], now: at(minute: 24), leadMinutes: 5)

        #expect(due.isEmpty)
    }

    @Test("終了前: 未開始の予定には通知しない(長さがリード時間以下でも開始前は出ない)")
    func endNotDueBeforeStart() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 10), end: at(minute: 13))

        // 終了-リード時間(8分)は過ぎているが、まだ開始していない
        let due = notifier.dueEndingEvents(in: [event], now: at(minute: 9), leadMinutes: 5)

        #expect(due.isEmpty)
    }

    @Test("終了前: 長さがリード時間以下の予定は開始した時点でcatch-upされる")
    func endCatchUpShortEvent() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 10), end: at(minute: 13))

        let due = notifier.dueEndingEvents(in: [event], now: at(minute: 10), leadMinutes: 5)

        #expect(due == [event])
    }

    @Test("終了前: 同じ通知回への通知は1回まで")
    func endNotifiesOncePerOccasion() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 0), end: at(minute: 30))

        #expect(
            notifier.dueEndingEvents(in: [event], now: at(minute: 25), leadMinutes: 5) == [event])
        #expect(notifier.dueEndingEvents(in: [event], now: at(minute: 26), leadMinutes: 5).isEmpty)
    }

    @Test("終了前: 終了時刻を過ぎた予定には通知しない")
    func endNoNotificationAfterEnd() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 0), end: at(minute: 30))

        let due = notifier.dueEndingEvents(in: [event], now: at(minute: 30), leadMinutes: 5)

        #expect(due.isEmpty)
    }

    @Test("終了前: 終了の後ろ倒しは新しい通知回として再通知される")
    func endRescheduleLater() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 0), end: at(minute: 30))
        _ = notifier.dueEndingEvents(in: [event], now: at(minute: 25), leadMinutes: 5)

        var extended = event
        extended.end = at(minute: 60)
        #expect(
            notifier.dueEndingEvents(in: [extended], now: at(minute: 40), leadMinutes: 5).isEmpty)
        #expect(
            notifier.dueEndingEvents(in: [extended], now: at(minute: 55), leadMinutes: 5)
                == [extended])
    }

    @Test("終了前: 開始前の通知回とは独立に通知される")
    func endIndependentFromStartOccasion() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 5), end: at(minute: 35))

        #expect(notifier.dueEvents(in: [event], now: at(minute: 0), leadMinutes: 5) == [event])
        #expect(
            notifier.dueEndingEvents(in: [event], now: at(minute: 30), leadMinutes: 5) == [event])
    }

    @Test("終了前: nextFireDateは終了前の通知時刻も候補にする")
    func nextFireDateIncludesEndOccasion() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 10), end: at(minute: 40))

        // 開始前(5分)を通知済みにしたら、次は終了前(35分)
        _ = notifier.dueEvents(in: [event], now: at(minute: 5), leadMinutes: 5)
        #expect(
            notifier.nextFireDate(
                in: [event], now: at(minute: 6), leadMinutes: 5, endLeadMinutes: 5)
                == at(minute: 35))
    }

    @Test("終了前: nextFireDateの終了前通知時刻は開始時刻を下回らない(短い予定)")
    func nextFireDateEndClampedToStart() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 10), end: at(minute: 13))

        _ = notifier.dueEvents(in: [event], now: at(minute: 5), leadMinutes: 5)
        #expect(
            notifier.nextFireDate(
                in: [event], now: at(minute: 6), leadMinutes: 5, endLeadMinutes: 5)
                == at(minute: 10))
    }

    @Test("終了前: 無効(endLeadMinutesがnil)ならnextFireDateの候補にしない")
    func nextFireDateExcludesEndWhenDisabled() {
        var notifier = CalendarNotifier()
        let event = makeEvent(start: at(minute: 10), end: at(minute: 40))

        _ = notifier.dueEvents(in: [event], now: at(minute: 5), leadMinutes: 5)
        #expect(
            notifier.nextFireDate(
                in: [event], now: at(minute: 6), leadMinutes: 5, endLeadMinutes: nil)
                == nil)
    }
}
