import Foundation
import Testing

@testable import KokukokuCore

@Suite("SorobanArt")
struct SorobanArtTests {
    @Test("道具の実比率で横長にする(正方形では実寸で格子の塊に見える)")
    func aspectRatio() {
        #expect(SorobanArt.canvasW > SorobanArt.canvasH)
        #expect(SorobanArt.canvasW / SorobanArt.canvasH > 1.5)
    }

    @Test("珠は梁から離れた「零」の位置に置く")
    func beadsAreClearedFromBeam() {
        // 上珠は梁より上、下珠は梁より下。どちらも梁に接していない
        #expect(SorobanArt.upperBeadY + SorobanArt.beadHalfH < SorobanArt.beamY)
        #expect(SorobanArt.lowerBeadY - SorobanArt.beadHalfH > SorobanArt.beamY)
        // 枠の内側に収まる
        #expect(SorobanArt.upperBeadY - SorobanArt.beadHalfH > SorobanArt.frameInset)
        #expect(
            SorobanArt.lowerBeadY + SorobanArt.beadHalfH < SorobanArt.canvasH
                - SorobanArt.frameInset)
    }

    @Test("桁は3本。各桁に上珠と下珠を1つずつ描く")
    func rodsAndBeads() {
        let svg = SorobanArt.svg(color: PanelLayout.Colors.subText)
        #expect(SorobanArt.rodXs.count == 3)
        // 珠は菱形のpath。3桁 × 上下2つ
        #expect(svg.components(separatedBy: "<path").count - 1 == 6)
    }

    @Test("色ごとにキャッシュを分ける(通常・ホバー・確認で色が変わる)")
    func cacheKeyVariesByColor() {
        let colors = PanelLayout.Colors.self
        #expect(
            SorobanArt.cacheKey(color: colors.subText)
                != SorobanArt.cacheKey(color: colors.text))
        #expect(SorobanArt.svg(color: colors.text).contains(colors.text.hexString))
    }
}
