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

    @Test("実物の構造をなぞる: 上端の小玉・途中の大玉・奥へ入る軸")
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
        // 軸は大玉より下へ伸びてから面に入る(玉の直下で断つと団子2つに見える)
        #expect(KanzashiArt.shaftSunkY > KanzashiArt.beadCenterY + KanzashiArt.beadRadius)
    }

    @Test("軸は先端を尖らせず、面に入る位置で薄墨へ溶かす(刺さっている手がかり)")
    func shaftSinksIntoSurface() {
        for pinned in [true, false] {
            let svg = KanzashiArt.svg(pinned: pinned)
            // 奥行きは陰影ではなく濃淡で作る(和の遠近。玉のハイライトは実寸で点に読まれる)
            #expect(svg.contains("linearGradient"))
            #expect(svg.contains("fill=\"url(#kanzashi-shaft)\""))
            // 断つ位置で透明になり、刺し口を描かずに貫通を語る
            #expect(svg.contains("stop-opacity=\"0\""))
            #expect(svg.contains("y2=\"\(KanzashiArt.f(KanzashiArt.shaftSunkY))\""))
        }
        // 溶けるのは軸の下側だけ。根元まで霞ませると軸全体が「弱った線」に見える
        #expect(KanzashiArt.shaftFadeStartY > KanzashiArt.shaftTopY)
        #expect(KanzashiArt.shaftFadeStartY < KanzashiArt.shaftSunkY)
    }

    @Test("玉は実物寄りに小さくしても、軸が全長だった頃より大きく見える")
    func beadReadableSize() {
        // 玉の径は「外接の高さに対する比 × 枠」で決まる。軸が全長(canvasH=55)・枠40だった頃は
        // 7.9pxしかなく実機で控えめすぎた(2026-07-26)。挿した姿では外接が41まで縮むので、
        // 玉そのものを実物寄りに落としても、見た目は旧構図より大きく保てる
        let beadDiameter = KanzashiArt.beadRadius * 2
            * PanelLayout.pinButtonHeight / KanzashiArt.canvasH
        #expect(beadDiameter > 9.0)
    }

    @Test("巻き模様の反りは玉の径に比例させる(固定値だと玉を縮めたとき反りだけ強く残る)")
    func stripeScalesWithBead() {
        let svg = KanzashiArt.svg(pinned: true)
        let endY = KanzashiArt.beadCenterY
            - KanzashiArt.beadRadius * KanzashiArt.stripeEndRiseRatio
        let controlY = KanzashiArt.beadCenterY
            + KanzashiArt.beadRadius * KanzashiArt.stripeControlDropRatio
        #expect(svg.contains("Q13.00 \(KanzashiArt.f(controlY))"))
        // 弧は玉の赤道あたりを巡る(端点が玉の外へ出ると輪郭からはみ出して見える)
        #expect(endY > KanzashiArt.beadCenterY - KanzashiArt.beadRadius)
        #expect(controlY < KanzashiArt.beadCenterY + KanzashiArt.beadRadius)
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
