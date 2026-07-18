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
        public var isVersionVisible: Bool
        public var resetConfirming: Bool
        public var versionText: String?
        public var editingTarget: PanelEditingTarget?
        public var ui: ResolvedUIConfig

        public init(
            projects: [KokukokuConfig.Project],
            breakItem: KokukokuConfig.BreakItem? = nil,
            state: TimerState,
            selectedIndex: Int? = nil,
            hoveredId: String? = nil,
            isVersionVisible: Bool = false,
            resetConfirming: Bool = false,
            versionText: String? = nil,
            editingTarget: PanelEditingTarget? = nil,
            ui: ResolvedUIConfig
        ) {
            self.projects = projects
            self.breakItem = breakItem
            self.state = state
            self.selectedIndex = selectedIndex
            self.hoveredId = hoveredId
            self.isVersionVisible = isVersionVisible
            self.resetConfirming = resetConfirming
            self.versionText = versionText
            self.editingTarget = editingTarget
            self.ui = ui
        }
    }

    private let now: () -> Int
    private let measureTextHeight: (_ text: String, _ fontName: String, _ size: Double) -> Double
    private let resolveIcon: (String) -> IconResolution
    private let hasLogoImage: Bool

    public init(
        now: @escaping () -> Int,
        measureTextHeight: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double,
        resolveIcon: @escaping (String) -> IconResolution,
        hasLogoImage: Bool
    ) {
        self.now = now
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
            frame: .init(x: 0, y: 0, w: layout.panelWidth, h: layout.headerHeight),
            fillColor: colors.headerBg,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: layout.headerHeight - 10, w: layout.panelWidth, h: 10),
            fillColor: colors.headerBg))

        let logoSize = layout.headerLogoSize
        let logoTextGap = layout.headerLogoTextGap
        let timeFrame = layout.continuousTimeFrame
        let startX = timeFrame.x - logoTextGap - logoSize
        if hasLogoImage {
            elements.append(.image(
                frame: .init(x: startX, y: 8, w: logoSize, h: logoSize),
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

        if inputs.isVersionVisible, let versionText = inputs.versionText, !versionText.isEmpty {
            let height = measureTextHeight(versionText, inputs.ui.monoFontName, 10)
            elements.append(.text(
                frame: .init(x: layout.panelWidth - layout.padding - 72, y: 6, w: 72, h: height),
                text: versionText,
                fontName: inputs.ui.monoFontName,
                fontSize: 10,
                color: colors.subText,
                alignment: .right))
        }

        elements.append(.rectangle(
            frame: .init(x: 0, y: layout.headerHeight, w: layout.panelWidth, h: 1),
            fillColor: colors.separator))

        for (offset, project) in inputs.projects.enumerated() {
            let index = offset + 1
            let y = layout.headerHeight + Double(offset) * layout.rowHeight
            let isActive = inputs.state.activeProjectId == project.id
            let isSelected = inputs.selectedIndex == index || inputs.hoveredId == "row_\(project.id)"
            let rowColor: PanelColor
            if isActive {
                rowColor = isSelected ? colors.activeRowHoverBg : colors.activeRowBg
            } else {
                rowColor = isSelected ? colors.rowHoverBg : colors.rowBg
            }
            elements.append(.rectangle(
                frame: .init(x: 0, y: y, w: layout.panelWidth, h: layout.rowHeight),
                fillColor: rowColor,
                id: "row_\(project.id)",
                tracksMouse: true))

            if index <= 9 {
                let numberText = String(index)
                let height = measureTextHeight(numberText, inputs.ui.monoFontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: layout.padding, y: y + centeredOffset(layout.rowHeight, height),
                        w: 20, h: height),
                    text: numberText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 12,
                    color: colors.subText))
            }

            let icon = project.icon ?? ""
            appendIcon(
                icon, x: layout.projectContentX, containerY: y,
                containerHeight: layout.rowHeight, color: isActive ? colors.activeText : colors.text,
                fontName: inputs.ui.fontName, to: &elements)

            let nameX = layout.projectContentX + layout.iconSlotWidth + layout.iconGap
            let nameHeight = measureTextHeight(project.name, inputs.ui.fontName, 14)
            elements.append(.text(
                frame: .init(
                    x: nameX, y: y + centeredOffset(layout.rowHeight, nameHeight),
                    w: layout.projectNameRight - nameX, h: nameHeight),
                text: project.name,
                fontName: inputs.ui.fontName,
                fontSize: 14,
                color: isActive ? colors.activeText : colors.text))

            var accumulated = inputs.state.accumulated[project.id] ?? 0
            if isActive, let startedAt = inputs.state.activeStartedAt {
                accumulated += now() - startedAt
            }
            if inputs.editingTarget != .project(id: project.id) {
                let accumulatedText = TimerEngine.formatTime(accumulated)
                let accumulatedHeight = measureTextHeight(
                    accumulatedText, inputs.ui.monoFontName, 14)
                elements.append(.text(
                    frame: .init(
                        x: layout.timeColumnX,
                        y: y + centeredOffset(layout.rowHeight, accumulatedHeight),
                        w: layout.timeColumnWidth, h: accumulatedHeight),
                    text: accumulatedText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 14,
                    color: isActive ? colors.activeText : colors.subText,
                    alignment: .right))
            }

            if isActive {
                let activeText = "▶ 計測中"
                let height = measureTextHeight(activeText, inputs.ui.fontName, 11)
                elements.append(.text(
                    frame: .init(
                        x: 350, y: y + centeredOffset(layout.rowHeight, height), w: 60, h: height),
                    text: activeText,
                    fontName: inputs.ui.fontName,
                    fontSize: 11,
                    color: colors.activeText))
            }

            if index < inputs.projects.count {
                elements.append(.rectangle(
                    frame: .init(
                        x: layout.padding, y: y + layout.rowHeight - 1,
                        w: layout.panelWidth - layout.padding * 2, h: 1),
                    fillColor: colors.separator))
            }
        }

        let footerY = layout.headerHeight + Double(inputs.projects.count) * layout.rowHeight
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
            color: colors.text, fontName: inputs.ui.fontName, to: &elements)
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

        return elements
    }

    private func appendIcon(
        _ icon: String,
        x: Double,
        containerY: Double,
        containerHeight: Double,
        color: PanelColor,
        fontName: String,
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
            let height = measureTextHeight(icon, fontName, 14)
            elements.append(.text(
                frame: .init(
                    x: x, y: containerY + centeredOffset(containerHeight, height),
                    w: layout.iconSlotWidth, h: height),
                text: icon,
                fontName: fontName,
                fontSize: 14,
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
