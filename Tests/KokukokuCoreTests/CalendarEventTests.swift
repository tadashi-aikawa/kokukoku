import Foundation
import Testing

@testable import KokukokuCore

private struct FakeAttendee: CalendarAttendeeSource {
    var attendeeStatus: CalendarEvent.ParticipationStatus
    var attendeeIsCurrentUser: Bool

    init(
        status: CalendarEvent.ParticipationStatus = .accepted,
        isCurrentUser: Bool = false
    ) {
        self.attendeeStatus = status
        self.attendeeIsCurrentUser = isCurrentUser
    }
}

private struct FakeEventSource: CalendarEventSource {
    var sourceExternalIdentifier: String?
    var sourceOccurrenceDate: Date?
    var sourceTitle: String?
    var sourceStart: Date?
    var sourceEnd: Date?
    var sourceIsAllDay: Bool
    var sourceLocation: String?
    var sourceNotes: String?
    var sourceAttendees: [any CalendarAttendeeSource]
    var sourceOrganizerURL: URL?

    init(
        externalIdentifier: String? = "ext-1",
        occurrenceDate: Date? = Date(timeIntervalSince1970: 1000),
        title: String? = "MTG",
        start: Date? = Date(timeIntervalSince1970: 1000),
        end: Date? = Date(timeIntervalSince1970: 4600),
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        attendees: [any CalendarAttendeeSource] = [],
        organizerURL: URL? = nil
    ) {
        self.sourceExternalIdentifier = externalIdentifier
        self.sourceOccurrenceDate = occurrenceDate
        self.sourceTitle = title
        self.sourceStart = start
        self.sourceEnd = end
        self.sourceIsAllDay = isAllDay
        self.sourceLocation = location
        self.sourceNotes = notes
        self.sourceAttendees = attendees
        self.sourceOrganizerURL = organizerURL
    }
}

@Suite("CalendarEvent conversion")
struct CalendarEventConversionTests {
    @Test("取得元の全項目を純粋モデルへ変換する")
    func convertFullSource() throws {
        let notes = "Google Meet に参加: https://meet.google.com/abc-defg-hij"
        let source = FakeEventSource(
            externalIdentifier: "ext-42",
            occurrenceDate: Date(timeIntervalSince1970: 100),
            title: "定例",
            start: Date(timeIntervalSince1970: 200),
            end: Date(timeIntervalSince1970: 300),
            isAllDay: false,
            location: "会議室A",
            notes: notes,
            attendees: [
                FakeAttendee(status: .accepted, isCurrentUser: true),
                FakeAttendee(status: .pending),
            ])

        let event = try #require(CalendarEvent(source: source))

        #expect(
            event.key
                == .init(
                    externalIdentifier: "ext-42",
                    occurrenceDate: Date(timeIntervalSince1970: 100)))
        #expect(event.title == "定例")
        #expect(event.start == Date(timeIntervalSince1970: 200))
        #expect(event.end == Date(timeIntervalSince1970: 300))
        #expect(event.location == "会議室A")
        #expect(event.meetURL == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(event.notes == notes)
        #expect(event.myStatus == .accepted)
    }

    @Test("論理キー・開始・終了が欠けた予定はnilになる")
    func convertMissingRequiredFields() {
        #expect(CalendarEvent(source: FakeEventSource(externalIdentifier: nil)) == nil)
        #expect(CalendarEvent(source: FakeEventSource(externalIdentifier: "")) == nil)
        #expect(CalendarEvent(source: FakeEventSource(occurrenceDate: nil)) == nil)
        #expect(CalendarEvent(source: FakeEventSource(start: nil)) == nil)
        #expect(CalendarEvent(source: FakeEventSource(end: nil)) == nil)
    }

    @Test("自分を特定できない場合myStatusはunknownになる")
    func myStatusWithoutCurrentUser() throws {
        let source = FakeEventSource(attendees: [FakeAttendee(status: .accepted)])

        let event = try #require(CalendarEvent(source: source))

        #expect(event.myStatus == .unknown)
    }

    @Test("参加者が空でもmyStatusはunknownになる")
    func myStatusWithoutAttendees() throws {
        let event = try #require(CalendarEvent(source: FakeEventSource()))

        #expect(event.myStatus == .unknown)
    }

    @Test("主催者のmailto URLからorganizerEmailを取り出す")
    func organizerEmail() throws {
        let source = FakeEventSource(
            organizerURL: URL(string: "mailto:boss@example.com"))

        let event = try #require(CalendarEvent(source: source))

        #expect(event.organizerEmail == "boss@example.com")
    }

    @Test("空白だけの場所はnilになる")
    func blankLocationBecomesNil() throws {
        let event = try #require(CalendarEvent(source: FakeEventSource(location: "  \n")))

        #expect(event.location == nil)
    }

    @Test("mailto以外の主催者URLからはorganizerEmailを取り出さない")
    func nonMailtoOrganizerURLIsIgnored() throws {
        let source = FakeEventSource(organizerURL: URL(string: "https://example.com/bot"))

        let event = try #require(CalendarEvent(source: source))

        #expect(event.organizerEmail == nil)
    }
}

@Suite("MeetURLExtractor")
struct MeetURLExtractorTests {
    @Test("Google Meetの定型文からURLを抽出する")
    func extractFromBoilerplate() {
        let notes = """
            アジェンダ:
            -=-=-=-=-=-=-=-=-=-=-=-
            Google Meet に参加: https://meet.google.com/abc-defg-hij
            """

        #expect(
            MeetURLExtractor.extract(from: notes)
                == URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    @Test("複数候補があれば最初のURLを抽出する")
    func extractFirstMatch() {
        let notes = "https://meet.google.com/aaa-aaaa-aaa と https://meet.google.com/bbb-bbbb-bbb"

        #expect(
            MeetURLExtractor.extract(from: notes)
                == URL(string: "https://meet.google.com/aaa-aaaa-aaa"))
    }

    @Test("Meet URLがなければnilになる")
    func extractNoMatch() {
        #expect(MeetURLExtractor.extract(from: "https://example.com/meeting") == nil)
        #expect(MeetURLExtractor.extract(from: "") == nil)
        #expect(MeetURLExtractor.extract(from: nil) == nil)
    }
}
