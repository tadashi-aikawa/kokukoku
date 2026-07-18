import Foundation
import TOMLKit

/// `~/.config/kokukoku/config.toml` に対応する設定。
public struct KokukokuConfig: Codable, Equatable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var icon: String?

        public init(id: String, name: String, icon: String? = nil) {
            self.id = id
            self.name = name
            self.icon = icon
        }
    }

    public struct BreakItem: Codable, Equatable, Sendable {
        public var name: String
        public var icon: String?

        public init(name: String, icon: String? = nil) {
            self.name = name
            self.icon = icon
        }
    }

    public struct Hotkey: Codable, Equatable, Sendable {
        public var modifiers: [String]
        public var key: String

        public init(modifiers: [String], key: String) {
            self.modifiers = modifiers
            self.key = key
        }
    }

    public struct Alert: Codable, Equatable, Sendable {
        public struct ContinuousWork: Codable, Equatable, Sendable {
            public var thresholds: [Int]
            public var message: String?

            public init(thresholds: [Int], message: String? = nil) {
                self.thresholds = thresholds
                self.message = message
            }
        }

        public var continuousWork: ContinuousWork?

        public init(continuousWork: ContinuousWork? = nil) {
            self.continuousWork = continuousWork
        }
    }

    public struct UI: Codable, Equatable, Sendable {
        public var fontName: String?
        public var copyTextFormat: String?

        public init(
            fontName: String? = nil,
            copyTextFormat: String? = nil
        ) {
            self.fontName = fontName
            self.copyTextFormat = copyTextFormat
        }
    }

    public struct Keymap: Codable, Equatable, Sendable {
        public var startBreak: String?
        public var reset: String?

        public init(
            startBreak: String? = nil,
            reset: String? = nil
        ) {
            self.startBreak = startBreak
            self.reset = reset
        }
    }

    public var projects: [Project]
    public var breakItem: BreakItem?
    public var hotkey: Hotkey?
    public var alert: Alert?
    public var ui: UI?
    public var keymap: Keymap?

    public init(
        projects: [Project] = [],
        breakItem: BreakItem? = nil,
        hotkey: Hotkey? = nil,
        alert: Alert? = nil,
        ui: UI? = nil,
        keymap: Keymap? = nil
    ) {
        self.projects = projects
        self.breakItem = breakItem
        self.hotkey = hotkey
        self.alert = alert
        self.ui = ui
        self.keymap = keymap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.breakItem = try container.decodeIfPresent(BreakItem.self, forKey: .breakItem)
        self.hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        self.alert = try container.decodeIfPresent(Alert.self, forKey: .alert)
        self.ui = try container.decodeIfPresent(UI.self, forKey: .ui)
        self.keymap = try container.decodeIfPresent(Keymap.self, forKey: .keymap)
    }
}

public struct ResolvedUIConfig: Equatable, Sendable {
    public var fontName: String
    /// 時間表示の等幅フォント(設定不可の固定値)
    public let monoFontName = "Menlo"
    public var copyTextFormat: String

    public init(ui: KokukokuConfig.UI?) {
        self.fontName = ui?.fontName ?? ".AppleSystemUIFont"
        self.copyTextFormat = ui?.copyTextFormat ?? "- {name}: {hh}:{mm}:{ss}"
    }
}

public struct ResolvedKeymap: Equatable, Sendable {
    public var startBreak: String
    public var reset: String

    public init(keymap: KokukokuConfig.Keymap?) {
        self.startBreak = keymap?.startBreak ?? "0"
        self.reset = keymap?.reset ?? "r"
    }
}

public enum ConfigError: Error, Equatable {
    case unreadable(path: String)
    case invalid(description: String)
}

public enum ConfigLoader {
    /// 既定の設定ファイルパス(JINRAIと同じ ~/.config/<product>/ 配下)
    public static func defaultPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("kokukoku")
            .appendingPathComponent("config.toml")
    }

    /// TOML文字列から設定を読み込む
    public static func parse(toml: String) throws -> KokukokuConfig {
        let config: KokukokuConfig
        do {
            config = try TOMLDecoder().decode(KokukokuConfig.self, from: toml)
        } catch {
            throw ConfigError.invalid(description: String(describing: error))
        }
        try validate(config)
        return config
    }

    /// Spoon版(timer_engine_config.lua)と同等の設定値検証
    private static func validate(_ config: KokukokuConfig) throws {
        var seenIds = Set<String>()
        for (index, project) in config.projects.enumerated() {
            if project.id.isEmpty {
                throw ConfigError.invalid(
                    description: "projects[\(index)].id must be a non-empty string")
            }
            if project.name.isEmpty {
                throw ConfigError.invalid(
                    description: "projects[\(index)].name must be a non-empty string")
            }
            if !seenIds.insert(project.id).inserted {
                throw ConfigError.invalid(description: "duplicate project id: \(project.id)")
            }
        }
    }

    /// 設定ファイルを読み込む。ファイルが存在しない場合はデフォルト設定を返す
    public static func load(from url: URL = defaultPath()) throws -> KokukokuConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return KokukokuConfig()
        }
        guard let toml = try? String(contentsOf: url, encoding: .utf8) else {
            throw ConfigError.unreadable(path: url.path)
        }
        return try parse(toml: toml)
    }
}
