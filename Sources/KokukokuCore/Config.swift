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

    public struct Calendar: Codable, Equatable, Sendable {
        public var name: String
        public var refreshIntervalMinutes: Int?
        public var notificationLeadMinutes: Int?
        public var maxVisibleEvents: Int?
        public var gapRailMinutes: Int?
        public var upcomingCountdownMaxMinutes: Int?
        public var ongoingCountdownMaxMinutes: Int?

        public init(
            name: String,
            refreshIntervalMinutes: Int? = nil,
            notificationLeadMinutes: Int? = nil,
            maxVisibleEvents: Int? = nil,
            gapRailMinutes: Int? = nil,
            upcomingCountdownMaxMinutes: Int? = nil,
            ongoingCountdownMaxMinutes: Int? = nil
        ) {
            self.name = name
            self.refreshIntervalMinutes = refreshIntervalMinutes
            self.notificationLeadMinutes = notificationLeadMinutes
            self.maxVisibleEvents = maxVisibleEvents
            self.gapRailMinutes = gapRailMinutes
            self.upcomingCountdownMaxMinutes = upcomingCountdownMaxMinutes
            self.ongoingCountdownMaxMinutes = ongoingCountdownMaxMinutes
        }
    }

    public struct Keymap: Codable, Equatable, Sendable {
        public var startBreak: String?
        public var reset: String?
        public var toggleCalendar: String?

        public init(
            startBreak: String? = nil,
            reset: String? = nil,
            toggleCalendar: String? = nil
        ) {
            self.startBreak = startBreak
            self.reset = reset
            self.toggleCalendar = toggleCalendar
        }
    }

    public var projects: [Project]
    public var hotkey: Hotkey?
    public var alert: Alert?
    public var ui: UI?
    public var keymap: Keymap?
    public var calendar: Calendar?

    public init(
        projects: [Project] = [],
        hotkey: Hotkey? = nil,
        alert: Alert? = nil,
        ui: UI? = nil,
        keymap: Keymap? = nil,
        calendar: Calendar? = nil
    ) {
        self.projects = projects
        self.hotkey = hotkey
        self.alert = alert
        self.ui = ui
        self.keymap = keymap
        self.calendar = calendar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        self.alert = try container.decodeIfPresent(Alert.self, forKey: .alert)
        self.ui = try container.decodeIfPresent(UI.self, forKey: .ui)
        self.keymap = try container.decodeIfPresent(Keymap.self, forKey: .keymap)
        self.calendar = try container.decodeIfPresent(Calendar.self, forKey: .calendar)
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
    public var toggleCalendar: String

    public init(keymap: KokukokuConfig.Keymap?) {
        self.startBreak = keymap?.startBreak ?? "0"
        self.reset = keymap?.reset ?? "r"
        self.toggleCalendar = keymap?.toggleCalendar ?? "o"
    }
}

/// [calendar] 設定の既定値を解決したもの
public struct ResolvedCalendarConfig: Equatable, Sendable {
    public var name: String
    public var refreshIntervalMinutes: Int
    public var notificationLeadMinutes: Int
    /// 展開前に表示する予定数の上限(超過分は「他◯件」に畳む)。
    /// パネルの本業は計測操作のため既定は控えめの3
    public var maxVisibleEvents: Int
    /// タイムラインのレールを表示する最小間隔(分)。これ未満は「間隔なし」の接触表現になる
    public var gapRailMinutes: Int
    /// 未開始予定の「あと◯◯」を表示する残り時間の上限(分)。
    /// 既定120: 集中力の一区切り(60〜90分)の手前で見えれば「あとどれだけ作業してよいか」の判断に足りる
    public var upcomingCountdownMaxMinutes: Int
    /// 進行中予定の「終了まで◯◯」を表示する残り時間の上限(分)。
    /// 既定30: 終わりが迫って急ぐ判断が要るときだけ出す
    public var ongoingCountdownMaxMinutes: Int

    public init(calendar: KokukokuConfig.Calendar) {
        self.name = calendar.name
        self.refreshIntervalMinutes = calendar.refreshIntervalMinutes ?? 5
        self.notificationLeadMinutes = calendar.notificationLeadMinutes ?? 5
        self.maxVisibleEvents = calendar.maxVisibleEvents ?? 2
        self.gapRailMinutes = calendar.gapRailMinutes ?? 1
        self.upcomingCountdownMaxMinutes = calendar.upcomingCountdownMaxMinutes ?? 120
        self.ongoingCountdownMaxMinutes = calendar.ongoingCountdownMaxMinutes ?? 30
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
        if let calendar = config.calendar {
            if calendar.name.isEmpty {
                throw ConfigError.invalid(description: "calendar.name must be a non-empty string")
            }
            if let interval = calendar.refreshIntervalMinutes, interval < 1 {
                throw ConfigError.invalid(
                    description: "calendar.refreshIntervalMinutes must be >= 1")
            }
            if let lead = calendar.notificationLeadMinutes, lead < 1 {
                throw ConfigError.invalid(
                    description: "calendar.notificationLeadMinutes must be >= 1")
            }
            if let max = calendar.maxVisibleEvents, max < 1 {
                throw ConfigError.invalid(description: "calendar.maxVisibleEvents must be >= 1")
            }
            if let rail = calendar.gapRailMinutes, rail < 1 {
                throw ConfigError.invalid(description: "calendar.gapRailMinutes must be >= 1")
            }
            if let max = calendar.upcomingCountdownMaxMinutes, max < 1 {
                throw ConfigError.invalid(
                    description: "calendar.upcomingCountdownMaxMinutes must be >= 1")
            }
            if let max = calendar.ongoingCountdownMaxMinutes, max < 1 {
                throw ConfigError.invalid(
                    description: "calendar.ongoingCountdownMaxMinutes must be >= 1")
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
