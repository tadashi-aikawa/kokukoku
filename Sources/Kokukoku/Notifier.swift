import AppKit
import UserNotifications

/// macOS通知(元 hs.notify 相当)。
/// .appバンドル実行ではUserNotificationsで送る(アプリアイコンが表示され、クリックでパネルが開く)。
/// 素の実行バイナリ(swift run等)ではUserNotificationsが使えないためosascriptで送る。
enum Notifier {
    static let notificationTitle = "KOKUKOKU(刻刻)"

    @MainActor private static let delegate = NotificationDelegate()

    /// バンドル実行時のみUN通知をセットアップする(権限要求+クリックでパネル表示の配線)
    @MainActor
    static func setUp(onClick: @escaping @MainActor () -> Void) {
        guard supportsUserNotifications else { return }
        delegate.onClick = onClick
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                FileHandle.standardError.write(
                    Data("Kokukoku: notification permission denied\n".utf8))
            }
        }
    }

    static func send(_ message: String) {
        if supportsUserNotifications {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
            content.body = message
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: UUID().uuidString, content: content, trigger: nil))
        } else {
            sendViaOsascript(message)
        }
    }

    /// UNUserNotificationCenterはバンドルIDがない実行体から触るとクラッシュする
    private static var supportsUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private static func sendViaOsascript(_ message: String) {
        let source =
            "display notification \"\(escape(message))\" with title \"\(escape(notificationTitle))\" sound name \"default\""
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            try? process.run()
        }
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// UNUserNotificationCenter.delegateは弱参照のため、Notifier側で保持する
@MainActor
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (@MainActor () -> Void)?

    /// アプリ起動中でもバナーを出す(既定では前面アプリの通知は表示されない)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onClick?() }
    }
}
