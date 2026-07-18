import AppKit
import KokukokuCore

/// 時刻表示の位置に重ねるインライン編集フィールド。
/// Enterで確定・Escでキャンセル。不正入力は赤字で示し編集を継続する。
@MainActor
final class InlineTimeEditor: NSObject, NSTextFieldDelegate {
    let field: NSTextField
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    // アクセントはPanelLayout.Colors.activeText(炎色)と揃える
    private static let accent = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.50, alpha: 1)
    private static let invalid = NSColor(srgbRed: 1, green: 0.4, blue: 0.4, alpha: 1)
    private static let textColor = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.83, alpha: 1)

    init(frame: NSRect, text: String, fontName: String, fontSize: Double,
         alignment: NSTextAlignment) {
        field = NSTextField(frame: frame)
        super.init()
        let cell = CenteredTextFieldCell(textCell: "")
        cell.usesSingleLineMode = true
        cell.isScrollable = true
        cell.wraps = false
        field.cell = cell
        field.isEditable = true
        field.isSelectable = true
        field.stringValue = text
        field.font = NSFont(name: fontName, size: fontSize)
            ?? .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        field.alignment = alignment
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.08, alpha: 1)
        field.textColor = Self.textColor
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1
        field.layer?.borderColor = Self.accent.cgColor
        field.delegate = self
    }

    /// first responder化と、フィールドエディタの配色(挿入点・選択ハイライト)の調整。
    /// 標準の青ハイライトは暗色パネル上で白文字が溶けるため、アクセント色+黒文字にする
    func activate(in window: NSWindow) {
        window.makeFirstResponder(field)
        guard let fieldEditor = field.currentEditor() as? NSTextView else { return }
        fieldEditor.insertionPointColor = Self.textColor
        fieldEditor.selectedTextAttributes = [
            .backgroundColor: Self.accent,
            .foregroundColor: NSColor.black,
        ]
    }

    func markInvalid() {
        field.textColor = Self.invalid
        field.layer?.borderColor = Self.invalid.cgColor
    }

    func controlTextDidChange(_ obj: Notification) {
        field.textColor = Self.textColor
        field.layer?.borderColor = Self.accent.cgColor
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onCommit?(field.stringValue)
            return true
        }
        // Escは補完が有効な環境ではcomplete:に化けるため両方をキャンセル扱いにする
        if commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSStandardKeyBindingResponding.complete(_:))
        {
            onCancel?()
            return true
        }
        return false
    }
}

/// NSTextFieldCellは単一行でも文字を上寄せで描くため、枠の縦中央に補正する。
/// 編集中の文字はフィールドエディタが描くので、その配置経路
/// (edit/select(withFrame:))にも同じ補正が要る
private final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centered(rect))
    }

    override func edit(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
        delegate: Any?, event: NSEvent?
    ) {
        super.edit(
            withFrame: centered(rect), in: controlView, editor: textObj,
            delegate: delegate, event: event)
    }

    override func select(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
        delegate: Any?, start selStart: Int, length selLength: Int
    ) {
        super.select(
            withFrame: centered(rect), in: controlView, editor: textObj,
            delegate: delegate, start: selStart, length: selLength)
    }

    private func centered(_ rect: NSRect) -> NSRect {
        let contentHeight = cellSize(forBounds: rect).height
        let delta = rect.height - contentHeight
        guard delta > 0 else { return rect }
        var adjusted = rect
        adjusted.origin.y += floor(delta / 2)
        adjusted.size.height -= delta
        return adjusted
    }
}
