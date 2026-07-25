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
        public var pinned: Bool
        /// ウィンドウがキーウィンドウ(フォーカス中)か。外枠の色切替(B)に使う
        public var focused: Bool

        public init(
            projects: [KokukokuConfig.Project],
            state: TimerState,
            selectedTarget: PanelSelectionTarget? = nil,
            hoveredId: String? = nil,
            resetConfirming: Bool = false,
            editingTarget: PanelEditingTarget? = nil,
            alertThresholds: [Int] = [],
            calendarRows: [CalendarSectionRow] = [],
            ui: ResolvedUIConfig,
            pinned: Bool = false,
            focused: Bool = false
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
            self.pinned = pinned
            self.focused = focused
        }
    }

    private let now: () -> Int
    private let localTime: () -> ClockTime
    private let measureTextHeight: (_ text: String, _ fontName: String, _ size: Double) -> Double
    /// 予定名の省略判定に使う実測幅。未指定時は文字数からの概算
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

        // 連続稼働の蝋燭(フッター中央)。数字は出さない: 連続稼働は「そろそろヤバいか否か」
        // しか語らない目安で、分単位の値を読む用途が無いため(累積時間とは役割が違う)。
        // 遊び心の表示なので声量は抑え、他の情報を邪魔しない範囲で楽しませるに留める。
        // 炎だけは揺らすためにここでは描かず、Platform側がレイヤーとして重ねる
        var continuousElapsed = inputs.state.continuousElapsedBase
        if let startedAt = inputs.state.continuousStartedAt {
            continuousElapsed += now() - startedAt
        }
        if inputs.editingTarget != .continuous,
            let candle = CandleArt.state(
                continuousElapsed: continuousElapsed,
                thresholds: inputs.alertThresholds,
                isRunning: inputs.state.continuousStartedAt != nil)
        {
            let frame = metrics.candleFrame(
                projectCount: inputs.projects.count,
                calendarSectionHeight: calendarHeight)
            elements.append(.svg(
                frame: frame,
                svg: CandleArt.bodySVG(candle),
                cacheKey: candle.cacheKey))
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

        appendPinButton(inputs, to: &elements)

        // 外周の縁取り(暗い背景でもパネルの輪郭が分かるように最前面へ)。
        // フォーカス中は金茶系に切り替え、非フォーカス時と視覚的に区別する(B)
        elements.append(.rectangle(
            frame: .init(x: 0.5, y: 0.5, w: metrics.panelWidth - 1, h: panelHeight - 1),
            fillColor: PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 10,
            strokeColor: inputs.focused ? colors.panelBorderFocused : colors.panelBorder,
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
        let countdownColumnWidth = 110.0
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
                // タイムラインの点は上段(タイトル段)の中央に置く
                let titleRowHeight = PanelLayout.calendarEventRowHeight
                let lineCenterY = y + titleRowHeight / 2
                dots.append(
                    (lineCenterY, event.gapStyle, event.isInProgress, event.isAlertTarget))

                let id = "cal_event_\(eventIndex)"
                let isHovered = inputs.hoveredId == id
                let rowFill =
                    isHovered
                    ? colors.rowHoverBg : PanelColor(red: 0, green: 0, blue: 0, alpha: 0)
                elements.append(.rectangle(
                    frame: .init(x: 0, y: y, w: metrics.panelWidth, h: rowHeight),
                    fillColor: rowFill,
                    id: id,
                    tracksMouse: true))

                let startHeight = measureTextHeight(event.startText, inputs.ui.monoFontName, 13)
                let startY = y + centeredOffset(titleRowHeight, startHeight)
                elements.append(.text(
                    frame: .init(
                        x: layout.calendarContentX, y: startY,
                        w: 42, h: startHeight),
                    text: event.startText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: event.isInProgress ? colors.subText : colors.text))
                let endColor = event.isInProgress ? colors.text : colors.subText
                let hyphenX = layout.calendarContentX
                    + measureTextWidth(event.startText, inputs.ui.monoFontName, 13)
                    + layout.calendarTimeSeparatorPad
                let hyphenWidth = measureTextWidth("-", inputs.ui.monoFontName, 13)
                elements.append(.text(
                    frame: .init(x: hyphenX, y: startY, w: hyphenWidth, h: startHeight),
                    text: "-",
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: endColor))
                let endX = hyphenX + hyphenWidth + layout.calendarTimeSeparatorPad
                elements.append(.text(
                    frame: .init(
                        x: endX, y: startY,
                        w: layout.calendarContentX + layout.calendarTimeWidth - endX,
                        h: startHeight),
                    text: event.endText,
                    fontName: inputs.ui.monoFontName,
                    fontSize: 13,
                    color: endColor))

                // 進行中カウントダウンはタイトル右端に表示
                if event.isInProgress, let countdown = event.countdownText {
                    let color: PanelColor
                    switch event.countdownUrgency {
                    case .imminent: color = colors.countdownImminent
                    case .near: color = colors.activeText
                    case .distant, nil: color = colors.subText
                    }
                    let height = measureTextHeight(countdown, inputs.ui.fontName, 12)
                    elements.append(.text(
                        frame: .init(
                            x: metrics.panelWidth - layout.padding - countdownColumnWidth,
                            y: y + centeredOffset(titleRowHeight, height),
                            w: countdownColumnWidth, h: height),
                        text: countdown,
                        fontName: inputs.ui.fontName,
                        fontSize: 12,
                        color: color,
                        alignment: .right))
                }

                // タイトル(上段)
                let titleX = layout.calendarContentX + layout.calendarTimeWidth + 8
                let hasCountdown = event.isInProgress && event.countdownText != nil
                let titleRight = metrics.panelWidth - layout.padding
                    - (hasCountdown ? countdownColumnWidth + 8 : 0)
                let titleHeight = measureTextHeight(event.title, inputs.ui.fontName, 13)
                elements.append(.text(
                    frame: .init(
                        x: titleX, y: y + centeredOffset(titleRowHeight, titleHeight),
                        w: titleRight - titleX, h: titleHeight),
                    text: event.title,
                    fontName: inputs.ui.fontName,
                    fontSize: 13,
                    color: colors.text))
                // 場所(下段): タイトルの下に小さめフォントで表示
                if let locationText = event.locationText {
                    let text = locationText
                    let locationY = y + titleRowHeight
                    let locationHeight = rowHeight - titleRowHeight
                    let locationX = layout.calendarContentX + layout.calendarTimeWidth + 8
                    let locationRight = metrics.panelWidth - layout.padding
                    elements.append(.text(
                        frame: .init(
                            x: locationX, y: locationY,
                            w: locationRight - locationX, h: locationHeight),
                        text: text,
                        fontName: inputs.ui.fontName,
                        fontSize: 11,
                        color: colors.subText))
                }
                eventIndex += 1

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
                case .imminent: color = colors.countdownImminent
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
                // 文字インクは枠の上寄りに乗るため、枠中央(midY-7)だと上の行の時刻に接する。
                // 2px下げて上下の抜けを揃える
                elements.append(.text(
                    frame: .init(x: railX + 9, y: midY - 5, w: 72, h: 14),
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

    /// ヘッダー右上の押しピンボタン(クリックとpキーでPin切替)。
    /// 掴む場所(ヘッダードラッグ)と留める場所を同じヘッダーに揃える。
    /// 絵文字ではなく頭のクロスバー+軸+針の3本線で描き、時計と同じ線の文法に馴染ませる
    /// (頭を円にすると虫眼鏡に見える)。off=鈍色で45度に傾き、on=生成りで垂直に刺さる
    private func appendPinButton(_ inputs: Inputs, to elements: inout [PanelElement]) {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let size = layout.pinButtonSize
        let rect = PanelFrame(x: metrics.panelWidth - size - 6, y: 6, w: size, h: size)
        let hovered = inputs.hoveredId == "btn_pin"
        elements.append(.rectangle(
            frame: rect,
            fillColor: hovered
                ? colors.rowHoverBg : PanelColor(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 5,
            id: "btn_pin",
            tracksMouse: true))

        let color = inputs.pinned ? colors.text : colors.subText
        let head: (PanelPoint, PanelPoint)
        let shaft: (PanelPoint, PanelPoint)
        let needle: (PanelPoint, PanelPoint)
        if inputs.pinned {
            head = (.init(x: rect.x + 7.5, y: rect.y + 6.5), .init(x: rect.x + 14.5, y: rect.y + 6.5))
            shaft = (.init(x: rect.x + 11, y: rect.y + 6.5), .init(x: rect.x + 11, y: rect.y + 11.5))
            needle = (.init(x: rect.x + 11, y: rect.y + 11.5), .init(x: rect.x + 11, y: rect.y + 15.5))
        } else {
            head = (.init(x: rect.x + 12, y: rect.y + 5), .init(x: rect.x + 17, y: rect.y + 10))
            shaft = (.init(x: rect.x + 14.5, y: rect.y + 7.5), .init(x: rect.x + 11, y: rect.y + 11))
            needle = (.init(x: rect.x + 11, y: rect.y + 11), .init(x: rect.x + 7.5, y: rect.y + 14.5))
        }
        elements.append(.line(from: head.0, to: head.1, color: color, width: 3))
        elements.append(.line(from: shaft.0, to: shaft.1, color: color, width: 2))
        elements.append(.line(from: needle.0, to: needle.1, color: color, width: 1))
    }

    /// 現在時刻段(ロゴの意匠のアナログ時計+デジタル秒表示)を構築する。
    ///
    /// 文字盤と針をSVGで分けて持つのは、分ごとにしか変わらない絵を
    /// 毎秒動く日輪のために作り直さずに済ませるため(キャッシュキーの粒度が違う)
    private func appendClock(_ inputs: Inputs, to elements: inout [PanelElement]) {
        let layout = PanelLayout.self
        let colors = PanelLayout.Colors.self
        let center = metrics.clockCenter
        let time = localTime()
        let frame = PanelFrame(
            x: center.x - ClockArt.canvas / 2, y: center.y - ClockArt.canvas / 2,
            w: ClockArt.canvas, h: ClockArt.canvas)

        elements.append(.svg(
            frame: frame, svg: ClockArt.dialSVG(), cacheKey: "clock-dial"))
        elements.append(.svg(
            frame: frame,
            svg: ClockArt.handsSVG(hour: time.hour, minute: time.minute),
            cacheKey: ClockArt.handsCacheKey(hour: time.hour, minute: time.minute)))

        // 秒は三本目の針ではなく、盤の上を巡る朱の日輪が刻む
        // (ロゴが二針であり、針を足すと意匠が崩れるため)
        let sun = ClockArt.sunOffset(second: time.second)
        let sunCenter = PanelPoint(x: center.x + sun.x, y: center.y + sun.y)
        elements.append(.circle(
            center: sunCenter, radius: ClockArt.sunHaloRadius, fillColor: colors.clockSunHalo))
        elements.append(.circle(
            center: sunCenter, radius: ClockArt.sunRadius, fillColor: colors.clockSecondHand))

        elements.append(.text(
            frame: metrics.clockDigitalFrame,
            text: String(format: "%02d:%02d:%02d", time.hour, time.minute, time.second),
            fontName: inputs.ui.monoFontName,
            fontSize: layout.clockDigitalFontSize,
            color: colors.text))
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
