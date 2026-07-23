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

    @Test("popover表示中はh/l・左右キーをボタンフォーカス移動として解釈する")
    func eventPopoverNavigation() {
        let context = PanelKeyContext(
            isEventPopoverVisible: true,
            isCalendarEventSelected: true,
            isPopoverForSelectedEvent: true)

        #expect(action("l", context: context) == .moveEventPopoverFocus(delta: 1))
        #expect(action("h", context: context) == .moveEventPopoverFocus(delta: -1))
        #expect(action(nil, keyCode: 124, context: context) == .moveEventPopoverFocus(delta: 1))
        #expect(action(nil, keyCode: 123, context: context) == .moveEventPopoverFocus(delta: -1))
    }

    @Test("popover表示中でもカーソルが別の予定ならl・右キーはpopover切替として解釈する")
    func switchPopoverToSelectedEvent() {
        let context = PanelKeyContext(
            isEventPopoverVisible: true,
            isCalendarEventSelected: true,
            isPopoverForSelectedEvent: false)

        #expect(action("l", context: context) == .showEventPopover)
        #expect(action(nil, keyCode: 124, context: context) == .showEventPopover)
        // h/左はカーソル位置にかかわらずフォーカス後退(popoverクローズ側)のまま
        #expect(action("h", context: context) == .moveEventPopoverFocus(delta: -1))
    }

    @Test("popover表示中にカーソルが予定以外の行にあるときのl・右キーはフォーカスインする")
    func focusInWhenNonEventSelected() {
        let context = PanelKeyContext(isEventPopoverVisible: true)

        #expect(action("l", context: context) == .moveEventPopoverFocus(delta: 1))
    }

    @Test("予定行選択中はl・右キーでpopoverを開く")
    func showEventPopover() {
        let context = PanelKeyContext(isCalendarEventSelected: true)

        #expect(action("l", context: context) == .showEventPopover)
        #expect(action(nil, keyCode: 124, context: context) == .showEventPopover)
        #expect(action("h", context: context) == .reserved)
    }

    @Test("Pin中のESCはpopover表示中ならpopoverだけ閉じ、popoverなしなら何もしない")
    func escWhilePinned() {
        let withPopover = PanelKeyContext(isEventPopoverVisible: true, isPinned: true)
        #expect(action(nil, keyCode: 53, context: withPopover) == .dismissPopover)

        let withoutPopover = PanelKeyContext(isEventPopoverVisible: false, isPinned: true)
        #expect(action(nil, keyCode: 53, context: withoutPopover) == .reserved)
    }

    @Test("Pin中でなければESCは従来どおりパネルを閉じる")
    func escWhileUnpinned() {
        let withPopover = PanelKeyContext(isEventPopoverVisible: true, isPinned: false)
        #expect(action(nil, keyCode: 53, context: withPopover) == .dismiss)

        #expect(action(nil, keyCode: 53) == .dismiss)
    }

    @Test("修飾キー付き矢印はコンテキストにかかわらず消費しない")
    func modifiedArrowsPassThrough() {
        let context = PanelKeyContext(
            isEventPopoverVisible: true, isCalendarEventSelected: true)

        for keyCode: UInt16 in 123...126 {
            #expect(
                action(nil, keyCode: keyCode, hasModifiers: true, context: context)
                    == .passthrough)
        }
    }

    @Test("修飾キー付き文字キーはコンテキストにかかわらず消費しない")
    func modifiedCharactersPassThrough() {
        let context = PanelKeyContext(
            isEventPopoverVisible: true, isCalendarEventSelected: true)

        for characters in ["g", "G", "]", "h", "l", "j", "k", "0", "r", "o", "e", "E", "c", "3"] {
            #expect(action(characters, hasModifiers: true, context: context) == .passthrough)
        }
    }

    @Test("h/lはキーマップより優先する予約キー")
    func reservedKeysPrecedeKeymap() {
        let keymap = ResolvedKeymap(
            keymap: .init(startBreak: "h", reset: "l", toggleCalendar: "o"))

        #expect(
            PanelKeyInterpreter.interpret(characters: "h", keyCode: 0, keymap: keymap)
                == .reserved)
        #expect(
            PanelKeyInterpreter.interpret(characters: "l", keyCode: 0, keymap: keymap)
                == .reserved)
    }

    @Test("g/G/]でジャンプ操作を解釈する")
    func jumpNavigation() {
        #expect(action("g") == .moveToTop)
        #expect(action("G") == .moveToBottom)
        #expect(action("]") == .moveToFirstProject)
    }

    @Test("popover表示中もg/G/]でジャンプ操作を解釈する")
    func jumpNavigationWhilePopoverVisible() {
        let context = PanelKeyContext(isEventPopoverVisible: true)

        #expect(action("g", context: context) == .moveToTop)
        #expect(action("G", context: context) == .moveToBottom)
        #expect(action("]", context: context) == .moveToFirstProject)
    }

    @Test("g/G/]はキーマップより優先する固定キー")
    func jumpKeysPrecedeKeymap() {
        let keymap = ResolvedKeymap(
            keymap: .init(startBreak: "g", reset: "G", toggleCalendar: "]"))

        #expect(
            PanelKeyInterpreter.interpret(characters: "g", keyCode: 0, keymap: keymap)
                == .moveToTop)
        #expect(
            PanelKeyInterpreter.interpret(characters: "G", keyCode: 0, keymap: keymap)
                == .moveToBottom)
        #expect(
            PanelKeyInterpreter.interpret(characters: "]", keyCode: 0, keymap: keymap)
                == .moveToFirstProject)
    }

    @Test("既定キーマップと固定キーを解釈する")
    func defaultKeymap() {
        #expect(action("0") == .startBreak)
        #expect(action("r") == .reset)
        #expect(action("e") == .editTime)
        #expect(action("E") == .editContinuousTime)
        #expect(action("c") == .copyToClipboard)
        #expect(action("p") == .togglePin)
        #expect(action("o") == .toggleCalendar)
        #expect(action("3") == .selectProject(index: 3))
        #expect(action("x") == .passthrough)
    }

    @Test("カスタムキーマップを解釈する")
    func customKeymap() {
        let keymap = ResolvedKeymap(keymap: .init(startBreak: "b", reset: "R", toggleCalendar: "t"))

        #expect(PanelKeyInterpreter.interpret(characters: "b", keyCode: 0, keymap: keymap) == .startBreak)
        #expect(PanelKeyInterpreter.interpret(characters: "R", keyCode: 0, keymap: keymap) == .reset)
        #expect(PanelKeyInterpreter.interpret(characters: "t", keyCode: 0, keymap: keymap) == .toggleCalendar)
        #expect(PanelKeyInterpreter.interpret(characters: "0", keyCode: 0, keymap: keymap) == .passthrough)
        #expect(PanelKeyInterpreter.interpret(characters: "o", keyCode: 0, keymap: keymap) == .passthrough)
    }

    @Test("キーマップは数字選択より優先される")
    func keymapPrecedesNumber() {
        let keymap = ResolvedKeymap(keymap: .init(reset: "2"))

        #expect(PanelKeyInterpreter.interpret(characters: "2", keyCode: 0, keymap: keymap) == .reset)
    }

    private func action(
        _ characters: String?,
        keyCode: UInt16 = 0,
        hasModifiers: Bool = false,
        context: PanelKeyContext = .init()
    ) -> PanelKeyAction {
        PanelKeyInterpreter.interpret(
            characters: characters,
            keyCode: keyCode,
            hasModifiers: hasModifiers,
            context: context,
            keymap: defaults)
    }
}
