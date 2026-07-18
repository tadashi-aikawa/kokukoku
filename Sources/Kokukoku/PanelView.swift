import AppKit
import KokukokuCore

/// [PanelElement] を描画するビュー(元 hs.canvas 相当)。
/// 座標系はLua版と同じ左上原点(isFlipped)。
@MainActor
final class PanelView: NSView {
    var elements: [PanelElement] = [] {
        didSet { needsDisplay = true }
    }
    var imageProvider: ((String) -> NSImage?)?
    var onMouseDown: ((String) -> Void)?
    var onHoverChange: ((String?) -> Void)?

    private var hoveredId: String?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for element in elements {
            switch element {
            case .rectangle(
                let frame, let fillColor, let cornerRadius,
                let strokeColor, let strokeWidth, _, _):
                let rect = nsRect(frame)
                let path =
                    cornerRadius > 0
                    ? NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                    : NSBezierPath(rect: rect)
                if fillColor.alpha > 0 {
                    nsColor(fillColor).setFill()
                    path.fill()
                }
                if let strokeColor, strokeWidth > 0 {
                    nsColor(strokeColor).setStroke()
                    path.lineWidth = strokeWidth
                    path.stroke()
                }
            case .circle(let center, let radius, let fillColor, let strokeColor, let strokeWidth):
                let rect = NSRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2)
                let path = NSBezierPath(ovalIn: rect)
                if let fillColor {
                    nsColor(fillColor).setFill()
                    path.fill()
                }
                if let strokeColor, strokeWidth > 0 {
                    nsColor(strokeColor).setStroke()
                    path.lineWidth = strokeWidth
                    path.stroke()
                }
            case .neonRectangle(
                let frame, let cornerRadius, let strokeColor, let strokeWidth,
                let glowColor, let glowRadius):
                let path = NSBezierPath(
                    roundedRect: nsRect(frame), xRadius: cornerRadius, yRadius: cornerRadius)
                path.lineWidth = strokeWidth
                NSGraphicsContext.current?.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = nsColor(glowColor)
                shadow.shadowBlurRadius = glowRadius
                shadow.shadowOffset = .zero
                shadow.set()
                nsColor(strokeColor).setStroke()
                path.stroke()
                NSGraphicsContext.current?.restoreGraphicsState()
                // にじみの上へ芯線を重ね描きしてネオン管の質感を出す
                nsColor(strokeColor).setStroke()
                path.stroke()
            case .line(let from, let to, let color, let width):
                context.setStrokeColor(cgColor(color))
                context.setLineWidth(width)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: from.x, y: from.y))
                context.addLine(to: CGPoint(x: to.x, y: to.y))
                context.strokePath()
            case .text(let frame, let text, let fontName, let fontSize, let color, let alignment):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byClipping
                switch alignment {
                case .left: paragraph.alignment = .left
                case .center: paragraph.alignment = .center
                case .right: paragraph.alignment = .right
                }
                let font =
                    NSFont(name: fontName, size: fontSize)
                    ?? NSFont.systemFont(ofSize: fontSize)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: nsColor(color),
                    .paragraphStyle: paragraph,
                ]
                NSAttributedString(string: text, attributes: attributes)
                    .draw(in: nsRect(frame))
            case .image(let frame, let iconKey, let scaling):
                guard let image = imageProvider?(iconKey) else { continue }
                let rect = fitRect(for: image, in: nsRect(frame), scaling: scaling)
                image.draw(
                    in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let id = trackedElementId(at: location(of: event)) {
            onMouseDown?(id)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: location(of: event))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(at: nil)
    }

    private func updateHover(at point: NSPoint?) {
        let id = point.flatMap { trackedElementId(at: $0) }
        guard id != hoveredId else { return }
        hoveredId = id
        onHoverChange?(id)
    }

    private func location(of event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// マウストラッキング対象の要素idを座標から引く(後勝ち=Luaのcanvasと同じ前面優先)
    private func trackedElementId(at point: NSPoint) -> String? {
        var found: String?
        for element in elements {
            if case .rectangle(let frame, _, _, _, _, let id, let tracksMouse) = element,
                tracksMouse, let id, nsRect(frame).contains(point)
            {
                found = id
            }
        }
        return found
    }

    private func nsRect(_ frame: PanelFrame) -> NSRect {
        NSRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }

    private func nsColor(_ color: PanelColor) -> NSColor {
        NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private func cgColor(_ color: PanelColor) -> CGColor {
        nsColor(color).cgColor
    }

    private func fitRect(for image: NSImage, in rect: NSRect, scaling: PanelImageScaling)
        -> NSRect
    {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return rect }
        let scale: CGFloat
        switch scaling {
        case .shrinkToFit:
            scale = min(1, min(rect.width / size.width, rect.height / size.height))
        case .scaleProportionally:
            scale = min(rect.width / size.width, rect.height / size.height)
        }
        let w = size.width * scale
        let h = size.height * scale
        return NSRect(
            x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
