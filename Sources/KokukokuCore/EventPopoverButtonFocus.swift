/// 予定詳細popover内のボタンフォーカス移動(h/l・←→)のロジック。
/// フォーカス位置 nil は「ボタン未フォーカス(メインUI側)」を表す
public enum EventPopoverButtonFocus {
    /// h/l移動の結果
    public enum Move: Equatable, Sendable {
        /// 指定インデックスのボタンへフォーカスを移す
        case focus(Int)
        /// popupを閉じてメインUIへ戻る(一番左のボタンからの後退)
        case closePopover
        /// 何もしない
        case none
    }

    /// メインUIを左端に置いた直線イメージで動く:
    /// 前進(l/→)は未フォーカスから先頭ボタンに入り、末尾では留まる。
    /// 後退(h/←)は先頭ボタンまたは未フォーカスからpopupクローズ
    public static func moved(from current: Int?, delta: Int, count: Int) -> Move {
        guard count > 0 else { return delta < 0 ? .closePopover : .none }
        guard let current else { return delta >= 0 ? .focus(0) : .closePopover }
        let next = current + delta
        if next < 0 { return .closePopover }
        return .focus(min(next, count - 1))
    }
}
