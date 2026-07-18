import Testing

@testable import KokukokuCore

@Suite("PanelElementsBuilder")
struct PanelElementsBuilderTests {
    private let ui = ResolvedUIConfig(ui: nil)

    @Test("Luaと同じ順序・座標・色・idで主要素を構築する")
    func representativeLayout() {
        let elements = builder().build(inputs())

        #expect(elements.count == 18)
        #expect(elements[0] == .rectangle(
            frame: .init(x: 0, y: 0, w: 420, h: 120),
            fillColor: PanelLayout.Colors.background, cornerRadius: 10))
        #expect(elements[1] == .rectangle(
            frame: .init(x: 0, y: 0, w: 420, h: 44),
            fillColor: PanelLayout.Colors.headerBg, cornerRadius: 10))
        #expect(elements[3] == .text(
            frame: .init(x: 182, y: 12, w: 90, h: 28), text: "00:00:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(elements[5] == .rectangle(
            frame: .init(x: 0, y: 44, w: 420, h: 36),
            fillColor: PanelLayout.Colors.rowBg, id: "row_work", tracksMouse: true))
        #expect(elements[6] == .text(
            frame: .init(x: 12, y: 52, w: 20, h: 20), text: "1",
            fontName: "Menlo", fontSize: 12, color: PanelLayout.Colors.subText))
        #expect(elements[8] == .text(
            frame: .init(x: 66, y: 51, w: 166, h: 22), text: "Work",
            fontName: ".AppleSystemUIFont", fontSize: 14, color: PanelLayout.Colors.text))
        #expect(elements[10] == .rectangle(
            frame: .init(x: 0, y: 80, w: 420, h: 1),
            fillColor: PanelLayout.Colors.separator))
        #expect(elements[13] == .rectangle(
            frame: .init(x: 8, y: 84, w: 108, h: 30),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 6,
            id: "btn_break", tracksMouse: true))
        #expect(elements[16] == .rectangle(
            frame: .init(x: 294, y: 84, w: 118, h: 30),
            fillColor: PanelLayout.Colors.footerBg, cornerRadius: 6,
            id: "btn_reset", tracksMouse: true))
    }

    @Test("ロゴがある場合だけロゴ画像を追加する")
    func logo() {
        let withoutLogo = builder(hasLogoImage: false).build(inputs())
        let withLogo = builder(hasLogoImage: true).build(inputs())

        #expect(!withoutLogo.contains(.image(
            frame: .init(x: 148, y: 8, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit)))
        #expect(withLogo[3] == .image(
            frame: .init(x: 148, y: 8, w: 28, h: 28),
            iconKey: "logo", scaling: .shrinkToFit))
    }

    @Test("表示指定時だけバージョンを追加する")
    func versionVisibility() {
        let hidden = builder().build(inputs(isVersionVisible: false, versionText: "v0.5.0"))
        let shown = builder().build(inputs(isVersionVisible: true, versionText: "v0.5.0"))

        #expect(!containsText("v0.5.0", in: hidden))
        #expect(shown[4] == .text(
            frame: .init(x: 336, y: 6, w: 72, h: 18), text: "v0.5.0",
            fontName: "Menlo", fontSize: 10,
            color: PanelLayout.Colors.subText, alignment: .right))
    }

    @Test("絵文字アイコンをテキストとして描画する")
    func textIcon() {
        let elements = builder(resolveIcon: { _ in
            Issue.record("テキストアイコンでresolveIconが呼ばれた")
            return .none
        }).build(inputs())

        #expect(elements[7] == .text(
            frame: .init(x: 34, y: 51, w: 24, h: 22), text: "🔵",
            fontName: ".AppleSystemUIFont", fontSize: 14,
            color: PanelLayout.Colors.text, alignment: .center))
    }

    @Test("URL・パスアイコンの解決成功時は画像を描画する")
    func imageIcon() {
        let elements = builder(resolveIcon: { icon in .image(key: "cached:\(icon)") })
            .build(inputs(project: .init(id: "work", name: "Work", icon: "/tmp/work.png")))

        #expect(elements[7] == .image(
            frame: .init(x: 36, y: 52, w: 20, h: 20),
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

        #expect(stopped[3] == .text(
            frame: .init(x: 182, y: 12, w: 90, h: 28), text: "00:10:00",
            fontName: "Menlo", fontSize: 16, color: PanelLayout.Colors.subText))
        #expect(running[3] == .text(
            frame: .init(x: 182, y: 12, w: 90, h: 28), text: "00:11:40",
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
        let selected = builder().build(inputs(selectedIndex: 1))
        let hoveredBreak = builder().build(inputs(hoveredId: "btn_break"))
        let confirming = builder().build(inputs(resetConfirming: true))

        #expect(selected[5] == .rectangle(
            frame: .init(x: 0, y: 44, w: 420, h: 36),
            fillColor: PanelLayout.Colors.rowHoverBg, id: "row_work", tracksMouse: true))
        #expect(hoveredBreak[13] == .rectangle(
            frame: .init(x: 8, y: 84, w: 108, h: 30),
            fillColor: PanelLayout.Colors.footerHoverBg, cornerRadius: 6,
            id: "btn_break", tracksMouse: true))
        #expect(confirming[16] == .rectangle(
            frame: .init(x: 294, y: 84, w: 118, h: 30),
            fillColor: PanelLayout.Colors.resetConfirmBg, cornerRadius: 6,
            id: "btn_reset", tracksMouse: true))
        #expect(containsText("⚠️ 本当に?", in: confirming))
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
        #expect(PanelLayout.continuousTimeFrame == .init(x: 182, y: 12, w: 90, h: 28))
        #expect(PanelLayout.accumulatedTimeFrame(rowOffset: 0)
            == .init(x: 240, y: 44, w: 100, h: 36))
        #expect(PanelLayout.accumulatedTimeFrame(rowOffset: 2)
            == .init(x: 240, y: 116, w: 100, h: 36))
    }

    @Test("パネル高さをプロジェクト数から算出する")
    func panelHeight() {
        #expect(PanelLayout.panelHeight(projectCount: 0) == 84)
        #expect(PanelLayout.panelHeight(projectCount: 3) == 192)
    }

    private func builder(
        now: Int = 1_000,
        resolveIcon: @escaping (String) -> IconResolution = { _ in .none },
        hasLogoImage: Bool = false
    ) -> PanelElementsBuilder {
        PanelElementsBuilder(
            now: { now },
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
        isVersionVisible: Bool = false,
        resetConfirming: Bool = false,
        versionText: String? = nil,
        editingTarget: PanelEditingTarget? = nil
    ) -> PanelElementsBuilder.Inputs {
        .init(
            projects: [project], breakItem: breakItem, state: state,
            selectedIndex: selectedIndex, hoveredId: hoveredId,
            isVersionVisible: isVersionVisible, resetConfirming: resetConfirming,
            versionText: versionText, editingTarget: editingTarget, ui: ui)
    }

    private func containsText(_ text: String, in elements: [PanelElement]) -> Bool {
        elements.contains { element in
            guard case .text(_, let value, _, _, _, _) = element else { return false }
            return value == text
        }
    }
}
