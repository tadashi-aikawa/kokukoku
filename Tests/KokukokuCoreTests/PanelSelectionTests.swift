import Testing

@testable import KokukokuCore

@Suite("PanelSelection")
struct PanelSelectionTests {
    @Test("次のプロジェクトへ移動して折り返す")
    func next() {
        #expect(PanelSelection.nextIndex(current: nil, projectCount: 3) == 1)
        #expect(PanelSelection.nextIndex(current: 1, projectCount: 3) == 2)
        #expect(PanelSelection.nextIndex(current: 3, projectCount: 3) == 1)
        #expect(PanelSelection.nextIndex(current: 4, projectCount: 3) == 1)
    }

    @Test("前のプロジェクトへ移動して折り返す")
    func previous() {
        #expect(PanelSelection.previousIndex(current: nil, projectCount: 3) == 3)
        #expect(PanelSelection.previousIndex(current: 3, projectCount: 3) == 2)
        #expect(PanelSelection.previousIndex(current: 1, projectCount: 3) == 3)
    }
}
