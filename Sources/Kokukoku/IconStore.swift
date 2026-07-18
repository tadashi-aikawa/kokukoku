import AppKit
import KokukokuCore

/// アイコン画像のキャッシュと解決(元 ui_panel.lua の resolveIconImage / iconCache 相当)。
/// URLアイコンは非同期で一度だけ取得し、取得完了時に onLoad で再描画を促す。
@MainActor
final class IconStore {
    private enum Entry {
        case loading
        case loaded(NSImage)
        case failed
    }

    private var cache: [String: Entry] = [:]
    var onLoad: (() -> Void)?

    /// ロゴ画像(SwiftPMリソースのkokukoku.webp)。
    /// Bundle.moduleは「実行体と同じディレクトリ」か「ビルドマシンのbuildパス」しか
    /// 探さず、.appのContents/Resourcesを見つけられずfatalErrorするため自前で解決する
    /// (アプリ: Contents/Resources直下 / swift run: 実行体と同じ.buildディレクトリ)
    let logoImage: NSImage? = IconStore.loadLogoImage()

    private static func loadLogoImage() -> NSImage? {
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        for base in candidates {
            guard let base else { continue }
            let url = base
                .appendingPathComponent("Kokukoku_Kokukoku.bundle")
                .appendingPathComponent("kokukoku.webp")
            if let image = NSImage(contentsOf: url) { return image }
        }
        FileHandle.standardError.write(
            Data("Kokukoku: logo image not found in resource bundle\n".utf8))
        return nil
    }

    func image(forKey key: String) -> NSImage? {
        if key == "logo" { return logoImage }
        if case .loaded(let image)? = cache[key] { return image }
        return nil
    }

    /// PanelElementsBuilder に渡す解決関数
    func resolve(_ icon: String) -> IconResolution {
        switch IconKind.classify(icon) {
        case .url:
            let key = "url:" + icon
            switch cache[key] {
            case .loaded: return .image(key: key)
            case .loading, .failed: return .none
            case nil:
                cache[key] = .loading
                fetchURLIcon(icon, key: key)
                return .none
            }
        case .filePath:
            let resolvedPath = (icon as NSString).expandingTildeInPath
            let key = "path:" + resolvedPath
            switch cache[key] {
            case .loaded: return .image(key: key)
            case .loading, .failed: return .none
            case nil:
                if let image = NSImage(contentsOfFile: resolvedPath) {
                    cache[key] = .loaded(image)
                    return .image(key: key)
                }
                cache[key] = .failed
                return .none
            }
        case .text, .empty:
            return .none
        }
    }

    private func fetchURLIcon(_ urlString: String, key: String) {
        guard let url = URL(string: urlString) else {
            cache[key] = .failed
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, let image = NSImage(data: data) {
                    self.cache[key] = .loaded(image)
                } else {
                    self.cache[key] = .failed
                }
                self.onLoad?()
            }
        }.resume()
    }
}
