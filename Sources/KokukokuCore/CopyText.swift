import Foundation

public enum CopyText {
    public static func build(
        projects: [KokukokuConfig.Project],
        state: TimerState,
        lineFormat: String = "- {name}: {hh}:{mm}:{ss}",
        separator: String = "\n",
        now: () -> Int
    ) -> String {
        projects.compactMap { project in
            var accumulated = state.accumulated[project.id] ?? 0
            if state.activeProjectId == project.id, let activeStartedAt = state.activeStartedAt {
                accumulated += now() - activeStartedAt
            }
            guard accumulated > 0 else { return nil }

            let hours = accumulated / 3600
            let minutes = (accumulated % 3600) / 60
            let seconds = accumulated % 60
            let replacements = [
                "{name}": project.name,
                "{hh}": String(format: "%02d", hours),
                "{mm}": String(format: "%02d", minutes),
                "{ss}": String(format: "%02d", seconds),
                "{h}": String(hours),
                "{m}": String(minutes),
                "{s}": String(seconds),
            ]
            return replacePlaceholders(in: lineFormat, with: replacements)
        }.joined(separator: separator)
    }

    private static func replacePlaceholders(
        in format: String, with replacements: [String: String]
    ) -> String {
        var result = ""
        var index = format.startIndex

        while index < format.endIndex {
            if format[index] == "{",
                let closingIndex = format[index...].firstIndex(of: "}")
            {
                let endIndex = format.index(after: closingIndex)
                let placeholder = String(format[index..<endIndex])
                if let replacement = replacements[placeholder] {
                    result += replacement
                    index = endIndex
                    continue
                }
            }
            result.append(format[index])
            index = format.index(after: index)
        }

        return result
    }
}

public enum TodayScheduleCopyText {
    public static func build(
        events: [CalendarEvent],
        separator: String = "\n",
        calendar: Foundation.Calendar = .autoupdatingCurrent
    ) -> String {
        events.map { event in
            let startHour = calendar.component(.hour, from: event.start)
            let startMinute = calendar.component(.minute, from: event.start)
            let endHour = calendar.component(.hour, from: event.end)
            let endMinute = calendar.component(.minute, from: event.end)
            return String(
                format: "- %02d:%02d-%02d:%02d %@",
                startHour, startMinute, endHour, endMinute, event.title)
        }.joined(separator: separator)
    }
}
