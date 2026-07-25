import Foundation
import Testing

@testable import KokukokuCore

@Suite("ClockArt")
struct ClockArtTests {
    /// 座標比較。三角関数の丸め差を吸収する
    private func expectNear(
        _ actual: PanelPoint, _ expected: PanelPoint,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.x - expected.x) < 0.001, sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < 0.001, sourceLocation: sourceLocation)
    }

    @Test("12時=真上・3時=右・6時=真下・9時=左(isFlippedのy下向き座標)")
    func pointDirections() {
        let c = ClockArt.center
        expectNear(ClockArt.point(fraction: 0, length: 10), .init(x: c, y: c - 10))
        expectNear(ClockArt.point(fraction: 0.25, length: 10), .init(x: c + 10, y: c))
        expectNear(ClockArt.point(fraction: 0.5, length: 10), .init(x: c, y: c + 10))
        expectNear(ClockArt.point(fraction: 0.75, length: 10), .init(x: c - 10, y: c))
    }

    @Test("時針は分に応じて連続的に進み、分針は秒で滑らせず分で刻む")
    func handFractions() {
        // 9時30分の時針は9時と10時の中間
        #expect(ClockArt.hourFraction(hour: 9, minute: 30) == 9.5 / 12)
        #expect(ClockArt.hourFraction(hour: 21, minute: 30) == 9.5 / 12)
        #expect(ClockArt.minuteFraction(minute: 30) == 0.5)
    }

    @Test("秒の日輪は文字盤中心からのオフセットで、60秒で一周する")
    func sunOrbit() {
        let orbit = ClockArt.dialRadius * 0.62
        expectNear(ClockArt.sunOffset(second: 0), .init(x: 0, y: -orbit))
        expectNear(ClockArt.sunOffset(second: 15), .init(x: orbit, y: 0))
        expectNear(ClockArt.sunOffset(second: 30), .init(x: 0, y: orbit))
        expectNear(ClockArt.sunOffset(second: 45), .init(x: -orbit, y: 0))
        // 60秒は0秒と同じ位置に戻る(閏秒でsecond=60が来ても破綻しない)
        expectNear(ClockArt.sunOffset(second: 60), ClockArt.sunOffset(second: 0))
    }

    @Test("円相は閉じた輪ではなく、書き始めと書き終わりの間に隙間が残る")
    func ensoIsNotAClosedRing() {
        let svg = ClockArt.dialSVG()
        // 円は<circle>ではなく弧の連なりで描く(太さを途中で変えるため)
        #expect(svg.contains("<path"))
        let arcs = svg.components(separatedBy: "<path").count - 1
        #expect(arcs == 9)

        // 弧の端点が12時の真上に達していない = 隙間が空いている
        let top = ClockArt.point(fraction: 0, length: ClockArt.dialRadius)
        #expect(!svg.contains("M\(ClockArt.f(top.x)) \(ClockArt.f(top.y))"))
    }

    @Test("筆圧のプロファイルで円相の太さが場所により変わる")
    func ensoStrokeWidthVaries() {
        let svg = ClockArt.dialSVG()
        let widths = Set(
            svg.components(separatedBy: "stroke-width=\"").dropFirst()
                .map { $0.prefix(while: { $0 != "\"" }) })
        // 目盛の太さを除いても複数種類ある(一定の太さで引いた輪ではない)
        #expect(widths.count > 3)
    }

    @Test("和紙の丸窓に墨で描く(明暗はロゴのまま。デジタル表示と明度を揃えるため)")
    func inkOnPaper() {
        let svg = ClockArt.dialSVG()

        #expect(svg.contains("fill=\"\(PanelLayout.Colors.clockWashi.hexString)\""))
        #expect(svg.contains("stroke=\"\(PanelLayout.Colors.clockSumi.hexString)\""))
        // 生成り(パネル本文の色)では描かない
        #expect(!svg.contains(PanelLayout.Colors.text.hexString))
    }

    @Test("盤に乗る「点」は秒の日輪だけ。ロゴの金の点は置かない")
    func noDotsOnDial() {
        let svg = ClockArt.dialSVG()

        // 文字盤の円(和紙)以外にcircleは無い。目盛は線なので日輪と形が違い、混同しない
        #expect(svg.components(separatedBy: "<circle").count - 1 == 1)
        #expect(svg.components(separatedBy: "<line").count - 1 == 4)
    }

    @Test("針は二本だけ。秒針は持たず、日輪が秒を受け持つ")
    func twoHandsOnly() {
        let svg = ClockArt.handsSVG(hour: 9, minute: 30)
        #expect(svg.components(separatedBy: "<path").count - 1 == 2)
        #expect(!svg.contains(PanelLayout.Colors.clockSecondHand.hexString))
    }

    @Test("針の絵は分ごとにしか変わらない")
    func handsChangePerMinute() {
        let at30 = ClockArt.handsSVG(hour: 9, minute: 30)
        #expect(at30 == ClockArt.handsSVG(hour: 9, minute: 30))
        #expect(at30 != ClockArt.handsSVG(hour: 9, minute: 31))
        #expect(at30 != ClockArt.handsSVG(hour: 10, minute: 30))
    }

    @Test("針のキャッシュキーは12時間周期(0時と12時は同じ絵)")
    func handsCacheKeyIsTwelveHourCycle() {
        #expect(ClockArt.handsCacheKey(hour: 0, minute: 30)
            == ClockArt.handsCacheKey(hour: 12, minute: 30))
        #expect(ClockArt.handsCacheKey(hour: 9, minute: 30) == "clock-hands:9:30")
        #expect(ClockArt.handsCacheKey(hour: 21, minute: 30) == "clock-hands:9:30")
        #expect(ClockArt.handsCacheKey(hour: 9, minute: 30)
            != ClockArt.handsCacheKey(hour: 9, minute: 31))
    }

    @Test("組み立てたSVGはXMLとして妥当(座標や属性の綴りが壊れていない)")
    func svgIsWellFormedXML() {
        var sources = [ClockArt.dialSVG()]
        // 針の角度は時刻で変わるため、代表時刻をひと通り舐める
        for hour in [0, 3, 9, 12, 23] {
            for minute in [0, 7, 30, 59] {
                sources.append(ClockArt.handsSVG(hour: hour, minute: minute))
            }
        }
        for svg in sources {
            #expect(XMLParser(data: Data(svg.utf8)).parse(), "XMLとして読めない: \(svg)")
        }
    }

    @Test("針も文字盤も円相の太さぶんを含めてキャンバスに収まる")
    func artFitsInCanvas() {
        // 円相の中心線半径+太さの半分が、はみ出さずキャンバスの内側に収まる
        let outermost = ClockArt.dialRadius + ClockArt.ensoWidth * 1.30 / 2
        #expect(outermost <= ClockArt.canvas / 2)
        // 針は文字盤の内側で収まる
        #expect(ClockArt.dialRadius * ClockArt.minuteHandLength < ClockArt.dialRadius)
    }
}
