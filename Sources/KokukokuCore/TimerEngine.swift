import Foundation

public struct TimerSnapshot: Equatable, Sendable {
    public struct ProjectSnapshot: Equatable, Sendable {
        public var id: String
        public var name: String
        public var icon: String?
        public var accumulated: Int
        public var isActive: Bool

        public init(
            id: String,
            name: String,
            icon: String? = nil,
            accumulated: Int,
            isActive: Bool
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.accumulated = accumulated
            self.isActive = isActive
        }
    }

    public var projects: [ProjectSnapshot]
    public var activeProjectId: String?
    public var currentElapsed: Int
    public var continuousElapsed: Int
    public var isRunning: Bool

    public init(
        projects: [ProjectSnapshot],
        activeProjectId: String?,
        currentElapsed: Int,
        continuousElapsed: Int,
        isRunning: Bool
    ) {
        self.projects = projects
        self.activeProjectId = activeProjectId
        self.currentElapsed = currentElapsed
        self.continuousElapsed = continuousElapsed
        self.isRunning = isRunning
    }
}

public final class TimerEngine {
    private let projects: [KokukokuConfig.Project]
    private let now: () -> Int
    private let onStateChange: ((TimerState) -> Void)?
    private var currentState: TimerState

    public init(
        projects: [KokukokuConfig.Project],
        initialState: TimerState? = nil,
        now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
        onStateChange: ((TimerState) -> Void)? = nil
    ) {
        self.projects = projects
        self.now = now
        self.onStateChange = onStateChange
        if var initialState {
            if initialState.continuousElapsedBase < 0 {
                initialState.continuousElapsedBase = 0
            }
            self.currentState = initialState
        } else {
            self.currentState = TimerState(lastResetAt: now())
        }
    }

    public func startProject(_ projectId: String) {
        guard projects.contains(where: { $0.id == projectId }) else { return }

        finalizeActive()
        currentState.activeProjectId = projectId
        currentState.activeStartedAt = now()
        if currentState.continuousStartedAt == nil {
            currentState.continuousStartedAt = now()
        }
        notifyStateChange()
    }

    public func startBreak() {
        finalizeActive()
        currentState.continuousElapsedBase = 0
        currentState.continuousStartedAt = nil
        notifyStateChange()
    }

    public func reset() {
        finalizeActive()
        currentState.accumulated = [:]
        currentState.continuousElapsedBase = 0
        currentState.continuousStartedAt = nil
        currentState.lastResetAt = now()
        notifyStateChange()
    }

    @discardableResult
    public func setAccumulated(projectId: String, seconds: Int) -> Bool {
        guard projects.contains(where: { $0.id == projectId }), seconds >= 0 else { return false }

        if currentState.activeProjectId == projectId, currentState.activeStartedAt != nil {
            currentState.activeStartedAt = now()
        }
        currentState.accumulated[projectId] = seconds
        notifyStateChange()
        return true
    }

    @discardableResult
    public func setContinuousElapsed(_ seconds: Int) -> Bool {
        guard seconds >= 0 else { return false }

        currentState.continuousElapsedBase = seconds
        if currentState.activeProjectId != nil, currentState.activeStartedAt != nil {
            currentState.continuousStartedAt = now()
        } else {
            currentState.continuousStartedAt = nil
        }
        notifyStateChange()
        return true
    }

    public var state: TimerState {
        currentState
    }

    public func snapshot() -> TimerSnapshot {
        let projectSnapshots = projects.map { project in
            var accumulated = currentState.accumulated[project.id] ?? 0
            if currentState.activeProjectId == project.id,
                let activeStartedAt = currentState.activeStartedAt
            {
                accumulated += now() - activeStartedAt
            }
            return TimerSnapshot.ProjectSnapshot(
                id: project.id,
                name: project.name,
                icon: project.icon,
                accumulated: accumulated,
                isActive: currentState.activeProjectId == project.id)
        }

        let currentElapsed: Int
        if currentState.activeProjectId != nil, let activeStartedAt = currentState.activeStartedAt {
            currentElapsed = now() - activeStartedAt
        } else {
            currentElapsed = 0
        }

        var continuousElapsed = currentState.continuousElapsedBase
        if let continuousStartedAt = currentState.continuousStartedAt {
            continuousElapsed += now() - continuousStartedAt
        }

        return TimerSnapshot(
            projects: projectSnapshots,
            activeProjectId: currentState.activeProjectId,
            currentElapsed: currentElapsed,
            continuousElapsed: continuousElapsed,
            isRunning: currentState.activeProjectId != nil)
    }

    public static func formatTime(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "00:00:00" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private func finalizeActive() {
        if let activeProjectId = currentState.activeProjectId,
            let activeStartedAt = currentState.activeStartedAt
        {
            let elapsed = now() - activeStartedAt
            currentState.accumulated[activeProjectId, default: 0] += elapsed
        }
        currentState.activeProjectId = nil
        currentState.activeStartedAt = nil
    }

    private func notifyStateChange() {
        onStateChange?(currentState)
    }
}
