import Foundation
import Testing

@testable import KokukokuCore

@Suite("PanelElementsBuilder")
struct PanelElementsBuilderTests {
    private let ui = ResolvedUIConfig(ui: nil)
    private let metrics = PanelMetrics(panelWidth: 480)

    @Test("Luaと同じ順序・座標・色・idで主要素を構築する")
    func representativeLayout() {
        let elements = builder().build(inputs())

        #expect(elements.count == 26)
        #expect(elements[0] == .rectangle(
            frame: .init(x: 0, y: 0, w: 480, h: 164),
            fillColor: PanelLayout.Colors.background, cornerRadius: 10))
        #expect(elements[1] == .rectangle(
            frame: .init(x: 0, y: 0, w: 480, h: 84),
            fillColor: PanelLayout.Colors.headerBg, cornerRadius: 10))
        #expect(elements[3] == .circle(
            center: metrics.clockCenter, radius: 28,
            fillColor: PanelLayout.Colors.rowBg,
            strokeColor: PanelLayout.Colors.separator, strokeWidth: 1))
        #expect(elements[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(elements[15] == .text(
            frame: .init(x: 24, y: 93, w: 14, h: 21), text: "1",
            fontName: "Menlo", fontSize: 13, color: PanelLayout.Colors.subText))
        #expect(elements[17] == .text(
            frame: .init(x: 74, y: 92, w: 270, h: 24), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 16, color: PanelLayout.Colors.text))
        #expect(elements[19] == .rectangle(
            frame: .init(x: 0, y: 124, w: 480, h: 1),
            fillColor: PanelLayout.Colors.separator))
        #expect(elements[22] == .text(
            frame: .init(x: 212, y: 134, w: 90, h: 28), text: "00:00:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(elements[23] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(elements[25] == .rectangle(
            frame: .init(x: 0.5, y: 0.5, w: 479, h: 163),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 10,
            strokeColor: PanelLayout.Colors.panelBorder, strokeWidth: 1))
    }

    @Test("ロゴがある場合だけロゴ画像を追加する")
    func logo() {
        let withoutLogo = builder(hasLogoImage: false).build(inputs())
        let withLogo = builder(hasLogoImage: true).build(inputs())

        #expect(!withoutLogo.contains(.image(
            frame: .init(x: 178, y: 130, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit)))
        #expect(withLogo[22] == .image(
            frame: .init(x: 178, y: 130, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit))
    }

    @Test("絵文字アイコンをテキストとして描画する")
    func textIcon() {
        let elements = builder(resolveIcon: { _ in
            Issue.record("テキストアイコンでresolveIconが呼ばれた")
            return .none
        }).build(inputs())

        #expect(elements[16] == .text(
            frame: .init(x: 42, y: 91, w: 24, h: 25), text: "🔵",
            fontName: ".AppleSystemUIFont", fontSize: 17,
            color: PanelLayout.Colors.text, alignment: .center))
    }

    @Test("URL・パスアイコンの解決成功時は画像を描画する")
    func imageIcon() {
        let elements = builder(resolveIcon: { icon in .image(key: "cached:\(icon)") })
            .build(inputs(project: .init(id: "work", name: "Work", icon: "/tmp/work.png")))

        #expect(elements[16] == .image(
            frame: .init(x: 42, y: 92, w: 24, h: 24),
            iconKey: "cached:/tmp/work.png", scaling: .scaleProportionally,
            cornerRadius: 12))
    }

    @Test("画像アイコンの解決失敗時はパス文字列を描画しない")
    func failedImageIcon() {
        let url = "https://example.com/missing.png"
        let elements = builder(resolveIcon: { _ in .none })
            .build(inputs(project: .init(id: "work", name: "Work", icon: url)))

        #expect(!containsText(url, in: elements))
        #expect(containsText("Work", in: elements))
    }

    @Test("ヘッダーは停止中の基準時間と稼働中の経過時間を表示する")
    func continuousElapsed() {
        let stopped = builder().build(inputs(state: .init(continuousElapsedBase: 600)))
        let running = builder(now: 1_100).build(inputs(state: .init(
            continuousElapsedBase: 600, continuousStartedAt: 1_000)))

        #expect(stopped[22] == .text(
            frame: .init(x: 212, y: 134, w: 90, h: 28), text: "00:10:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(running[22] == .text(
            frame: .init(x: 212, y: 134, w: 90, h: 28), text: "00:11:40",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.text))
    }

    @Test("選択・ホバー・リセット確認の色を反映する")
    func interactionColors() {
        let hovered = builder().build(inputs(hoveredId: "row_work"))
        let hoveredReset = builder().build(inputs(hoveredId: "btn_reset"))
        let confirming = builder().build(inputs(resetConfirming: true))

        #expect(hovered[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.rowHoverBg, id: "row_work", tracksMouse: true))
        #expect(hoveredReset[23] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.footerHoverBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(confirming[23] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.resetConfirmBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(containsText("↺ 本当に?", in: confirming))
    }

    @Test("キーボード選択はカプセル輪郭で示し行背景は変えない")
    func selectionOutline() {
        let selected = builder().build(inputs(selectedIndex: 1))

        #expect(selected[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(selected.last == .rectangle(
            frame: .init(x: 8, y: 87, w: 464, h: 34),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 17,
            strokeColor: PanelLayout.Colors.selectionOutline,
            strokeWidth: 1))
    }

    @Test("計測中の行を選択した場合はネオンの内側に細い輪を引く")
    func selectionOutlineOnActiveRow() {
        let elements = builder(now: 1_100).build(inputs(
            state: .init(activeProjectId: "work", activeStartedAt: 1_000),
            selectedIndex: 1))

        guard case .neonRectangle = elements[elements.count - 2] else {
            Issue.record("選択輪郭の直前にネオン縁取りがない")
            return
        }
        #expect(elements.last == .rectangle(
            frame: .init(x: 12, y: 91, w: 456, h: 26),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 13,
            strokeColor: PanelLayout.Colors.selectionOutline,
            strokeWidth: 1))
    }

    @Test("計測中の行は炎色ネオン縁取りで示し文字ラベルは置かない")
    func activeRowNeon() {
        let inactive = builder().build(inputs())
        let active = builder(now: 1_100).build(inputs(state: .init(
            activeProjectId: "work", activeStartedAt: 1_000)))

        #expect(!inactive.contains { if case .neonRectangle = $0 { true } else { false } })
        // グローが他要素に塗り潰されないよう最前面(末尾)に置く
        #expect(active.last == .neonRectangle(
            frame: .init(x: 8, y: 87, w: 464, h: 34),
            cornerRadius: 17,
            strokeWidth: 1,
            topColor: PanelLayout.Colors.neonCoreTop,
            bottomColor: PanelLayout.Colors.neonCoreBottom,
            glowColor: PanelLayout.Colors.neonGlow,
            glowRadius: 7))
        #expect(!containsText("▶ 計測中", in: active))
        // 行背景と文字はアクティブ配色になる
        #expect(active[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.activeRowBg, id: "row_work", tracksMouse: true))
        #expect(active[17] == .text(
            frame: .init(x: 74, y: 92, w: 270, h: 24), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 16,
            color: PanelLayout.Colors.activeText))
    }

    @Test("IconKindはLuaと同じ接頭辞で分類する")
    func iconKind() {
        #expect(IconKind.classify(nil) == .empty)
        #expect(IconKind.classify("") == .empty)
        #expect(IconKind.classify("https://example.com/a.png") == .url)
        #expect(IconKind.classify("http://example.com/a.png") == .url)
        #expect(IconKind.classify("/tmp/a.png") == .filePath)
        #expect(IconKind.classify("~/a.png") == .filePath)
        #expect(IconKind.classify("🔵") == .text)
    }

    @Test("プロジェクト時間の編集中は該当行の時刻テキストだけ描画しない")
    func editingProjectHidesAccumulatedText() {
        let normal = builder().build(inputs(state: .init(accumulated: ["work": 90])))
        let editing = builder().build(inputs(
            state: .init(accumulated: ["work": 90]),
            editingTarget: .project(id: "work")))

        #expect(containsText("00:01:30", in: normal))
        #expect(!containsText("00:01:30", in: editing))
        #expect(containsText("00:00:00", in: editing))  // ヘッダーの連続稼働時間は残る
    }

    @Test("連続稼働時間の編集中はヘッダーの時刻テキストを描画しない")
    func editingContinuousHidesHeaderText() {
        let editing = builder().build(inputs(
            state: .init(continuousElapsedBase: 600),
            editingTarget: .continuous))

        #expect(!containsText("00:10:00", in: editing))
        #expect(containsText("00:00:00", in: editing))  // プロジェクト行の時刻は残る
    }

    @Test("編集フィールドの枠は時刻テキストの列位置と一致する")
    func editingFrames() {
        #expect(metrics.continuousTimeFrame(projectCount: 1)
            == .init(x: 212, y: 134, w: 90, h: 28))
        #expect(metrics.accumulatedTimeFrame(rowOffset: 0)
            == .init(x: 356, y: 84, w: 100, h: 40))
        #expect(metrics.accumulatedTimeFrame(rowOffset: 2)
            == .init(x: 356, y: 164, w: 100, h: 40))
    }

    @Test("連続稼働ゲージの進行率は次の閾値まで基準で閾値なしなら非表示")
    func gaugeFraction() {
        #expect(PanelElementsBuilder.gaugeFraction(continuousElapsed: 1800, thresholds: [3600]) == 0.5)
        // 閾値を1つ超えたら次の閾値基準に切り替わる
        #expect(
            PanelElementsBuilder.gaugeFraction(continuousElapsed: 2700, thresholds: [1800, 3600])
                == 0.5)
        // 全閾値超過後は満タン
        #expect(PanelElementsBuilder.gaugeFraction(continuousElapsed: 4000, thresholds: [3600]) == 1)
        #expect(PanelElementsBuilder.gaugeFraction(continuousElapsed: 100, thresholds: []) == nil)
        #expect(PanelElementsBuilder.gaugeFraction(continuousElapsed: 100, thresholds: [0]) == nil)
    }

    @Test("閾値があればフッター下端に連続稼働ゲージの溝と火を描く")
    func gaugeElements() {
        let none = builder().build(inputs())
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: 1_000),
            alertThresholds: [3_600]))

        // 溝はロゴ+連続稼働時間の中央ブロック全体の直下・同じ幅
        let track = PanelFrame(x: 178, y: 159, w: 124, h: 3)
        #expect(!none.contains(.rectangle(
            frame: track, fillColor: PanelLayout.Colors.gaugeTrack, cornerRadius: 1.5)))
        #expect(elements.contains(.rectangle(
            frame: track, fillColor: PanelLayout.Colors.gaugeTrack, cornerRadius: 1.5)))
        #expect(elements.contains(.rectangle(
            frame: .init(x: 178, y: 159, w: 62, h: 3),
            fillColor: PanelElementsBuilder.gaugeColor(fraction: 0.5), cornerRadius: 1.5)))
    }

    @Test("パネル幅は最長プロジェクト名の幅に連動し下限420・上限480で頭打ちする")
    func metricsCompute() {
        func width(nameWidths: [String: Double]) -> Double {
            PanelMetrics.compute(
                projectNames: Array(nameWidths.keys),
                measureNameWidth: { nameWidths[$0] ?? 0 }
            ).panelWidth
        }

        // 幅 = 名前左端74 + 名前幅 + 間隔12 + 時間列100 + 右余白24
        #expect(width(nameWidths: ["short": 100]) == 420)  // 310 → 下限で頭打ち
        #expect(width(nameWidths: ["medium": 250]) == 460)
        #expect(width(nameWidths: ["short": 100, "medium": 250]) == 460)  // 最長が勝つ
        #expect(width(nameWidths: ["long": 400]) == 480)  // 610 → 上限で頭打ち
        #expect(width(nameWidths: [:]) == 420)
    }

    @Test("パネル高さをプロジェクト数から算出する")
    func panelHeight() {
        #expect(PanelLayout.panelHeight(projectCount: 0) == 124)
        #expect(PanelLayout.panelHeight(projectCount: 3) == 244)
    }

    @Test("現在時刻をデジタル秒付き・ゼロ埋めで表示する")
    func digitalClock() {
        let elements = builder(localTime: .init(hour: 9, minute: 5, second: 7)).build(inputs())

        #expect(elements[12] == .text(
            frame: metrics.clockDigitalFrame, text: "09:05:07",
            fontName: "Menlo", fontSize: PanelLayout.clockDigitalFontSize,
            color: PanelLayout.Colors.text))
    }

    @Test("アナログ針の先端を時刻の一周比から計算する")
    func clockHandGeometry() {
        let center = PanelPoint(x: 100, y: 100)

        // 12時=真上・3時=右・6時=真下・9時=左(isFlippedのy下向き座標)
        expectNear(
            PanelElementsBuilder.clockHandPoint(center: center, length: 10, fraction: 0),
            .init(x: 100, y: 90))
        expectNear(
            PanelElementsBuilder.clockHandPoint(center: center, length: 10, fraction: 0.25),
            .init(x: 110, y: 100))
        expectNear(
            PanelElementsBuilder.clockHandPoint(center: center, length: 10, fraction: 0.5),
            .init(x: 100, y: 110))
        expectNear(
            PanelElementsBuilder.clockHandPoint(center: center, length: 10, fraction: 0.75),
            .init(x: 90, y: 100))
    }

    @Test("針は時針=時+分・分針=分+秒・秒針=秒の一周比で回る")
    func clockHands() {
        let center = metrics.clockCenter
        let elements = builder(localTime: .init(hour: 9, minute: 30, second: 45)).build(inputs())

        guard case .line(let hourFrom, let hourTo, _, _) = elements[8],
            case .line(_, let minuteTo, _, _) = elements[9],
            case .line(_, let secondTo, let secondColor, _) = elements[10]
        else {
            Issue.record("針のline要素が想定位置にない")
            return
        }
        #expect(hourFrom == center)
        // 9時30分: 時針は9時と10時の中間 = 一周比 (9 + 0.5) / 12
        expectNear(
            hourTo,
            PanelElementsBuilder.clockHandPoint(center: center, length: 14, fraction: 9.5 / 12))
        expectNear(
            minuteTo,
            PanelElementsBuilder.clockHandPoint(center: center, length: 20, fraction: 30.75 / 60))
        expectNear(
            secondTo,
            PanelElementsBuilder.clockHandPoint(center: center, length: 23, fraction: 45 / 60))
        #expect(secondColor == PanelLayout.Colors.clockSecondHand)
    }

    @Test("予定セクションはヘッダー直下に入り、行エリアとフッターが下へずれる")
    func calendarSectionShiftsRowsAndFooter() {
        let rows: [CalendarSectionRow] = [
            .event(.init(
                startText: "13:00", endText: "-14:00", title: "定例",
                locationText: "会議室A",
                detailURL: URL(string: "https://calendar.google.com/calendar/event?eid=x"),
                countdownText: "あと30分")),
            .attendees(.init(organizerName: "boss", othersText: "a, b 他3人")),
        ]
        let sectionHeight = PanelLayout.calendarSectionHeight(rows: rows)
        let elements = builder().build(inputs(calendarRows: rows))

        // 背景(全高)が伸びる
        guard case .rectangle(let bgFrame, _, _, _, _, _, _) = elements[0] else {
            Issue.record("背景がない")
            return
        }
        #expect(bgFrame.h == 164 + sectionHeight)
        // セクションの中身(時刻分離・カウントダウン・主催者強調)と行クリックのホバー追跡
        #expect(containsText("13:00", in: elements))
        #expect(containsText("-14:00", in: elements))
        #expect(containsText("定例", in: elements))
        #expect(containsText("会議室A", in: elements))
        #expect(containsText("あと30分", in: elements))
        #expect(containsText("boss", in: elements))
        #expect(containsText(", a, b 他3人", in: elements))
        #expect(elements.contains { element in
            guard case .rectangle(_, _, _, _, _, let id, let tracksMouse) = element else {
                return false
            }
            return id == "cal_event_0" && tracksMouse
        })
        // プロジェクト行(ホバー追跡の行背景)がセクション分だけ下がる
        #expect(elements.contains { element in
            guard case .rectangle(let frame, _, _, _, _, let id, _) = element else { return false }
            return id == "row_work" && frame.y == 84 + sectionHeight
        })
        // リセットボタン(フッター)も同様に下がる
        #expect(elements.contains { element in
            guard case .rectangle(let frame, _, _, _, _, let id, _) = element else { return false }
            return id == "btn_reset" && frame.y == 131 + sectionHeight
        })
    }

    @Test("間隔ありはレール、間隔なしは朱の接触線、重複は接触線+朱の分数になる")
    func calendarRail() {
        let rows: [CalendarSectionRow] = [
            .event(.init(startText: "13:00", endText: "-14:00", title: "a", countdownText: "あと5分")),
            .event(.init(
                startText: "14:10", endText: "-15:00", title: "b", gapStyle: .rail)),
            .event(.init(
                startText: "15:00", endText: "-16:00", title: "c", gapStyle: .contact)),
            .event(.init(
                startText: "15:30", endText: "-16:30", title: "d",
                gapStyle: .overlap(minutes: 30))),
        ]
        let elements = builder().build(inputs(calendarRows: rows))

        // 予定4件分の点は全予定で同色(明るい生成り)。間隔の意味はレールだけが背負う
        let dotColors = elements.compactMap { element -> PanelColor? in
            guard case .circle(_, let radius, let fill, _, _) = element, radius == 3 else {
                return nil
            }
            return fill
        }
        #expect(dotColors == Array(repeating: PanelLayout.Colors.calendarChain, count: 4))
        // 通常レール(縦線・subText色)は間隔ありの1本だけ
        // (時計の目盛もsubTextの縦線のため、レールのx座標で絞る)
        let railLines = elements.filter { element in
            guard case .line(let from, let to, let color, _) = element else { return false }
            return from.x == PanelLayout.calendarRailX && from.x == to.x
                && color == PanelLayout.Colors.subText
        }
        #expect(railLines.count == 1)
        // 連鎖レール(燻し橙)と重複レール(朱)が1本ずつ
        func verticalRailCount(of color: PanelColor) -> Int {
            elements.filter { element in
                guard case .line(let from, let to, let lineColor, _) = element else {
                    return false
                }
                return from.x == PanelLayout.calendarRailX && from.x == to.x
                    && lineColor == color
            }.count
        }
        #expect(verticalRailCount(of: PanelLayout.Colors.calendarChain) == 1)
        #expect(verticalRailCount(of: PanelLayout.Colors.clockSecondHand) == 1)
        // 数字は重複だけに残る
        #expect(containsText("30分重複", in: elements))
        #expect(!containsText("0分", in: elements))
    }

    @Test("通知モードでは閉じるボタン・強調背景・鮮度表示を描く")
    func calendarNotificationMode() {
        let rows: [CalendarSectionRow] = [
            .notice(text: "『定例』は中止になりました"),
            .event(.init(
                startText: "13:00", endText: "-14:00", title: "a",
                countdownText: "あと5分", isHighlighted: true)),
            .attendees(.init(othersText: "x, y")),
            .freshness(text: "3分前時点の情報"),
        ]
        let elements = builder().build(
            inputs(calendarRows: rows, showsCalendarCloseButton: true))

        #expect(containsText("✕ 閉じる", in: elements))
        #expect(containsText("『定例』は中止になりました", in: elements))
        #expect(containsText("3分前時点の情報", in: elements))
        #expect(elements.contains { element in
            guard case .rectangle(_, _, _, _, _, let id, let tracksMouse) = element else {
                return false
            }
            return id == "btn_cal_close" && tracksMouse
        })
        // 強調行と参加者行に暖色背景が敷かれる(2枚)
        let highlightCount = elements.filter { element in
            guard case .rectangle(_, let fill, _, _, _, _, _) = element else { return false }
            return fill == PanelLayout.Colors.activeRowBg
        }.count
        #expect(highlightCount == 2)
    }

    @Test("エラー行は朱のメッセージだけを描く")
    func calendarErrorRow() {
        let rows: [CalendarSectionRow] = [.error(message: "カレンダー『一般』が見つかりません")]
        let elements = builder().build(inputs(calendarRows: rows))

        #expect(containsText("カレンダー『一般』が見つかりません", in: elements))
    }

    private func expectNear(
        _ actual: PanelPoint, _ expected: PanelPoint,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.x - expected.x) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < 0.0001, sourceLocation: sourceLocation)
    }

    private func builder(
        now: Int = 1_000,
        localTime: ClockTime = .init(hour: 0, minute: 0, second: 0),
        resolveIcon: @escaping (String) -> IconResolution = { _ in .none },
        hasLogoImage: Bool = false
    ) -> PanelElementsBuilder {
        PanelElementsBuilder(
            now: { now },
            localTime: { localTime },
            measureTextHeight: { _, _, size in size + 8 },
            resolveIcon: resolveIcon,
            hasLogoImage: hasLogoImage,
            metrics: metrics)
    }

    private func inputs(
        project: KokukokuConfig.Project = .init(id: "work", name: "Work", icon: "🔵"),
        state: TimerState = .init(),
        selectedIndex: Int? = nil,
        hoveredId: String? = nil,
        resetConfirming: Bool = false,
        editingTarget: PanelEditingTarget? = nil,
        alertThresholds: [Int] = [],
        calendarRows: [CalendarSectionRow] = [],
        showsCalendarCloseButton: Bool = false
    ) -> PanelElementsBuilder.Inputs {
        .init(
            projects: [project], state: state,
            selectedIndex: selectedIndex, hoveredId: hoveredId,
            resetConfirming: resetConfirming,
            editingTarget: editingTarget,
            alertThresholds: alertThresholds,
            calendarRows: calendarRows,
            showsCalendarCloseButton: showsCalendarCloseButton, ui: ui)
    }

    private func containsText(_ text: String, in elements: [PanelElement]) -> Bool {
        elements.contains { element in
            guard case .text(_, let value, _, _, _, _) = element else { return false }
            return value == text
        }
    }
}
