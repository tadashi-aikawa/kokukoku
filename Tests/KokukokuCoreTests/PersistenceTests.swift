import Foundation
import Testing

@testable import KokukokuCore

@Suite("Persistence")
struct PersistenceTests {
    @Test("状態を保存して等価な状態を読み込める")
    func saveAndLoadRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = Persistence(path: directory.appendingPathComponent("nested/state.json"))
        let state = TimerState(
            accumulated: ["proj-a": 3600],
            activeProjectId: "proj-a",
            activeStartedAt: 1_000_000,
            continuousElapsedBase: 120,
            continuousStartedAt: 999_000,
            lastResetAt: 990_000)

        persistence.save(state)

        #expect(persistence.load() == state)
    }

    @Test("空のaccumulatedを保存して読み込める")
    func saveAndLoadEmptyAccumulated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = Persistence(path: directory.appendingPathComponent("state.json"))
        let state = TimerState(lastResetAt: 990_000)

        persistence.save(state)

        #expect(persistence.load() == state)
    }

    @Test("ファイルが存在しない場合はnilを返す")
    func loadMissingFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(Persistence(path: directory.appendingPathComponent("missing.json")).load() == nil)
    }

    @Test("空ファイルの場合はnilを返す")
    func loadEmptyFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state.json")
        try Data().write(to: path)

        #expect(Persistence(path: path).load() == nil)
    }

    @Test("壊れたJSONの場合はnilを返す")
    func loadBrokenJSON() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state.json")
        try Data("not-json".utf8).write(to: path)

        #expect(Persistence(path: path).load() == nil)
    }

    @Test("既定パスはlocal state配下になる")
    func defaultPath() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/kokukoku/state.json")

        #expect(Persistence.defaultPath() == expected)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokukoku-persistence-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
