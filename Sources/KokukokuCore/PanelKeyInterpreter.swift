public enum PanelKeyAction: Equatable, Sendable {
    case dismiss
    case confirm
    case moveDown
    case moveUp
    case startBreak
    case reset
    case editTime
    case editContinuousTime
    case copyToClipboard
    case toggleCalendar
    case selectProject(index: Int)
    /// 予定詳細popover内のボタンフォーカスを移動する
    case moveEventPopoverFocus(delta: Int)
    /// 選択中の予定の詳細popoverを開く
    case showEventPopover
    /// 先頭へジャンプ(予定があれば予定の先頭)
    case moveToTop
    /// 末尾へジャンプ
    case moveToBottom
    /// 計測項目(プロジェクト行)の先頭へジャンプ
    case moveToFirstProject
    /// パネル固定(Pin)のon/off切替
    case togglePin
    /// パネルは残したまま、フォーカスだけ直前のアプリへ返す(popover表示中なら同時に閉じる)。
    /// Pin中にESCが押されたとき
    case returnFocus
    /// 現在のコンテキストでは動作しないが、他の操作には割り当てない(h/lの予約キーなど、
    /// 意図的に無効化するキー)
    case reserved
    case passthrough
}

/// パネルのキー解釈に必要な表示・選択コンテキスト
public struct PanelKeyContext: Equatable, Sendable {
    public var isEventPopoverVisible: Bool
    public var isCalendarEventSelected: Bool
    /// 表示中のpopoverが「選択カーソル配下の予定」を指しているか。
    /// カーソルが別の予定へ移った後のl/→はフォーカスインではなくpopoverの切替になる
    public var isPopoverForSelectedEvent: Bool
    /// パネル固定(Pin)がonか。ESCの挙動をホットキーと同様に閉じ抑止する判定に使う
    public var isPinned: Bool

    public init(
        isEventPopoverVisible: Bool = false,
        isCalendarEventSelected: Bool = false,
        isPopoverForSelectedEvent: Bool = false,
        isPinned: Bool = false
    ) {
        self.isEventPopoverVisible = isEventPopoverVisible
        self.isCalendarEventSelected = isCalendarEventSelected
        self.isPopoverForSelectedEvent = isPopoverForSelectedEvent
        self.isPinned = isPinned
    }
}

public enum PanelKeyInterpreter {
    public static func interpret(
        characters: String?,
        keyCode: UInt16,
        hasModifiers: Bool = false,
        context: PanelKeyContext = .init(),
        keymap: ResolvedKeymap
    ) -> PanelKeyAction {
        // Command/Option等とのOS標準ショートカットを妨げない
        if hasModifiers, (123...126).contains(keyCode) { return .passthrough }
        if hasModifiers, characters != nil { return .passthrough }
        if keyCode == 53 || characters == "q" {
            // Pin中はホットキーと同じく閉じ抑止: パネルは残したまま、
            // popoverが出ていれば閉じたうえでフォーカスを直前のアプリへ返す
            if context.isPinned { return .returnFocus }
            return .dismiss
        }
        if keyCode == 36 { return .confirm }
        if characters == "l" || keyCode == 124 {
            if context.isEventPopoverVisible {
                // カーソルが別の予定に移っているなら、まずその予定のpopoverへ切り替える
                if context.isCalendarEventSelected, !context.isPopoverForSelectedEvent {
                    return .showEventPopover
                }
                return .moveEventPopoverFocus(delta: 1)
            }
            if context.isCalendarEventSelected { return .showEventPopover }
            return .reserved
        }
        if characters == "h" || keyCode == 123 {
            if context.isEventPopoverVisible { return .moveEventPopoverFocus(delta: -1) }
            return .reserved
        }
        if characters == "g" { return .moveToTop }
        if characters == "G" { return .moveToBottom }
        if characters == "]" { return .moveToFirstProject }
        if characters == "j" || keyCode == 125 { return .moveDown }
        if characters == "k" || keyCode == 126 { return .moveUp }
        if characters == keymap.startBreak { return .startBreak }
        if characters == keymap.reset { return .reset }
        if characters == keymap.toggleCalendar { return .toggleCalendar }
        if characters == "p" { return .togglePin }
        if characters == "e" { return .editTime }
        if characters == "c" { return .copyToClipboard }
        if characters == "E" { return .editContinuousTime }
        if let characters, characters.count == 1,
            let scalar = characters.unicodeScalars.first,
            (49...57).contains(scalar.value)
        {
            return .selectProject(index: Int(scalar.value - 48))
        }
        return .passthrough
    }
}
