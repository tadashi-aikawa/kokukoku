import AppKit
import EventKit
import KokukokuCore

/// EventKitアダプタ(docs/calendar-integration.md「同期(Platform: EventKitアダプタ)」)。
/// [calendar] 設定がある場合のみ生成・start()する。設定再読込時は旧インスタンスを stop() してから
/// 新インスタンスを start() する(多重購読・二重通知の防止)
@MainActor
final class CalendarService {
    private let config: ResolvedCalendarConfig
    private let eventStore = EKEventStore()
    private(set) var snapshot = CalendarSnapshotStore()

    private var started = false
    private var observers: [any NSObjectProtocol] = []
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    /// --calendar-debug: 取得スモーク用にスナップショット全件をstderrへ出力する
    private let debugDump = CommandLine.arguments.contains("--calendar-debug")

    init(config: ResolvedCalendarConfig) {
        self.config = config
    }

    func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            let granted: Bool
            do {
                // self を跨いで await しないよう、権限要求だけ切り出す
                guard let store = self?.eventStore else { return }
                granted = try await store.requestFullAccessToEvents()
            } catch {
                granted = false
            }
            guard let self else { return }
            if granted {
                self.beginObserving()
                self.refetch(reason: "初回取得")
            } else {
                self.snapshot.markFailure(.accessDenied)
                self.log("カレンダーへのアクセスが許可されていません")
            }
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        workspaceObservers = []
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func beginObserving() {
        // 外部変更(同期完了)の検知。メインRunLoopでの購読が常駐プロセスの必須構成
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: eventStore, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refetch(reason: "EKEventStoreChanged") }
            })
        // 0時跨ぎで当日基準へ切り替える(EKEventStoreChanged の発火には頼らない)
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSCalendarDayChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refetch(reason: "日付変更") }
            })
        // システム時計・タイムゾーン変更
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refetch(reason: "時計変更") }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refetch(reason: "タイムゾーン変更") }
            })
        // スリープ復帰時は即時再クエリ+同期キック
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refetch(reason: "スリープ復帰")
                    self.eventStore.refreshSourcesIfNecessary()
                }
            })
        // 定期更新: refreshIntervalMinutes ごとに同期をキックする。
        // 変更があれば EKEventStoreChanged 経由で再クエリされる
        refreshTask = Task { [weak self] in
            let interval = self?.config.refreshIntervalMinutes ?? 5
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval * 60))
                guard let self else { return }
                self.eventStore.refreshSourcesIfNecessary()
            }
        }
    }

    /// 対象カレンダーを再クエリしてスナップショットを更新する。
    /// クエリ範囲(今日0:00〜明日0:00)は毎回現在日付から計算し直す
    private func refetch(reason: String) {
        let now = Date()
        switch resolveCalendar() {
        case .failure(let error):
            snapshot.markFailure(error)
            log("取得エラー(\(reason)): \(describe(error))")
        case .success(let calendar):
            let dayCalendar = Foundation.Calendar.autoupdatingCurrent
            let dayStart = dayCalendar.startOfDay(for: now)
            guard let dayEnd = dayCalendar.date(byAdding: .day, value: 1, to: dayStart) else {
                return
            }
            let predicate = eventStore.predicateForEvents(
                withStart: dayStart, end: dayEnd, calendars: [calendar])
            // predicate は範囲に重なる予定を返すため「今日中に開始する予定」に絞る(生スナップショットの定義)
            let events = eventStore.events(matching: predicate)
                .compactMap { CalendarEvent(source: $0) }
                .filter { $0.start >= dayStart && $0.start < dayEnd }
            let diff = snapshot.applySuccess(events: events, at: now)
            reportRemovals(diff.removedCandidates)
            if !diff.isEmpty || debugDump {
                log(
                    "\(reason): 全\(events.count)件 (+\(diff.added.count) ~\(diff.changed.count) -\(diff.removedCandidates.count))"
                )
            }
            if debugDump {
                dumpSnapshot(now: now)
            }
        }
    }

    /// カレンダー名の解決。0件・複数一致はエラー状態(統合はしない)
    private func resolveCalendar() -> Result<EKCalendar, CalendarFetchError> {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return .failure(.accessDenied)
        }
        let matches = eventStore.calendars(for: .event).filter { $0.title == config.name }
        switch matches.count {
        case 0:
            return .failure(.calendarNotFound(name: config.name))
        case 1:
            return .success(matches[0])
        default:
            return .failure(
                .multipleCalendars(
                    name: config.name,
                    candidates: matches.map { "\($0.source.title)/\($0.title)" }))
        }
    }

    /// 生スナップショットから消えた予定を再照会し、中止(削除)かどうかを確定する。
    /// 通知への接続は後続タスク(現状はログ出力まで)
    private func reportRemovals(_ candidates: [CalendarEvent]) {
        for event in candidates {
            let items = eventStore.calendarItems(
                withExternalIdentifier: event.key.externalIdentifier)
            if items.isEmpty {
                log("中止確定: \(event.title)")
            } else {
                log("取得範囲外へ移動: \(event.title)")
            }
        }
    }

    /// 生スナップショット全件を出力し、表示フィルタを通る予定に * を付ける
    private func dumpSnapshot(now: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let visibleKeys = Set(snapshot.visibleEvents(now: now).map(\.key))
        for event in snapshot.rawEvents ?? [] {
            let place = event.meetURL.map { "meet: \($0.absoluteString)" }
                ?? event.location ?? "-"
            log(
                "  \(visibleKeys.contains(event.key) ? "*" : " ")"
                    + " \(formatter.string(from: event.start))-\(formatter.string(from: event.end))"
                    + " \(event.title) [\(place)] \(event.attendees.count)人 \(event.myStatus)")
        }
    }

    private func describe(_ error: CalendarFetchError) -> String {
        switch error {
        case .accessDenied:
            return "カレンダーへのアクセスが許可されていません"
        case .calendarNotFound(let name):
            return "カレンダー『\(name)』が見つかりません"
        case .multipleCalendars(let name, let candidates):
            return "カレンダー『\(name)』が複数あります: \(candidates.joined(separator: ", "))"
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("Kokukoku[calendar]: \(message)\n".utf8))
    }
}

extension EKEvent: CalendarEventSource {
    public var sourceExternalIdentifier: String? { calendarItemExternalIdentifier }
    public var sourceOccurrenceDate: Date? { occurrenceDate }
    public var sourceTitle: String? { title }
    public var sourceStart: Date? { startDate }
    public var sourceEnd: Date? { endDate }
    public var sourceIsAllDay: Bool { isAllDay }
    public var sourceLocation: String? { location }
    public var sourceNotes: String? { notes }
    public var sourceAttendees: [any CalendarAttendeeSource] { attendees ?? [] }
}

extension EKParticipant: CalendarAttendeeSource {
    public var attendeeName: String? { name }
    public var attendeeURL: URL? { url }
    public var attendeeIsCurrentUser: Bool { isCurrentUser }
    public var attendeeStatus: CalendarEvent.ParticipationStatus {
        switch participantStatus {
        case .accepted: return .accepted
        case .pending: return .pending
        case .tentative: return .tentative
        case .declined: return .declined
        default: return .unknown
        }
    }
}
