import Foundation

public enum IconResolution: Equatable, Sendable {
    case image(key: String)
    case none
}

public struct PanelElementsBuilder {
    public struct Inputs: Sendable {
        public var projects: [KokukokuConfig.Project]
        public var breakItem: KokukokuConfig.BreakItem?
        public var state: TimerState
        public var selectedIndex: Int?
        public var hoveredId: String?
        public var resetConfirming: Bool
        public var editingTarget: PanelEditingTarget?
        public var ui: ResolvedUIConfig

        public init(
            projects: [KokukokuConfig.Project],
            breakItem: KokukokuConfig.BreakItem? = nil,
            state: TimerState,
            selectedIndex: Int? = nil,
            hoveredId: String? = nil,
            resetConfirming: Bool = false,
            editingTarget: PanelEditingTarget? = nil,
            ui: ResolvedUIConfig
        ) {
            self.projects = projects
            self.breakItem = breakItem
            self.state = state
            self.selectedIndex = selectedIndex
            self.hoveredId = hoveredId
            self.resetConfirming = resetConfirming
            self.editingTarget = editingTarget
            self.ui = ui
        }
    }

    private let now: () -> Int
    private let localTime: () -> ClockTime
    private let measureTextHeight: (_ text: String, _ fontName: String, _ size: Double) -> Double
    private let resolveIcon: (String) -> IconResolution
    private let hasLogoImage: Bool

    public init(
        now: @escaping () -> Int,
        localTime: @escaping () -> ClockTime = { ClockTime(hour: 0, minute: 0, second: 0) },
        measureTextHeight: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double,
        resolveIcon: @escaping (String) -> IconResolution,
        hasLogoImage: Bool
    ) {
        self.now = now
        self.localTime = localTime
        self.measureTextHeight = measureTextHeight
        self.resolveIcon = resolveIcon
        self.hasLogoImage = hasLogoImage
    }

    public func build(_ inputs: Inputs) -> [PanelElement] {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let panelHeight = layout.panelHeight(projectCount: inputs.projects.count)
        var elements: [PanelElement] = []

        elements.append(.rectangle(
            frame: .init(x: 0, y: 0, w: layout.panelWidth, h: panelHeight),
            fillColor: colors.background,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: 0, w: layout.panelWidth, h: layout.clockSectionHeight),
            fillColor: colors.headerBg,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: layout.clockSectionHeight - 10, w: layout.panelWidth, h: 10),
            fillColor: colors.headerBg))

        appendClock(inputs, to: &elements)

        elements.append(.rectangle(
            frame: .init(x: 0, y: layout.clockSectionHeight, w: layout.panelWidth, h: 1),
            fillColor: colors.separator))

        for (offset, project) in inputs.projects.enumerated() {
            let index = offset + 1
            let y = layout.clockSectionHeight + Double(offset) * layout.rowHeight
            let isActive = inputs.state.activeProjectId == project.id
            // マウスホバーは背景の明度変化のみ。キーボード選択はカプセル輪郭で示す(末尾で構築)
            let isHovered = inputs.hoveredId == "row_\(project.id)"
            let rowColor: PanelColor
            if isActive {
                rowColor = isHovered ? colors.activeRowHoverBg : colors.activeRowBg
            } else {
                rowColor = isHovered ? colors.rowHoverBg : colors.rowBg
            }
            elements.append(.rectangle(
                frame: .init(x: 0, y: y, w: layout.panelWidth, h: layout.rowHeight),
                fillColor: rowColor,
                id: "row_\(project.id)",
                tracksMouse: true))

            if index <= 9 {
                let numberText = String(index)
                let height = measureTextHeight(numberText, inputs.ui.monoFontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: layout.padding, y: y + centeredOffset(layout.rowHeight, height),
                        w: 20, h: height),
                    text: numberText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: colors.subText))
            }

            let icon = project.icon ?? ""
            appendIcon(
                icon, x: layout.projectContentX, containerY: y,
                containerHeight: layout.rowHeight, color: isActive ? colors.activeText : colors.text,
                fontName: inputs.ui.fontName, fontSize: 17, to: &elements)

            let nameX = layout.projectContentX + layout.iconSlotWidth + layout.iconGap
            let nameHeight = measureTextHeight(project.name, inputs.ui.fontName, 16)
            elements.append(.text(
                frame: .init(
                    x: nameX, y: y + centeredOffset(layout.rowHeight, nameHeight),
                    w: layout.projectNameRight - nameX, h: nameHeight),
                text: project.name,
                fontName: inputs.ui.fontName,
                fontSize: 16,
                color: isActive ? colors.activeText : colors.text))

            var accumulated = inputs.state.accumulated[project.id] ?? 0
            if isActive, let startedAt = inputs.state.activeStartedAt {
                accumulated += now() - startedAt
            }
            if inputs.editingTarget != .project(id: project.id) {
                let accumulatedText = TimerEngine.formatTime(accumulated)
                let accumulatedHeight = measureTextHeight(
                    accumulatedText, inputs.ui.monoFontName, 16)
                elements.append(.text(
                    frame: .init(
                        x: layout.timeColumnX,
                        y: y + centeredOffset(layout.rowHeight, accumulatedHeight),
                        w: layout.timeColumnWidth, h: accumulatedHeight),
                    text: accumulatedText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 16,
                    color: isActive ? colors.activeText : colors.subText,
                    alignment: .right))
            }

            if index < inputs.projects.count {
                elements.append(.rectangle(
                    frame: .init(
                        x: layout.padding, y: y + layout.rowHeight - 1,
                        w: layout.panelWidth - layout.padding * 2, h: 1),
                    fillColor: colors.separator))
            }
        }

        let footerY = layout.clockSectionHeight + Double(inputs.projects.count) * layout.rowHeight
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: layout.panelWidth, h: 1),
            fillColor: colors.separator))
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: layout.panelWidth, h: layout.footerHeight),
            fillColor: colors.footerBg,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: layout.panelWidth, h: 10),
            fillColor: colors.footerBg))

        // ロゴ+連続稼働時間(フッター中央)
        let timeFrame = layout.continuousTimeFrame(projectCount: inputs.projects.count)
        if hasLogoImage {
            elements.append(.image(
                frame: .init(
                    x: timeFrame.x - layout.headerLogoTextGap - layout.headerLogoSize,
                    y: footerY + 6, w: layout.headerLogoSize, h: layout.headerLogoSize),
                iconKey: "logo",
                scaling: .shrinkToFit))
        }
        var continuousElapsed = inputs.state.continuousElapsedBase
        if let startedAt = inputs.state.continuousStartedAt {
            continuousElapsed += now() - startedAt
        }
        if inputs.editingTarget != .continuous {
            elements.append(.text(
                frame: timeFrame,
                text: TimerEngine.formatTime(continuousElapsed),
                fontName: inputs.ui.monoFontName,
                fontSize: 16,
                color: inputs.state.continuousStartedAt == nil ? colors.subText : colors.text))
        }

        let breakSelected = inputs.selectedIndex == inputs.projects.count + 1
            || inputs.hoveredId == "btn_break"
        let breakName = inputs.breakItem?.name ?? "休憩"
        let breakIcon = inputs.breakItem?.icon ?? "☕"
        elements.append(.rectangle(
            frame: .init(x: layout.padding - 4, y: footerY + 4, w: 108, h: 30),
            fillColor: breakSelected ? colors.footerHoverBg : colors.footerBg,
            cornerRadius: 6,
            id: "btn_break",
            tracksMouse: true))
        appendIcon(
            breakIcon, x: layout.padding, containerY: footerY + 4, containerHeight: 30,
            color: colors.text, fontName: inputs.ui.fontName, fontSize: 14, to: &elements)
        let breakHeight = measureTextHeight(breakName, inputs.ui.fontName, 14)
        elements.append(.text(
            frame: .init(
                x: layout.padding + layout.iconSlotWidth + layout.iconGap,
                y: footerY + 4 + centeredOffset(30, breakHeight), w: 72, h: breakHeight),
            text: breakName,
            fontName: inputs.ui.fontName,
            fontSize: 14,
            color: colors.text))

        let resetSelected = inputs.selectedIndex == inputs.projects.count + 2
            || inputs.hoveredId == "btn_reset"
        let resetColor = inputs.resetConfirming
            ? colors.resetConfirmBg : (resetSelected ? colors.footerHoverBg : colors.footerBg)
        elements.append(.rectangle(
            frame: .init(x: layout.panelWidth - layout.padding - 114, y: footerY + 4, w: 118, h: 30),
            fillColor: resetColor,
            cornerRadius: 6,
            id: "btn_reset",
            tracksMouse: true))
        let resetText = inputs.resetConfirming ? "⚠️ 本当に?" : "🔄 リセット"
        let resetHeight = measureTextHeight(resetText, inputs.ui.fontName, 14)
        elements.append(.text(
            frame: .init(
                x: layout.panelWidth - layout.padding - 110,
                y: footerY + 4 + centeredOffset(30, resetHeight), w: 110, h: resetHeight),
            text: resetText,
            fontName: inputs.ui.fontName,
            fontSize: 14,
            color: colors.subText,
            alignment: .right))

        // 外周の縁取り(暗い背景でもパネルの輪郭が分かるように最前面へ)
        elements.append(.rectangle(
            frame: .init(x: 0.5, y: 0.5, w: layout.panelWidth - 1, h: panelHeight - 1),
            fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 10,
            strokeColor: colors.panelBorder,
            strokeWidth: 1))

        // 計測中の合図は炎色ネオンのカプセル縁取り(文字ラベルは置かない)。
        // グローの光が隣の行や区切り線に自然ににじむよう最前面へ置く
        if let activeOffset = inputs.projects.firstIndex(where: {
            inputs.state.activeProjectId == $0.id
        }) {
            let y = layout.clockSectionHeight + Double(activeOffset) * layout.rowHeight
            let height = layout.rowHeight - 4
            elements.append(.neonRectangle(
                frame: .init(x: 3, y: y + 2, w: layout.panelWidth - 6, h: height),
                cornerRadius: height / 2,
                strokeWidth: 2,
                topColor: colors.neonCoreTop,
                bottomColor: colors.neonCoreBottom,
                glowColor: colors.neonGlow,
                glowRadius: 7))
        }

        // キーボード選択はネオンと同形のカプセル輪郭(消灯版)。Enterの確定対象を示す。
        // 選択行が計測中(ネオンと重なる)場合は、ネオンの内側に細い輪として引っ込める
        if let selected = inputs.selectedIndex,
            selected >= 1, selected <= inputs.projects.count
        {
            let project = inputs.projects[selected - 1]
            let y = layout.clockSectionHeight + Double(selected - 1) * layout.rowHeight
            let inset = inputs.state.activeProjectId == project.id ? 7.0 : 3.0
            let height = layout.rowHeight - inset * 2
            elements.append(.rectangle(
                frame: .init(
                    x: inset, y: y + inset, w: layout.panelWidth - inset * 2, h: height),
                fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
                cornerRadius: height / 2,
                strokeColor: colors.selectionOutline,
                strokeWidth: 1))
        }

        return elements
    }

    /// 現在時刻段(アナログ時計+デジタル秒表示)を構築する
    private func appendClock(_ inputs: Inputs, to elements: inout [PanelElement]) {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let center = layout.clockCenter
        let radius = layout.clockRadius
        let time = localTime()

        elements.append(.circle(
            center: center, radius: radius,
            fillColor: colors.rowBg, strokeColor: colors.separator, strokeWidth: 1))

        // 12・3・6・9時の目盛
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            elements.append(.line(
                from: Self.clockHandPoint(center: center, length: radius - 5, fraction: fraction),
                to: Self.clockHandPoint(center: center, length: radius - 1, fraction: fraction),
                color: colors.subText, width: 1))
        }

        let hourFraction = (Double(time.hour % 12) + Double(time.minute) / 60) / 12
        let minuteFraction = (Double(time.minute) + Double(time.second) / 60) / 60
        let secondFraction = Double(time.second) / 60
        elements.append(.line(
            from: center,
            to: Self.clockHandPoint(center: center, length: radius - 14, fraction: hourFraction),
            color: colors.text, width: 3))
        elements.append(.line(
            from: center,
            to: Self.clockHandPoint(center: center, length: radius - 8, fraction: minuteFraction),
            color: colors.text, width: 2))
        elements.append(.line(
            from: center,
            to: Self.clockHandPoint(center: center, length: radius - 5, fraction: secondFraction),
            color: colors.clockSecondHand, width: 1))
        elements.append(.circle(center: center, radius: 2.5, fillColor: colors.text))

        elements.append(.text(
            frame: layout.clockDigitalFrame,
            text: String(format: "%02d:%02d:%02d", time.hour, time.minute, time.second),
            fontName: inputs.ui.monoFontName,
            fontSize: layout.clockDigitalFontSize,
            color: colors.text))
    }

    /// 文字盤中心から針の先端座標を求める。fractionは12時起点で時計回りの一周比(0.0〜1.0)
    static func clockHandPoint(center: PanelPoint, length: Double, fraction: Double)
        -> PanelPoint
    {
        let angle = fraction * 2 * Double.pi - Double.pi / 2
        return PanelPoint(
            x: center.x + length * cos(angle),
            y: center.y + length * sin(angle))
    }

    private func appendIcon(
        _ icon: String,
        x: Double,
        containerY: Double,
        containerHeight: Double,
        color: PanelColor,
        fontName: String,
        fontSize: Double,
        to elements: inout [PanelElement]
    ) {
        let layout = PanelLayout.self
        switch IconKind.classify(icon) {
        case .url, .filePath:
            guard case .image(let key) = resolveIcon(icon) else { return }
            elements.append(.image(
                frame: .init(
                    x: x + floor((layout.iconSlotWidth - layout.iconImageSize) / 2),
                    y: containerY + centeredOffset(containerHeight, layout.iconImageSize),
                    w: layout.iconImageSize, h: layout.iconImageSize),
                iconKey: key,
                scaling: .scaleProportionally))
        case .text:
            let height = measureTextHeight(icon, fontName, fontSize)
            elements.append(.text(
                frame: .init(
                    x: x, y: containerY + centeredOffset(containerHeight, height),
                    w: layout.iconSlotWidth, h: height),
                text: icon,
                fontName: fontName,
                fontSize: fontSize,
                color: color,
                alignment: .center))
        case .empty:
            break
        }
    }

    private func centeredOffset(_ containerHeight: Double, _ contentHeight: Double) -> Double {
        floor((containerHeight - contentHeight) / 2)
    }
}
