import Foundation
import Testing

@testable import KokukokuCore

private func testEventKey(_ id: String) -> CalendarEvent.EventKey {
    .init(externalIdentifier: id, occurrenceDate: .distantPast)
}

@Suite("PanelElementsBuilder")
struct PanelElementsBuilderTests {
    private let ui = ResolvedUIConfig(ui: nil)
    private let metrics = PanelMetrics(panelWidth: 480)

    @Test("Luaと同じ順序・座標・色・idで主要素を構築する")
    func representativeLayout() {
        let elements = builder().build(inputs())

        #expect(elements.count == 30)
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
            frame: .init(x: 24, y: 94, w: 14, h: 21), text: "1",
            fontName: "Menlo", fontSize: 13, color: PanelLayout.Colors.subText))
        #expect(elements[17] == .text(
            frame: .init(x: 74, y: 92, w: 270, h: 24), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 16, color: PanelLayout.Colors.text))
        #expect(elements[19] == .rectangle(
            frame: .init(x: 0, y: 124, w: 480, h: 1),
            fillColor: PanelLayout.Colors.separator))
        let labelWidth = 7.0 * 14 * 0.62  // 「連続稼働 0分」の概算幅
        #expect(elements[22] == .text(
            frame: .init(x: (480 - labelWidth) / 2, y: 129, w: labelWidth, h: 22),
            text: "連続稼働 0分",
            fontName: ".AppleSystemUIFont", fontSize: 14, color: PanelLayout.Colors.subText))
        #expect(elements[23] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(elements[25] == .rectangle(
            frame: .init(x: 452, y: 6, w: 22, h: 22),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 5,
            id: "btn_pin", tracksMouse: true))
        #expect(elements[29] == .rectangle(
            frame: .init(x: 0.5, y: 0.5, w: 479, h: 163),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 10,
            strokeColor: PanelLayout.Colors.panelBorder, strokeWidth: 1))
    }

    @Test("Pinボタンは常設で、off時は鈍色の45度傾き・on時は生成りの垂直姿勢で描く")
    func pinButton() {
        let offElements = builder().build(inputs())
        let onElements = builder().build(inputs(pinned: true))

        // 頭のクロスバー(width 3の線)で姿勢と色を判定する
        #expect(offElements[26] == .line(
            from: .init(x: 464, y: 11), to: .init(x: 469, y: 16),
            color: PanelLayout.Colors.subText, width: 3))
        #expect(onElements[26] == .line(
            from: .init(x: 459.5, y: 12.5), to: .init(x: 466.5, y: 12.5),
            color: PanelLayout.Colors.text, width: 3))
    }

    @Test("絵文字アイコンをテキストとして描画する")
    func textIcon() {
        let elements = builder(resolveIcon: { _ in
            Issue.record("テキストアイコンでresolveIconが呼ばれた")
            return .none
        }).build(inputs())

        #expect(elements[16] == .text(
            frame: .init(x: 42, y: 92, w: 24, h: 25), text: "🔵",
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

    @Test("フッターは停止中の基準時間と稼働中の経過時間を分単位ラベルで表示する")
    func continuousElapsed() {
        let stopped = builder().build(inputs(state: .init(continuousElapsedBase: 600)))
        let running = builder(now: 1_100).build(inputs(state: .init(
            continuousElapsedBase: 600, continuousStartedAt: 1_000)))

        let labelWidth = 8.0 * 14 * 0.62  // 「連続稼働 10分」の概算幅
        #expect(stopped[22] == .text(
            frame: .init(x: (480 - labelWidth) / 2, y: 129, w: labelWidth, h: 22),
            text: "連続稼働 10分",
            fontName: ".AppleSystemUIFont", fontSize: 14, color: PanelLayout.Colors.subText))
        // 計測中でも色は沈み生成りのまま(計測中は行のカプセルが語る。朱は超過時のみ)
        #expect(running[22] == .text(
            frame: .init(x: (480 - labelWidth) / 2, y: 129, w: labelWidth, h: 22),
            text: "連続稼働 11分",
            fontName: ".AppleSystemUIFont", fontSize: 14, color: PanelLayout.Colors.subText))
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
        let selected = builder().build(inputs(selectedTarget: .project(index: 1)))

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
            selectedTarget: .project(index: 1)))

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

    @Test("予定行のキーボード選択もカプセル輪郭で示す")
    func selectionOutlineOnCalendarRow() {
        let rows: [CalendarSectionRow] = [
            .event(.init(
                eventKey: testEventKey("a"), startText: "13:00", endText: "14:00",
                title: "a", countdownText: "あと5分")),
            .event(.init(
                eventKey: testEventKey("b"), startText: "14:10", endText: "15:00",
                title: "b", gapStyle: .rail)),
            .overflow(hiddenCount: 2),
        ]
        let selected = builder().build(inputs(
            selectedTarget: .calendarEvent(eventIndex: 1), calendarRows: rows))

        // 2件目の予定行(セクション上端84+余白6+nowマーカー帯18+1行分26)に輪郭が乗る
        #expect(selected.contains(.rectangle(
            frame: .init(x: 8, y: 136, w: 464, h: 22),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 11,
            strokeColor: PanelLayout.Colors.selectionOutline,
            strokeWidth: 1)))

        // 「他◯件」行の選択にも輪郭が乗る(Enterで展開できる合図)
        let overflowSelected = builder().build(inputs(
            selectedTarget: .calendarOverflow, calendarRows: rows))
        #expect(overflowSelected.contains(.rectangle(
            frame: .init(x: 8, y: 162, w: 464, h: 14),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0),
            cornerRadius: 7,
            strokeColor: PanelLayout.Colors.selectionOutline,
            strokeWidth: 1)))
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
        #expect(containsText("連続稼働 0分", in: editing))  // フッターの連続稼働ラベルは残る
    }

    @Test("連続稼働時間の編集中はフッターのラベルを描画しない")
    func editingContinuousHidesFooterLabel() {
        let editing = builder().build(inputs(
            state: .init(continuousElapsedBase: 600),
            editingTarget: .continuous))

        #expect(!containsText("連続稼働 10分", in: editing))
        #expect(containsText("00:00:00", in: editing))  // プロジェクト行の時刻は残る
    }

    @Test("編集フィールドの枠は時刻テキストの列位置と一致する")
    func editingFrames() {
        #expect(metrics.continuousTimeFrame(projectCount: 1)
            == .init(x: 195, y: 134, w: 90, h: 28))
        #expect(metrics.accumulatedTimeFrame(rowOffset: 0)
            == .init(x: 356, y: 84, w: 100, h: 40))
        #expect(metrics.accumulatedTimeFrame(rowOffset: 2)
            == .init(x: 356, y: 164, w: 100, h: 40))
    }

    @Test("連続稼働ゲージの進行率は最大閾値までの全行程基準で閾値なしなら非表示")
    func gaugeProgress() {
        #expect(PanelElementsBuilder.gaugeProgress(continuousElapsed: 1800, thresholds: [3600]) == 0.5)
        // 複数閾値でも最大閾値までの全行程で進む(区切りがセグメントを示す)
        #expect(
            PanelElementsBuilder.gaugeProgress(continuousElapsed: 2700, thresholds: [1800, 3600])
                == 0.75)
        // 超過後は満タン(朱)に張り付く
        #expect(PanelElementsBuilder.gaugeProgress(continuousElapsed: 4000, thresholds: [3600]) == 1)
        #expect(PanelElementsBuilder.gaugeProgress(continuousElapsed: 100, thresholds: []) == nil)
        #expect(PanelElementsBuilder.gaugeProgress(continuousElapsed: 100, thresholds: [0]) == nil)
    }

    @Test("ゲージの区切りは閾値2本以上のとき中間閾値の位置だけに入る")
    func gaugeSeparators() {
        #expect(PanelElementsBuilder.gaugeSeparatorPositions(thresholds: [3600]) == [])
        #expect(PanelElementsBuilder.gaugeSeparatorPositions(thresholds: [3600, 1800]) == [0.5])
        #expect(
            PanelElementsBuilder.gaugeSeparatorPositions(thresholds: [1800, 1800, 3600]) == [0.5])
        #expect(PanelElementsBuilder.gaugeSeparatorPositions(thresholds: []) == [])
    }

    @Test("連続稼働ラベルは分単位表記で最大閾値の超過判定は閾値ちょうどから立つ")
    func minuteDurationAndOverThreshold() {
        #expect(PanelElementsBuilder.minuteDuration(13_560) == "3時間46分")
        #expect(PanelElementsBuilder.minuteDuration(59) == "0分")
        #expect(PanelElementsBuilder.minuteDuration(3_630) == "1時間0分")
        #expect(!PanelElementsBuilder.isOverThreshold(elapsed: 3_599, thresholds: [3600]))
        #expect(PanelElementsBuilder.isOverThreshold(elapsed: 3_600, thresholds: [1800, 3600]))
        #expect(!PanelElementsBuilder.isOverThreshold(elapsed: 10_000, thresholds: []))
    }

    @Test("閾値があればフッター下端に連続稼働ゲージの溝と火を描く")
    func gaugeElements() {
        let none = builder().build(inputs())
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: 1_000),
            alertThresholds: [3_600]))

        // 溝はフッター中央の固定幅
        let track = PanelFrame(x: 150, y: 159, w: 180, h: 3)
        #expect(!none.contains(.rectangle(
            frame: track, fillColor: PanelLayout.Colors.gaugeTrack, cornerRadius: 1.5)))
        #expect(elements.contains(.rectangle(
            frame: track, fillColor: PanelLayout.Colors.gaugeTrack, cornerRadius: 1.5)))
        #expect(elements.contains(.rectangle(
            frame: .init(x: 150, y: 159, w: 90, h: 3),
            fillColor: PanelElementsBuilder.gaugeColor(fraction: 0.5), cornerRadius: 1.5)))
    }

    @Test("閾値が複数なら中間閾値の位置に区切りを描き超過中はラベルが朱になる")
    func segmentedGaugeAndOverColor() {
        let elements = builder(now: 4_700).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: 1_000),
            alertThresholds: [1_800, 3_600]))

        // 経過3700秒 = 最大閾値3600を超過 → 満タンの朱+中間区切り+朱ラベル
        #expect(elements.contains(.rectangle(
            frame: .init(x: 150, y: 159, w: 180, h: 3),
            fillColor: PanelElementsBuilder.gaugeColor(fraction: 1), cornerRadius: 1.5)))
        #expect(elements.contains(.rectangle(
            frame: .init(x: 239, y: 159, w: 2, h: 3),
            fillColor: PanelLayout.Colors.footerBg)))
        #expect(elements.contains { element in
            guard case .text(_, let text, _, _, let color, _) = element else { return false }
            return text == "連続稼働 1時間1分" && color == PanelLayout.Colors.gaugeEnd
        })
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

    @Test("パネル幅の下限・上限を設定で変更できる")
    func metricsComputeCustomWidth() {
        func width(nameWidths: [String: Double], min: Double, max: Double) -> Double {
            PanelMetrics.compute(
                projectNames: Array(nameWidths.keys),
                measureNameWidth: { nameWidths[$0] ?? 0 },
                minWidth: min,
                maxWidth: max
            ).panelWidth
        }

        #expect(width(nameWidths: ["short": 100], min: 300, max: 600) == 310)
        #expect(width(nameWidths: ["short": 100], min: 350, max: 600) == 350)
        #expect(width(nameWidths: ["long": 400], min: 300, max: 500) == 500)
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
                eventKey: testEventKey("meeting"),
                startText: "13:00", endText: "14:00", title: "定例",
                locationText: "会議室A",
                detailURL: URL(string: "https://calendar.google.com/calendar/event?eid=x"),
                countdownText: "あと30分")),
        ]
        let sectionHeight = PanelLayout.calendarSectionHeight(rows: rows)
        let elements = builder().build(inputs(calendarRows: rows))

        // 背景(全高)が伸びる
        guard case .rectangle(let bgFrame, _, _, _, _, _, _) = elements[0] else {
            Issue.record("背景がない")
            return
        }
        #expect(bgFrame.h == 164 + sectionHeight)
        // セクションの中身(時刻分離・カウントダウン)と行クリックのホバー追跡
        #expect(containsText("13:00", in: elements))
        #expect(containsText("14:00", in: elements))
        #expect(containsText("定例", in: elements))
        // 場所はタイトル下段に表示される
        #expect(containsText("会議室A", in: elements))
        #expect(containsText("あと30分", in: elements))
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
            .event(.init(
                eventKey: testEventKey("a"), startText: "13:00", endText: "14:00",
                title: "a", countdownText: "あと5分")),
            .event(.init(
                eventKey: testEventKey("b"), startText: "14:10", endText: "15:00",
                title: "b", gapStyle: .rail)),
            .event(.init(
                eventKey: testEventKey("c"), startText: "15:00", endText: "16:00",
                title: "c", gapStyle: .contact)),
            .event(.init(
                eventKey: testEventKey("d"), startText: "15:30", endText: "16:30", title: "d",
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
        // 通常レール(縦線・subText色)はnow→先頭と間隔ありの2本だけ
        // (時計の目盛もsubTextの縦線のため、レールのx座標で絞る)
        let railLines = elements.filter { element in
            guard case .line(let from, let to, let color, _) = element else { return false }
            return from.x == PanelLayout.calendarRailX && from.x == to.x
                && color == PanelLayout.Colors.subText
        }
        #expect(railLines.count == 2)
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

    @Test("nowマーカー帯: レールをヘッダー境界から降ろし、未開始の「あと◯分」は区間ラベルとして描く")
    func nowMarkerWithUpcomingCountdown() {
        let rows: [CalendarSectionRow] = [
            .event(.init(
                eventKey: testEventKey("a"), startText: "13:00", endText: "14:00", title: "a",
                countdownText: "あと38分", countdownUrgency: .distant)),
        ]
        let elements = builder().build(inputs(calendarRows: rows))
        let railX = PanelLayout.calendarRailX

        // セクション上端84(時計=いまの面との境界)から先頭の点(中心 84+6+18+13=121)へ通常レール
        #expect(elements.contains(.line(
            from: .init(x: railX, y: 84), to: .init(x: railX, y: 116),
            color: PanelLayout.Colors.subText, width: 1)))
        // 「あと38分」は区間ラベルとして帯(中心 84+6+9=99)に出る(ヘッダー右端には出ない)
        let labelFrames = elements.compactMap { element -> PanelFrame? in
            guard case .text(let frame, "あと38分", _, _, _, _) = element else { return nil }
            return frame
        }
        #expect(labelFrames.map(\.x) == [railX + 9])
    }

    @Test("進行中の「終了まで◯分」はタイトル右端に出て、場所は下段に表示される")
    func ongoingCountdownInRow() {
        let rows: [CalendarSectionRow] = [
            .event(.init(
                eventKey: testEventKey("a"), startText: "13:00", endText: "14:00", title: "a",
                locationText: "会議室A",
                countdownText: "終了まで8分", countdownUrgency: .imminent,
                isInProgress: true)),
        ]
        let elements = builder().build(inputs(calendarRows: rows))

        // カウントダウンはタイトル右端(右寄せ・警告色)
        #expect(elements.contains { element in
            guard case .text(let frame, "終了まで8分", _, 12, let color, .right) = element
            else { return false }
            return frame.x == 358 && color == PanelLayout.Colors.countdownImminent
        })
        // 場所は下段に表示される(進行中でも表示)
        #expect(containsText("会議室A", in: elements))
        // 帯は置かず(高さごと詰める)、nowレールも出さない(「いま」はリングが語る)。
        // 行はセクション上端84+余白6から始まる
        #expect(!elements.contains { element in
            guard case .line(let from, let to, _, _) = element else { return false }
            return from.x == PanelLayout.calendarRailX && from.x == to.x
        })
        // 進行中の点は橙の炎色の中抜きリング+単層の淡い橙グロー(色相と光で「いま消化中」を語る)
        #expect(elements.contains { element in
            guard case .circle(let center, 3, let fill, let stroke, 1.5) = element
            else { return false }
            return center == PanelPoint(x: PanelLayout.calendarRailX, y: 103)
                && fill == PanelLayout.Colors.headerBg
                && stroke == PanelLayout.Colors.calendarOngoing
        })
        #expect(elements.contains { element in
            guard case .circle(let center, 7.5, let fill, nil, _) = element
            else { return false }
            return center == PanelPoint(x: PanelLayout.calendarRailX, y: 103)
                && fill == PanelLayout.Colors.calendarOngoingGlow
        })
    }

    @Test("通知モードでは対象の点のハロー・告知・鮮度表示を描く(閉じるボタンは置かない)")
    func calendarNotificationMode() {
        let rows: [CalendarSectionRow] = [
            .notice(text: "『定例』は中止になりました"),
            .event(.init(
                eventKey: testEventKey("a"), startText: "13:00", endText: "14:00", title: "a",
                countdownText: "あと5分", isAlertTarget: true)),
            .freshness(text: "3分前時点の情報"),
        ]
        let elements = builder().build(inputs(calendarRows: rows))

        #expect(containsText("『定例』は中止になりました", in: elements))
        #expect(containsText("3分前時点の情報", in: elements))
        // 場所が無い予定には場所行が出ない(場所テキストを含む要素がない)
        // 通知対象の点には生成りの二層ハローが灯る(点の位置はレール上)
        #expect(elements.contains { element in
            guard case .circle(let center, 8, let fill, _, _) = element else { return false }
            return center.x == PanelLayout.calendarRailX
                && fill == PanelLayout.Colors.alertHaloOuter
        })
        #expect(elements.contains { element in
            guard case .circle(_, 5.5, let fill, _, _) = element else { return false }
            return fill == PanelLayout.Colors.alertHaloInner
        })
        // 閉じるボタンは廃止(フォーカス非奪取のため1クリック目が届かず2クリック要る体験になる。
        // 閉じるのはパネルクリック後のEscかホットキー。2026-07-19 タダシ決定)
        #expect(!containsText("✕ 閉じる", in: elements))
        // 行の暖色強調は廃止(名指しは点のハローが担い「暖色=計測中」の単義を守る)
        #expect(!elements.contains { element in
            guard case .rectangle(_, let fill, _, _, _, _, _) = element else { return false }
            return fill == PanelLayout.Colors.activeRowBg
        })
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
        resolveIcon: @escaping (String) -> IconResolution = { _ in .none }
    ) -> PanelElementsBuilder {
        PanelElementsBuilder(
            now: { now },
            localTime: { localTime },
            measureTextHeight: { _, _, size in size + 8 },
            resolveIcon: resolveIcon,
            metrics: metrics)
    }

    private func inputs(
        project: KokukokuConfig.Project = .init(id: "work", name: "Work", icon: "🔵"),
        state: TimerState = .init(),
        selectedTarget: PanelSelectionTarget? = nil,
        hoveredId: String? = nil,
        resetConfirming: Bool = false,
        editingTarget: PanelEditingTarget? = nil,
        alertThresholds: [Int] = [],
        calendarRows: [CalendarSectionRow] = [],
        pinned: Bool = false
    ) -> PanelElementsBuilder.Inputs {
        .init(
            projects: [project], state: state,
            selectedTarget: selectedTarget, hoveredId: hoveredId,
            resetConfirming: resetConfirming,
            editingTarget: editingTarget,
            alertThresholds: alertThresholds,
            calendarRows: calendarRows, ui: ui,
            pinned: pinned)
    }

    private func containsText(_ text: String, in elements: [PanelElement]) -> Bool {
        elements.contains { element in
            guard case .text(_, let value, _, _, _, _) = element else { return false }
            return value == text
        }
    }
}
