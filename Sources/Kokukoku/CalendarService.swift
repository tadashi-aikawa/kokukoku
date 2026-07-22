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

    /// 開始前通知の通知済み管理(通知回単位・プロセス内のみ)
    private var notifier = CalendarNotifier()
    private var notifyTask: Task<Void, Never>?
    /// 中止(確定)告知。通知パネルが閉じられたら clearNotices() でクリアされる
    private(set) var notices: [String] = []
    /// 通知すべき予定が発生したときに呼ばれる(空Setは告知のみの再表示)
    var onNotification: ((Set<CalendarEvent.EventKey>) -> Void)?

    var maxVisibleEvents: Int { config.maxVisibleEvents }
    var gapRailMinutes: Int { config.gapRailMinutes }
    var upcomingCountdownMaxMinutes: Int { config.upcomingCountdownMaxMinutes }
    var ongoingCountdownMaxMinutes: Int { config.ongoingCountdownMaxMinutes }

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
        notifyTask?.cancel()
        notifyTask = nil
    }

    func clearNotices() {
        notices = []
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
            log("取得エラー(\(reason)): \(error.userMessage)")
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
            // 通知判定の一般規則: すべてのスナップショット更新時に評価する
            // (同期遅延で通知時刻経過後に取得された予定・寝ていた間の取りこぼし防止)
            evaluateNotifications(now: Date())
            scheduleNextNotification()
        }
    }

    /// 「通知時刻 ≤ 現在 < 開始時刻 かつ 未通知の通知回」を通知する
    private func evaluateNotifications(now: Date) {
        let due = notifier.dueEvents(
            in: snapshot.visibleEvents(now: now), now: now,
            leadMinutes: config.notificationLeadMinutes)
        guard !due.isEmpty else { return }
        log("開始前通知: \(due.map(\.title).joined(separator: ", "))")
        onNotification?(Set(due.map(\.key)))
    }

    /// 次の通知時刻へタイマーを仕掛け直す。表示の60秒前と表示時点に同期をキックして鮮度を上げる
    private func scheduleNextNotification() {
        notifyTask?.cancel()
        notifyTask = nil
        guard
            let fireDate = notifier.nextFireDate(
                in: snapshot.visibleEvents(now: Date()), now: Date(),
                leadMinutes: config.notificationLeadMinutes)
        else { return }
        notifyTask = Task { [weak self] in
            let kickDelay = fireDate.timeIntervalSinceNow - 60
            if kickDelay > 0 {
                try? await Task.sleep(for: .seconds(kickDelay))
                guard let self, !Task.isCancelled else { return }
                self.eventStore.refreshSourcesIfNecessary()
            }
            let fireDelay = fireDate.timeIntervalSinceNow
            if fireDelay > 0 {
                try? await Task.sleep(for: .seconds(fireDelay))
            }
            guard let self, !Task.isCancelled else { return }
            self.eventStore.refreshSourcesIfNecessary()
            self.evaluateNotifications(now: Date())
            self.scheduleNextNotification()
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
    /// 開始前の予定の中止が確定したら告知を積んで通知パネルを出す(黙って取り消さない)
    private func reportRemovals(_ candidates: [CalendarEvent]) {
        var noticed = false
        for event in candidates {
            let items = eventStore.calendarItems(
                withExternalIdentifier: event.key.externalIdentifier)
            if items.isEmpty {
                log("中止確定: \(event.title)")
                // 表示フィルタ相当(終日・辞退除外)かつ終了前の予定だけを告知対象にする。
                // 開始時刻基準にすると同期遅延(3〜4分)で開始直前の中止を告知できないため終了基準
                if event.end > Date(), !event.isAllDay, event.myStatus != .declined {
                    notices.append("『\(event.title)』は中止になりました")
                    noticed = true
                }
            } else {
                // 取得範囲外への移動・時刻変更(単発予定はEventKeyごと変わる)など。中止ではない
                log("取得範囲外へ移動: \(event.title)")
            }
        }
        if noticed {
            onNotification?([])
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
                    + " \(event.title) [\(place)] \(event.myStatus)")
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
    public var sourceOrganizerURL: URL? { organizer?.url }
}

extension EKParticipant: CalendarAttendeeSource {
    public var attendeeName: String? { name }
    public var attendeeEmail: String? {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        let address = url.absoluteString.dropFirst("mailto:".count)
        return address.isEmpty ? nil : String(address)
    }
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
