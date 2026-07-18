import Foundation

public enum IconResolution: Equatable, Sendable {
    case image(key: String)
    case none
}

public struct PanelElementsBuilder {
    public struct Inputs: Sendable {
        public var projects: [KokukokuConfig.Project]
        public var state: TimerState
        public var selectedIndex: Int?
        public var hoveredId: String?
        public var resetConfirming: Bool
        public var editingTarget: PanelEditingTarget?
        /// 連続稼働アラートの閾値(秒)。ゲージの「次の閾値まで」の基準。空ならゲージ非表示
        public var alertThresholds: [Int]
        /// 本日の残予定セクションの行データ列(CalendarSectionModel.rows)。空ならセクション非表示
        public var calendarRows: [CalendarSectionRow]
        /// 通知モード: 閉じるボタンをヘッダー右上に出す(通知パネルは外クリックで閉じないため)
        public var showsCalendarCloseButton: Bool
        public var ui: ResolvedUIConfig

        public init(
            projects: [KokukokuConfig.Project],
            state: TimerState,
            selectedIndex: Int? = nil,
            hoveredId: String? = nil,
            resetConfirming: Bool = false,
            editingTarget: PanelEditingTarget? = nil,
            alertThresholds: [Int] = [],
            calendarRows: [CalendarSectionRow] = [],
            showsCalendarCloseButton: Bool = false,
            ui: ResolvedUIConfig
        ) {
            self.projects = projects
            self.state = state
            self.selectedIndex = selectedIndex
            self.hoveredId = hoveredId
            self.resetConfirming = resetConfirming
            self.editingTarget = editingTarget
            self.alertThresholds = alertThresholds
            self.calendarRows = calendarRows
            self.showsCalendarCloseButton = showsCalendarCloseButton
            self.ui = ui
        }
    }

    private let now: () -> Int
    private let localTime: () -> ClockTime
    private let measureTextHeight: (_ text: String, _ fontName: String, _ size: Double) -> Double
    /// 参加者一覧の主催者強調(色分け連結)に使う実測幅。未指定時は文字数からの概算
    private let measureTextWidth: (_ text: String, _ fontName: String, _ size: Double) -> Double
    private let resolveIcon: (String) -> IconResolution
    private let hasLogoImage: Bool
    private let metrics: PanelMetrics

    public init(
        now: @escaping () -> Int,
        localTime: @escaping () -> ClockTime = { ClockTime(hour: 0, minute: 0, second: 0) },
        measureTextHeight: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double,
        measureTextWidth: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double =
            { text, _, size in Double(text.count) * size * 0.62 },
        resolveIcon: @escaping (String) -> IconResolution,
        hasLogoImage: Bool,
        metrics: PanelMetrics
    ) {
        self.now = now
        self.localTime = localTime
        self.measureTextHeight = measureTextHeight
        self.measureTextWidth = measureTextWidth
        self.resolveIcon = resolveIcon
        self.hasLogoImage = hasLogoImage
        self.metrics = metrics
    }

    public func build(_ inputs: Inputs) -> [PanelElement] {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let calendarHeight = layout.calendarSectionHeight(rows: inputs.calendarRows)
        let panelHeight = layout.panelHeight(
            projectCount: inputs.projects.count, calendarSectionHeight: calendarHeight)
        var elements: [PanelElement] = []

        elements.append(.rectangle(
            frame: .init(x: 0, y: 0, w: metrics.panelWidth, h: panelHeight),
            fillColor: colors.background,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: 0, w: metrics.panelWidth, h: layout.clockSectionHeight),
            fillColor: colors.headerBg,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: layout.clockSectionHeight - 10, w: metrics.panelWidth, h: 10),
            fillColor: colors.headerBg))

        appendClock(inputs, to: &elements)

        // 先頭予定のカウントダウンは「いま」の情報として時計セクションの右端に置く
        // (予定行に置くと先頭行だけタイトル幅が縮んで折り返し位置が揃わないため)
        if let countdown = Self.firstCountdown(in: inputs.calendarRows) {
            let height = measureTextHeight(countdown, inputs.ui.fontName, 12)
            elements.append(.text(
                frame: .init(
                    x: metrics.panelWidth - layout.padding - 110,
                    y: layout.clockSectionHeight / 2 - height / 2,
                    w: 110, h: height),
                text: countdown,
                fontName: inputs.ui.fontName,
                fontSize: 12,
                color: colors.activeText,
                alignment: .right))
        }

        // 通知パネルは外クリックで閉じないため、常時表示の閉じるボタンを右上に置く
        if inputs.showsCalendarCloseButton {
            let closeText = "✕ 閉じる"
            let closeHovered = inputs.hoveredId == "btn_cal_close"
            let closeFrame = PanelFrame(
                x: metrics.panelWidth - layout.padding - 76, y: 8, w: 76, h: 22)
            elements.append(.rectangle(
                frame: closeFrame,
                fillColor: closeHovered ? colors.footerHoverBg : colors.headerBg,
                cornerRadius: 11,
                id: "btn_cal_close",
                tracksMouse: true))
            let closeHeight = measureTextHeight(closeText, inputs.ui.fontName, 11)
            elements.append(.text(
                frame: .init(
                    x: closeFrame.x, y: closeFrame.y + centeredOffset(closeFrame.h, closeHeight),
                    w: closeFrame.w, h: closeHeight),
                text: closeText,
                fontName: inputs.ui.fontName,
                fontSize: 11,
                color: colors.subText,
                alignment: .center))
        }

        // 予定セクションは時計と同じ「時間の世界」ゾーンとしてヘッダー直下に置く
        appendCalendarSection(inputs, startY: layout.clockSectionHeight, to: &elements)
        let rowsStartY = layout.clockSectionHeight + calendarHeight

        elements.append(.rectangle(
            frame: .init(x: 0, y: rowsStartY, w: metrics.panelWidth, h: 1),
            fillColor: colors.separator))

        for (offset, project) in inputs.projects.enumerated() {
            let index = offset + 1
            let y = rowsStartY + Double(offset) * layout.rowHeight
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
                frame: .init(x: 0, y: y, w: metrics.panelWidth, h: layout.rowHeight),
                fillColor: rowColor,
                id: "row_\(project.id)",
                tracksMouse: true))

            if index <= 9 {
                let numberText = String(index)
                let height = measureTextHeight(numberText, inputs.ui.monoFontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: layout.numberColumnX, y: y + centeredOffset(layout.rowHeight, height),
                        w: 14, h: height),
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
                    w: metrics.projectNameRight - nameX, h: nameHeight),
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
                        x: metrics.timeColumnX,
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
                        w: metrics.panelWidth - layout.padding * 2, h: 1),
                    fillColor: colors.separator))
            }
        }

        let footerY = rowsStartY + Double(inputs.projects.count) * layout.rowHeight
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: metrics.panelWidth, h: 1),
            fillColor: colors.separator))
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: metrics.panelWidth, h: layout.footerHeight),
            fillColor: colors.footerBg,
            cornerRadius: 10))
        elements.append(.rectangle(
            frame: .init(x: 0, y: footerY, w: metrics.panelWidth, h: 10),
            fillColor: colors.footerBg))

        // ロゴ+連続稼働時間(フッター中央)
        let timeFrame = metrics.continuousTimeFrame(
            projectCount: inputs.projects.count, calendarSectionHeight: calendarHeight)
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

        // 連続稼働ゲージ(時刻テキスト直下のコンパクトなエンバーライン)。
        // 次のアラート閾値へどれだけ近いかを示し、近づくほど金茶から朱へ燃える
        if let fraction = Self.gaugeFraction(
            continuousElapsed: continuousElapsed, thresholds: inputs.alertThresholds)
        {
            // ロゴ左端から時刻テキスト右端までの中央ブロック全体に敷く
            let track = PanelFrame(
                x: timeFrame.x - layout.headerLogoTextGap - layout.headerLogoSize,
                y: footerY + layout.footerHeight - 5,
                w: layout.headerLogoSize + layout.headerLogoTextGap + layout.headerTimeWidth,
                h: 3)
            elements.append(.rectangle(
                frame: track, fillColor: colors.gaugeTrack, cornerRadius: 1.5))
            if fraction > 0 {
                elements.append(.rectangle(
                    frame: .init(x: track.x, y: track.y, w: track.w * fraction, h: track.h),
                    fillColor: Self.gaugeColor(fraction: fraction),
                    cornerRadius: 1.5))
            }
        }

        // リセットは小さな文字ボタン(枠線なし・ホバーとリセット確認時だけ背景が浮かぶ)。
        // 休憩ボタンは廃止(計測中プロジェクトの再選択トグルで休憩に入れるため)。
        // 絵文字(青い🔄・⚠️)は墨絵パレットから浮くため、生成りの「↺」に統一する
        let resetHovered = inputs.hoveredId == "btn_reset"
        let resetColor = inputs.resetConfirming
            ? colors.resetConfirmBg : (resetHovered ? colors.footerHoverBg : colors.footerBg)
        let resetFrame = PanelFrame(
            x: metrics.panelWidth - layout.padding - 96, y: footerY + 7, w: 96, h: 26)
        elements.append(.rectangle(
            frame: resetFrame,
            fillColor: resetColor,
            cornerRadius: 13,
            id: "btn_reset",
            tracksMouse: true))
        let resetText = inputs.resetConfirming ? "↺ 本当に?" : "↺ リセット"
        let resetHeight = measureTextHeight(resetText, inputs.ui.fontName, 13)
        elements.append(.text(
            frame: .init(
                x: resetFrame.x, y: resetFrame.y + centeredOffset(resetFrame.h, resetHeight),
                w: resetFrame.w, h: resetHeight),
            text: resetText,
            fontName: inputs.ui.fontName,
            fontSize: 13,
            color: inputs.resetConfirming ? colors.text : colors.subText,
            alignment: .center))

        // 外周の縁取り(暗い背景でもパネルの輪郭が分かるように最前面へ)
        elements.append(.rectangle(
            frame: .init(x: 0.5, y: 0.5, w: metrics.panelWidth - 1, h: panelHeight - 1),
            fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 10,
            strokeColor: colors.panelBorder,
            strokeWidth: 1))

        // 計測中の合図は炎色ネオンのカプセル縁取り(文字ラベルは置かない)。
        // グローの光が隣の行や区切り線に自然ににじむよう最前面へ置く
        if let activeOffset = inputs.projects.firstIndex(where: {
            inputs.state.activeProjectId == $0.id
        }) {
            let y = rowsStartY + Double(activeOffset) * layout.rowHeight
            let height = layout.rowHeight - layout.capsuleInsetY * 2
            elements.append(.neonRectangle(
                frame: .init(
                    x: layout.capsuleInsetX, y: y + layout.capsuleInsetY,
                    w: metrics.panelWidth - layout.capsuleInsetX * 2, h: height),
                cornerRadius: height / 2,
                strokeWidth: 1,
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
            let y = rowsStartY + Double(selected - 1) * layout.rowHeight
            let isActiveRow = inputs.state.activeProjectId == project.id
            let insetX = layout.capsuleInsetX + (isActiveRow ? 4 : 0)
            let insetY = layout.capsuleInsetY + (isActiveRow ? 4 : 0)
            let height = layout.rowHeight - insetY * 2
            elements.append(.rectangle(
                frame: .init(
                    x: insetX, y: y + insetY, w: metrics.panelWidth - insetX * 2, h: height),
                fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
                cornerRadius: height / 2,
                strokeColor: colors.selectionOutline,
                strokeWidth: 1))
        }

        return elements
    }

    /// 本日の残予定セクション(ヘッダーの時計直下)を構築する。行データ列が空なら何も描かない。
    /// 左端のタイムライン(縦レール+予定ごとの点)で間隔を表現し、ラベル行は置かない
    private func appendCalendarSection(
        _ inputs: Inputs, startY: Double, to elements: inout [PanelElement]
    ) {
        guard !inputs.calendarRows.isEmpty else { return }
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let sectionHeight = layout.calendarSectionHeight(rows: inputs.calendarRows)

        // 時計と同じヘッダー色で「時間の世界」ゾーンとしてまとめ、時計との間に控えめな区切りを入れる
        elements.append(.rectangle(
            frame: .init(x: 0, y: startY, w: metrics.panelWidth, h: sectionHeight),
            fillColor: colors.headerBg))
        elements.append(.rectangle(
            frame: .init(
                x: layout.padding, y: startY, w: metrics.panelWidth - layout.padding * 2, h: 1),
            fillColor: colors.separator))

        var y = startY + layout.calendarSectionPaddingTop
        var eventIndex = 0
        let locationColumnWidth: Double = inputs.calendarRows.contains(where: { row in
            if case .event(let event) = row { return event.locationText != nil }
            return false
        }) ? 110 : 0
        // タイムラインの点の中心Yと、その予定の間隔情報(レール描画は行の後にまとめて行う)
        var dots: [(centerY: Double, gapText: String?, gapIsWarning: Bool)] = []
        // 参加者行は直前の予定行の強調に追随させる
        var lastEventHighlighted = false

        for row in inputs.calendarRows {
            let rowHeight = layout.calendarRowHeight(row)
            switch row {
            case .event(let event):
                let lineCenterY = y + rowHeight / 2
                dots.append((lineCenterY, event.gapText, event.gapIsWarning))
                lastEventHighlighted = event.isHighlighted

                // 行背景: 通知の強調は計測中行と同じ暖色背景で示す。
                // クリックで詳細ページを開けるようホバー追跡も兼ねる
                let id = "cal_event_\(eventIndex)"
                let isHovered = inputs.hoveredId == id
                let rowFill: PanelColor
                if event.isHighlighted {
                    rowFill = isHovered ? colors.activeRowHoverBg : colors.activeRowBg
                } else {
                    rowFill = isHovered
                        ? colors.rowHoverBg : PanelColor(red: 0, green: 0, blue: 0, alpha: 0)
                }
                elements.append(.rectangle(
                    frame: .init(x: 0, y: y, w: metrics.panelWidth, h: rowHeight),
                    fillColor: rowFill,
                    id: event.detailURL != nil ? id : nil,
                    tracksMouse: event.detailURL != nil))

                // 開始は明色・終了は沈み色で一目で区別する
                let startHeight = measureTextHeight(event.startText, inputs.ui.monoFontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX,
                        y: y + centeredOffset(rowHeight, startHeight),
                        w: 42, h: startHeight),
                    text: event.startText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: colors.text))
                let endHeight = measureTextHeight(event.endText, inputs.ui.monoFontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX + 42,
                        y: y + centeredOffset(rowHeight, endHeight),
                        w: layout.calendarTimeWidth - 42, h: endHeight),
                    text: event.endText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 12,
                    color: colors.subText))

                // グリッドは全行共通にし、タイトルの折り返し位置を揃える
                // (場所列はセクション内に場所を持つ予定が1件でもあれば全行分を確保する)
                if let locationText = event.locationText {
                    let height = measureTextHeight(locationText, inputs.ui.fontName, 12)
                    elements.append(.text(
                        frame: .init(
                            x: metrics.panelWidth - layout.padding - locationColumnWidth,
                            y: y + centeredOffset(rowHeight, height),
                            w: locationColumnWidth, h: height),
                        text: locationText,
                        fontName: inputs.ui.fontName,
                        fontSize: 12,
                        color: colors.subText,
                        alignment: .right))
                }

                let titleX = layout.calendarContentX + layout.calendarTimeWidth + 8
                let titleRight = metrics.panelWidth - layout.padding
                    - (locationColumnWidth > 0 ? locationColumnWidth + 8 : 0)
                let titleHeight = measureTextHeight(event.title, inputs.ui.fontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: titleX, y: y + centeredOffset(rowHeight, titleHeight),
                        w: titleRight - titleX, h: titleHeight),
                    text: event.title,
                    fontName: inputs.ui.fontName,
                    fontSize: 13,
                    color: colors.text))
                eventIndex += 1

            case .attendees(let attendees):
                // 直前の予定行が強調中なら参加者行も同じ背景でつなげる
                if lastEventHighlighted {
                    elements.append(.rectangle(
                        frame: .init(x: 0, y: y, w: metrics.panelWidth, h: rowHeight),
                        fillColor: colors.activeRowBg))
                }
                // 予定名の列に揃えたインデントで参加者一覧を小さく添える。主催者は明色で強調
                var x = layout.calendarContentX + layout.calendarTimeWidth + 8
                let height = measureTextHeight("参加者", inputs.ui.fontName, 11)
                let textY = y + centeredOffset(rowHeight, height)
                if let organizer = attendees.organizerName {
                    let width = measureTextWidth(organizer, inputs.ui.fontName, 11).rounded(.up)
                    elements.append(.text(
                        frame: .init(x: x, y: textY, w: width + 2, h: height),
                        text: organizer,
                        fontName: inputs.ui.fontName,
                        fontSize: 11,
                        color: colors.activeText))
                    x += width + 2
                }
                if let others = attendees.othersText {
                    let text = attendees.organizerName == nil ? others : ", \(others)"
                    elements.append(.text(
                        frame: .init(
                            x: x, y: textY,
                            w: metrics.panelWidth - layout.padding - x, h: height),
                        text: text,
                        fontName: inputs.ui.fontName,
                        fontSize: 11,
                        color: colors.subText))
                }

            case .overflow(let hiddenCount):
                let text = "他\(hiddenCount)件"
                let height = measureTextHeight(text, inputs.ui.fontName, 11)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX, y: y + centeredOffset(rowHeight, height),
                        w: metrics.panelWidth - layout.calendarContentX * 2, h: height),
                    text: text,
                    fontName: inputs.ui.fontName,
                    fontSize: 11,
                    color: colors.subText))

            case .error(let message):
                let height = measureTextHeight(message, inputs.ui.fontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX, y: y + centeredOffset(rowHeight, height),
                        w: metrics.panelWidth - layout.calendarContentX * 2, h: height),
                    text: message,
                    fontName: inputs.ui.fontName,
                    fontSize: 12,
                    color: colors.clockSecondHand))

            case .notice(let text):
                let height = measureTextHeight(text, inputs.ui.fontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX, y: y + centeredOffset(rowHeight, height),
                        w: metrics.panelWidth - layout.calendarContentX - layout.padding,
                        h: height),
                    text: text,
                    fontName: inputs.ui.fontName,
                    fontSize: 12,
                    color: colors.clockSecondHand))

            case .freshness(let text):
                let height = measureTextHeight(text, inputs.ui.fontName, 10)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX, y: y + centeredOffset(rowHeight, height),
                        w: metrics.panelWidth - layout.calendarContentX - layout.padding,
                        h: height),
                    text: text,
                    fontName: inputs.ui.fontName,
                    fontSize: 10,
                    color: colors.subText,
                    alignment: .right))
            }
            y += rowHeight
        }

        appendCalendarRail(dots, ui: inputs.ui, to: &elements)
    }

    /// 先頭予定のカウントダウン(行データ列に1つだけ入っている)
    static func firstCountdown(in rows: [CalendarSectionRow]) -> String? {
        for row in rows {
            if case .event(let event) = row, let countdown = event.countdownText {
                return countdown
            }
        }
        return nil
    }

    /// タイムラインのレール: 予定ごとの点を縦線でつなぎ、間隔の分数を線の中点に添える。
    /// 警告間隔(10分未満・重複)は線も数字も朱にする
    private func appendCalendarRail(
        _ dots: [(centerY: Double, gapText: String?, gapIsWarning: Bool)],
        ui: ResolvedUIConfig,
        to elements: inout [PanelElement]
    ) {
        guard !dots.isEmpty else { return }
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let railX = layout.calendarRailX
        let dotRadius = 3.0

        for (previous, current) in zip(dots, dots.dropFirst()) {
            let lineColor = current.gapIsWarning ? colors.clockSecondHand : colors.separator
            elements.append(.line(
                from: PanelPoint(x: railX, y: previous.centerY + dotRadius + 2),
                to: PanelPoint(x: railX, y: current.centerY - dotRadius - 2),
                color: lineColor,
                width: 1))
            if let gapText = current.gapText {
                let midY = (previous.centerY + current.centerY) / 2
                elements.append(.text(
                    frame: .init(x: railX + 7, y: midY - 7, w: 64, h: 14),
                    text: gapText,
                    fontName: ui.fontName,
                    fontSize: 10,
                    color: current.gapIsWarning ? colors.clockSecondHand : colors.subText))
            }
        }
        for (index, dot) in dots.enumerated() {
            elements.append(.circle(
                center: PanelPoint(x: railX, y: dot.centerY),
                radius: dotRadius,
                fillColor: index == 0 ? colors.activeText : colors.subText))
        }
    }

    /// 現在時刻段(アナログ時計+デジタル秒表示)を構築する
    private func appendClock(_ inputs: Inputs, to elements: inout [PanelElement]) {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let center = metrics.clockCenter
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
            frame: metrics.clockDigitalFrame,
            text: String(format: "%02d:%02d:%02d", time.hour, time.minute, time.second),
            fontName: inputs.ui.monoFontName,
            fontSize: layout.clockDigitalFontSize,
            color: colors.text))
    }

    /// 連続稼働ゲージの進行率(0.0〜1.0)。「次の閾値まで」を基準にし、
    /// 閾値を1つ超えるたびに次の閾値基準へ切り替わる。全閾値超過後は満タン。
    /// 閾値が無い場合はnil(ゲージ非表示)
    static func gaugeFraction(continuousElapsed: Int, thresholds: [Int]) -> Double? {
        let sorted = thresholds.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        guard let next = sorted.first(where: { continuousElapsed < $0 }) else { return 1 }
        let previous = sorted.last(where: { $0 <= continuousElapsed }) ?? 0
        return Double(continuousElapsed - previous) / Double(next - previous)
    }

    /// ゲージの火の色。進行に応じて金茶から朱へ線形補間する
    static func gaugeColor(fraction: Double) -> PanelColor {
        let t = min(max(fraction, 0), 1)
        let from = PanelLayout.Colors.gaugeStart
        let to = PanelLayout.Colors.gaugeEnd
        return PanelColor(
            red: from.red + (to.red - from.red) * t,
            green: from.green + (to.green - from.green) * t,
            blue: from.blue + (to.blue - from.blue) * t,
            alpha: 1)
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
                scaling: .scaleProportionally,
                cornerRadius: layout.iconImageCornerRadius))
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
