import Foundation
import Testing

@testable import KokukokuCore

/// テスト用の日時(ローカルタイムゾーンで「今日」を固定して組み立てる)
private let calendar = Foundation.Calendar(identifier: .gregorian)
private let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_752_800_000))

private func at(hour: Int, minute: Int = 0) -> Date {
    dayStart.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private func makeEvent(
    id: String = "ext-1",
    occurrence: Date? = nil,
    title: String = "MTG",
    start: Date,
    end: Date,
    isAllDay: Bool = false,
    myStatus: CalendarEvent.ParticipationStatus = .accepted
) -> CalendarEvent {
    CalendarEvent(
        key: .init(externalIdentifier: id, occurrenceDate: occurrence ?? start),
        title: title,
        start: start,
        end: end,
        isAllDay: isAllDay,
        myStatus: myStatus)
}

@Suite("CalendarIgnoreRule")
struct CalendarIgnoreRuleTests {
    @Test("予定名が完全一致したら除外する")
    func ignoresExactMatch() {
        #expect(CalendarIgnoreRule.isIgnored(title: "確保", ignoreTitles: ["確保", "出社業務"]))
        #expect(CalendarIgnoreRule.isIgnored(title: "出社業務", ignoreTitles: ["確保", "出社業務"]))
    }

    @Test("部分一致では除外しない")
    func keepsPartialMatch() {
        #expect(!CalendarIgnoreRule.isIgnored(title: "確保: 資料作成", ignoreTitles: ["確保"]))
        #expect(!CalendarIgnoreRule.isIgnored(title: "席の確保について", ignoreTitles: ["確保"]))
        #expect(!CalendarIgnoreRule.isIgnored(title: "保", ignoreTitles: ["確保"]))
    }

    @Test("前後の空白は無視して比較する")
    func ignoresSurroundingWhitespace() {
        #expect(CalendarIgnoreRule.isIgnored(title: " 確保 ", ignoreTitles: ["確保"]))
        #expect(CalendarIgnoreRule.isIgnored(title: "確保", ignoreTitles: [" 確保"]))
    }

    @Test("設定が空なら何も除外しない")
    func keepsAllWhenUnset() {
        #expect(!CalendarIgnoreRule.isIgnored(title: "確保", ignoreTitles: []))
        #expect(!CalendarIgnoreRule.isIgnored(title: "", ignoreTitles: []))
    }

    @Test("採用分と除外分に順序を保って分割する")
    func partitionsKeepingOrder() {
        let events = [
            makeEvent(id: "a", title: "朝会", start: at(hour: 10), end: at(hour: 11)),
            makeEvent(id: "b", title: "確保", start: at(hour: 11), end: at(hour: 12)),
            makeEvent(id: "c", title: "MTG", start: at(hour: 12), end: at(hour: 13)),
            makeEvent(id: "d", title: "出社業務", start: at(hour: 13), end: at(hour: 14)),
        ]

        let result = CalendarIgnoreRule.partition(events, ignoreTitles: ["確保", "出社業務"])

        #expect(result.kept.map(\.key.externalIdentifier) == ["a", "c"])
        #expect(result.ignored.map(\.key.externalIdentifier) == ["b", "d"])
    }

    @Test("設定が空なら全件を採用分として返す")
    func partitionKeepsAllWhenUnset() {
        let events = [makeEvent(id: "a", title: "確保", start: at(hour: 10), end: at(hour: 11))]

        let result = CalendarIgnoreRule.partition(events, ignoreTitles: [])

        #expect(result.kept.map(\.key.externalIdentifier) == ["a"])
        #expect(result.ignored.isEmpty)
    }
}

@Suite("CalendarDisplayFilter")
struct CalendarDisplayFilterTests {
    let now = at(hour: 12)

    @Test("終日予定は除外される")
    func excludesAllDay() {
        let events = [
            makeEvent(id: "a", start: at(hour: 0), end: at(hour: 24), isAllDay: true),
            makeEvent(id: "b", start: at(hour: 13), end: at(hour: 14)),
        ]

        let visible = CalendarDisplayFilter.apply(to: events, now: now, calendar: calendar)

        #expect(visible.map(\.key.externalIdentifier) == ["b"])
    }

    @Test("辞退した予定は除外され、未回答・仮承諾・不明は表示される")
    func excludesDeclinedOnly() {
        let events = [
            makeEvent(id: "a", start: at(hour: 13), end: at(hour: 14), myStatus: .declined),
            makeEvent(id: "b", start: at(hour: 14), end: at(hour: 15), myStatus: .pending),
            makeEvent(id: "c", start: at(hour: 15), end: at(hour: 16), myStatus: .tentative),
            makeEvent(id: "d", start: at(hour: 16), end: at(hour: 17), myStatus: .unknown),
        ]

        let visible = CalendarDisplayFilter.apply(to: events, now: now, calendar: calendar)

        #expect(visible.map(\.key.externalIdentifier) == ["b", "c", "d"])
    }

    @Test("今日開始かつ終了が現在より後の予定だけが対象になる(進行中を含む)")
    func filtersByTodayAndEnd() {
        let events = [
            // 終了済み
            makeEvent(id: "done", start: at(hour: 9), end: at(hour: 10)),
            // 進行中(今日開始)
            makeEvent(id: "ongoing", start: at(hour: 11), end: at(hour: 13)),
            // 未開始
            makeEvent(id: "future", start: at(hour: 15), end: at(hour: 16)),
            // 前日から続く進行中
            makeEvent(id: "overnight", start: at(hour: -2), end: at(hour: 13)),
            // 翌日開始
            makeEvent(id: "tomorrow", start: at(hour: 25), end: at(hour: 26)),
        ]

        let visible = CalendarDisplayFilter.apply(to: events, now: now, calendar: calendar)

        #expect(visible.map(\.key.externalIdentifier) == ["ongoing", "future"])
    }

    @Test("ちょうど現在時刻に終了する予定は対象外になる")
    func excludesEndingExactlyNow() {
        let events = [makeEvent(id: "a", start: at(hour: 11), end: now)]

        #expect(CalendarDisplayFilter.apply(to: events, now: now, calendar: calendar).isEmpty)
    }
}

@Suite("CalendarSnapshotStore")
struct CalendarSnapshotStoreTests {
    @Test("初回の取得成功は全件ADDEDになる")
    func firstSuccessIsAllAdded() {
        var store = CalendarSnapshotStore()
        let events = [
            makeEvent(id: "a", start: at(hour: 10), end: at(hour: 11)),
            makeEvent(id: "b", start: at(hour: 13), end: at(hour: 14)),
        ]

        let diff = store.applySuccess(events: events, at: at(hour: 9))

        #expect(diff.added.map(\.key.externalIdentifier) == ["a", "b"])
        #expect(diff.changed.isEmpty)
        #expect(diff.removedCandidates.isEmpty)
        #expect(store.lastSuccessAt == at(hour: 9))
    }

    @Test("追加・変更・消滅を生スナップショット同士の差分で検知する")
    func diffDetectsAddedChangedRemoved() {
        var store = CalendarSnapshotStore()
        let unchanged = makeEvent(id: "keep", start: at(hour: 10), end: at(hour: 11))
        var moved = makeEvent(id: "move", start: at(hour: 13), end: at(hour: 14))
        let removed = makeEvent(id: "gone", start: at(hour: 15), end: at(hour: 16))
        store.applySuccess(events: [unchanged, moved, removed], at: at(hour: 9))

        // 時刻変更してもEventKeyは変わらない(occurrenceDateは元の発生日時のまま)
        moved.start = at(hour: 13, minute: 30)
        moved.end = at(hour: 14, minute: 30)
        let added = makeEvent(id: "new", start: at(hour: 17), end: at(hour: 18))

        let diff = store.applySuccess(events: [unchanged, moved, added], at: at(hour: 9, minute: 5))

        #expect(diff.added == [added])
        #expect(diff.changed == [moved])
        #expect(diff.removedCandidates == [removed])
    }

    @Test("変化がなければ差分は空になる")
    func noChangeYieldsEmptyDiff() {
        var store = CalendarSnapshotStore()
        let events = [makeEvent(id: "a", start: at(hour: 10), end: at(hour: 11))]
        store.applySuccess(events: events, at: at(hour: 9))

        let diff = store.applySuccess(events: events, at: at(hour: 9, minute: 5))

        #expect(diff.isEmpty)
    }

    @Test("0件の取得成功も正当な結果として反映され、全件が消滅候補になる")
    func emptySuccessUpdatesSnapshot() {
        var store = CalendarSnapshotStore()
        let events = [makeEvent(id: "a", start: at(hour: 10), end: at(hour: 11))]
        store.applySuccess(events: events, at: at(hour: 9))

        let diff = store.applySuccess(events: [], at: at(hour: 9, minute: 5))

        #expect(diff.removedCandidates == events)
        #expect(store.rawEvents == [])
    }

    @Test("取得失敗ではスナップショットを更新せずエラー状態になる")
    func failureKeepsSnapshot() {
        var store = CalendarSnapshotStore()
        let events = [makeEvent(id: "a", start: at(hour: 10), end: at(hour: 11))]
        store.applySuccess(events: events, at: at(hour: 9))

        store.markFailure(.calendarNotFound(name: "一般"))

        #expect(store.rawEvents == events)
        #expect(store.lastSuccessAt == at(hour: 9))
        #expect(store.lastError == .calendarNotFound(name: "一般"))
    }

    @Test("取得成功でエラー状態が解消される")
    func successClearsError() {
        var store = CalendarSnapshotStore()
        store.markFailure(.accessDenied)

        store.applySuccess(events: [], at: at(hour: 9))

        #expect(store.lastError == nil)
    }

    @Test("一度も成功していなければ表示用リストは空になる")
    func visibleEventsBeforeFirstSuccess() {
        let store = CalendarSnapshotStore()

        #expect(store.visibleEvents(now: at(hour: 12), calendar: calendar).isEmpty)
    }

    @Test("表示用リストは生スナップショットへのフィルタ適用結果になる")
    func visibleEventsAppliesFilter() {
        var store = CalendarSnapshotStore()
        store.applySuccess(
            events: [
                makeEvent(id: "declined", start: at(hour: 13), end: at(hour: 14), myStatus: .declined),
                makeEvent(id: "shown", start: at(hour: 14), end: at(hour: 15)),
            ],
            at: at(hour: 9))

        let visible = store.visibleEvents(now: at(hour: 12), calendar: calendar)

        #expect(visible.map(\.key.externalIdentifier) == ["shown"])
    }

    @Test("start→end→論理キーの順で安定ソートされる")
    func stableSort() {
        let events = [
            makeEvent(id: "c", start: at(hour: 10), end: at(hour: 11)),
            makeEvent(id: "b", start: at(hour: 10), end: at(hour: 11)),
            makeEvent(id: "a", start: at(hour: 10), end: at(hour: 12)),
            makeEvent(id: "d", start: at(hour: 9), end: at(hour: 10)),
        ]

        let sorted = CalendarSnapshotStore.stableSorted(events)

        #expect(sorted.map(\.key.externalIdentifier) == ["d", "b", "c", "a"])
    }
}
