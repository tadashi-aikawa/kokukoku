import Foundation
import Testing

@testable import KokukokuCore

@Suite("ConfigLoader")
struct ConfigLoaderTests {
    @Test("TOML文字列から全セクションを読み込める")
    func parseFullConfig() throws {
        let toml = """
            [[projects]]
            id = "dev"
            name = "Development"
            icon = "💻"

            [[projects]]
            id = "meeting"
            name = "Meeting"

            [hotkey]
            modifiers = ["alt"]
            key = "t"
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(
            config.projects == [
                .init(id: "dev", name: "Development", icon: "💻"),
                .init(id: "meeting", name: "Meeting"),
            ])
        #expect(config.hotkey == .init(modifiers: ["alt"], key: "t"))
    }

    @Test("空のTOMLはデフォルト設定になる")
    func parseEmptyConfig() throws {
        let config = try ConfigLoader.parse(toml: "")

        #expect(config == KokukokuConfig())
    }

    @Test("不正なTOMLはinvalidエラーになる")
    func parseInvalidConfig() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml: "projects = not-a-value")
        }
    }

    @Test("空のproject idはinvalidエラーになる")
    func parseEmptyProjectId() {
        let toml = """
            [[projects]]
            id = ""
            name = "Work"
            """

        #expect(throws: ConfigError.invalid(description: "projects[0].id must be a non-empty string")) {
            try ConfigLoader.parse(toml: toml)
        }
    }

    @Test("空のproject nameはinvalidエラーになる")
    func parseEmptyProjectName() {
        let toml = """
            [[projects]]
            id = "work"
            name = ""
            """

        #expect(
            throws: ConfigError.invalid(description: "projects[0].name must be a non-empty string")
        ) {
            try ConfigLoader.parse(toml: toml)
        }
    }

    @Test("重複したproject idはinvalidエラーになる")
    func parseDuplicateProjectId() {
        let toml = """
            [[projects]]
            id = "work"
            name = "Work"

            [[projects]]
            id = "work"
            name = "Work 2"
            """

        #expect(throws: ConfigError.invalid(description: "duplicate project id: work")) {
            try ConfigLoader.parse(toml: toml)
        }
    }

    @Test("設定ファイルが存在しない場合はデフォルト設定を返す")
    func loadMissingFile() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/kokukoku/config.toml")

        let config = try ConfigLoader.load(from: missing)

        #expect(config == KokukokuConfig())
    }

    @Test("設定ファイルから読み込める")
    func loadFromFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokukoku-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("config.toml")
        try """
        [[projects]]
        id = "work"
        name = "Work"
        """.write(to: file, atomically: true, encoding: .utf8)

        let config = try ConfigLoader.load(from: file)

        #expect(config.projects == [.init(id: "work", name: "Work")])
    }

    @Test("alertセクションを読み込める")
    func parseAlert() throws {
        let toml = """
            [alert.continuousWork]
            thresholds = [3600, 7200]
            message = "%d分経過"
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(
            config.alert == .init(
                continuousWork: .init(thresholds: [3600, 7200], message: "%d分経過")))
    }

    @Test("alertセクションがなければnilになる")
    func parseWithoutAlert() throws {
        let config = try ConfigLoader.parse(toml: "")

        #expect(config.alert == nil)
    }

    @Test("alertのmessageを省略できる")
    func parseAlertWithoutMessage() throws {
        let toml = """
            [alert.continuousWork]
            thresholds = [3600]
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(config.alert?.continuousWork?.thresholds == [3600])
        #expect(config.alert?.continuousWork?.message == nil)
    }

    @Test("ui・keymapセクションを読み込める")
    func parseUIAndKeymap() throws {
        let toml = """
            [ui]
            fontName = "Helvetica"
            copyTextFormat = "{name}: {h}"

            [keymap]
            startBreak = "b"
            reset = "R"
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(config.ui == .init(fontName: "Helvetica", copyTextFormat: "{name}: {h}"))
        #expect(config.keymap == .init(startBreak: "b", reset: "R"))
    }

    @Test("断捨離済みの旧設定キーは無視される")
    func parseIgnoresRemovedKeys() throws {
        let toml = """
            [ui]
            closeOnSwitch = false
            monoFontName = "Monaco"

            [keymap]
            toggleVersion = "V"
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(config.ui == .init())
        #expect(config.keymap == .init())
    }

    @Test("ui・keymapセクションがなければnilになる")
    func parseWithoutUIAndKeymap() throws {
        let config = try ConfigLoader.parse(toml: "")

        #expect(config.ui == nil)
        #expect(config.keymap == nil)
    }

    @Test("calendarセクションを読み込める")
    func parseCalendar() throws {
        let toml = """
            [calendar]
            name = "一般"
            refreshIntervalMinutes = 10
            notificationLeadMinutes = 3
            """

        let config = try ConfigLoader.parse(toml: toml)

        #expect(
            config.calendar
                == .init(name: "一般", refreshIntervalMinutes: 10, notificationLeadMinutes: 3))
    }

    @Test("calendarセクションがなければnilになる(連携は完全に無効)")
    func parseWithoutCalendar() throws {
        let config = try ConfigLoader.parse(toml: "")

        #expect(config.calendar == nil)
    }

    @Test("calendarのnameがなければinvalidエラーになる")
    func parseCalendarWithoutName() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse(toml: "[calendar]\nrefreshIntervalMinutes = 5")
        }
    }

    @Test("calendarのnameが空文字ならinvalidエラーになる")
    func parseCalendarEmptyName() {
        #expect(
            throws: ConfigError.invalid(description: "calendar.name must be a non-empty string")
        ) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"\"")
        }
    }

    @Test("calendarの更新間隔が1未満ならinvalidエラーになる")
    func parseCalendarInvalidRefreshInterval() {
        #expect(
            throws: ConfigError.invalid(
                description: "calendar.refreshIntervalMinutes must be >= 1")
        ) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"一般\"\nrefreshIntervalMinutes = 0")
        }
    }

    @Test("calendarの通知リード時間が1未満ならinvalidエラーになる")
    func parseCalendarInvalidNotificationLead() {
        #expect(
            throws: ConfigError.invalid(
                description: "calendar.notificationLeadMinutes must be >= 1")
        ) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"一般\"\nnotificationLeadMinutes = -1")
        }
    }

    @Test("calendarの参加者表示上限が1未満ならinvalidエラーになる")
    func parseCalendarInvalidMaxAttendees() {
        #expect(throws: ConfigError.invalid(description: "calendar.maxAttendees must be >= 1")) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"一般\"\nmaxAttendees = 0")
        }
    }

    @Test("calendarの予定表示上限が1未満ならinvalidエラーになる")
    func parseCalendarInvalidMaxVisibleEvents() {
        #expect(
            throws: ConfigError.invalid(description: "calendar.maxVisibleEvents must be >= 1")
        ) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"一般\"\nmaxVisibleEvents = 0")
        }
    }

    @Test("ui・keymapは部分指定できる")
    func parsePartialUIAndKeymap() throws {
        let config = try ConfigLoader.parse(toml: """
            [ui]
            fontName = "Helvetica"

            [keymap]
            reset = "x"
            """)

        #expect(config.ui == .init(fontName: "Helvetica"))
        #expect(config.keymap == .init(reset: "x"))
    }
}

@Suite("Resolved panel config")
struct ResolvedPanelConfigTests {
    @Test("UI設定の既定値を解決する")
    func defaultUI() {
        #expect(ResolvedUIConfig(ui: nil) == .init(ui: .init(
            fontName: ".AppleSystemUIFont",
            copyTextFormat: "- {name}: {hh}:{mm}:{ss}")))
    }

    @Test("UI設定の指定値と既定値をマージする")
    func partialUI() {
        let resolved = ResolvedUIConfig(ui: .init(fontName: "Helvetica"))

        #expect(resolved.fontName == "Helvetica")
        #expect(resolved.monoFontName == "Menlo")
        #expect(resolved.copyTextFormat == "- {name}: {hh}:{mm}:{ss}")
    }

    @Test("キーマップの既定値を解決する")
    func defaultKeymap() {
        let resolved = ResolvedKeymap(keymap: nil)

        #expect(resolved.startBreak == "0")
        #expect(resolved.reset == "r")
    }

    @Test("calendar設定の既定値を解決する")
    func defaultCalendar() {
        let resolved = ResolvedCalendarConfig(calendar: .init(name: "一般"))

        #expect(resolved.name == "一般")
        #expect(resolved.refreshIntervalMinutes == 5)
        #expect(resolved.notificationLeadMinutes == 5)
        #expect(resolved.maxAttendees == 5)
        #expect(resolved.maxVisibleEvents == 3)
        #expect(resolved.selfEmail == nil)
    }

    @Test("calendarのselfEmailを読み込める(空文字はinvalidエラー)")
    func parseCalendarSelfEmail() throws {
        let config = try ConfigLoader.parse(
            toml: "[calendar]\nname = \"一般\"\nselfEmail = \"me@example.com\"")

        #expect(ResolvedCalendarConfig(calendar: config.calendar!).selfEmail == "me@example.com")
        #expect(
            throws: ConfigError.invalid(description: "calendar.selfEmail must be a non-empty string")
        ) {
            try ConfigLoader.parse(toml: "[calendar]\nname = \"一般\"\nselfEmail = \"\"")
        }
    }

    @Test("calendar設定の指定値が既定値より優先される")
    func specifiedCalendar() {
        let resolved = ResolvedCalendarConfig(
            calendar: .init(name: "仕事", refreshIntervalMinutes: 15, notificationLeadMinutes: 2))

        #expect(resolved == ResolvedCalendarConfig(
            calendar: .init(name: "仕事", refreshIntervalMinutes: 15, notificationLeadMinutes: 2)))
        #expect(resolved.refreshIntervalMinutes == 15)
        #expect(resolved.notificationLeadMinutes == 2)
    }
}
