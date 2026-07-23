/// パネル表示ホットキー押下時に実行する動作。
/// 表示状態・フォーカス状態・Pin状態から一意に決まる(2026-07-24 仕様変更:
/// 表示中でも非フォーカスなら閉じずにフォーカスだけ移す)
public enum PanelHotkeyAction: Equatable, Sendable {
    /// 非表示 → 表示する
    case show
    /// 表示中だが非フォーカス → 閉じずにフォーカスを移す
    case focus
    /// 表示中かつフォーカスあり、Pin on → 何もしない(閉じない)
    case none
    /// 表示中かつフォーカスあり、Pin off → 閉じる
    case hide
}

public enum PanelHotkeyDecision {
    /// - Parameters:
    ///   - visible: パネルが表示中か
    ///   - focused: パネルがキーウィンドウか(`window.isKeyWindow`)
    ///   - pinned: パネル固定(Pin)がonか
    public static func decide(visible: Bool, focused: Bool, pinned: Bool) -> PanelHotkeyAction {
        guard visible else { return .show }
        guard focused else { return .focus }
        return pinned ? .none : .hide
    }
}
