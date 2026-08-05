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

    @Test("吹き消しの煙は真新しい蝋燭の芯先から上へ立つ")
    func blowOutWispRisesFromWickTip() {
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let box = CandleArt.blowOutWispBox(remain: 1, in: frame)

        // 横は蝋燭の中心に揃う
        #expect(box.x + box.w / 2 == frame.x + frame.w / 2)
        // 根本は枠の上寄り(満丈の芯先)、先は枠の上端を突き抜ける(燃え尽きの煙と同じ理屈)
        #expect(box.y + box.h < frame.y + frame.h / 2)
        #expect(box.y < frame.y)

        let svg = CandleArt.blowOutWispSVG()
        #expect(svg.hasPrefix("<svg") && svg.hasSuffix("</svg>"))
        #expect(svg.contains(PanelLayout.Colors.candleSmoke.hexString))
        #expect(
            svg.contains(
                "viewBox=\"0 0 \(CandleArt.blowOutWispWidth) \(CandleArt.blowOutWispHeight)\""))
    }

    @Test("煙は蝋燭の枠を越えて上へ突き抜ける(枠内では小さすぎて気づけない)")
    func smokeOutgrowsCandleFrame() {
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let box = try? #require(CandleArt.smokeBox(burntOut, in: frame))

        // 蝋燭の枠の2倍強の高さ。枠の縮尺に縛られていたのが地味さの正体だった
        #expect(box!.h > frame.h * 2)
        // 幅は細い一筋の儚さを残すため蝋燭より狭い
        #expect(box!.w < frame.w)
        // 根本は蝋だまり(枠の下寄り)、先は枠の上端より上
        #expect(box!.y + box!.h > frame.y + frame.h * 0.7)
        #expect(box!.y < frame.y)
    }

    @Test("煙の絵の余りは見える範囲の下に置き、上へ流す(逆だと流れた先で根本が空く)")
    func smokeArtHasSpareBelow() {
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let box = try! #require(CandleArt.smokeBox(burntOut, in: frame))
        let scroll = CandleArt.smokeScroll

        // 上へ1周期ぶん動かしても下端が空かないだけの余りを持つ
        #expect(
            scroll.artHeight
                == box.h + CandleArt.smokeScrollPeriod + CandleArt.smokeArtFootroom)
        // 絵は枠の上端に揃える。余りが出るのは枠の**下**側
        #expect(scroll.artTopOffset == 0)
        let spareBelow = scroll.artTopOffset + scroll.artHeight - box.h
        #expect(spareBelow > 0)
        // 進む向きは上(負)。流す距離はくねり1周期そのもの:
        // ここがずれるとループの継ぎ目で絵が飛ぶ
        #expect(scroll.translation < 0)
        #expect(abs(scroll.translation) == CandleArt.smokeScrollPeriod)
        #expect(abs(scroll.translation) <= spareBelow)

        // 絵の座標系は見える範囲ではなく絵の全長
        let svg = try! #require(CandleArt.smokeSVG(burntOut))
        #expect(svg.contains("viewBox=\"0 0 \(CandleArt.smokeWidth) \(scroll.artHeight)\""))
    }

    private struct TracedPath {
        /// 曲線の通過点(各コマンドの終点)
        var anchors: [(x: Double, y: Double)] = []
        /// 通過点＋制御点。はみ出し判定に使う(ベジェは制御点に届かないので安全側)
        var all: [(x: Double, y: Double)] = []
    }

    /// 相対コマンド(q)で書かれたパスを辿る。数値の最大値を見るだけでは
    /// 縦横の区別も相対座標の累積もできず、はみ出しの防波堤にならないため
    private func trace(in svg: String) -> [TracedPath] {
        svg.components(separatedBy: "d=\"").dropFirst().compactMap { chunk in
            guard let d = chunk.components(separatedBy: "\"").first else { return nil }
            let numbers = d.split(whereSeparator: { " \n".contains($0) })
                .compactMap {
                    Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "MqCLZz")))
                }
            guard numbers.count >= 2 else { return nil }
            var path = TracedPath()
            var x = numbers[0], y = numbers[1]
            path.anchors.append((x, y))
            path.all.append((x, y))
            var i = 2
            while i + 3 < numbers.count {
                path.all.append((x + numbers[i], y + numbers[i + 1]))
                x += numbers[i + 2]
                y += numbers[i + 3]
                path.anchors.append((x, y))
                path.all.append((x, y))
                i += 4
            }
            return path
        }
    }

    private func pathBounds(in svg: String)
        -> (minX: Double, maxX: Double, minY: Double, maxY: Double)?
    {
        let points = trace(in: svg).flatMap(\.all)
        guard !points.isEmpty else { return nil }
        return (
            points.map(\.x).min()!, points.map(\.x).max()!,
            points.map(\.y).min()!, points.map(\.y).max()!
        )
    }

    @Test("くねりは1周期ごとに同じ位相へ戻る(ループの継ぎ目が合う条件)")
    func smokeWiggleRepeatsPerPeriod() {
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let svg = try! #require(CandleArt.smokeSVG(burntOut))
        let period = CandleArt.smokeScrollPeriod
        let paths = trace(in: svg)
        #expect(paths.count >= 2)  // 主筋と副筋

        // 1周期ぶん上がった点では横位置が根本と一致していること。
        // 太さや振れ幅を変えるときに周期を崩すと、ここで落ちる
        for path in paths {
            let start = try! #require(path.anchors.first)
            for step in 1...2 {
                let target = start.y - period * Double(step)
                let point = path.anchors.first { abs($0.y - target) < 0.001 }
                #expect(point != nil, "y=\(target) を通過していない")
                #expect(abs((point?.x ?? .infinity) - start.x) < 0.001)
            }
        }
    }

    @Test("煙の描画は絵の枠の中に収まり、なお流し切った先まで根本を供給できる")
    func smokeDrawingStaysInsideArt() {
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let box = try! #require(CandleArt.smokeBox(burntOut, in: frame))
        let svg = try! #require(CandleArt.smokeSVG(burntOut))
        let bounds = try! #require(pathBounds(in: svg))
        // 線の太さとぼかしの裾(3σ)の分だけ内側に収まっていること
        let margin = CandleArt.smokeArtFootroom

        #expect(bounds.minX - margin >= 0)
        #expect(bounds.maxX + margin <= CandleArt.smokeWidth)
        // 上端は絵の外へ出てよい(マスクで消える)。下端は裾ごと絵に収まっていること
        #expect(bounds.maxY + margin <= CandleArt.smokeArtHeight)
        // かつ筋の根本は、1周期ぶん流し切ったときの枠の下端まで届いていること。
        // 裾の余白を稼ぐために根本を内側へ寄せすぎると、ここで根本が空く
        let scroll = CandleArt.smokeScroll
        #expect(bounds.maxY >= box.h + abs(scroll.translation))
    }

    @Test("煙の濃淡は絵に焼かずマスクで作る(焼くと根本の濃さが流れて煙が絶える)")
    func smokeShadingLivesInMask() {
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let svg = try! #require(CandleArt.smokeSVG(burntOut))

        // 絵にグラデーションを持たせると、絵と一緒に濃淡が流れて
        // 「先端から煙が出ていない瞬間」ができてしまう
        #expect(!svg.contains("linearGradient"))

        // 濃淡はマスク側の停止点が持つ。根本(0)から先端(1)へ向かって薄れる
        let stops = CandleArt.smokeMaskStops
        #expect(stops.first?.location == 0)
        #expect(stops.last?.location == 1)
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
        // 両端は透かす。下端を不透明にするとマスクの縁で煙が切れて断面が出る
        #expect(stops.first?.opacity == 0)
        #expect(stops.last?.opacity == 0)
        // いちばん濃いのは根本寄り(先端へ向かって単調に薄れる)
        let peak = try! #require(stops.max(by: { $0.opacity < $1.opacity }))
        #expect(peak.location < 0.2)
        let afterPeak = stops.filter { $0.location > peak.location }
        #expect(afterPeak.map(\.opacity) == afterPeak.map(\.opacity).sorted(by: >))
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

    /// SVG文字列から描画座標の数値だけを拾う。座標以外の数値を先に落とす:
    /// svg開始タグ(名前空間URL・width・height・viewBoxの枠寸法そのもの)・
    /// 色コード(#DA5932)・フィルタ領域の百分率(260%)が紛れ込むため
    private func coordinates(in svg: String) -> [Double] {
        svg
            .replacingOccurrences(
                of: "<svg[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "#[0-9A-Fa-f]{6}", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "-?[0-9.]+%", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
            .compactMap(Double.init)
    }

    @Test("どの残量でも蝋燭の描画がキャンバスをはみ出さない")
    func bodyStaysWithinCanvas() {
        // 溶けたたれが丈より長くなると台を突き抜け、下端で不自然に切れる
        for step in 0...20 {
            let remain = Double(step) / 20
            for lit in [true, false] {
                let svg = CandleArt.bodySVG(.init(remain: remain, lit: lit))
                let maxValue = coordinates(in: svg).max() ?? 0
                #expect(
                    maxValue <= CandleArt.canvas,
                    "remain=\(remain) lit=\(lit) で \(maxValue) がキャンバス外へ出た")
            }
        }
    }

    @Test("煙の根本は蝋だまりへ沈めて、マスクの縁が切れて見えないようにする")
    func smokeRootSinksIntoWaxPool() {
        let burntOut = CandleArt.State(remain: 0, lit: true)
        let frame = PanelFrame(x: 100, y: 200, w: 38, h: 38)
        let box = try! #require(CandleArt.smokeBox(burntOut, in: frame))

        // 枠の下端(マスクが煙を切る縁)は、蝋だまりの位置より下に潜っている
        let scale = min(frame.w, frame.h) / CandleArt.canvas
        let waxPool = frame.y + (CandleArt.baseY - CandleArt.smokeRootInset) * scale
        #expect(box.y + box.h > waxPool)
        #expect(box.y + box.h - waxPool == CandleArt.smokeRootSink)

        // 細い筋とぼかしが左右へはみ出さない(はみ出すと縦の縁で切れる)
        let svg = try! #require(CandleArt.smokeSVG(burntOut))
        #expect(svg.contains("stroke-width=\"\(CandleArt.smokeStrokeWidth)\""))
        #expect(svg.contains("stdDeviation=\"\(CandleArt.smokeBlur)\""))
        let margin = CandleArt.smokeStrokeWidth / 2 + CandleArt.smokeBlur * 3
        // くねりの振れ幅(±4pt)と副筋のずれ(+2.5pt)を足した最も外側
        #expect(CandleArt.smokeWidth / 2 - (4 + 2.5) > margin)
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
