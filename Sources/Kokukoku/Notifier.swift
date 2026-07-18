import Foundation

/// macOS通知(元 hs.notify 相当)。
/// バンドルなしの実行バイナリではUserNotificationsフレームワークが使えないため、
/// AppleScriptの display notification で送出する。
enum Notifier {
    static func send(title: String, message: String) {
        let escapedTitle = escape(title)
        let escapedMessage = escape(message)
        let source = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\" sound name \"default\""
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
