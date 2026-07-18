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

            [breakItem]
            name = "Break"
            icon = "☕"

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
        #expect(config.breakItem == .init(name: "Break", icon: "☕"))
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
}
