import AppKit
import KokukokuCore

/// メニューバー常駐アイコン(バージョン確認・アップデート確認・設定ファイル・設定再読込・終了の入口。JINRAIのStatusItemと同型)
@MainActor
final class StatusItem {
    private let item: NSStatusItem
    var onReloadConfig: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionItem = NSMenuItem(
            title: "KOKUKOKU \(version ?? "0.0.0-development")",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        let updateItem = NSMenuItem(
            title: "アップデートを確認…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        let openConfigItem = NSMenuItem(
            title: "設定ファイルを開く",
            action: #selector(openConfigFile),
            keyEquivalent: ""
        )
        openConfigItem.target = self
        menu.addItem(openConfigItem)
        let reloadItem = NSMenuItem(
            title: "設定を再読込",
            action: #selector(reloadConfig),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit KOKUKOKU",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        item.menu = menu
    }

    @objc private func reloadConfig() {
        onReloadConfig?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func openConfigFile() {
        ConfigLoader.openInEditor()
    }

    private static func menuBarIcon() -> NSImage? {
        if let image = IconStore.loadLogoImage() {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        let image = NSImage(
            systemSymbolName: "clock.fill",
            accessibilityDescription: "KOKUKOKU"
        )
        image?.isTemplate = true
        return image
    }
}
