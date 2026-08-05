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

        #expect(elements.count == 23)
        #expect(elements[0] == .rectangle(
            frame: .init(x: 0, y: 0, w: 480, h: 164),
            fillColor: PanelLayout.Colors.background, cornerRadius: 10))
        #expect(elements[1] == .rectangle(
            frame: .init(x: 0, y: 0, w: 480, h: 84),
            fillColor: PanelLayout.Colors.headerBg, cornerRadius: 10))
        // 文字盤は時刻に依らないSVG。針(elements[4])とは別レイヤーで持つ
        guard case .svg(let dialFrame, _, let dialCacheKey) = elements[3] else {
            Issue.record("文字盤がSVGで構築されていない")
            return
        }
        #expect(dialFrame == .init(
            x: metrics.clockCenter.x - 31, y: metrics.clockCenter.y - 31, w: 62, h: 62))
        #expect(dialCacheKey == "clock-dial")
        #expect(elements[9] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(elements[10] == .text(
            frame: .init(x: 24, y: 94, w: 14, h: 21), text: "1",
            fontName: "Menlo", fontSize: 13, color: PanelLayout.Colors.subText))
        #expect(elements[12] == .text(
            frame: .init(x: 74, y: 92, w: 270, h: 24), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 16, color: PanelLayout.Colors.text))
        #expect(elements[14] == .rectangle(
            frame: .init(x: 0, y: 124, w: 480, h: 1),
            fillColor: PanelLayout.Colors.separator))
        // 閾値未設定のデフォルトでは蝋燭は立たず、フッターにはリセットだけが残る
        #expect(elements[17] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        // リセットは そろばん(elements[18]) + 文言 の2つをひとかたまりで中央に置く
        #expect(elements[19] == .text(
            frame: .init(
                x: 423.4814285714286, y: 134, w: 24.18, h: 21), text: "ご破算",
            fontName: ".AppleSystemUIFont", fontSize: 13,
            color: PanelLayout.Colors.subText, alignment: .left))
        #expect(elements[20] == .rectangle(
            frame: .init(
                x: 480 - PanelLayout.pinButtonWidth - 6, y: 6,
                w: PanelLayout.pinButtonWidth, h: PanelLayout.pinButtonHeight),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 8,
            id: "btn_pin", tracksMouse: true))
        #expect(elements[22] == .rectangle(
            frame: .init(x: 0.5, y: 0.5, w: 479, h: 163),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 10,
            strokeColor: PanelLayout.Colors.panelBorder, strokeWidth: 1))
    }

    @Test("Pinの簪は姿を変えず、留めているかは紅と燻しの色で分ける")
    func pinButton() {
        let offElements = builder().build(inputs())
        let onElements = builder().build(inputs(pinned: true))

        guard case .svg(let frame, let offSVG, let offKey) = offElements[21],
            case .svg(_, let onSVG, let onKey) = onElements[21]
        else {
            Issue.record("簪がSVGで構築されていない")
            return
        }
        #expect(frame == .init(
            x: 480 - PanelLayout.pinButtonWidth - 6, y: 6,
            w: PanelLayout.pinButtonWidth, h: PanelLayout.pinButtonHeight))
        #expect(offKey == "kanzashi:off")
        #expect(onKey == "kanzashi:on")
        // 姿(30度の傾き)は状態で変えない。押しピンの記号であって状態表現ではないため
        #expect(offSVG.contains("rotate(30.00"))
        #expect(onSVG.contains("rotate(30.00"))
        // 状態は色だけが担う: onは紅と金の点睛、offは燻し一色
        #expect(onSVG.contains(PanelLayout.Colors.kanzashiBeni.hexString))
        #expect(onSVG.contains(PanelLayout.Colors.kanzashiKin.hexString))
        #expect(!offSVG.contains(PanelLayout.Colors.kanzashiBeni.hexString))
        #expect(offSVG.contains(PanelLayout.Colors.kanzashiIbushi.hexString))
    }

    @Test("リセットはご破算のそろばんを前置し、文言と一体で中央に置く")
    func resetSoroban() {
        let elements = builder().build(inputs())
        let confirming = builder().build(inputs(resetConfirming: true))

        guard case .svg(let frame, _, let key) = elements[18],
            case .svg(_, _, let confirmKey) = confirming[18]
        else {
            Issue.record("そろばんがSVGで構築されていない")
            return
        }
        #expect(frame.w == PanelLayout.sorobanWidth)
        #expect(frame.h == PanelLayout.sorobanHeight)
        // 確認中は文言と同じ生成りへ切り替わる(色ごとにキャッシュを分ける)
        #expect(key == "soroban:\(PanelLayout.Colors.subText.hexString)")
        #expect(confirmKey == "soroban:\(PanelLayout.Colors.text.hexString)")
        // そろばん+間隔+文言のかたまりが、ボタン(x=372, w=96)の中央に載る
        guard case .text(let textFrame, _, _, _, _, _) = elements[19] else {
            Issue.record("リセット文言がテキストで構築されていない")
            return
        }
        let total = frame.w + PanelLayout.sorobanTextGap + textFrame.w
        #expect(abs((frame.x + total / 2) - (372 + 96 / 2.0)) < 0.001)
    }

    @Test("絵文字アイコンをテキストとして描画する")
    func textIcon() {
        let elements = builder(resolveIcon: { _ in
            Issue.record("テキストアイコンでresolveIconが呼ばれた")
            return .none
        }).build(inputs())

        #expect(elements[11] == .text(
            frame: .init(x: 42, y: 92, w: 24, h: 25), text: "🔵",
            fontName: ".AppleSystemUIFont", fontSize: 17,
            color: PanelLayout.Colors.text, alignment: .center))
    }

    @Test("URL・パスアイコンの解決成功時は画像を描画する")
    func imageIcon() {
        let elements = builder(resolveIcon: { icon in .image(key: "cached:\(icon)") })
            .build(inputs(project: .init(id: "work", name: "Work", icon: "/tmp/work.png")))

        #expect(elements[11] == .image(
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

    @Test("蝋燭は計測中の経過ぶんだけ溶け、停止中の基準時間は溶けた扱いにしない")
    func continuousElapsed() {
        // 停止中(休憩中)は基準時間が残っていても満丈・消灯。次に点ける蝋燭が立っている
        let stopped = builder().build(inputs(
            state: .init(continuousElapsedBase: 600), alertThresholds: [3_600]))
        // 計測中は基準10分+経過10分=20分ぶん溶ける(60分中の1/3)
        let running = builder(now: 1_600).build(inputs(
            state: .init(continuousElapsedBase: 600, continuousStartedAt: 1_000),
            alertThresholds: [3_600]))

        #expect(candleCacheKey(in: stopped) == "candle:1000:0")
        #expect(candleCacheKey(in: running) == "candle:667:1")
    }

    @Test("選択・ホバー・リセット確認の色を反映する")
    func interactionColors() {
        let hovered = builder().build(inputs(hoveredId: "row_work"))
        let hoveredReset = builder().build(inputs(hoveredId: "btn_reset"))
        let confirming = builder().build(inputs(resetConfirming: true))

        #expect(hovered[9] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.rowHoverBg, id: "row_work", tracksMouse: true))
        #expect(hoveredReset[17] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.footerHoverBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(confirming[17] == .rectangle(
            frame: .init(x: 372, y: 131, w: 96, h: 26),
            fillColor: PanelLayout.Colors.resetConfirmBg, cornerRadius: 13,
            id: "btn_reset", tracksMouse: true))
        #expect(containsText("本当に?", in: confirming))
    }

    @Test("キーボード選択はカプセル輪郭で示し行背景は変えない")
    func selectionOutline() {
        let selected = builder().build(inputs(selectedTarget: .project(index: 1)))

        #expect(selected[9] == .rectangle(
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
        #expect(active[9] == .rectangle(
            frame: .init(x: 0, y: 84, w: 480, h: 40),
            fillColor: PanelLayout.Colors.activeRowBg, id: "row_work", tracksMouse: true))
        #expect(active[12] == .text(
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
            editingTarget: .project(id: "work"),
            alertThresholds: [3_600]))

        #expect(containsText("00:01:30", in: normal))
        #expect(!containsText("00:01:30", in: editing))
        #expect(candleCacheKey(in: editing) != nil)  // フッターの蝋燭は残る
    }

    @Test("連続稼働時間の編集中はフッターの蝋燭を消して編集フィールドに場所を譲る")
    func editingContinuousHidesCandle() {
        let editing = builder().build(inputs(
            state: .init(continuousElapsedBase: 600),
            editingTarget: .continuous,
            alertThresholds: [3_600]))

        #expect(candleCacheKey(in: editing) == nil)
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

    @Test("閾値があればフッター中央に蝋燭を置き、閾値がなければ何も置かない")
    func candleElement() {
        let none = builder().build(inputs())
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: 1_000),
            alertThresholds: [3_600]))

        #expect(!containsCandle(in: none))
        // 経過1800秒 = 最大閾値3600の半分 → 残量0.5の蝋燭がフッター中央に立つ
        let expected = metrics.candleFrame(projectCount: 1)
        #expect(elements.contains { element in
            guard case .svg(let frame, let svg, let cacheKey) = element else { return false }
            return frame == expected && cacheKey == "candle:500:1" && svg.hasPrefix("<svg")
        })
    }

    @Test("連続稼働の編集中は蝋燭を描かない(編集フィールドに場所を譲る)")
    func candleHiddenWhileEditing() {
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: 1_000),
            editingTarget: .continuous,
            alertThresholds: [3_600]))

        #expect(!containsCandle(in: elements))
    }

    @Test("休憩中は連続稼働が止まるため、蝋燭は満丈のまま消灯する")
    func candleUnlitWhileResting() {
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            alertThresholds: [3_600]))

        #expect(elements.contains { element in
            guard case .svg(_, _, let cacheKey) = element else { return false }
            return cacheKey == "candle:1000:0"
        })
    }

    @Test("計測停止の直後は実状態(満丈)ではなく、保たれた丈の蝋燭を描く")
    func candleRestoreOverridesBody() {
        // 停止直後は実状態が満丈・消灯へ跳ぶ状況
        let stopped = inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            alertThresholds: [3_600])
        #expect(candleCacheKey(in: builder(now: 2_800).build(stopped)) == "candle:1000:0")

        // 火が消えた時点の丈を保つ間は、その丈のまま描く
        let held = inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            alertThresholds: [3_600],
            candleRestore: .init(
                state: .init(remain: 0.5, lit: true), waxOpacity: 1))
        #expect(candleCacheKey(in: builder(now: 2_800).build(held)) == "candle:500:1")

        // 滲み出しの最中は不透明度まで絵に効き、キャッシュキーも別物になる
        let fading = inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            alertThresholds: [3_600],
            candleRestore: .init(
                state: .init(remain: 0.8, lit: false), waxOpacity: 0.8))
        let elements = builder(now: 2_800).build(fading)
        #expect(candleCacheKey(in: elements) == "candle:800:0:o80")
        #expect(elements.contains { element in
            guard case .svg(_, let svg, let cacheKey) = element,
                cacheKey.hasPrefix("candle:")
            else { return false }
            return svg.contains("<g opacity=\"0.8\">")
        })
    }

    @Test("燃え尽きから止めた直後は、熾火を沈めた蝋だまりを描く")
    func candleRestoreKeepsEmberPool() {
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            alertThresholds: [3_600],
            candleRestore: .init(
                state: .init(remain: 0, lit: true), waxOpacity: 1, emberOpacity: 0.4)))

        #expect(candleCacheKey(in: elements) == "candle:0:1:e40")
        #expect(elements.contains { element in
            guard case .svg(_, let svg, let cacheKey) = element, cacheKey.hasPrefix("candle:")
            else { return false }
            // 熾火だけが沈み、蝋だまりと台はそのまま
            return svg.contains("<g opacity=\"0.4\">")
                && svg.contains(PanelLayout.Colors.candleHolder.hexString)
        })
    }

    @Test("連続稼働の編集中は、丈を戻す途中でも蝋燭を描かない")
    func candleRestoreHiddenWhileEditing() {
        let elements = builder(now: 2_800).build(inputs(
            state: .init(continuousElapsedBase: 0, continuousStartedAt: nil),
            editingTarget: .continuous,
            alertThresholds: [3_600],
            candleRestore: .init(state: .init(remain: 0.5, lit: true), waxOpacity: 1)))

        #expect(!containsCandle(in: elements))
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

        #expect(elements[7] == .text(
            frame: metrics.clockDigitalFrame, text: "09:05:07",
            fontName: "Menlo", fontSize: PanelLayout.clockDigitalFontSize,
            color: PanelLayout.Colors.text))
    }

    @Test("針の絵は分ごとにしか変わらないため、秒が進んでもキャッシュが効き続ける")
    func clockHandsCacheKey() {
        let elements = builder(localTime: .init(hour: 9, minute: 30, second: 45)).build(inputs())
        let later = builder(localTime: .init(hour: 9, minute: 30, second: 46)).build(inputs())

        guard case .svg(_, let handsSVG, let handsKey) = elements[4],
            case .svg(_, let laterSVG, let laterKey) = later[4]
        else {
            Issue.record("針がSVGで構築されていない")
            return
        }
        #expect(handsKey == "clock-hands:9:30")
        #expect(laterKey == handsKey)
        #expect(laterSVG == handsSVG)
    }

    @Test("秒は針ではなく朱の日輪が刻む。にじみを敷いた二層で盤の上を巡る")
    func clockSun() {
        let center = metrics.clockCenter
        // 45秒 = 一周比 0.75 = 9時方向(isFlippedのy下向き座標では左)
        let elements = builder(localTime: .init(hour: 9, minute: 30, second: 45)).build(inputs())
        let expected = PanelPoint(x: center.x - 28 * 0.62, y: center.y)

        guard case .circle(let haloCenter, let haloRadius, let haloColor, _, _) = elements[5],
            case .circle(let sunCenter, let sunRadius, let sunColor, _, _) = elements[6]
        else {
            Issue.record("日輪のcircle要素が想定位置にない")
            return
        }
        expectNear(haloCenter, expected)
        expectNear(sunCenter, expected)
        #expect(haloRadius > sunRadius)
        #expect(haloColor == PanelLayout.Colors.clockSunHalo)
        #expect(sunColor == PanelLayout.Colors.clockSecondHand)
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
        pinned: Bool = false,
        candleRestore: CandleArt.Restore? = nil
    ) -> PanelElementsBuilder.Inputs {
        .init(
            projects: [project], state: state,
            selectedTarget: selectedTarget, hoveredId: hoveredId,
            resetConfirming: resetConfirming,
            editingTarget: editingTarget,
            alertThresholds: alertThresholds,
            calendarRows: calendarRows, ui: ui,
            pinned: pinned,
            candleRestore: candleRestore)
    }

    /// 蝋燭要素のキャッシュキー(残量・点灯状態がそのまま読める)。無ければnil。
    /// ヘッダー時計も同じSVG要素で描かれるため、キーの接頭辞で選り分ける
    private func candleCacheKey(in elements: [PanelElement]) -> String? {
        for element in elements {
            if case .svg(_, _, let cacheKey) = element, cacheKey.hasPrefix("candle:") {
                return cacheKey
            }
        }
        return nil
    }

    /// 蝋燭が立っているか。時計のSVGを蝋燭と取り違えないよう接頭辞で判定する
    private func containsCandle(in elements: [PanelElement]) -> Bool {
        candleCacheKey(in: elements) != nil
    }

    private func containsText(_ text: String, in elements: [PanelElement]) -> Bool {
        elements.contains { element in
            guard case .text(_, let value, _, _, _, _) = element else { return false }
            return value == text
        }
    }
}
