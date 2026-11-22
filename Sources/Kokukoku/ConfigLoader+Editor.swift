import AppKit
import KokukokuCore

extension ConfigLoader {
    /// 設定ファイルをエディタで開く。.toml を開くアプリが無いか開けなければテキストエディットで開く
    @MainActor
    static func openInEditor() {
        let url = defaultPath()
        do {
            try ensureConfigFileExists(at: url)
        } catch {
            showOpenError(error.localizedDescription)
            return
        }
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) {
            return
        }
        guard
            let textEdit = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.TextEdit")
        else {
            showOpenError(url.path)
            return
        }
        NSWorkspace.shared.open(
            [url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in showOpenError("\(error.localizedDescription)\n\n\(url.path)") }
        }
    }

    @MainActor
    private static func showOpenError(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "設定ファイルを開けません"
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
