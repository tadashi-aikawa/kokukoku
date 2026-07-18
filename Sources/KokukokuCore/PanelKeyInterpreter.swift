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
    case selectProject(index: Int)
    case passthrough
}

public enum PanelKeyInterpreter {
    public static func interpret(
        characters: String?, keyCode: UInt16, keymap: ResolvedKeymap
    ) -> PanelKeyAction {
        if keyCode == 53 { return .dismiss }
        if keyCode == 36 { return .confirm }
        if characters == "j" || keyCode == 125 { return .moveDown }
        if characters == "k" || keyCode == 126 { return .moveUp }
        if characters == keymap.startBreak { return .startBreak }
        if characters == keymap.reset { return .reset }
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
