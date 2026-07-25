import Foundation

/// ヘッダーの現在時刻を語るアナログ時計。
///
/// 元は無国籍な線画時計だったが、和ろうそく(フッター)・墨絵パレットの世界から浮いていた。
/// アナログは「デザイン性・ヘッダのバランス取り」の側面が強い(正確な時刻はデジタルで読む)ため、
/// 意匠として立っているものが世界観から浮いているのは筋が通らない。
/// そこでKOKUKOKUのアプリロゴ(墨絵の円相+和紙の文字盤+筆の二針+金の点+朱の日輪)の語彙で描き直す。
///
/// ロゴのラスター画像を貼らないのは、(1)針が絵に焼き付いていて動かせない
/// (2)56pxでは富士・波・かすれが潰れる ため。
/// 蝋燭と同じくSVG文字列をコードで組み立てるので、アセットを同梱せず色も形も作れる。
///
/// 明暗はロゴのまま和紙の丸窓に倒した。暗い盤に生成りで描く案も実機で見比べたが、
/// デジタル表示と明度が揃う丸窓のほうがヘッダーがひとかたまりに読める(2026-07-25 タダシ判断)。
/// 金の点だけはロゴにあっても置かない。秒を刻む朱の日輪と同じ「点」であり、
/// 盤の上で毎分すれ違って読み分けられなくなるため(目盛は線なので形が違い、混同しない)
public enum ClockArt {
    /// SVGの内部座標。実表示サイズはPanelMetricsが決める。
    /// 円相の太さが外へはみ出すぶん、文字盤の直径より一回り大きく取る
    public static let canvas = 62.0
    static let center = 31.0
    static let dialRadius = 28.0

    // MARK: - 部品の寸法(内部座標)

    /// 円相の基準の太さ。筆圧プロファイルでこの値に倍率がかかる
    static let ensoWidth = 3.8
    /// 12・3・6・9時の目盛
    static let tickWidth = 2.2
    static let tickLength = 4.6
    static let tickInset = 4.5
    /// 針の長さと最大幅(ロゴの実測: 時針0.55R・分針0.83R)
    static let hourHandLength = 0.55
    static let minuteHandLength = 0.83
    static let hourHandWidth = 6.4
    static let minuteHandWidth = 5.0
    /// 針が中心から反対側へ僅かに突き出す長さ(筆の入りを見せる)
    static let handTail = 4.0
    static let hubRadius = 3.0
    /// 秒を刻む日輪
    public static let sunRadius = 3.2
    public static let sunHaloRadius = 6.2
    static let sunOrbit = 0.62

    // MARK: - 角度と座標

    /// 文字盤中心から見た座標。fractionは12時起点で時計回りの一周比(0.0〜1.0)
    static func point(fraction: Double, length: Double) -> PanelPoint {
        let angle = fraction * 2 * Double.pi - Double.pi / 2
        return PanelPoint(
            x: center + length * cos(angle),
            y: center + length * sin(angle))
    }

    /// 秒の日輪の中心。文字盤中心からのオフセットで返す(パネル座標への変換は呼び出し側)
    public static func sunOffset(second: Int) -> PanelPoint {
        let p = point(fraction: Double(second % 60) / 60, length: dialRadius * sunOrbit)
        return PanelPoint(x: p.x - center, y: p.y - center)
    }

    /// 時針の一周比。分に応じて連続的に進む
    public static func hourFraction(hour: Int, minute: Int) -> Double {
        (Double(hour % 12) + Double(minute) / 60) / 12
    }

    /// 分針の一周比。秒針を持たないぶん、分針は秒で滑らせず分で刻む
    /// (盤の上で動くのは日輪だけ、という役割分担を保つ)
    public static func minuteFraction(minute: Int) -> Double {
        Double(minute % 60) / 60
    }

    // MARK: - 描画

    /// 文字盤(和紙の丸窓・円相・目盛)。時刻に依らないのでキャッシュが効き続ける
    public static func dialSVG() -> String {
        let colors = PanelLayout.Colors.self
        let ink = colors.clockSumi.hexString
        var body = """
        <circle cx="\(center)" cy="\(center)" r="\(dialRadius - 1.5)" \
        fill="\(colors.clockWashi.hexString)" opacity="0.92"/>
        """
        body += ensoPath(color: ink, opacity: 1.0)
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let inner = point(fraction: fraction, length: dialRadius - tickInset - tickLength)
            let outer = point(fraction: fraction, length: dialRadius - tickInset)
            body += """
            <line x1="\(f(inner.x))" y1="\(f(inner.y))" x2="\(f(outer.x))" y2="\(f(outer.y))" \
            stroke="\(ink)" stroke-width="\(tickWidth)" stroke-linecap="round"/>
            """
        }
        return svg(body)
    }

    /// 針の絵を一意に決めるキー。文字盤は12時間で一巡するため、0時と12時は同じ絵になる
    /// (24時間ぶんのキーを配ると、同じ絵を二度焼いたうえキャッシュを倍の速さで埋める)
    public static func handsCacheKey(hour: Int, minute: Int) -> String {
        "clock-hands:\(hour % 12):\(minute % 60)"
    }

    /// 針(時針・分針)。文字盤と分けるのは、分ごとにしか変わらない絵を
    /// 毎秒動く日輪のために作り直さずに済ませるため
    public static func handsSVG(hour: Int, minute: Int) -> String {
        let ink = PanelLayout.Colors.clockSumi.hexString
        let body =
            brushHand(
                fraction: hourFraction(hour: hour, minute: minute),
                length: dialRadius * hourHandLength, width: hourHandWidth, color: ink)
            + brushHand(
                fraction: minuteFraction(minute: minute),
                length: dialRadius * minuteHandLength, width: minuteHandWidth, color: ink)
            + """
            <circle cx="\(center)" cy="\(center)" r="\(hubRadius)" fill="\(ink)"/>
            """
        return svg(body)
    }

    /// 一筆書きの円相。SVGは一本のstrokeの太さを途中で変えられないため、
    /// 弧を分割して筆圧プロファイルを近似する。
    /// 入りは細く、すぐ筆圧が乗って太り、中盤は速く細く、抜き際はかすれて薄く消える
    static func ensoPath(color: String, opacity: Double) -> String {
        // (進行度, 太さ倍率, 不透明度倍率)
        let profile: [(Double, Double, Double)] = [
            (0.00, 0.75, 0.80),
            (0.10, 1.30, 1.00),
            (0.32, 0.95, 1.00),
            (0.50, 0.70, 0.90),
            (0.68, 1.05, 0.95),
            (0.85, 0.80, 0.75),
            (1.00, 0.35, 0.35),
        ]
        func sample(_ t: Double) -> (width: Double, opacity: Double) {
            for i in 0..<(profile.count - 1) {
                let (t0, w0, o0) = profile[i]
                let (t1, w1, o1) = profile[i + 1]
                if t >= t0 && t <= t1 {
                    let k = (t - t0) / (t1 - t0)
                    return (w0 + (w1 - w0) * k, o0 + (o1 - o0) * k)
                }
            }
            return (profile[profile.count - 1].1, profile[profile.count - 1].2)
        }
        // 書き始めと書き終わりの間に隙間を残す(閉じない輪が円相)
        let start = 0.035
        let end = 0.965
        let segments = 9
        var out = ""
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            let t1 = Double(i + 1) / Double(segments)
            let s0 = start + (end - start) * t0
            // 継ぎ目が筋になって見えないよう、次の弧と僅かに重ねる
            let s1 = start + (end - start) * t1 + 0.004
            let (widthScale, opacityScale) = sample((t0 + t1) / 2)
            let p0 = point(fraction: s0, length: dialRadius)
            let p1 = point(fraction: s1, length: dialRadius)
            out += """
            <path d="M\(f(p0.x)) \(f(p0.y)) A\(f(dialRadius)) \(f(dialRadius)) 0 0 1 \
            \(f(p1.x)) \(f(p1.y))" fill="none" stroke="\(color)" \
            stroke-width="\(f(ensoWidth * widthScale))" stroke-linecap="round" \
            opacity="\(f(opacity * opacityScale))"/>
            """
        }
        return out
    }

    /// 筆の穂の形をした針。中心の少し手前から立ち上がり、中ほどで最も太く、先は尖る
    static func brushHand(fraction: Double, length: Double, width: Double, color: String)
        -> String
    {
        let angle = fraction * 2 * Double.pi - Double.pi / 2
        let dx = cos(angle)
        let dy = sin(angle)
        // 穂の幅を取る向き(進行方向の法線)
        let nx = -dy
        let ny = dx
        let baseX = center - dx * handTail
        let baseY = center - dy * handTail
        let tipX = center + dx * length
        let tipY = center + dy * length
        func edge(_ t: Double, _ w: Double) -> PanelPoint {
            PanelPoint(
                x: baseX + (tipX - baseX) * t + nx * w,
                y: baseY + (tipY - baseY) * t + ny * w)
        }
        let l0 = edge(0.0, width * 0.16)
        let l1 = edge(0.26, width * 0.50)
        let l2 = edge(0.70, width * 0.26)
        let r2 = edge(0.70, -width * 0.26)
        let r1 = edge(0.26, -width * 0.50)
        let r0 = edge(0.0, -width * 0.16)
        return """
        <path d="M\(f(l0.x)) \(f(l0.y)) C\(f(l1.x)) \(f(l1.y)) \(f(l2.x)) \(f(l2.y)) \
        \(f(tipX)) \(f(tipY)) C\(f(r2.x)) \(f(r2.y)) \(f(r1.x)) \(f(r1.y)) \
        \(f(r0.x)) \(f(r0.y)) Z" fill="\(color)"/>
        """
    }

    /// SVGは小数の桁が増えても見た目に効かないうえ、キャッシュキーと同様に
    /// 文字列比較のテストが読みにくくなるため2桁に丸める
    static func f(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func svg(_ body: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" \
        viewBox="0 0 \(canvas) \(canvas)">\(body)</svg>
        """
    }
}
