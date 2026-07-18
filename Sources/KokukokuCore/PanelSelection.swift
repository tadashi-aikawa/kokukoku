public enum PanelSelection {
    public static func nextIndex(current: Int?, projectCount: Int) -> Int {
        guard let current else { return 1 }
        let next = current + 1
        return next > projectCount ? 1 : next
    }

    public static func previousIndex(current: Int?, projectCount: Int) -> Int {
        guard let current else { return projectCount }
        let previous = current - 1
        return previous < 1 ? projectCount : previous
    }
}
