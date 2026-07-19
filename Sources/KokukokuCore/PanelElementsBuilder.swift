import Foundation

public enum IconResolution: Equatable, Sendable {
    case image(key: String)
    case none
}

public struct PanelElementsBuilder {
    public struct Inputs: Sendable {
        public var projects: [KokukokuConfig.Project]
        public var state: TimerState
        /// キーボード選択の対象(予定行・トグル行・プロジェクト行の統一ループ)
        public var selectedTarget: PanelSelectionTarget?
        public var hoveredId: String?
        public var resetConfirming: Bool
        public var editingTarget: PanelEditingTarget?
        /// 連続稼働アラートの閾値(秒)。ゲージの「次の閾値まで」の基準。空ならゲージ非表示
        public var alertThresholds: [Int]
        /// 本日の残予定セクションの行データ列(CalendarSectionModel.rows)。空ならセクション非表示
        public var calendarRows: [CalendarSectionRow]
        public var ui: ResolvedUIConfig

        public init(
            projects: [KokukokuConfig.Project],
            state: TimerState,
            selectedTarget: PanelSelectionTarget? = nil,
            hoveredId: String? = nil,
            resetConfirming: Bool = false,
            editingTarget: PanelEditingTarget? = nil,
            alertThresholds: [Int] = [],
            calendarRows: [CalendarSectionRow] = [],
            ui: ResolvedUIConfig
        ) {
            self.projects = projects
            self.state = state
            self.selectedTarget = selectedTarget
            self.hoveredId = hoveredId
            self.resetConfirming = resetConfirming
            self.editingTarget = editingTarget
            self.alertThresholds = alertThresholds
            self.calendarRows = calendarRows
            self.ui = ui
        }
    }

    private let now: () -> Int
    private let localTime: () -> ClockTime
    private let measureTextHeight: (_ text: String, _ fontName: String, _ size: Double) -> Double
    /// 参加者一覧の主催者強調(色分け連結)と予定名の省略判定に使う実測幅。未指定時は文字数からの概算
    private let measureTextWidth: (_ text: String, _ fontName: String, _ size: Double) -> Double
    private let resolveIcon: (String) -> IconResolution
    private let metrics: PanelMetrics

    public init(
        now: @escaping () -> Int,
        localTime: @escaping () -> ClockTime = { ClockTime(hour: 0, minute: 0, second: 0) },
        measureTextHeight: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double,
        measureTextWidth: @escaping (_ text: String, _ fontName: String, _ size: Double) -> Double =
            { text, _, size in Double(text.count) * size * 0.62 },
        resolveIcon: @escaping (String) -> IconResolution,
        metrics: PanelMetrics
    ) {
        self.now = now
        self.localTime = localTime
        self.measureTextHeight = measureTextHeight
        self.measureTextWidth = measureTextWidth
        self.resolveIcon = resolveIcon
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

        // 連続稼働ラベル(フッター中央)。秒のカウントアップは時計・計測行と三重に
        // 視線を引くため、分単位の日本語表記(タイムラインの「あと◯分」と同語彙)に留める
        var continuousElapsed = inputs.state.continuousElapsedBase
        if let startedAt = inputs.state.continuousStartedAt {
            continuousElapsed += now() - startedAt
        }
        if inputs.editingTarget != .continuous {
            let text = "連続稼働 " + Self.minuteDuration(continuousElapsed)
            let fontSize = 14.0
            let width = measureTextWidth(text, inputs.ui.fontName, fontSize)
            let textHeight = measureTextHeight(text, inputs.ui.fontName, fontSize)
            let textY = footerY + centeredOffset(layout.footerHeight - 8, textHeight)
            // 超過量の併記はリセットボタンに食い込むため、超過中はラベル自体を朱にして語らせる。
            // 通常時は計測中でも沈み色に固定する(計測中は行のカプセルが既に語っており、
            // フッターは脇役に徹して沈んだ色から朱へ跳ねるコントラストを稼ぐ)
            let over = Self.isOverThreshold(
                elapsed: continuousElapsed, thresholds: inputs.alertThresholds)
            let color = over ? colors.gaugeEnd : colors.subText
            elements.append(.text(
                frame: .init(x: (metrics.panelWidth - width) / 2, y: textY, w: width, h: textHeight),
                text: text,
                fontName: inputs.ui.fontName,
                fontSize: fontSize,
                color: color))
        }

        // 連続稼働ゲージ(ラベル直下のエンバーライン)。最大閾値までの全行程を1本で表し、
        // 進むほど金茶から朱へ燃える。閾値が複数なら中間閾値の位置に区切りを入れて
        // セグメント化し、アラート何回分を消費したかが読めるようにする(超過後は朱に張り付く)
        if let progress = Self.gaugeProgress(
            continuousElapsed: continuousElapsed, thresholds: inputs.alertThresholds)
        {
            let track = PanelFrame(
                x: (metrics.panelWidth - layout.gaugeWidth) / 2,
                y: footerY + layout.footerHeight - 5,
                w: layout.gaugeWidth, h: 3)
            elements.append(.rectangle(
                frame: track, fillColor: colors.gaugeTrack, cornerRadius: 1.5))
            if progress > 0 {
                elements.append(.rectangle(
                    frame: .init(x: track.x, y: track.y, w: track.w * progress, h: track.h),
                    fillColor: Self.gaugeColor(fraction: progress),
                    cornerRadius: 1.5))
            }
            for position in Self.gaugeSeparatorPositions(thresholds: inputs.alertThresholds) {
                elements.append(.rectangle(
                    frame: .init(
                        x: track.x + track.w * position - 1, y: track.y, w: 2, h: track.h),
                    fillColor: colors.footerBg))
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
        if case .project(let selected)? = inputs.selectedTarget,
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

        // 時計と同じヘッダー色で「時間の世界」ゾーンとしてまとめ、時計との間に控えめな区切りを入れる。
        // 塗りは末尾の谷(ゾーン間余白)の手前で止め、パネル地色を見せて計測行との世界の切れ目を作る
        elements.append(.rectangle(
            frame: .init(
                x: 0, y: startY, w: metrics.panelWidth,
                h: sectionHeight - layout.calendarSectionGap),
            fillColor: colors.headerBg))
        elements.append(.rectangle(
            frame: .init(
                x: layout.padding, y: startY, w: metrics.panelWidth - layout.padding * 2, h: 1),
            fillColor: colors.separator))

        var y = startY + layout.calendarSectionPaddingTop
        var eventIndex = 0
        // 右端の列は場所と進行中カウントダウンが同じスロットを使う。
        // どちらか1つでも表示があれば全行分を確保し、タイトルの折り返し位置を揃える
        let locationColumnWidth: Double = inputs.calendarRows.contains(where: { row in
            guard case .event(let event) = row else { return false }
            return event.locationText != nil
                || (event.isInProgress && event.countdownText != nil)
        }) ? 110 : 0
        // タイムラインの点の中心Yと、その予定の間隔表現(レール描画は行の後にまとめて行う)
        var dots:
            [(
                centerY: Double, gapStyle: CalendarGapStyle?,
                isInProgress: Bool, isAlertTarget: Bool
            )] = []
        // nowマーカー帯の中心Yと、未開始カウントダウン(帯は先頭予定行の直上に置く)
        var nowMarker: (centerY: Double, countdown: (text: String, urgency: CalendarCountdownUrgency?)?)?
        // キーボード選択中の行の位置(輪郭はレールより手前に描くため後でまとめて構築)
        var selectedRowFrame: (y: Double, height: Double)?

        let hasNowMarkerBand = layout.hasNowMarkerBand(rows: inputs.calendarRows)
        for row in inputs.calendarRows {
            // 「いま」はタイムラインの先頭予定より前(順序の事実)なので、
            // nowマーカー帯を先頭予定行の直上に差し込む。帯の高さはカウントダウンの
            // 表示閾値では出没させない(リストが縦ずれしないように)。
            // 先頭が進行中のときは帯ごと詰める(nowはリングが語るため空の帯が残るだけ)
            if hasNowMarkerBand, case .event(let event) = row, nowMarker == nil {
                let centerY = y + layout.calendarNowMarkerHeight / 2
                let countdown: (text: String, urgency: CalendarCountdownUrgency?)? =
                    if let text = event.countdownText {
                        (text, event.countdownUrgency)
                    } else { nil }
                nowMarker = (centerY, countdown)
                y += layout.calendarNowMarkerHeight
            }
            let rowHeight = layout.calendarRowHeight(row)
            if Self.rowMatchesSelection(
                row: row, eventIndex: eventIndex, target: inputs.selectedTarget)
            {
                selectedRowFrame = (y, rowHeight)
            }
            switch row {
            case .event(let event):
                let lineCenterY = y + rowHeight / 2
                dots.append(
                    (lineCenterY, event.gapStyle, event.isInProgress, event.isAlertTarget))

                // 行背景はホバー追跡のみ(クリックで詳細ページを開ける)。
                // 通知対象は点のハローが指し、行の暖色強調は置かない
                // (「暖色=計測中」の単義を守る。2026-07-19 タダシ決定)
                let id = "cal_event_\(eventIndex)"
                let isHovered = inputs.hoveredId == id
                let rowFill =
                    isHovered
                    ? colors.rowHoverBg : PanelColor(red: 0, green: 0, blue: 0, alpha: 0)
                elements.append(.rectangle(
                    frame: .init(x: 0, y: y, w: metrics.panelWidth, h: rowHeight),
                    fillColor: rowFill,
                    id: event.detailURL != nil ? id : nil,
                    tracksMouse: event.detailURL != nil))

                // 「明るい時刻=次に来る境界」: 未開始は開始を明色・終了を沈み色、
                // 進行中は反転して終了だけ明るくする(進行中の一瞥区別。カウントダウンの判定と同型)
                let startHeight = measureTextHeight(event.startText, inputs.ui.monoFontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX,
                        y: y + centeredOffset(rowHeight, startHeight),
                        w: 42, h: startHeight),
                    text: event.startText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: event.isInProgress ? colors.subText : colors.text))
                let endHeight = measureTextHeight(event.endText, inputs.ui.monoFontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX + 42,
                        y: y + centeredOffset(rowHeight, endHeight),
                        w: layout.calendarTimeWidth - 42, h: endHeight),
                    text: event.endText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 12,
                    color: event.isInProgress ? colors.text : colors.subText))

                // 進行中の「終了まで◯分」は行内(右端スロット)で完結させる。
                // 独立行にすると残30分を切った瞬間にリスト中程へ行が挿入されて縦ずれするため。
                // 表示中は場所より優先する(進行中=もう現地に居るので場所の価値が下がっている)
                if event.isInProgress, let countdown = event.countdownText {
                    let color: PanelColor
                    switch event.countdownUrgency {
                    case .imminent: color = colors.clockSecondHand
                    case .near: color = colors.activeText
                    case .distant, nil: color = colors.subText
                    }
                    let height = measureTextHeight(countdown, inputs.ui.fontName, 12)
                    elements.append(.text(
                        frame: .init(
                            x: metrics.panelWidth - layout.padding - locationColumnWidth,
                            y: y + centeredOffset(rowHeight, height),
                            w: locationColumnWidth, h: height),
                        text: countdown,
                        fontName: inputs.ui.fontName,
                        fontSize: 12,
                        color: color,
                        alignment: .right))
                } else if let locationText = event.locationText {
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
                // 枠に収まらず「…」で省略される予定名だけ、ホバーで全文を見せる
                // (収まっている名前にまで出すとノイズになるため)
                if measureTextWidth(event.title, inputs.ui.fontName, 13) > titleRight - titleX {
                    elements.append(.tooltip(
                        frame: .init(x: titleX, y: y, w: titleRight - titleX, h: rowHeight),
                        text: event.title))
                }
                eventIndex += 1

            case .attendees(let attendees):
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
                appendCalendarToggleRow(
                    text: "他\(hiddenCount)件 ▾", id: "cal_overflow",
                    y: y, rowHeight: rowHeight, inputs: inputs, to: &elements)

            case .collapse:
                appendCalendarToggleRow(
                    text: "畳む ▴", id: "cal_collapse",
                    y: y, rowHeight: rowHeight, inputs: inputs, to: &elements)

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

        appendCalendarRail(
            dots, nowMarker: nowMarker, sectionTopY: startY, ui: inputs.ui, to: &elements)

        // キーボード選択の輪郭(プロジェクト行と同じ「消灯版カプセル」でEnterの対象を示す)。
        // レールや文字に重なっても輪郭線だけなので最前面でよい
        if let selected = selectedRowFrame {
            let insetY = 2.0
            let height = selected.height - insetY * 2
            elements.append(.rectangle(
                frame: .init(
                    x: layout.capsuleInsetX, y: selected.y + insetY,
                    w: metrics.panelWidth - layout.capsuleInsetX * 2, h: height),
                fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
                cornerRadius: height / 2,
                strokeColor: colors.selectionOutline,
                strokeWidth: 1))
        }
    }

    /// 予定セクションの行がキーボード選択中かどうか。
    /// eventIndex はその行までに現れた予定行の数(=予定行なら自分の cal_event_N)
    static func rowMatchesSelection(
        row: CalendarSectionRow, eventIndex: Int, target: PanelSelectionTarget?
    ) -> Bool {
        switch (row, target) {
        case (.event, .calendarEvent(let selected)):
            return eventIndex == selected
        case (.overflow, .calendarOverflow), (.collapse, .calendarCollapse):
            return true
        default:
            return false
        }
    }

    /// 「他◯件」「畳む」のクリック可能なトグル行(ホバーで背景が浮かぶ)
    private func appendCalendarToggleRow(
        text: String, id: String,
        y: Double, rowHeight: Double,
        inputs: Inputs, to elements: inout [PanelElement]
    ) {
        let colors = PanelLayout.Colors.self
        elements.append(.rectangle(
            frame: .init(x: 0, y: y, w: metrics.panelWidth, h: rowHeight),
            fillColor: inputs.hoveredId == id
                ? colors.rowHoverBg : PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
            id: id,
            tracksMouse: true))
        let height = measureTextHeight(text, inputs.ui.fontName, 11)
        elements.append(.text(
            frame: .init(
                x: PanelLayout.calendarContentX, y: y + centeredOffset(rowHeight, height),
                w: metrics.panelWidth - PanelLayout.calendarContentX * 2, h: height),
            text: text,
            fontName: inputs.ui.fontName,
            fontSize: 11,
            color: colors.subText))
    }

    /// タイムラインのレール: 予定の間の空き時間をレール(縦線)の有無で表現する。
    /// 間隔あり=レールでつなぐ(分数は出さない)/ 間隔なし=レールを消し朱の接触線 /
    /// 重複=接触線+朱の「◯分重複」だけ数字を残す。
    /// レールはセクション上端(=時計ヘッダーとの境界。上は「いま」の面)から先頭の点へ
    /// 直接降ろし、未開始の「あと◯分」はこの区間のラベルとして帯に描く
    private func appendCalendarRail(
        _ dots: [(
            centerY: Double, gapStyle: CalendarGapStyle?,
            isInProgress: Bool, isAlertTarget: Bool
        )],
        nowMarker: (centerY: Double, countdown: (text: String, urgency: CalendarCountdownUrgency?)?)?,
        sectionTopY: Double,
        ui: ResolvedUIConfig,
        to elements: inout [PanelElement]
    ) {
        guard !dots.isEmpty else { return }
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let railX = layout.calendarRailX
        let dotRadius = 3.0

        // nowマーカー帯(先頭が未開始のときだけ存在する。進行中の「いま」はリングが語る)
        if let nowMarker, let firstDot = dots.first {
            // いま→先頭予定のレール: 上端をヘッダー境界に接続して「時計(いま)から
            // 降りてくる」時系列を示す(「いま」専用の印は増やさない)
            elements.append(.line(
                from: PanelPoint(x: railX, y: sectionTopY),
                to: PanelPoint(x: railX, y: firstDot.centerY - dotRadius - 2),
                color: colors.subText,
                width: 1))
            // 未開始の「あと◯分」はこの区間のラベル。色は緊急度連動:
            // 遠いときは沈めて主張させず、近づいたときだけ光らせる
            if let countdown = nowMarker.countdown {
                let color: PanelColor
                switch countdown.urgency {
                case .imminent: color = colors.clockSecondHand
                case .near: color = colors.activeText
                case .distant, nil: color = colors.subText
                }
                let height = measureTextHeight(countdown.text, ui.fontName, 12)
                elements.append(.text(
                    frame: .init(
                        x: railX + 9, y: nowMarker.centerY - height / 2,
                        w: 130, h: height),
                    text: countdown.text,
                    fontName: ui.fontName,
                    fontSize: 12,
                    color: color))
            }
        }

        for (previous, current) in zip(dots, dots.dropFirst()) {
            let midY = (previous.centerY + current.centerY) / 2
            switch current.gapStyle {
            case .rail, nil:
                // 点との間に半径+2pxの隙間を空ける(タダシ確認で「隙間がある方が映える」)
                elements.append(.line(
                    from: PanelPoint(x: railX, y: previous.centerY + dotRadius + 2),
                    to: PanelPoint(x: railX, y: current.centerY - dotRadius - 2),
                    color: colors.subText,
                    width: 1))
            case .contact:
                // 「間がない」連鎖の印: 明るい生成りの太めレール(連鎖は構造情報のため炎色を使わない)
                elements.append(.line(
                    from: PanelPoint(x: railX, y: previous.centerY + dotRadius + 2),
                    to: PanelPoint(x: railX, y: current.centerY - dotRadius - 2),
                    color: colors.calendarChain,
                    width: 2))
            case .overlap(let minutes):
                elements.append(.line(
                    from: PanelPoint(x: railX, y: previous.centerY + dotRadius + 2),
                    to: PanelPoint(x: railX, y: current.centerY - dotRadius - 2),
                    color: colors.clockSecondHand,
                    width: 2))
                elements.append(.text(
                    frame: .init(x: railX + 9, y: midY - 7, w: 72, h: 14),
                    text: "\(minutes)分重複",
                    fontName: ui.fontName,
                    fontSize: 10,
                    color: colors.clockSecondHand))
            }
        }
        // 点=予定そのもの(ノード)、レール=関係(エッジ)。間隔の意味はレールだけが背負い、
        // 点は全予定で同色に統一する(点の色が違うと予定の種類が違うように読めるため)。
        // 進行中の予定だけ橙の炎色の中抜きリングにする(塗り=これから、抜き=いま消化中)。
        // 進行中は「種類」やなく全予定が通る一時的な「状態」のため色相変更が種類には読めない。
        // 同色リングでは一瞥で沈むため色相で語る(2026-07-19 第二ラウンド検討でタダシ承認)
        for dot in dots {
            // 開始前通知の対象は点の周りに生成りのハロー(入場パルスと同じ光の声)を灯して
            // 「この予定のアラートや」と指す。情報は行が既に語っているため文字は足さない
            // (バナー帯は行との二度言いになり不採用。2026-07-19 タダシ決定)
            if dot.isAlertTarget {
                elements.append(.circle(
                    center: PanelPoint(x: railX, y: dot.centerY),
                    radius: dotRadius + 5,
                    fillColor: colors.alertHaloOuter))
                elements.append(.circle(
                    center: PanelPoint(x: railX, y: dot.centerY),
                    radius: dotRadius + 2.5,
                    fillColor: colors.alertHaloInner))
            }
            if dot.isInProgress {
                // 単層の淡い橙グロー(色相変更だけでは径3pxの点は一瞥で沈むため。
                // 二層のアラートハローより一段静かな光に留める)
                elements.append(.circle(
                    center: PanelPoint(x: railX, y: dot.centerY),
                    radius: dotRadius + 4.5,
                    fillColor: colors.calendarOngoingGlow))
                elements.append(.circle(
                    center: PanelPoint(x: railX, y: dot.centerY),
                    radius: dotRadius,
                    fillColor: colors.headerBg,
                    strokeColor: colors.calendarOngoing,
                    strokeWidth: 1.5))
            } else {
                elements.append(.circle(
                    center: PanelPoint(x: railX, y: dot.centerY),
                    radius: dotRadius,
                    fillColor: colors.calendarChain))
            }
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

    /// 連続稼働ゲージの進行率(0.0〜1.0)。最大閾値までの全行程を基準にし、
    /// 超過後は1.0(朱)に張り付く。閾値が無い場合はnil(ゲージ非表示)
    static func gaugeProgress(continuousElapsed: Int, thresholds: [Int]) -> Double? {
        guard let last = thresholds.filter({ $0 > 0 }).max() else { return nil }
        return min(Double(continuousElapsed) / Double(last), 1)
    }

    /// ゲージのセグメント区切り位置(0.0〜1.0)。中間閾値ごとに1本。
    /// 閾値が1本なら区切りなし(従来の1本ゲージと同じ見た目に退化する)
    static func gaugeSeparatorPositions(thresholds: [Int]) -> [Double] {
        let sorted = Set(thresholds.filter { $0 > 0 }).sorted()
        guard sorted.count > 1, let last = sorted.last else { return [] }
        return sorted.dropLast().map { Double($0) / Double(last) }
    }

    /// 最大閾値を超過中か(ラベルを朱へ切り替える判定)。閾値なしなら常にfalse
    static func isOverThreshold(elapsed: Int, thresholds: [Int]) -> Bool {
        guard let last = thresholds.filter({ $0 > 0 }).max() else { return false }
        return elapsed >= last
    }

    /// 分単位(切り捨て)の日本語表記。1時間未満は「◯分」、以上は「◯時間◯分」
    static func minuteDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
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
        // floorだと余りの1pxが常に下側に付いて上寄りに見えるため四捨五入で振り分ける
        ((containerHeight - contentHeight) / 2).rounded()
    }
}
