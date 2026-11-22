import AppKit
import KokukokuCore

/// メニューの「アップデートを確認…」から起動する確認フロー(NSAlert ベース。JINRAIのUpdaterFeatureと同型)。
/// 更新そのものは行わず、Homebrew なら brew のコマンドを、それ以外はリリースページを案内する
@MainActor
final class UpdaterFeature {
    /// 確認の開始から、結果のアラートを閉じるまで立てておく(開発ビルドのアラート表示中の再入も防ぐ)
    private var checking = false

    func checkForUpdates() {
        guard !checking else { return }
        checking = true
        let currentVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0-development"

        Task { @MainActor in
            defer { checking = false }
            let content: UpdateAlertContent
            do {
                let result = try await UpdateChecker.check(currentVersion: currentVersion)
                content = .forResult(
                    result, target: UpdateChecker.target,
                    isInstalledViaHomebrew: UpdateChecker.isInstalledViaHomebrew)
            } catch {
                content = .forFailure(
                    errorDescription: error.localizedDescription, target: UpdateChecker.target)
            }
            present(content)
        }
    }

    private func present(_ content: UpdateAlertContent) {
        let alert = NSAlert()
        alert.messageText = content.title
        alert.informativeText = content.message
        alert.alertStyle = content.style == .warning ? .warning : .informational
        if let primary = content.primaryButton {
            alert.addButton(withTitle: primary.title)
            alert.addButton(withTitle: UpdateAlertContent.closeButtonTitle)
        }
        let response = alert.runModal()
        guard let primary = content.primaryButton, response == .alertFirstButtonReturn else { return }

        switch primary.action {
        case .copyCommandAndQuit(let command):
            NSPasteboard.general.clearContents()
            // コピーできないまま終了すると、更新のコマンドが手元に残らない
            guard NSPasteboard.general.setString(command, forType: .string) else {
                present(content)
                return
            }
            NSApp.terminate(nil)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        }
    }
}
