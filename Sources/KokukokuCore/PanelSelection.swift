/// パネルのキーボード選択対象。予定行・「他◯件/畳む」行・プロジェクト行を
/// 一つの選択ループで回す(2026-07-19 タダシ決定で予定セクションへのキー操作を解禁)
public enum PanelSelectionTarget: Equatable, Sendable {
    /// 予定行。eventIndex は予定行だけを数えた 0-origin(クリックIDの cal_event_N と同じ数え方)
    case calendarEvent(eventIndex: Int)
    /// 「他◯件」行(Enterで全件展開)
    case calendarOverflow
    /// 「畳む」行(Enterで上限表示へ戻す)
    case calendarCollapse
    /// プロジェクト行(1-origin。Luaと同じ)
    case project(index: Int)
}

public enum PanelSelection {
    /// 選択ループの巡回順(見た目の上から下: 予定セクション→プロジェクト行)。
    /// 参加者・エラー・告知・鮮度の行は操作対象がないため選択に含めない
    public static func targets(
        calendarRows: [CalendarSectionRow], projectCount: Int
    ) -> [PanelSelectionTarget] {
        var targets: [PanelSelectionTarget] = []
        var eventIndex = 0
        for row in calendarRows {
            switch row {
            case .event:
                targets.append(.calendarEvent(eventIndex: eventIndex))
                eventIndex += 1
            case .overflow:
                targets.append(.calendarOverflow)
            case .collapse:
                targets.append(.calendarCollapse)
            case .attendees, .error, .notice, .freshness:
                break
            }
        }
        if projectCount > 0 {
            targets += (1...projectCount).map { .project(index: $0) }
        }
        return targets
    }

    /// 次の選択対象(末尾からは先頭へ折り返す)。未選択・選択対象が消えていた場合は先頭
    public static func next(
        current: PanelSelectionTarget?, in targets: [PanelSelectionTarget]
    ) -> PanelSelectionTarget? {
        guard !targets.isEmpty else { return nil }
        guard let current, let index = targets.firstIndex(of: current) else {
            return targets.first
        }
        return targets[(index + 1) % targets.count]
    }

    /// 前の選択対象(先頭からは末尾へ折り返す)。未選択・選択対象が消えていた場合は末尾
    public static func previous(
        current: PanelSelectionTarget?, in targets: [PanelSelectionTarget]
    ) -> PanelSelectionTarget? {
        guard !targets.isEmpty else { return nil }
        guard let current, let index = targets.firstIndex(of: current) else {
            return targets.last
        }
        return targets[(index - 1 + targets.count) % targets.count]
    }
}
