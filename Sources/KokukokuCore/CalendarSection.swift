import Foundation

/// パネルへ渡すカレンダー連携の現在状態([calendar] 未設定なら渡さない=セクション非表示)
public struct CalendarPanelState: Equatable, Sendable {
    /// 表示フィルタ適用済みの予定(上限カットはCalendarSectionModelが行う)
    public var events: [CalendarEvent]
    public var error: CalendarFetchError?
    /// 展開前に表示する予定数の上限(ResolvedCalendarConfig.maxVisibleEvents)
    public var maxVisibleEvents: Int
    /// レールを表示する最小間隔(分)。これ未満は「間隔なし」として接触表現にする
    public var gapRailMinutes: Int
    /// 未開始の「あと◯◯」を表示する残り時間の上限(分)(ResolvedCalendarConfig.upcomingCountdownMaxMinutes)
    public var upcomingCountdownMaxMinutes: Int
    /// 進行中の「終了まで◯◯」を表示する残り時間の上限(分)(ResolvedCalendarConfig.ongoingCountdownMaxMinutes)
    public var ongoingCountdownMaxMinutes: Int
    /// 最後に取得成功した時刻(通知パネルの鮮度表示に使う)
    public var lastSuccessAt: Date?
    /// 通知の対象予定(通知モードのみ。タイムラインの点のハロー表示に使う)
    public var highlightedKeys: Set<CalendarEvent.EventKey>
    /// 中止(または確認不能)になった予定の告知(通知予約済み・表示中の予定のみ対象)
    public var notices: [String]

    public init(
        events: [CalendarEvent],
        error: CalendarFetchError? = nil,
        maxVisibleEvents: Int = 2,
        lastSuccessAt: Date? = nil,
        highlightedKeys: Set<CalendarEvent.EventKey> = [],
        notices: [String] = [],
        gapRailMinutes: Int = 1,
        upcomingCountdownMaxMinutes: Int = 120,
        ongoingCountdownMaxMinutes: Int = 30
    ) {
        self.events = events
        self.error = error
        self.maxVisibleEvents = maxVisibleEvents
        self.lastSuccessAt = lastSuccessAt
        self.highlightedKeys = highlightedKeys
        self.notices = notices
        self.gapRailMinutes = gapRailMinutes
        self.upcomingCountdownMaxMinutes = upcomingCountdownMaxMinutes
        self.ongoingCountdownMaxMinutes = ongoingCountdownMaxMinutes
    }
}

/// 予定セクションの1行(描画要素の構築入力。docs/calendar-integration.md「一覧UI(パネル)」)。
/// 間隔・カウントダウンは予定行が持ち、専用のラベル行は置かない(タイムライン描画)
public enum CalendarSectionRow: Equatable, Sendable {
    case event(CalendarEventRow)
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
    /// 終了時刻 "02:00"(沈み色で描き、開始と一目で区別する。区切りの「-」は描画側が挟む)
    public var endText: String
    public var title: String
    public var locationText: String?
    /// 行クリックで開くカレンダー詳細ページ(組み立て不能なら日ビュー)
    public var detailURL: URL?
    /// 先頭予定のみ: 「あと◯分」(未開始)/「終了まで◯分」(進行中)。
    /// 未開始はnowマーカー帯(now→先頭の点の区間ラベル)、進行中は行内の右端スロットに描く
    public var countdownText: String?
    /// カウントダウンの緊急度(色分けの入力)。countdownText とセットで入る
    public var countdownUrgency: CalendarCountdownUrgency?
    /// 直前の予定との間隔の表現。先頭は nil
    public var gapStyle: CalendarGapStyle?
    /// 開始前通知の対象か(通知モードの未開始予定のみ)。
    /// 情報は行が既に語っているため文字は足さず、タイムラインの点のハローで「指す」だけにする
    /// (バナー帯は行とほぼ同内容の二度言いになり不採用。2026-07-19 タダシ決定)。
    /// 開始後はハローを消して進行中表示へ引き継ぐ
    public var isAlertTarget: Bool
    /// 進行中か(開始済みで終了前)。重複時は先頭以外も進行中になり得るため各行で判定する。
    /// 描画は点のリング化+時刻の明暗反転で静かに区別する(色相は増やさない。2026-07-19 3人検討)
    public var isInProgress: Bool

    public init(
        startText: String,
        endText: String,
        title: String,
        locationText: String? = nil,
        detailURL: URL? = nil,
        countdownText: String? = nil,
        countdownUrgency: CalendarCountdownUrgency? = nil,
        gapStyle: CalendarGapStyle? = nil,
        isAlertTarget: Bool = false,
        isInProgress: Bool = false
    ) {
        self.startText = startText
        self.endText = endText
        self.title = title
        self.locationText = locationText
        self.detailURL = detailURL
        self.countdownText = countdownText
        self.countdownUrgency = countdownUrgency
        self.gapStyle = gapStyle
        self.isAlertTarget = isAlertTarget
        self.isInProgress = isInProgress
    }
}

/// 予定間の間隔の表現(2026-07-19 タダシ発案の「レールの有無」方式)。
/// レール=空き時間がある印。数字は重複のときだけ出す
public enum CalendarGapStyle: Equatable, Sendable {
    /// 閾値(gapRailMinutes)以上の間隔: レールでつなぐ(分数は出さない)
    case rail
    /// 閾値未満(0分含む): レールを消して行を接触させ、朱の接触線で「間がない」危険を示す
    case contact
    /// 時間帯の重複: 接触+朱の「◯分重複」(食い込み量は判断材料のため数字を残す)
    case overlap(minutes: Int)
}

/// カウントダウンの緊急度。遠いときは沈み色、近づくと強調、直前は警告色で描く
public enum CalendarCountdownUrgency: Equatable, Sendable {
    /// 30分超: 沈み色(情報はあるが主張しない)
    case distant
    /// 30分以内: 強調色
    case near
    /// 10分以内: 警告色(間隔警告と同じ閾値)
    case imminent
}

public enum CalendarSectionModel {
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
            row.isAlertTarget = state.highlightedKeys.contains(event.key) && event.start > now
            // 表示対象は「終了が現在より後」なので、開始済み=進行中
            row.isInProgress = event.start <= now
            if index == 0 {
                if let countdown = countdown(
                    for: event, now: now,
                    upcomingMaxMinutes: state.upcomingCountdownMaxMinutes,
                    ongoingMaxMinutes: state.ongoingCountdownMaxMinutes)
                {
                    row.countdownText = countdown.text
                    row.countdownUrgency = countdown.urgency
                }
            } else {
                row.gapStyle = gapStyle(
                    from: shown[index - 1], to: event,
                    railMinutes: state.gapRailMinutes)
            }
            rows.append(.event(row))
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

    /// 鮮度表示が要る閾値(秒)。新鮮なうちは出さず「古いかもしれない」ときだけ警告する
    /// (常時表示だと視線が慣れて肝心のときに読まれないため。2026-07-19 タダシ決定)
    public static let freshnessThresholdSeconds = 300

    /// 鮮度表示。最終取得時刻(Googleとの同期完了時刻は把握できないため、それより新しく見せない)
    static func freshnessText(lastSuccessAt: Date?, now: Date) -> String? {
        guard let lastSuccessAt else { return nil }
        let seconds = Int(now.timeIntervalSince(lastSuccessAt))
        guard seconds >= freshnessThresholdSeconds else { return nil }
        return "\(seconds / 60)分前時点の情報"
    }

    /// 先頭予定のカウントダウン。分は切り上げ(残30秒を「あと0分」と見せない)。
    /// 緊急度は次の境界(未開始なら開始、進行中なら終了)までの残り時間で決める。
    /// 上限(分)を超える先の話は出さない(未開始は次の区切りが視界に入ってから、
    /// 進行中は急ぐ判断が要るときだけ。2026-07-19 タダシ決定)
    static func countdown(
        for event: CalendarEvent, now: Date,
        upcomingMaxMinutes: Int = 120, ongoingMaxMinutes: Int = 30
    )
        -> (text: String, urgency: CalendarCountdownUrgency)?
    {
        if event.start > now {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            guard minutes <= upcomingMaxMinutes else { return nil }
            return ("あと\(durationText(minutes: minutes))", urgency(minutes: minutes))
        }
        let minutes = Int((event.end.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes <= ongoingMaxMinutes else { return nil }
        return ("終了まで\(durationText(minutes: minutes))", urgency(minutes: minutes))
    }

    /// 60分超は「1時間10分」表記で瞬読しやすくする
    static func durationText(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)分" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)時間" : "\(hours)時間\(remainder)分"
    }

    static func urgency(minutes: Int) -> CalendarCountdownUrgency {
        if minutes <= 10 { return .imminent }
        if minutes <= 30 { return .near }
        return .distant
    }

    /// 予定間の間隔の表現を決める。重複の分数は切り上げ(実際より短く見せない)
    static func gapStyle(from previous: CalendarEvent, to next: CalendarEvent, railMinutes: Int)
        -> CalendarGapStyle
    {
        let gapSeconds = Int(next.start.timeIntervalSince(previous.end))
        if gapSeconds < 0 {
            return .overlap(minutes: Int((Double(-gapSeconds) / 60).rounded(.up)))
        }
        return gapSeconds >= railMinutes * 60 ? .rail : .contact
    }

    static func eventRow(for event: CalendarEvent, calendar: Foundation.Calendar)
        -> CalendarEventRow
    {
        let start = calendar.dateComponents([.hour, .minute], from: event.start)
        let end = calendar.dateComponents([.hour, .minute], from: event.end)
        return CalendarEventRow(
            startText: String(format: "%02d:%02d", start.hour ?? 0, start.minute ?? 0),
            endText: String(format: "%02d:%02d", end.hour ?? 0, end.minute ?? 0),
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
