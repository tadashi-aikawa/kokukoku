import Testing

@testable import KokukokuCore

@Suite("EventPopoverButtonFocus")
struct EventPopoverButtonFocusTests {
    @Test("ボタンがなければ前進は何もせず、後退はpopupを閉じる")
    func emptyButtons() {
        #expect(EventPopoverButtonFocus.moved(from: nil, delta: 1, count: 0) == .none)
        #expect(EventPopoverButtonFocus.moved(from: nil, delta: -1, count: 0) == .closePopover)
    }

    @Test("未フォーカスからは前進で先頭ボタンに入り、後退はpopupを閉じる")
    func enterFromUnfocused() {
        #expect(EventPopoverButtonFocus.moved(from: nil, delta: 1, count: 2) == .focus(0))
        #expect(EventPopoverButtonFocus.moved(from: nil, delta: -1, count: 2) == .closePopover)
    }

    @Test("前進・後退で隣のボタンへ移動する")
    func moveBetweenButtons() {
        #expect(EventPopoverButtonFocus.moved(from: 0, delta: 1, count: 3) == .focus(1))
        #expect(EventPopoverButtonFocus.moved(from: 2, delta: -1, count: 3) == .focus(1))
    }

    @Test("先頭ボタンから後退するとpopupを閉じる")
    func closeFromFirstButton() {
        #expect(EventPopoverButtonFocus.moved(from: 0, delta: -1, count: 2) == .closePopover)
    }

    @Test("末尾ボタンから前進しても末尾に留まる(循環しない)")
    func stayAtLast() {
        #expect(EventPopoverButtonFocus.moved(from: 1, delta: 1, count: 2) == .focus(1))
    }

    @Test("ボタンが1つだけでも入る・留まる・閉じるが成立する")
    func singleButton() {
        #expect(EventPopoverButtonFocus.moved(from: nil, delta: 1, count: 1) == .focus(0))
        #expect(EventPopoverButtonFocus.moved(from: 0, delta: 1, count: 1) == .focus(0))
        #expect(EventPopoverButtonFocus.moved(from: 0, delta: -1, count: 1) == .closePopover)
    }
}
