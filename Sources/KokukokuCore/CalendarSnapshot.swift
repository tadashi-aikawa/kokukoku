import Foundation

/// カレンダー取得の失敗状態。
/// EventKitのクエリ自体は失敗を返さないため、成否は「権限が有効か」「カレンダーが一意に解決できたか」で判定する
public enum CalendarFetchError: Error, Equatable, Sendable {
    case accessDenied
    case calendarNotFound(name: String)
    /// 複数一致。candidates は「ソース名/カレンダー名」の一覧
    case multipleCalendars(name: String, candidates: [String])
}

/// 生スナップショット同士の差分
public struct CalendarDiff: Equatable, Sendable {
    public var added: [CalendarEvent]
    public var changed: [CalendarEvent]
    /// 生スナップショットから消えた予定。「中止」と確定するには Platform 側での再照会が必要
    /// (再照会でアイテムが見つかれば取得範囲外への移動などであり、中止ではない)
    public var removedCandidates: [CalendarEvent]

    public var isEmpty: Bool {
        added.isEmpty && changed.isEmpty && removedCandidates.isEmpty
    }

    public init(
        added: [CalendarEvent] = [],
        changed: [CalendarEvent] = [],
        removedCandidates: [CalendarEvent] = []
    ) {
        self.added = added
        self.changed = changed
        self.removedCandidates = removedCandidates
    }
}

/// スナップショットの二層構造(生/表示用)。
/// 差分は生スナップショット同士で取り、「予定が終了した」「辞退に変えた」を REMOVED にしない
public struct CalendarSnapshotStore: Equatable, Sendable {
    /// 生スナップショット(フィルタ前・安定ソート済み)。nil は一度も取得成功していない状態
    public private(set) var rawEvents: [CalendarEvent]?
    /// 最後に取得成功した時刻(通知パネルの「◯分前時点の情報」表示に使う)
    public private(set) var lastSuccessAt: Date?
    /// 直近の取得エラー(成功で解消)
    public private(set) var lastError: CalendarFetchError?

    public init() {}

    /// 取得成功を反映し、前回の生スナップショットとの差分を返す。
    /// 0件でも正当な結果として更新する(全予定の正当な削除は全件 removedCandidates として検知される)
    @discardableResult
    public mutating func applySuccess(events: [CalendarEvent], at date: Date) -> CalendarDiff {
        let sorted = Self.stableSorted(events)
        let previous = rawEvents
        rawEvents = sorted
        lastSuccessAt = date
        lastError = nil

        guard let previous else {
            return CalendarDiff(added: sorted)
        }
        let previousByKey = Dictionary(
            previous.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let currentKeys = Set(sorted.map(\.key))

        return CalendarDiff(
            added: sorted.filter { previousByKey[$0.key] == nil },
            changed: sorted.filter { event in
                guard let old = previousByKey[event.key] else { return false }
                return old != event
            },
            removedCandidates: previous.filter { !currentKeys.contains($0.key) })
    }

    /// 取得失敗。生スナップショットは更新しない(古い内容で中止・変更を判定しない)
    public mutating func markFailure(_ error: CalendarFetchError) {
        lastError = error
    }

    /// 表示用リスト: 生スナップショットに表示フィルタを適用したもの
    public func visibleEvents(
        now: Date, calendar: Foundation.Calendar = .autoupdatingCurrent
    ) -> [CalendarEvent] {
        CalendarDisplayFilter.apply(to: rawEvents ?? [], now: now, calendar: calendar)
    }

    /// `start → end → 論理キー` の安定ソート(EventKitのクエリ結果に順序保証がないため)
    public static func stableSorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            if a.key.externalIdentifier != b.key.externalIdentifier {
                return a.key.externalIdentifier < b.key.externalIdentifier
            }
            return a.key.occurrenceDate < b.key.occurrenceDate
        }
    }
}

/// 表示フィルタ(docs/calendar-integration.md「表示フィルタ」)
public enum CalendarDisplayFilter {
    /// 1. 終日予定は除外
    /// 2. 自分が辞退(declined)した予定は除外(未回答・仮承諾・不明は表示)
    /// 3. 今日中に開始し、終了が現在時刻より後の予定(進行中を含む)。
    ///    前日から続く進行中予定・翌日開始の予定は対象外
    public static func apply(
        to events: [CalendarEvent], now: Date, calendar: Foundation.Calendar
    ) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        return events.filter { event in
            !event.isAllDay
                && event.myStatus != .declined
                && event.start >= dayStart
                && event.start < dayEnd
                && event.end > now
        }
    }
}
