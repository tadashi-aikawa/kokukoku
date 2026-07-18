public struct TimerState: Codable, Equatable, Sendable {
    public var accumulated: [String: Int]
    public var activeProjectId: String?
    public var activeStartedAt: Int?
    public var continuousElapsedBase: Int
    public var continuousStartedAt: Int?
    public var lastResetAt: Int

    public init(
        accumulated: [String: Int] = [:],
        activeProjectId: String? = nil,
        activeStartedAt: Int? = nil,
        continuousElapsedBase: Int = 0,
        continuousStartedAt: Int? = nil,
        lastResetAt: Int = 0
    ) {
        self.accumulated = accumulated
        self.activeProjectId = activeProjectId
        self.activeStartedAt = activeStartedAt
        self.continuousElapsedBase = continuousElapsedBase
        self.continuousStartedAt = continuousStartedAt
        self.lastResetAt = lastResetAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if !container.contains(.accumulated) {
            accumulated = [:]
        } else if try container.decodeNil(forKey: .accumulated) {
            accumulated = [:]
        } else {
            do {
                accumulated = try container.decode([String: Int].self, forKey: .accumulated)
            } catch {
                _ = try container.decode(EmptyArray.self, forKey: .accumulated)
                accumulated = [:]
            }
        }

        activeProjectId = try container.decodeIfPresent(String.self, forKey: .activeProjectId)
        activeStartedAt = try container.decodeIfPresent(Int.self, forKey: .activeStartedAt)
        continuousElapsedBase =
            try container.decodeIfPresent(Int.self, forKey: .continuousElapsedBase) ?? 0
        continuousStartedAt = try container.decodeIfPresent(Int.self, forKey: .continuousStartedAt)
        lastResetAt = try container.decodeIfPresent(Int.self, forKey: .lastResetAt) ?? 0
    }
}

private struct EmptyArray: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.unkeyedContainer()
        guard container.isAtEnd else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Expected an empty array"))
        }
    }
}
