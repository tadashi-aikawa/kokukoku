import AppKit
import KokukokuCore

/// パネル用の nonactivating ウィンドウ(JINRAIのOverlayPanelと同型)。
/// アプリをアクティブ化せずにキーウィンドウになれるため、
/// 閉じたときに直前のアクティブアプリへフォーカスが自然に戻る。
@MainActor
final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    var onKeyDown: ((NSEvent) -> Bool)?
    var onBecomeKey: (() -> Void)?
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // AppKit標準の表示アニメーションを無効化(Spoon版と同じ瞬間表示にする)
        animationBehavior = .none
    }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}
