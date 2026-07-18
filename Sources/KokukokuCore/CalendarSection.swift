import Foundation

/// パネルへ渡すカレンダー連携の現在状態([calendar] 未設定なら渡さない=セクション非表示)
public struct CalendarPanelState: Equatable, Sendable {
    /// 表示フィルタ適用済みの予定(上限カットはCalendarSectionModelが行う)
    public var events: [CalendarEvent]
    public var error: CalendarFetchError?
    /// 予定行に表示する参加者数の上限(ResolvedCalendarConfig.maxAttendees)
    public var maxAttendees: Int
    /// 展開前に表示する予定数の上限(ResolvedCalendarConfig.maxVisibleEvents)
    public var maxVisibleEvents: Int
    /// 最後に取得成功した時刻(通知パネルの鮮度表示に使う)
    public var lastSuccessAt: Date?
    /// 通知で強調する予定(通知モードのみ)
    public var highlightedKeys: Set<CalendarEvent.EventKey>
    /// 中止(または確認不能)になった予定の告知(通知予約済み・表示中の予定のみ対象)
    public var notices: [String]

    public init(
        events: [CalendarEvent],
        error: CalendarFetchError? = nil,
        maxAttendees: Int = 5,
        maxVisibleEvents: Int = 5,
        lastSuccessAt: Date? = nil,
        highlightedKeys: Set<CalendarEvent.EventKey> = [],
        notices: [String] = []
    ) {
        self.events = events
        self.error = error
        self.maxAttendees = maxAttendees
        self.maxVisibleEvents = maxVisibleEvents
        self.lastSuccessAt = lastSuccessAt
        self.highlightedKeys = highlightedKeys
        self.notices = notices
    }
}

/// 予定セクションの1行(描画要素の構築入力。docs/calendar-integration.md「一覧UI(パネル)」)。
/// 間隔・カウントダウンは予定行が持ち、専用のラベル行は置かない(タイムライン描画)
public enum CalendarSectionRow: Equatable, Sendable {
    case event(CalendarEventRow)
    /// 予定行の2行目: 参加者一覧。参加者情報が無い予定には付かない
    case attendees(CalendarAttendeesRow)
    /// 上限超過分の「他◯件」(クリックで全件展開)
    case overflow(hiddenCount: Int)
    /// 展開中の「畳む」(クリックで上限表示へ戻す)
    case collapse
    case error(message: String)
    /// 中止(または確認不能)の告知(通知文脈のみ)
    case notice(text: String)
    /// 「◯分前時点の情報」(通知モードのみ。同期遅延の可能性を利用者が判断できるように)
    case freshness(text: String)
}

/// 予定行の表示データ(時刻等は整形済み)
public struct CalendarEventRow: Equatable, Sendable {
    /// 開始時刻 "01:00"(明色で描く)
    public var startText: String
    /// 終了時刻 "-02:00"(沈み色で描き、開始と一目で区別する)
    public var endText: String
    public var title: String
    public var locationText: String?
    /// 行クリックで開くカレンダー詳細ページ(組み立て不能なら日ビュー)
    public var detailURL: URL?
    /// 先頭予定のみ: 「あと◯分」(未開始)/「終了まで◯分」(進行中)。行の右端に描く
    public var countdownText: String?
    /// 直前の予定との間隔(タイムラインのレール上に描く)。先頭は nil
    public var gapText: String?
    public var gapIsWarning: Bool
    /// 通知で強調中か(通知モードの該当予定)
    public var isHighlighted: Bool

    public init(
        startText: String,
        endText: String,
        title: String,
        locationText: String? = nil,
        detailURL: URL? = nil,
        countdownText: String? = nil,
        gapText: String? = nil,
        gapIsWarning: Bool = false,
        isHighlighted: Bool = false
    ) {
        self.startText = startText
        self.endText = endText
        self.title = title
        self.locationText = locationText
        self.detailURL = detailURL
        self.countdownText = countdownText
        self.gapText = gapText
        self.gapIsWarning = gapIsWarning
        self.isHighlighted = isHighlighted
    }
}

/// 参加者一覧行。主催者(招待されたMTGでのみ特定できる)は強調して先頭に置く
public struct CalendarAttendeesRow: Equatable, Sendable {
    public var organizerName: String?
    /// 主催者以外の一覧("a, b 他3人")
    public var othersText: String?

    public init(organizerName: String? = nil, othersText: String? = nil) {
        self.organizerName = organizerName
        self.othersText = othersText
    }
}

public enum CalendarSectionModel {
    /// 間隔警告の固定閾値(秒)。R2: 10分未満は移動猶予が少ないため強調する
    public static let gapWarningThresholdSeconds = 600

    /// 表示状態から予定セクションの行データ列を組み立てる。空配列はセクションごと非表示。
    /// includeFreshness は通知モードのみ true(「◯分前時点の情報」を末尾に付ける)。
    /// expanded は「他◯件」クリックでの全件展開中(末尾に「畳む」が付く)
    public static func rows(
        state: CalendarPanelState,
        now: Date,
        calendar: Foundation.Calendar = .autoupdatingCurrent,
        includeFreshness: Bool = false,
        expanded: Bool = false
    ) -> [CalendarSectionRow] {
        if let error = state.error {
            return [.error(message: error.userMessage)]
        }
        var rows: [CalendarSectionRow] = state.notices.map { .notice(text: $0) }
        guard !state.events.isEmpty else { return rows }

        let hasOverflow = state.events.count > state.maxVisibleEvents
        let shown = expanded
            ? state.events : Array(state.events.prefix(state.maxVisibleEvents))
        for (index, event) in shown.enumerated() {
            var row = eventRow(for: event, calendar: calendar)
            row.isHighlighted = state.highlightedKeys.contains(event.key)
            if index == 0 {
                row.countdownText = countdownText(for: event, now: now)
            } else {
                let gap = gapLabel(from: shown[index - 1], to: event)
                row.gapText = gap.text
                row.gapIsWarning = gap.isWarning
            }
            rows.append(.event(row))
            if let attendees = attendeesRow(for: event, maxAttendees: state.maxAttendees) {
                rows.append(.attendees(attendees))
            }
        }
        if hasOverflow {
            if expanded {
                rows.append(.collapse)
            } else {
                rows.append(.overflow(hiddenCount: state.events.count - state.maxVisibleEvents))
            }
        }
        if includeFreshness, let freshness = freshnessText(lastSuccessAt: state.lastSuccessAt, now: now) {
            rows.append(.freshness(text: freshness))
        }
        return rows
    }

    /// 鮮度表示。最終取得時刻(Googleとの同期完了時刻は把握できないため、それより新しく見せない)
    static func freshnessText(lastSuccessAt: Date?, now: Date) -> String? {
        guard let lastSuccessAt else { return nil }
        let minutes = Int(now.timeIntervalSince(lastSuccessAt) / 60)
        return minutes < 1 ? "1分以内に取得した情報" : "\(minutes)分前時点の情報"
    }

    /// 先頭予定のカウントダウン。分は切り上げ(残30秒を「あと0分」と見せない)
    static func countdownText(for event: CalendarEvent, now: Date) -> String {
        if event.start > now {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            return "あと\(minutes)分"
        }
        let minutes = Int((event.end.timeIntervalSince(now) / 60).rounded(.up))
        return "終了まで\(minutes)分"
    }

    /// 予定間の間隔ラベル。間隔は切り捨て(実際より長く見せない)、重複は切り上げ。
    /// back-to-backは「0分」として強調する
    static func gapLabel(from previous: CalendarEvent, to next: CalendarEvent)
        -> (text: String, isWarning: Bool)
    {
        let gapSeconds = Int(next.start.timeIntervalSince(previous.end))
        if gapSeconds < 0 {
            let minutes = Int((Double(-gapSeconds) / 60).rounded(.up))
            return ("\(minutes)分重複", true)
        }
        return ("\(gapSeconds / 60)分", gapSeconds < gapWarningThresholdSeconds)
    }

    static func eventRow(for event: CalendarEvent, calendar: Foundation.Calendar)
        -> CalendarEventRow
    {
        let start = calendar.dateComponents([.hour, .minute], from: event.start)
        let end = calendar.dateComponents([.hour, .minute], from: event.end)
        return CalendarEventRow(
            startText: String(format: "%02d:%02d", start.hour ?? 0, start.minute ?? 0),
            endText: String(format: "-%02d:%02d", end.hour ?? 0, end.minute ?? 0),
            title: event.title,
            locationText: event.location,
            detailURL: detailURL(for: event, calendar: calendar))
    }

    /// Googleカレンダーの予定詳細ページURL。
    /// eid = base64url("<eventId> <主催カレンダー/主催者のメール>")。
    /// 組み立てに必要な情報が無い予定はその日の日ビューへフォールバックする
    static func detailURL(for event: CalendarEvent, calendar: Foundation.Calendar) -> URL? {
        let googleSuffix = "@google.com"
        if let organizerEmail = event.organizerEmail,
            event.key.externalIdentifier.hasSuffix(googleSuffix)
        {
            let eventId = String(event.key.externalIdentifier.dropLast(googleSuffix.count))
            let eid = Data("\(eventId) \(organizerEmail)".utf8)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: event.start)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return URL(string: "https://calendar.google.com/calendar/r/day/\(year)/\(month)/\(day)")
    }

    /// 参加者一覧行。主催者を特定できたら強調用に分離して先頭に置き、
    /// 残りを maxAttendees(主催者込み)まで表示して超過分は「他◯人」に畳む
    static func attendeesRow(for event: CalendarEvent, maxAttendees: Int)
        -> CalendarAttendeesRow?
    {
        // 自分で作った予定はorganizerがカレンダー自身になるため「主催者」として扱わない
        let organizerEmail: String? = {
            guard let email = event.organizerEmail?.lowercased(),
                !email.hasSuffix("@group.calendar.google.com")
            else { return nil }
            return email
        }()

        var organizerName: String?
        var others: [String] = []
        for attendee in event.attendees {
            guard let name = displayName(for: attendee) else { continue }
            if organizerName == nil, let organizerEmail,
                attendee.email?.lowercased() == organizerEmail
            {
                organizerName = name
            } else {
                others.append(name)
            }
        }
        // 主催者が参加者一覧に居ない予定でも主催者は表示する
        if organizerName == nil, let organizerEmail {
            organizerName = displayName(
                for: .init(email: organizerEmail, status: .unknown))
        }
        guard organizerName != nil || !others.isEmpty else { return nil }

        let capacity = max(maxAttendees - (organizerName == nil ? 0 : 1), 0)
        let shownOthers = others.prefix(capacity)
        var othersText = shownOthers.joined(separator: ", ")
        let hiddenCount = others.count - shownOthers.count
        if hiddenCount > 0 {
            othersText += othersText.isEmpty ? "他\(hiddenCount)人" : " 他\(hiddenCount)人"
        }
        return CalendarAttendeesRow(
            organizerName: organizerName,
            othersText: othersText.isEmpty ? nil : othersText)
    }

    /// 参加者の表示名。EventKit経由ではnameにメールアドレスが入ることが多いため、
    /// メール形式ならローカル部(@より前)だけを使う
    static func displayName(for attendee: CalendarEvent.Attendee) -> String? {
        guard let raw = attendee.name ?? attendee.email, !raw.isEmpty else { return nil }
        if let atIndex = raw.firstIndex(of: "@"), atIndex != raw.startIndex {
            return String(raw[..<atIndex])
        }
        return raw
    }
}

extension CalendarFetchError {
    /// パネルのエラー行・ログに使う利用者向けメッセージ
    public var userMessage: String {
        switch self {
        case .accessDenied:
            return "カレンダーへのアクセスが許可されていません"
        case .calendarNotFound(let name):
            return "カレンダー『\(name)』が見つかりません"
        case .multipleCalendars(let name, let candidates):
            return "カレンダー『\(name)』が複数あります: \(candidates.joined(separator: ", "))"
        }
    }
}
