import Foundation

/// カレンダーから取得した1件の予定(EventKit非依存の純粋モデル)。
/// 仕様は docs/calendar-integration.md「データモデル(Core)」を参照。
public struct CalendarEvent: Equatable, Sendable {
    /// 同期をまたぐ論理キー。
    /// EKEvent.eventIdentifier は同期・カレンダー移動で変化し得るため差分・通知済み管理には使わない。
    /// occurrenceDate は定期予定の各発生を区別する「元の」発生日時で、発生の時刻変更では変わらない
    public struct EventKey: Hashable, Sendable {
        public var externalIdentifier: String
        public var occurrenceDate: Date

        public init(externalIdentifier: String, occurrenceDate: Date) {
            self.externalIdentifier = externalIdentifier
            self.occurrenceDate = occurrenceDate
        }
    }

    public enum ParticipationStatus: Equatable, Sendable {
        case accepted, pending, tentative, declined, unknown
    }

    public struct Attendee: Equatable, Sendable {
        public var name: String?
        public var email: String?
        public var status: ParticipationStatus
        public var isCurrentUser: Bool
        public var isOrganizer: Bool

        public init(
            name: String? = nil,
            email: String? = nil,
            status: ParticipationStatus = .unknown,
            isCurrentUser: Bool = false,
            isOrganizer: Bool = false
        ) {
            self.name = name
            self.email = email
            self.status = status
            self.isCurrentUser = isCurrentUser
            self.isOrganizer = isOrganizer
        }

        public var displayName: String {
            let raw = name ?? email ?? ""
            return raw.components(separatedBy: "@").first ?? raw
        }
    }

    public var key: EventKey
    public var title: String
    public var start: Date
    public var end: Date
    /// 終日予定か(生スナップショットには含め、表示フィルタで除外する)
    public var isAllDay: Bool
    /// 物理の場所文字列(空なら nil)
    public var location: String?
    /// notes から抽出した会議URL
    public var meetURL: URL?
    /// 主催者のメールアドレス。自分で作った予定ではカレンダー自身
    /// (`...@group.calendar.google.com`)が入る。詳細ページURLの組み立てに使う
    public var organizerEmail: String?
    /// 説明文(Meet定型文含む生テキスト)
    public var notes: String?
    /// 自分の参加ステータス。自分を特定できない場合は .unknown(表示対象に含める)
    public var myStatus: ParticipationStatus
    /// 参加者一覧(主催者含む)
    public var attendees: [Attendee]

    public init(
        key: EventKey,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        meetURL: URL? = nil,
        organizerEmail: String? = nil,
        notes: String? = nil,
        myStatus: ParticipationStatus = .unknown,
        attendees: [Attendee] = []
    ) {
        self.key = key
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.meetURL = meetURL
        self.organizerEmail = organizerEmail
        self.notes = notes
        self.myStatus = myStatus
        self.attendees = attendees
    }
}

/// EKEvent への依存を薄く切るための取得元プロトコル(変換ロジック自体をテスト可能にする)
public protocol CalendarEventSource {
    var sourceExternalIdentifier: String? { get }
    var sourceOccurrenceDate: Date? { get }
    var sourceTitle: String? { get }
    var sourceStart: Date? { get }
    var sourceEnd: Date? { get }
    var sourceIsAllDay: Bool { get }
    var sourceLocation: String? { get }
    var sourceNotes: String? { get }
    var sourceAttendees: [any CalendarAttendeeSource] { get }
    /// 主催者の mailto: URL
    var sourceOrganizerURL: URL? { get }
}

/// EKParticipant への依存を薄く切るための参加者プロトコル(myStatus の導出にのみ使う。
/// 参加者一覧の表示は2026-07-20に全廃)。
/// status のマッピング(EKParticipantStatus → ParticipationStatus)は Platform 側の責務
public protocol CalendarAttendeeSource {
    var attendeeName: String? { get }
    var attendeeEmail: String? { get }
    var attendeeStatus: CalendarEvent.ParticipationStatus { get }
    var attendeeIsCurrentUser: Bool { get }
}

extension CalendarEvent {
    /// 取得元(EKEvent相当)から純粋モデルへ変換する。論理キー・開始・終了が欠けた予定は nil
    public init?(source: any CalendarEventSource) {
        guard
            let externalIdentifier = source.sourceExternalIdentifier,
            !externalIdentifier.isEmpty,
            let occurrenceDate = source.sourceOccurrenceDate,
            let start = source.sourceStart,
            let end = source.sourceEnd
        else { return nil }

        let location = source.sourceLocation?.trimmingCharacters(in: .whitespacesAndNewlines)

        let organizerEmail = Self.email(fromMailto: source.sourceOrganizerURL)
        let attendees = source.sourceAttendees.map { a in
            Attendee(
                name: a.attendeeName,
                email: a.attendeeEmail,
                status: a.attendeeStatus,
                isCurrentUser: a.attendeeIsCurrentUser,
                isOrganizer: organizerEmail != nil && a.attendeeEmail == organizerEmail)
        }

        self.init(
            key: EventKey(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate),
            title: source.sourceTitle ?? "",
            start: start,
            end: end,
            isAllDay: source.sourceIsAllDay,
            location: (location?.isEmpty ?? true) ? nil : location,
            meetURL: MeetURLExtractor.extract(from: source.sourceNotes),
            organizerEmail: organizerEmail,
            notes: source.sourceNotes,
            myStatus: attendees.first(where: { $0.isCurrentUser })?.status ?? .unknown,
            attendees: attendees)
    }

    static func email(fromMailto url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "mailto" else { return nil }
        let address = url.absoluteString.dropFirst("mailto:".count)
        return address.isEmpty ? nil : String(address)
    }
}

/// 説明文からGoogle Calendarのボイラープレートセクション(-::~:~::~:~: 区切り)を除去する
public enum NotesCleaner {
    public static func clean(_ notes: String?) -> String? {
        guard let notes else { return nil }
        var lines: [String] = []
        var inBoilerplate = false
        for line in notes.components(separatedBy: .newlines) {
            if line.hasPrefix("-::~:~::~:~:") {
                inBoilerplate = !inBoilerplate
                continue
            }
            if !inBoilerplate {
                lines.append(line)
            }
        }
        let cleaned = lines.joined(separator: "\n").trimmingCharacters(
            in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// 説明文(notes)からの会議URL抽出。将来 Zoom 等へ広げる場合もここに追加する
public enum MeetURLExtractor {
    public static func extract(from notes: String?) -> URL? {
        // Google Meet の定型文(`Google Meet に参加: https://meet.google.com/xxx-xxxx-xxx`)を想定
        let meetPattern = /https:\/\/meet\.google\.com\/[a-z0-9\-]+/
        guard let notes, let match = notes.firstMatch(of: meetPattern) else { return nil }
        return URL(string: String(match.output))
    }
}
