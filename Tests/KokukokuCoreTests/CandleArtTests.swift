import Foundation
import Testing

@testable import KokukokuCore

@Suite("CandleArt")
struct CandleArtTests {
    @Test("残量は最大閾値までの線形で、超過後は0(燃え尽き)に張り付く")
    func remainIsLinearToLastThreshold() {
        func remain(_ elapsed: Int, _ thresholds: [Int]) -> Double? {
            CandleArt.state(
                continuousElapsed: elapsed, thresholds: thresholds, isRunning: true)?.remain
        }

        #expect(remain(0, [3_600]) == 1)
        #expect(remain(1_800, [3_600]) == 0.5)
        // 複数閾値でも基準は最大閾値だけ(中間閾値は通知が受け持つ)
        #expect(remain(2_700, [1_800, 3_600]) == 0.25)
        #expect(remain(3_600, [3_600]) == 0)
        #expect(remain(10_000, [3_600]) == 0)
    }

    @Test("丈は分単位に量子化する(秒で刻んでも見た目が変わらず作り直しが無駄になるため)")
    func remainIsQuantizedToMinutes() {
        func remain(_ elapsed: Int) -> Double? {
            CandleArt.state(
                continuousElapsed: elapsed, thresholds: [3_600], isRunning: true)?.remain
        }

        // 同じ「1分台」の間は同じ丈
        #expect(remain(60) == remain(119))
        #expect(remain(60) != remain(120))
    }

    @Test("閾値が分の倍数でなくても、超過した時点で必ず燃え尽きる")
    func burnsOutOnOddThresholds() {
        func remain(_ elapsed: Int, _ threshold: Int) -> Double? {
            CandleArt.state(
                continuousElapsed: elapsed, thresholds: [threshold], isRunning: true)?.remain
        }

        // 分に丸めた値だけで割ると0へ届かず、超過しても火が残ってしまう
        #expect(remain(89, 90) != 0)
        #expect(remain(90, 90) == 0)
        #expect(remain(30, 30) == 0)
        // 閾値が1分未満でも、その手前は満丈のまま(丈の刻みが分より細かくならないため)
        #expect(remain(9, 10) == 1)
        #expect(remain(10, 10) == 0)
    }

    @Test("閾値が無ければ蝋燭ごと出さない(ゲージ時代の非表示条件を引き継ぐ)")
    func noThresholdsMeansNoCandle() {
        #expect(
            CandleArt.state(continuousElapsed: 100, thresholds: [], isRunning: true) == nil)
        #expect(
            CandleArt.state(continuousElapsed: 100, thresholds: [0], isRunning: true) == nil)
    }

    @Test("休憩中は満丈のまま消灯する。次に点ける新品の蝋燭が立っている状態")
    func restingCandleIsFullAndUnlit() {
        let resting = CandleArt.state(
            continuousElapsed: 3_000, thresholds: [3_600], isRunning: false)

        #expect(resting == .init(remain: 1, lit: false))
        #expect(resting?.isBurntOut == false)
        // 消灯中は炎が無い
        #expect(CandleArt.flameSVG(.init(remain: 1, lit: false)) == nil)
    }

    @Test("燃え尽きは計測中に残量0となった状態だけを指す")
    func burntOutOnlyWhileLit() {
        #expect(CandleArt.State(remain: 0, lit: true).isBurntOut)
        #expect(!CandleArt.State(remain: 0, lit: false).isBurntOut)
        #expect(!CandleArt.State(remain: 0.1, lit: true).isBurntOut)
        // 燃え尽きた後は炎ではなく熾火と煙が語るため、炎は消える
        #expect(CandleArt.flameSVG(.init(remain: 0, lit: true)) == nil)
    }

    @Test("炎の色は点けたての橙金から燃え尽き際の朱へ倒れる")
    func flameColorFadesToVermilion() {
        #expect(CandleArt.flameColor(remain: 1) == PanelLayout.Colors.candleFlameFresh)
        #expect(CandleArt.flameColor(remain: 0) == PanelLayout.Colors.candleFlameSpent)
        // 終盤で一気に朱へ寄せるため、中間では朱側へまだ寄り切らない
        let mid = CandleArt.flameColor(remain: 0.5)
        #expect(mid.red > PanelLayout.Colors.candleFlameSpent.red)
        #expect(mid.green > PanelLayout.Colors.candleFlameSpent.green)
    }

    @Test("蝋燭の丈は残量に比例して縮み、燃え尽きると蝋が消える")
    func waxHeightShrinks() {
        #expect(CandleArt.waxHeight(remain: 1) == CandleArt.fullWaxHeight)
        #expect(CandleArt.waxHeight(remain: 0.5) == CandleArt.fullWaxHeight / 2)
        #expect(CandleArt.waxHeight(remain: 0) == 0)
        // 消える寸前でも芯を支える最低限の丈は残す(1pxの線に潰れないように)
        #expect(CandleArt.waxHeight(remain: 0.01) == 5)
    }

    @Test("本体SVGは常に描かれ、燃え尽きると熾火に変わる")
    func bodySVGSwitchesToEmber() {
        let burning = CandleArt.bodySVG(.init(remain: 0.5, lit: true))
        let burntOut = CandleArt.bodySVG(.init(remain: 0, lit: true))
        let ember = PanelLayout.Colors.candleEmber.hexString

        #expect(burning.hasPrefix("<svg") && burning.hasSuffix("</svg>"))
        #expect(burntOut.hasPrefix("<svg") && burntOut.hasSuffix("</svg>"))
        // 燃え尽き時だけ熾火の朱が現れる(超過を静けさで語らせないため)
        #expect(!burning.contains(ember))
        #expect(burntOut.contains(ember))
    }

    @Test("煙は燃え尽きた後だけ立ち、蝋だまりの上から伸びる")
    func smokeOnlyAfterBurnOut() {
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let burntOut = CandleArt.State(remain: 0, lit: true)

        // 燃えている間・消灯中は煙が無い
        #expect(CandleArt.smokeSVG(.init(remain: 0.5, lit: true)) == nil)
        #expect(CandleArt.smokeSVG(.init(remain: 1, lit: false)) == nil)
        #expect(CandleArt.smokeBox(.init(remain: 0.5, lit: true), in: frame) == nil)

        let svg = try? #require(CandleArt.smokeSVG(burntOut))
        #expect(svg?.contains(PanelLayout.Colors.candleSmoke.hexString) == true)

        let box = CandleArt.smokeBox(burntOut, in: frame)
        #expect(box != nil)
        // 横は蝋燭の中心に揃い、縦は枠の上側へ伸びる(立ち上る余地を取る)
        #expect(box!.x + box!.w / 2 == frame.x + frame.w / 2)
        #expect(box!.y < frame.y + frame.h / 2)
    }

    @Test("溶けたたれは燃えるほど増える")
    func dripsGrowWithBurn() {
        func dripCount(_ remain: Double) -> Int {
            CandleArt.bodySVG(.init(remain: remain, lit: true))
                .components(separatedBy: PanelLayout.Colors.candleWaxShade.hexString).count - 1
        }

        // 台の影にも同じ色を使うため、増分だけを見る
        #expect(dripCount(1) < dripCount(0.5))
        #expect(dripCount(0.5) < dripCount(0.2))
    }

    @Test("どの残量でも蝋燭の描画がキャンバスをはみ出さない")
    func bodyStaysWithinCanvas() {
        // 溶けたたれが丈より長くなると台を突き抜け、下端で不自然に切れる
        for step in 0...20 {
            let remain = Double(step) / 20
            for lit in [true, false] {
                let svg = CandleArt.bodySVG(.init(remain: remain, lit: lit))
                // 座標以外の数値を落としてから拾う: 名前空間URL(…/2000/svg)・
                // 色コード(#DA5932)・フィルタ領域の百分率(260%)が紛れ込むため
                let coordinatesOnly = svg
                    .replacingOccurrences(
                        of: "xmlns=\"[^\"]*\"", with: "", options: .regularExpression)
                    .replacingOccurrences(
                        of: "#[0-9A-Fa-f]{6}", with: "", options: .regularExpression)
                    .replacingOccurrences(
                        of: "-?[0-9.]+%", with: "", options: .regularExpression)
                let numbers = coordinatesOnly
                    .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
                    .compactMap(Double.init)
                let maxValue = numbers.max() ?? 0
                #expect(
                    maxValue <= CandleArt.canvas,
                    "remain=\(remain) lit=\(lit) で \(maxValue) がキャンバス外へ出た")
            }
        }
    }

    @Test("炎の枠は蝋の上端に乗り、蝋が短くなるほど下がる")
    func flameBoxFollowsWaxTop() {
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let fresh = CandleArt.flameBox(.init(remain: 1, lit: true), in: frame)
        let spent = CandleArt.flameBox(.init(remain: 0.2, lit: true), in: frame)

        #expect(fresh != nil)
        #expect(spent != nil)
        // 蝋が減れば炎も下がる(枠の中で沈んでいく)
        #expect(fresh!.y < spent!.y)
        // 横位置は蝋燭の中心に揃う
        #expect(fresh!.x + fresh!.w / 2 == frame.x + frame.w / 2)
        #expect(spent!.x + spent!.w / 2 == frame.x + frame.w / 2)
        // 炎が無い状態では枠も無い
        #expect(CandleArt.flameBox(.init(remain: 1, lit: false), in: frame) == nil)
        #expect(CandleArt.flameBox(.init(remain: 0, lit: true), in: frame) == nil)
    }

    @Test("キャッシュキーは残量と点灯状態で決まる")
    func cacheKeyIdentifiesLook() {
        #expect(CandleArt.State(remain: 1, lit: true).cacheKey == "candle:1000:1")
        #expect(CandleArt.State(remain: 0.5, lit: true).cacheKey == "candle:500:1")
        #expect(CandleArt.State(remain: 1, lit: false).cacheKey == "candle:1000:0")
        #expect(CandleArt.State(remain: 0, lit: true).cacheKey == "candle:0:1")
    }

    @Test("色はSVGへ埋め込める#RRGGBBへ変換される")
    func hexString() {
        #expect(PanelColor(red: 0, green: 0, blue: 0, alpha: 1).hexString == "#000000")
        #expect(PanelColor(red: 1, green: 1, blue: 1, alpha: 1).hexString == "#FFFFFF")
        #expect(
            PanelColor(red: 0.855, green: 0.349, blue: 0.196, alpha: 1).hexString == "#DA5932")
        // 範囲外は端に丸める
        #expect(PanelColor(red: -1, green: 2, blue: 0.5, alpha: 1).hexString == "#00FF80")
    }
}
