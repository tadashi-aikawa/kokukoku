import Foundation

public struct Persistence {
    private let path: URL

    public init(path: URL = Persistence.defaultPath()) {
        self.path = path
    }

    public static func defaultPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local")
            .appendingPathComponent("state")
            .appendingPathComponent("kokukoku")
            .appendingPathComponent("state.json")
    }

    public func save(_ state: TimerState) {
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: path)
        } catch {}
    }

    public func load() -> TimerState? {
        guard let data = try? Data(contentsOf: path), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TimerState.self, from: data)
    }
}
