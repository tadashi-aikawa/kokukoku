import Testing

@testable import KokukokuCore

@Suite("CopyText")
struct CopyTextTests {
    @Test("累積時間のあるプロジェクトのみ箇条書きにする")
    func buildNonZeroProjects() {
        let projects = makeProjects()
        let state = TimerState(accumulated: ["a": 3600, "b": 0, "c": 1830])

        let result = CopyText.build(projects: projects, state: state, now: { 100 })

        #expect(result == "- ProjectA: 01:00:00\n- ProjectC: 00:30:30")
    }

    @Test("全プロジェクトの累積が0なら空文字を返す")
    func buildEmptyText() {
        let result = CopyText.build(
            projects: [.init(id: "a", name: "ProjectA")], state: TimerState(), now: { 100 })

        #expect(result.isEmpty)
    }

    @Test("アクティブなプロジェクトの経過時間を含める")
    func includeActiveElapsed() {
        let state = TimerState(
            accumulated: ["a": 3600], activeProjectId: "a", activeStartedAt: 940)

        let result = CopyText.build(
            projects: [.init(id: "a", name: "ProjectA")], state: state, now: { 1000 })

        #expect(result == "- ProjectA: 01:01:00")
    }

    @Test("カスタムフォーマットで行を生成する")
    func customLineFormat() {
        let result = CopyText.build(
            projects: makeProjects(),
            state: TimerState(accumulated: ["a": 3600, "b": 1830]),
            lineFormat: "{name} ({hh}:{mm})",
            now: { 100 })

        #expect(result == "ProjectA (01:00)\nProjectB (00:30)")
    }

    @Test("カスタム区切り文字で結合する")
    func customSeparator() {
        let result = CopyText.build(
            projects: makeProjects(),
            state: TimerState(accumulated: ["a": 3600, "b": 1830]),
            lineFormat: "{name}: {hh}:{mm}",
            separator: " / ",
            now: { 100 })

        #expect(result == "ProjectA: 01:00 / ProjectB: 00:30")
    }

    @Test("全プレースホルダーを置換する")
    func replaceAllPlaceholders() {
        let result = CopyText.build(
            projects: [.init(id: "a", name: "ProjectA")],
            state: TimerState(accumulated: ["a": 3665]),
            lineFormat: "{name}|{hh}|{mm}|{ss}|{h}|{m}|{s}",
            now: { 100 })

        #expect(result == "ProjectA|01|01|05|1|1|5")
    }

    @Test("置換後のプロジェクト名に含まれるプレースホルダーは再置換しない")
    func doNotReplacePlaceholderInProjectName() {
        let result = CopyText.build(
            projects: [.init(id: "a", name: "{hh}")],
            state: TimerState(accumulated: ["a": 3600]),
            lineFormat: "{name}",
            now: { 100 })

        #expect(result == "{hh}")
    }

    private func makeProjects() -> [KokukokuConfig.Project] {
        [
            .init(id: "a", name: "ProjectA"),
            .init(id: "b", name: "ProjectB"),
            .init(id: "c", name: "ProjectC"),
        ]
    }
}
