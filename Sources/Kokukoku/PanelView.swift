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
    private var hoverTrackingArea: NSTrackingArea?
    /// SVG要素のラスタライズ結果。蝋燭は分単位でしか変わらないため、
    /// 毎秒の再描画でパースが走らないようキーで使い回す
    private var svgCache: [String: NSImage] = [:]
    private var isDragging = false
    private var dragStartScreenLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self)
        hoverTrackingArea = area
        addTrackingArea(area)
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
                let frame, let cornerRadius, let strokeWidth,
                let topColor, let bottomColor, let glowColor, let glowRadius):
                drawNeonRectangle(
                    in: context, rect: nsRect(frame), cornerRadius: cornerRadius,
                    strokeWidth: strokeWidth, topColor: topColor, bottomColor: bottomColor,
                    glowColor: glowColor, glowRadius: glowRadius)
            case .line(let from, let to, let color, let width):
                context.setStrokeColor(cgColor(color))
                context.setLineWidth(width)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: from.x, y: from.y))
                context.addLine(to: CGPoint(x: to.x, y: to.y))
                context.strokePath()
            case .text(let frame, let text, let fontName, let fontSize, let color, let alignment):
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
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
            case .image(let frame, let iconKey, let scaling, let cornerRadius):
                guard let image = imageProvider?(iconKey) else { continue }
                let rect = fitRect(for: image, in: nsRect(frame), scaling: scaling)
                if cornerRadius > 0 {
                    NSGraphicsContext.current?.saveGraphicsState()
                    NSBezierPath(
                        roundedRect: rect,
                        xRadius: min(cornerRadius, rect.width / 2),
                        yRadius: min(cornerRadius, rect.height / 2)
                    ).addClip()
                }
                image.draw(
                    in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
                if cornerRadius > 0 {
                    NSGraphicsContext.current?.restoreGraphicsState()
                }
            case .svg(let frame, let svg, let cacheKey):
                guard let image = svgImage(svg, cacheKey: cacheKey) else { continue }
                image.draw(
                    in: nsRect(frame), from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
            }
        }
    }

    /// SVG文字列をNSImageへ。macOS 13以降のAppKitはSVGをベクターのまま読めるため、
    /// 表示サイズに応じて綺麗にラスタライズされる
    private func svgImage(_ svg: String, cacheKey: String) -> NSImage? {
        if let cached = svgCache[cacheKey] { return cached }
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        // 際限なく溜まらないよう上限を設ける。時計の針は毎分キーが増えるため
        // (12時間で720通り)数時間に一度ここで全消しになるが、
        // キャッシュが狙うのは「同じ分の間に来る毎秒の再描画」であり、
        // 消えた側は一枚0.6ms程度で焼き直せるので凝った追い出しは要らない
        if svgCache.count > 256 { svgCache.removeAll() }
        svgCache[cacheKey] = image
        return image
    }

    /// ネオン管の輝き: 広い朱のにじみ→内側の強い光の二層グローの上へ、
    /// 上=淡い黄金→下=橙の炎色グラデーションの芯を重ねる
    private func drawNeonRectangle(
        in context: CGContext, rect: NSRect, cornerRadius: Double, strokeWidth: Double,
        topColor: PanelColor, bottomColor: PanelColor,
        glowColor: PanelColor, glowRadius: Double
    ) {
        let path = CGPath(
            roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
            transform: nil)

        // 内側にほのかな光を満たす
        if let innerLight = cgColor(glowColor).copy(alpha: glowColor.alpha * 0.10) {
            context.saveGState()
            context.addPath(path)
            context.setFillColor(innerLight)
            context.fillPath()
            context.restoreGState()
        }

        for blurScale in [2.6, 1.4, 0.6] {
            context.saveGState()
            context.setShadow(
                offset: .zero, blur: glowRadius * blurScale, color: cgColor(glowColor))
            context.addPath(path)
            context.setStrokeColor(cgColor(bottomColor))
            context.setLineWidth(strokeWidth + 1)
            context.strokePath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(path.copy(
            strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [cgColor(topColor), cgColor(bottomColor)] as CFArray,
            locations: [0, 1])
        {
            // isFlippedのためminYが上端
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: [])
        }
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = location(of: event)
        if let id = trackedElementId(at: loc) {
            onMouseDown?(id)
            return
        }
        if loc.y < PanelLayout.clockSectionHeight {
            isDragging = true
            dragStartScreenLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = window?.frame.origin ?? .zero
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartScreenLocation.x
        let dy = current.y - dragStartScreenLocation.y
        let newOrigin = NSPoint(
            x: dragStartWindowOrigin.x + dx,
            y: dragStartWindowOrigin.y + dy)
        // 単一スクリーン矩形へのクランプは、ディスプレイ境界でクランプ先が切り替わった
        // 瞬間に座標が跳ねてカクつく。クランプ計算はやめて「移動先でもヘッダー(ドラッグの
        // 取っ手)がどこかの画面に掴み直せるだけ見えているか」の可否判定に置き換え、
        // 見えなくなる移動だけ無視する(境界をまたぐ中間位置にも置け、死角にも置き去らない)
        let size = window.frame.size
        let headerRect = NSRect(
            x: newOrigin.x,
            y: newOrigin.y + size.height - PanelLayout.clockSectionHeight,
            width: size.width,
            height: PanelLayout.clockSectionHeight)
        let grabbable = NSScreen.screens.contains { screen in
            let visible = screen.visibleFrame.intersection(headerRect)
            return visible.width >= 40 && visible.height >= 20
        }
        guard grabbable else { return }
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
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
