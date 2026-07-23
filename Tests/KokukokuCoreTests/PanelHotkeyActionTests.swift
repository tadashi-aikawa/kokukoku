import Testing

@testable import KokukokuCore

@Suite("PanelHotkeyDecision")
struct PanelHotkeyActionTests {
    @Test("非表示ならフォーカス・Pinの状態に関わらず表示する")
    func showsWhenHidden() {
        for focused in [false, true] {
            for pinned in [false, true] {
                #expect(
                    PanelHotkeyDecision.decide(visible: false, focused: focused, pinned: pinned)
                        == .show)
            }
        }
    }

    @Test("表示中かつ非フォーカスならPinの状態に関わらずフォーカスを移す(閉じない)")
    func focusesWhenVisibleButUnfocused() {
        for pinned in [false, true] {
            #expect(
                PanelHotkeyDecision.decide(visible: true, focused: false, pinned: pinned)
                    == .focus)
        }
    }

    @Test("表示中かつフォーカスありでPin onなら何もしない")
    func doesNothingWhenVisibleFocusedAndPinned() {
        #expect(
            PanelHotkeyDecision.decide(visible: true, focused: true, pinned: true) == .none)
    }

    @Test("表示中かつフォーカスありでPin offなら閉じる")
    func hidesWhenVisibleFocusedAndUnpinned() {
        #expect(
            PanelHotkeyDecision.decide(visible: true, focused: true, pinned: false) == .hide)
    }
}
