import Testing

@testable import KokukokuCore

@Suite("PanelKeyInterpreter")
struct PanelKeyInterpreterTests {
    private let defaults = ResolvedKeymap(keymap: nil)

    @Test("特殊キーと移動キーを解釈する")
    func navigation() {
        #expect(PanelKeyInterpreter.interpret(characters: nil, keyCode: 53, keymap: defaults) == .dismiss)
        #expect(PanelKeyInterpreter.interpret(characters: nil, keyCode: 36, keymap: defaults) == .confirm)
        #expect(PanelKeyInterpreter.interpret(characters: "j", keyCode: 0, keymap: defaults) == .moveDown)
        #expect(PanelKeyInterpreter.interpret(characters: nil, keyCode: 125, keymap: defaults) == .moveDown)
        #expect(PanelKeyInterpreter.interpret(characters: "k", keyCode: 0, keymap: defaults) == .moveUp)
        #expect(PanelKeyInterpreter.interpret(characters: nil, keyCode: 126, keymap: defaults) == .moveUp)
    }

    @Test("既定キーマップを解釈する")
    func defaultKeymap() {
        #expect(action("0") == .startBreak)
        #expect(action("r") == .reset)
        #expect(action("v") == .toggleVersion)
        #expect(action("e") == .editTime)
        #expect(action("E") == .editContinuousTime)
        #expect(action("c") == .copyToClipboard)
        #expect(action("3") == .selectProject(index: 3))
        #expect(action("x") == .passthrough)
    }

    @Test("カスタムキーマップを解釈する")
    func customKeymap() {
        let keymap = ResolvedKeymap(keymap: .init(
            startBreak: "b", reset: "R", toggleVersion: "V", editTime: "t",
            editContinuousTime: "T", copyToClipboard: "y"))

        #expect(PanelKeyInterpreter.interpret(characters: "V", keyCode: 0, keymap: keymap) == .toggleVersion)
        #expect(PanelKeyInterpreter.interpret(characters: "v", keyCode: 0, keymap: keymap) == .passthrough)
    }

    @Test("キーマップは数字選択より優先される")
    func keymapPrecedesNumber() {
        let keymap = ResolvedKeymap(keymap: .init(reset: "2"))

        #expect(PanelKeyInterpreter.interpret(characters: "2", keyCode: 0, keymap: keymap) == .reset)
    }

    private func action(_ characters: String) -> PanelKeyAction {
        PanelKeyInterpreter.interpret(characters: characters, keyCode: 0, keymap: defaults)
    }
}
