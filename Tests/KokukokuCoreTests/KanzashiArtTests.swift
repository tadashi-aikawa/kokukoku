import Foundation
import Testing

@testable import KokukokuCore

@Suite("KanzashiArt")
struct KanzashiArtTests {
    @Test("押しピンの記号として、姿は常に30度傾いた一本軸で固定する")
    func tiltIsSymbolNotState() {
        let off = KanzashiArt.svg(pinned: false)
        let on = KanzashiArt.svg(pinned: true)

        // 傾きは状態ではなく記号。onでもoffでも同じ角度で、姿は動かさない
        #expect(off.contains("rotate(30.00"))
        #expect(on.contains("rotate(30.00"))
    }

    @Test("実物の構造をなぞる: 上端の小玉・途中の大玉・尖る軸")
    func structure() {
        let svg = KanzashiArt.svg(pinned: true)
        // 玉は2つ(上端の小玉と途中の大玉)
        #expect(svg.components(separatedBy: "<circle").count - 1 == 2)
        // pathは2つ(軸と巻き模様)
        #expect(svg.components(separatedBy: "<path").count - 1 == 2)
        // 小玉は大玉より小さく、両者の間には軸が見える(くっつけると団子2つに見える)
        #expect(KanzashiArt.capRadius < KanzashiArt.beadRadius)
        let gap = (KanzashiArt.beadCenterY - KanzashiArt.beadRadius)
            - (KanzashiArt.shaftTopY + KanzashiArt.capRadius)
        #expect(gap > 1.0)
        // 軸は大玉より下へ伸びて尖る
        #expect(KanzashiArt.shaftTipY > KanzashiArt.beadCenterY + KanzashiArt.beadRadius)
    }

    @Test("留めているかは紅と燻しの色だけで分ける")
    func stateIsColorOnly() {
        let colors = PanelLayout.Colors.self
        let off = KanzashiArt.svg(pinned: false)
        let on = KanzashiArt.svg(pinned: true)

        #expect(on.contains(colors.kanzashiBeni.hexString))
        #expect(on.contains(colors.kanzashiKin.hexString))
        #expect(on.contains(colors.kanzashiBekko.hexString))
        #expect(!off.contains(colors.kanzashiBeni.hexString))
        #expect(!off.contains(colors.kanzashiKin.hexString))
        #expect(off.contains(colors.kanzashiIbushi.hexString))
    }

    @Test("offでも小玉と巻き模様は形として残す(消すと簪の構造が読めない)")
    func offKeepsStructure() {
        let off = KanzashiArt.svg(pinned: false)
        #expect(off.contains(PanelLayout.Colors.kanzashiIbushiShade.hexString))
        #expect(off.components(separatedBy: "<circle").count - 1 == 2)
        #expect(off.components(separatedBy: "<path").count - 1 == 2)
    }

    @Test("キャンバスは回転後の外接を包み、簪が切れない")
    func canvasCoversRotatedBounds() {
        let radians = KanzashiArt.tiltDegrees * Double.pi / 180
        let boundsW =
            KanzashiArt.bodyW * cos(radians) + KanzashiArt.bodyH * sin(radians)
        let boundsH =
            KanzashiArt.bodyW * sin(radians) + KanzashiArt.bodyH * cos(radians)
        #expect(KanzashiArt.canvasW >= boundsW)
        #expect(KanzashiArt.canvasH >= boundsH)
    }

    @Test("キャッシュキーは状態の2通りしかない")
    func cacheKeys() {
        #expect(KanzashiArt.cacheKey(pinned: false) == "kanzashi:off")
        #expect(KanzashiArt.cacheKey(pinned: true) == "kanzashi:on")
    }
}
