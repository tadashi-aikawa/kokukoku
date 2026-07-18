import Testing

@testable import KokukokuCore

@Suite("PanelElementsBuilder")
struct PanelElementsBuilderTests {
    private let ui = ResolvedUIConfig(ui: nil)

    @Test("Luaと同じ順序・座標・色・idで主要素を構築する")
    func representativeLayout() {
        let elements = builder().build(inputs())

        #expect(elements.count == 29)
        #expect(elements[0] == .rectangle(
            frame: .init(x: 0, y: 0, w: 420, h: 164),
            fillColor: PanelLayout.Colors.background, cornerRadius: 10))
        #expect(elements[1] == .rectangle(
            frame: .init(x: 0, y: 0, w: 420, h: 84),
            fillColor: PanelLayout.Colors.headerBg, cornerRadius: 10))
        #expect(elements[3] == .circle(
            center: PanelLayout.clockCenter, radius: 28,
            fillColor: PanelLayout.Colors.rowBg,
            strokeColor: PanelLayout.Colors.separator, strokeWidth: 1))
        #expect(elements[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 420, h: 40),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(elements[15] == .text(
            frame: .init(x: 12, y: 93, w: 20, h: 21), text: "1",
            fontName: "Menlo", fontSize: 13, color: PanelLayout.Colors.subText))
        #expect(elements[17] == .text(
            frame: .init(x: 66, y: 92, w: 166, h: 24), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 16, color: PanelLayout.Colors.text))
        #expect(elements[19] == .rectangle(
            frame: .init(x: 0, y: 124, w: 420, h: 1),
            fillColor: PanelLayout.Colors.separator))
        #expect(elements[22] == .text(
            frame: .init(x: 182, y: 134, w: 90, h: 28), text: "00:00:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(elements[23] == .rectangle(
            frame: .init(x: 8, y: 128, w: 108, h: 30),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 6,
            id: "btn_break", tracksMouse: true))
        #expect(elements[26] == .rectangle(
            frame: .init(x: 294, y: 128, w: 118, h: 30),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 6,
            id: "btn_reset", tracksMouse: true))
        #expect(elements[28] == .rectangle(
            frame: .init(x: 0.5, y: 0.5, w: 419, h: 163),
            fillColor: .init(red: 0, green: 0, blue: 0, alpha: 0), cornerRadius: 10,
            strokeColor: PanelLayout.Colors.panelBorder, strokeWidth: 1))
    }

    @Test("ロゴがある場合だけロゴ画像を追加する")
    func logo() {
        let withoutLogo = builder(hasLogoImage: false).build(inputs())
        let withLogo = builder(hasLogoImage: true).build(inputs())

        #expect(!withoutLogo.contains(.image(
            frame: .init(x: 148, y: 130, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit)))
        #expect(withLogo[22] == .image(
            frame: .init(x: 148, y: 130, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit))
    }

    @Test("絵文字アイコンをテキストとして描画する")
    func textIcon() {
        let elements = builder(resolveIcon: { _ in
            Issue.record("テキストアイコンでresolveIconが呼ばれた")
            return .none
        }).build(inputs())

        #expect(elements[16] == .text(
            frame: .init(x: 34, y: 91, w: 24, h: 25), text: "🔵",
            fontName: ".AppleSystemUIFont", fontSize: 17,
            color: PanelLayout.Colors.text, alignment: .center))
    }

    @Test("URL・パスアイコンの解決成功時は画像を描画する")
    func imageIcon() {
        let elements = builder(resolveIcon: { icon in .image(key: "cached:\(icon)") })
            .build(inputs(project: .init(id: "work", name: "Work", icon: "/tmp/work.png")))

        #expect(elements[16] == .image(
            frame: .init(x: 34, y: 92, w: 24, h: 24),
            iconKey: "cached:/tmp/work.png", scaling: .scaleProportionally))
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
            frame: .init(x: 182, y: 134, w: 90, h: 28), text: "00:10:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(running[22] == .text(
            frame: .init(x: 182, y: 134, w: 90, h: 28), text: "00:11:40",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.text))
    }

    @Test("休憩ボタンにカスタムアイコンと名前を表示する")
    func customBreakItem() {
        let elements = builder().build(inputs(breakItem: .init(name: "深呼吸", icon: "🫖")))

        #expect(containsText("🫖", in: elements))
        #expect(containsText("深呼吸", in: elements))
        #expect(!containsText("☕", in: elements))
    }

    @Test("選択・ホバー・リセット確認の色を反映する")
    func interactionColors() {
        let hovered = builder().build(inputs(hoveredId: "row_work"))
        let hoveredBreak = builder().build(inputs(hoveredId: "btn_break"))
        let confirming = builder().build(inputs(resetConfirming: true))

        #expect(hovered[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 420, h: 40),
            fillColor: PanelLayout.Colors.rowHoverBg, id: "row_work", tracksMouse: true))
        #expect(hoveredBreak[23] == .rectangle(
            frame: .init(x: 8, y: 128, w: 108, h: 30),
            fillColor: PanelLayout.Colors.footerHoverBg, cornerRadius: 6,
            id: "btn_break", tracksMouse: true))
        #expect(confirming[26] == .rectangle(
            frame: .init(x: 294, y: 128, w: 118, h: 30),
            fillColor: PanelLayout.Colors.resetConfirmBg, cornerRadius: 6,
            id: "btn_reset", tracksMouse: true))
        #expect(containsText("⚠️ 本当に?", in: confirming))
    }

    @Test("キーボード選択はカプセル輪郭で示し行背景は変えない")
    func selectionOutline() {
        let selected = builder().build(inputs(selectedIndex: 1))

        #expect(selected[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 420, h: 40),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(selected.last == .rectangle(
            frame: .init(x: 3, y: 87, w: 414, h: 34),
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
            frame: .init(x: 7, y: 91, w: 406, h: 26),
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
            frame: .init(x: 3, y: 86, w: 414, h: 36),
            cornerRadius: 18,
            strokeWidth: 1,
            topColor: PanelLayout.Colors.neonCoreTop,
            bottomColor: PanelLayout.Colors.neonCoreBottom,
            glowColor: PanelLayout.Colors.neonGlow,
            glowRadius: 7))
        #expect(!containsText("▶ 計測中", in: active))
        // 行背景と文字はアクティブ配色になる
        #expect(active[14] == .rectangle(
            frame: .init(x: 0, y: 84, w: 420, h: 40),
            fillColor: PanelLayout.Colors.activeRowBg, id: "row_work", tracksMouse: true))
        #expect(active[17] == .text(
            frame: .init(x: 66, y: 92, w: 166, h: 24), text: "Work",
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
        #expect(PanelLayout.continuousTimeFrame(projectCount: 1)
            == .init(x: 182, y: 134, w: 90, h: 28))
        #expect(PanelLayout.accumulatedTimeFrame(rowOffset: 0)
            == .init(x: 240, y: 84, w: 100, h: 40))
        #expect(PanelLayout.accumulatedTimeFrame(rowOffset: 2)
            == .init(x: 240, y: 164, w: 100, h: 40))
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
            frame: PanelLayout.clockDigitalFrame, text: "09:05:07",
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
        let center = PanelLayout.clockCenter
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
            hasLogoImage: hasLogoImage)
    }

    private func inputs(
        project: KokukokuConfig.Project = .init(id: "work", name: "Work", icon: "🔵"),
        breakItem: KokukokuConfig.BreakItem? = nil,
        state: TimerState = .init(),
        selectedIndex: Int? = nil,
        hoveredId: String? = nil,
        resetConfirming: Bool = false,
        editingTarget: PanelEditingTarget? = nil
    ) -> PanelElementsBuilder.Inputs {
        .init(
            projects: [project], breakItem: breakItem, state: state,
            selectedIndex: selectedIndex, hoveredId: hoveredId,
            resetConfirming: resetConfirming,
            editingTarget: editingTarget, ui: ui)
    }

    private func containsText(_ text: String, in elements: [PanelElement]) -> Bool {
        elements.contains { element in
            guard case .text(_, let value, _, _, _, _) = element else { return false }
            return value == text
        }
    }
}
