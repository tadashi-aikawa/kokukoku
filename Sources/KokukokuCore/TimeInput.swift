import Foundation

public enum TimeInput {
    public static func parse(_ string: String?) -> Int? {
        guard let string, !string.isEmpty else { return nil }

        if let number = Double(string), number.isFinite,
            number >= Double(Int.min), number < Double(Int.max)
        {
            return Int(floor(number))
        }

        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
            parts.allSatisfy({ part in
                !part.isEmpty && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
            })
        else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }

        if values.count == 3 {
            guard let hours = multiply(values[0], by: 3600),
                let minutes = multiply(values[1], by: 60),
                let partial = add(hours, minutes)
            else { return nil }
            return add(partial, values[2])
        }
        guard let minutes = multiply(values[0], by: 60) else { return nil }
        return add(minutes, values[1])
    }

    private static func multiply(_ lhs: Int, by rhs: Int) -> Int? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func add(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}
