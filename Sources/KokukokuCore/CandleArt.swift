import Foundation

/// フッターの連続稼働表示: 溜まるゲージではなく「溶けていく蝋燭」。
///
/// 数字を出さないのは、連続稼働が「そろそろヤバいか否か」しか語らない目安であり、
/// 分単位の値を読む用途が無いため(プロジェクト別の累積時間とは役割が違う)。
/// 溜まる進捗バーは「満ちると嬉しい」記号なのに意味は「満ちたら休め」で逆さまだったが、
/// 減る蝋燭なら記号と意味が一致する。
///
/// macOSのNSImageはSVGを直接読めるため、アセットを同梱せずコード側で丈も色も作れる。
/// SVG文字列の組み立ては純粋な文字列生成なのでこの層に置き、テストを効かせる。
public enum CandleArt {
    /// 蝋燭の見た目を決める状態
    public struct State: Equatable, Sendable {
        /// 残量。1.0(点けたて)→ 0.0(燃え尽き)
        public var remain: Double
        /// 火が点いているか。休憩中は消灯し、真新しい蝋燭が立つ
        public var lit: Bool

        public init(remain: Double, lit: Bool) {
            self.remain = remain
            self.lit = lit
        }

        /// 燃え尽き(最大閾値の超過中)。蝋だまりだけが熾火として残る
        public var isBurntOut: Bool { lit && remain <= 0 }

        /// 絵のキャッシュキー。丈は分単位に量子化済みなので、
        /// 同じ残量・同じ点灯状態なら同じ絵として使い回せる
        public var cacheKey: String {
            "candle:\(Int((remain * 1000).rounded())):\(lit ? 1 : 0)"
        }
    }

    /// SVGの内部座標(viewBox)。実表示サイズはPanelMetrics側が決める
    static let canvas = 96.0
    /// 台の上面(蝋の下端)
    static let baseY = 84.0
    /// 満丈の蝋の高さ
    static let fullWaxHeight = 54.0
    static let centerX = 48.0
    /// 和ろうそくの胴の各部の半幅(上が広く、腰でくびれ、底で少し戻る碇型)
    static let topHalfWidth = 15.0
    static let waistHalfWidth = 10.5
    static let baseHalfWidth = 13.0

    /// 連続稼働の秒数から蝋燭の状態を決める。閾値が無ければnil(蝋燭ごと非表示)。
    ///
    /// 残量は最大閾値までの線形。**分単位に量子化**する: 2時間で数十pxしか縮まないため
    /// 秒で刻んでも見た目は変わらず、SVGの作り直しが無駄に走るだけになる
    public static func state(continuousElapsed: Int, thresholds: [Int], isRunning: Bool)
        -> State?
    {
        guard let last = thresholds.filter({ $0 > 0 }).max() else { return nil }
        guard isRunning else { return State(remain: 1, lit: false) }
        let elapsed = max(0, continuousElapsed)
        // 燃え尽きだけは量子化前の秒で判定する。閾値が分の倍数でないと
        // 分に丸めた値では最後まで0へ届かず、超過しても火が残ってしまう
        guard elapsed < last else { return State(remain: 0, lit: true) }
        let quantized = (elapsed / 60) * 60
        let remain = max(0, 1 - Double(quantized) / Double(last))
        return State(remain: remain, lit: true)
    }

    /// 炎の色: 点けたての明るい橙金から、燃え尽き際の朱へ倒れる。
    /// 実物大では色差が読み取りづらいため、終盤に一気に朱へ寄るよう二乗で効かせる
    public static func flameColor(remain: Double) -> PanelColor {
        let burn = min(max(1 - remain, 0), 1)
        let t = burn * burn
        let from = PanelLayout.Colors.candleFlameFresh
        let to = PanelLayout.Colors.candleFlameSpent
        return PanelColor(
            red: from.red + (to.red - from.red) * t,
            green: from.green + (to.green - from.green) * t,
            blue: from.blue + (to.blue - from.blue) * t,
            alpha: 1)
    }

    /// 蝋の上端(SVG内部座標)。燃え尽き時は台の上面と一致する
    static func waxTop(remain: Double) -> Double {
        baseY - waxHeight(remain: remain)
    }

    /// 芯の上端(SVG内部座標)。和ろうそくは芯が太い。消灯中(休憩中)は長めに残して
    /// 「まだ点けてへん新品」に見せ、点灯中は上端が炭化して短く見える
    static func wickTop(remain: Double, lit: Bool) -> Double {
        waxTop(remain: remain) - (lit ? 6 : 9)
    }

    static func waxHeight(remain: Double) -> Double {
        remain <= 0 ? 0 : max(5, fullWaxHeight * min(remain, 1))
    }

    /// 炎(揺らす部分)を除いた蝋燭本体のSVG。
    /// 台・蝋・溶けたたれ・芯を描き、燃え尽き時は蝋だまりと熾火と煙に変わる。
    ///
    /// waxOpacityは蝋(胴・芯・たれ・蝋だまり)だけに掛ける。台は蝋燭が載る器であって
    /// 燃えも替わりもしないため、蝋燭が滲み出す間も据え置く。
    /// emberOpacityは熾火の朱だけを別に沈められる(火の気だけ先に静める用)
    public static func bodySVG(
        _ state: State, waxOpacity: Double = 1, emberOpacity: Double = 1
    ) -> String {
        let colors = PanelLayout.Colors.self
        let wax = colors.candleWax.hexString
        let shade = colors.candleWaxShade.hexString
        let holder = colors.candleHolder.hexString
        let wick = colors.candleWick.hexString
        let ember = colors.candleEmber.hexString

        let stand = """
        <path d="M30 \(baseY) q18 -9 36 0 z" fill="\(shade)"/>
        <path d="M26 \(baseY + 2) h44" stroke="\(holder)" stroke-width="5" stroke-linecap="round"/>
        """

        if state.isBurntOut {
            // 超過の合図。煙だけでは静まり返ってしまい警告として逆行するため、
            // 蝋だまりに熾火の朱を残す(朱は面で使わず点で置くパレットの掟に従う)
            // 蝋だまりを先に敷き、熾火はその上に重ねる(順序を逆にすると蝋の明るさが朱を覆う)。
            // 蝋だまり自体も沈めた側の色にして、熾火の朱を浮かせる
            // 煙は立ち上らせるためレイヤーへ分けてある(smokeSVG)
            // 熾火(朱と、その芯のハイライト)は蝋だまりと分けて包む。
            // 計測を止めたときは火の気だけ先に静め、蝋だまりは新しい蝋燭が立つまで残す
            let embers = fading(
                """
                <ellipse cx="\(centerX)" cy="\(baseY - 3)" rx="13" ry="6" fill="\(ember)"
                         opacity="0.75" filter="url(#glow)"/>
                <ellipse cx="\(centerX)" cy="\(baseY - 3)" rx="7.5" ry="3" fill="\(ember)"/>
                <ellipse cx="\(centerX)" cy="\(baseY - 3.5)" rx="3.4" ry="1.4" fill="\(wax)"
                         opacity="0.55"/>
                """, emberOpacity)
            return svg(
                defs(blur: 3)
                    + fading(
                        """
                        <path d="M35 \(baseY) q13 -9 26 0 z" fill="\(shade)" opacity="0.95"/>
                        \(embers)
                        """, waxOpacity) + stand)
        }

        let top = waxTop(remain: state.remain)
        let height = waxHeight(remain: state.remain)
        let burn = 1 - state.remain
        // 溶けたたれ。燃えるほど増え、「時間が経った」を丈以外でも語らせる。
        // 胴の最も広い上端の縁から垂らすが、燃え尽き間際は胴自体が短いため
        // 垂らす長さを丈の内側に収める(はみ出すと台を突き抜けて下端で切れる)
        // 垂れ始めの位置も長さも丈に比例させ、短い胴でも本数は保ったまま小さく垂らす
        // (丈で頭打ちにすると燃え尽き間際にたれが消え、「燃えるほど増える」が崩れる)
        var drips = ""
        func drip(startRatio: Double, startMax: Double, lengthMax: Double) -> Double? {
            let start = min(startMax, height * startRatio)
            let length = min(lengthMax, height - start - 2)
            return length > 2 ? length : nil
        }
        if burn > 0.3, let length = drip(startRatio: 0.2, startMax: 5, lengthMax: 13) {
            let start = min(5.0, height * 0.2)
            drips += """
            <path d="M\(centerX - topHalfWidth + 1.5) \(top + start) \
            q-3 \(length * 0.7) 1 \(length) q4 -4 1 -\(length) z" fill="\(shade)" opacity="0.95"/>
            """
        }
        if burn > 0.65, let length = drip(startRatio: 0.35, startMax: 8, lengthMax: 11) {
            let start = min(8.0, height * 0.35)
            drips += """
            <path d="M\(centerX + topHalfWidth - 1.5) \(top + start) \
            q3 \(length * 0.7) -1 \(length) q-4 -4 -1 -\(length) z" fill="\(shade)" opacity="0.85"/>
            """
        }
        let wickTop = Self.wickTop(remain: state.remain, lit: state.lit)
        let defs = """
            <defs>
              <linearGradient id="wax" x1="0" y1="0" x2="1" y2="0">
                <stop offset="0" stop-color="\(shade)"/>
                <stop offset="0.32" stop-color="\(wax)"/>
                <stop offset="1" stop-color="\(shade)"/>
              </linearGradient>
            </defs>
            """
        return svg(
            defs
                + fading(
                    """
                    <path d="M\(centerX) \(wickTop) v\(top - wickTop + 4)" stroke="\(wick)"
                          stroke-width="3.4" stroke-linecap="round"/>
                    <path d="\(waxPath(top: top, height: height))" fill="url(#wax)"/>
                    <ellipse cx="\(centerX)" cy="\(top + 1)" rx="\(topHalfWidth - 2)" ry="2.6"
                             fill="\(shade)" opacity="0.9"/>
                    <path d="M\(centerX) \(wickTop + 1) v4" stroke="\(wick)"
                          stroke-width="3.4" stroke-linecap="round"/>
                    \(drips)
                    """, waxOpacity) + stand)
    }

    /// 蝋の部分をひとまとめに薄くする包み。1.0のときは包まない
    /// (絵が変わらないので、キャッシュキーも従来のまま使える)
    private static func fading(_ body: String, _ opacity: Double) -> String {
        opacity >= 1 ? body : "<g opacity=\"\(opacity)\">\(body)</g>"
    }

    /// 本体の絵のキャッシュキー。滲み出し・熾火の沈みの最中は
    /// 不透明度でも絵が変わるため、丈と併せて刻む
    public static func bodyCacheKey(
        _ state: State, waxOpacity: Double = 1, emberOpacity: Double = 1
    ) -> String {
        var key = state.cacheKey
        if waxOpacity < 1 { key += ":o\(Int((waxOpacity * 100).rounded()))" }
        if emberOpacity < 1 { key += ":e\(Int((emberOpacity * 100).rounded()))" }
        return key
    }

    /// 和ろうそくの胴。洋ロウソクの円筒ではなく、上が広く腰でくびれる碇型に描く。
    /// 墨絵パレットの世界に洋物が立っていると筋が通らないため(2026-07-25 タダシ指摘)
    static func waxPath(top: Double, height: Double) -> String {
        let waist = top + height * 0.62
        let bottom = top + height
        return """
        M\(centerX - topHalfWidth) \(top)
        L\(centerX + topHalfWidth) \(top)
        C \(centerX + topHalfWidth - 1.5) \(top + height * 0.34), \
        \(centerX + waistHalfWidth) \(waist - height * 0.1), \(centerX + waistHalfWidth) \(waist)
        C \(centerX + waistHalfWidth) \(bottom - height * 0.12), \
        \(centerX + baseHalfWidth) \(bottom - 1), \(centerX + baseHalfWidth) \(bottom)
        L\(centerX - baseHalfWidth) \(bottom)
        C \(centerX - baseHalfWidth) \(bottom - 1), \
        \(centerX - waistHalfWidth) \(bottom - height * 0.12), \(centerX - waistHalfWidth) \(waist)
        C \(centerX - waistHalfWidth) \(waist - height * 0.1), \
        \(centerX - topHalfWidth + 1.5) \(top + height * 0.34), \(centerX - topHalfWidth) \(top) Z
        """
    }

    /// 炎だけのSVG(揺らすためにレイヤーを分ける)。
    /// 消灯中・燃え尽き後は炎が無いのでnil。座標はflameBoxの枠を基準にした局所系
    public static func flameSVG(_ state: State) -> String? {
        guard state.lit, state.remain > 0 else { return nil }
        let color = flameColor(remain: state.remain).hexString
        let core = PanelLayout.Colors.candleFlameCore.hexString
        let box = flameBoxSize
        // 丈は残量に連動して小さくなる(消えかけの心細さを丈でも語る)
        let scale = 0.60 + 0.40 * min(state.remain, 1)
        // グローがにじむ余白を四方に残した内側で炎を組む(境界で切れると平らな断面が出る)
        let h = (box - flamePadding * 2) * 0.94 * scale
        // 和ろうそくの炎は幅広い。根本のすぐ上で最も膨らみ、そこから先が鋭く伸びる
        let w = (box - flamePadding * 2) * 0.40 * scale
        let baseY = box - flamePadding
        let tipY = baseY - h
        let cx = box / 2
        let bulge = baseY - h * 0.30  // 最も膨らむ高さ(低い位置ほど和ろうそくらしい)
        func flamePath(_ scaleW: Double, _ tipDrop: Double) -> String {
            let ww = w * scaleW
            return """
            M\(cx) \(baseY)
            C \(cx - ww * 0.62) \(baseY - h * 0.02), \(cx - ww) \(bulge + h * 0.14), \
            \(cx - ww) \(bulge)
            C \(cx - ww) \(tipY + h * 0.44), \(cx - ww * 0.30) \(tipY + h * 0.20), \
            \(cx) \(tipY + tipDrop)
            C \(cx + ww * 0.30) \(tipY + h * 0.20), \(cx + ww) \(tipY + h * 0.44), \
            \(cx + ww) \(bulge)
            C \(cx + ww) \(bulge + h * 0.14), \(cx + ww * 0.62) \(baseY - h * 0.02), \
            \(cx) \(baseY) Z
            """
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(box)" height="\(box)" \
        viewBox="0 0 \(box) \(box)">
        \(defs(blur: 3.6))
        <path d="\(flamePath(1.25, -h * 0.06))" fill="\(color)" opacity="0.4" filter="url(#glow)"/>
        <path d="\(flamePath(1.0, 0))" fill="\(color)"/>
        <path d="\(flamePath(0.46, h * 0.42))" fill="\(core)" opacity="0.9"/>
        </svg>
        """
    }

    /// 燃え尽きた後に立ち上る煙。周期的なくねりを繰り返す一本の細い筋として描き、
    /// ホストがこれを**1周期ぶん上へ流してループ**させる(2026-07-25 タダシ要望)。
    /// 燃え尽きていなければnil。
    ///
    /// 濃淡を絵に焼き込まないのが要点。焼き込むと絵ごと濃淡が流れて根本の濃さが上下し、
    /// 「先端から煙が出ていない瞬間」が生まれてしまう。実物の蝋燭は芯がくすぶる間
    /// 煙が絶えないため、そこが崩れると途端に嘘に見える(タダシ指摘)。
    /// 上ほど薄れる濃淡はホスト側が静止したマスクで作る(smokeMaskStops)
    public static func smokeSVG(_ state: State) -> String? {
        guard state.isBurntOut else { return nil }
        let smoke = PanelLayout.Colors.candleSmoke.hexString
        let w = smokeWidth
        let h = smokeArtHeight
        let cx = w / 2
        // くねりは1周期(smokeScrollPeriod)で左右へ一往復し、絵を埋めるまで繰り返す。
        // **繰り返しの単位が周期と一致していること**がループの継ぎ目が見えない条件。
        // 太さは変更前の儚さに寄せて細く保つ(太いと炎に見える。2026-07-25 タダシ指摘)
        let span = smokeScrollPeriod / 2
        let mainUnit = " q-4 -\(span / 2) 0 -\(span) q4 -\(span / 2) 0 -\(span)"
        let main = String(
            repeating: mainUnit, count: Int((h / smokeScrollPeriod).rounded(.up)))
        // 副筋は半分の周期で細かく振れる。周期が整数比なのでループの継ぎ目は合ったまま
        let subUnit = " q3 -\(span / 4) 0.5 -\(span / 2) q-3 -\(span / 4) -0.5 -\(span / 2)"
        let sub = String(repeating: subUnit, count: Int((h / span).rounded(.up)))
        // 筋の根本。絵の下端そのものではなく、裾の余白のぶん内側から始める
        let root = h - smokeArtFootroom
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        <defs>
          <filter id="soft" x="-80%" y="-20%" width="260%" height="150%">
            <feGaussianBlur stdDeviation="\(smokeBlur)"/>
          </filter>
        </defs>
        <g filter="url(#soft)">
        <path d="M\(cx) \(root)\(main)" stroke="\(smoke)" stroke-width="\(smokeStrokeWidth)"
        fill="none" stroke-linecap="round" opacity="0.9"/>
        <path d="M\(cx + 2.5) \(root)\(sub)" stroke="\(smoke)"
        stroke-width="\(smokeSubStrokeWidth)" fill="none" stroke-linecap="round" opacity="0.5"/>
        </g>
        </svg>
        """
    }

    /// 吹き消した直後に芯先から立つ一瞬の煙。燃え尽きの煙(smokeSVG)とは別物で、
    /// ループも周期も持たない一発もの: ホストが浮かせながらフェードで消す。
    /// 上りながら風下(なびいた側)へ流れる曲がりを絵に焼き込み、風の余韻を残す
    public static func blowOutWispSVG() -> String {
        let smoke = PanelLayout.Colors.candleSmoke.hexString
        let w = blowOutWispWidth
        let h = blowOutWispHeight
        let cx = w / 2
        // 筋の根本。丸端とぼかしの裾が下端で切れないよう内側から始める
        let root = h - 4.0
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        <defs>
          <filter id="soft" x="-80%" y="-20%" width="260%" height="150%">
            <feGaussianBlur stdDeviation="0.8"/>
          </filter>
        </defs>
        <g filter="url(#soft)">
        <path d="M\(cx) \(root) q-3.5 -6 0 -11 q3 -4.5 -0.5 -9 q-3 -4 -1.5 -9"
        stroke="\(smoke)" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.9"/>
        </g>
        </svg>
        """
    }

    /// 吹き消しの煙の大きさ(pt)。蝋燭の枠の縮尺には縛らない(燃え尽きの煙と同じ理屈で、
    /// 枠なりに縮めると実表示が小さすぎて見えないため)。一瞬の儚さなので煙よりは短い
    public static let blowOutWispWidth = 20.0
    public static let blowOutWispHeight = 40.0

    /// 吹き消しの煙を置く枠。消えたばかりの芯先を根本にして、そこから上へ伸ばす。
    /// 丈は火が消えた時点のまま保たれる(restore)ため、そのときの丈と芯の姿で位置を出す
    public static func blowOutWispBox(remain: Double, lit: Bool, in frame: PanelFrame) -> PanelFrame
    {
        let side = min(frame.w, frame.h)
        let scale = side / canvas
        let originY = frame.y + (frame.h - side) / 2
        // 根本は芯の上端。芯へわずかに沈め、根本の切れ目を芯に隠す
        let rootY = originY + wickTop(remain: remain, lit: lit) * scale + 2
        return PanelFrame(
            x: frame.x + frame.w / 2 - blowOutWispWidth / 2,
            y: rootY - blowOutWispHeight,
            w: blowOutWispWidth,
            h: blowOutWispHeight)
    }

    // MARK: - 計測停止後の丈の戻し

    /// 計測停止から丈を戻し始めるまで、丈を保つ時間(秒)。
    /// 火が消え(吹き消し0.4秒)、立ちのぼった煙が薄れ始める頃を狙う。
    /// 煙が消え切るまで待つと「停止したのに蝋燭が短いまま」が2秒近く続いて間延びする
    /// (2026-08-05 タダシ合意)
    public static let restoreHold = 0.95
    /// 丈を満丈へ戻すのにかける時間(秒)
    public static let restoreDuration = 0.55

    /// 燃え尽きから戻し始めるまで、蝋だまりのまま待つ時間(秒)。
    /// 熾火が静まり、絶えず立っていた煙が絶えるのを待つため通常より長く取る
    /// (「煙がほぼ消えてから新しい蝋燭が立つ」2026-08-05 タダシ合意)
    public static let emberRestoreHold = 1.2
    /// 燃え尽きから満丈へ戻すのにかける時間(秒)。丈0から立ち上げるぶん通常より長い
    public static let emberRestoreDuration = 0.7
    /// 熾火の朱が沈み切るまでの時間(秒)。計測を止めた合図として煙より先に静まる
    public static let emberFadeDuration = 0.8
    /// 燃え尽きの煙(ループ)が絶えるまでの時間(秒)。ホストがレイヤーを薄れさせる
    public static let emberSmokeFadeDuration = 1.4

    /// 計測停止の直後、実状態(満丈)の代わりに描く蝋燭の姿
    public struct Restore: Equatable, Sendable {
        public let state: State
        /// 蝋の不透明度(滲み出しの最中だけ1未満)
        public let waxOpacity: Double
        /// 熾火の不透明度(燃え尽きから戻す間だけ1未満)
        public let emberOpacity: Double

        public init(state: State, waxOpacity: Double, emberOpacity: Double = 1) {
            self.state = state
            self.waxOpacity = waxOpacity
            self.emberOpacity = emberOpacity
        }
    }

    /// 計測停止からの経過秒に対する蝋燭の姿。戻し終えていればnil(実状態の満丈をそのまま描く)。
    ///
    /// 停止すると連続稼働は0へ戻るため実状態は即座に満丈になるが、
    /// 火や熾火・煙が残っている間に丈だけ跳ね上がると
    /// 「消えかけの火が満丈の蝋燭に載る」絵になる。
    /// そこで火が消えた時点の姿をいったん保ち、煙が薄れる頃から戻す。
    ///
    /// 溶けた蝋は本来伸びないので、丈を戻すだけでは物として嘘になる。
    /// 伸びに合わせて滲み出させ「新しい蝋燭に替わった」と読ませる(2026-08-05 タダシ合意)
    public static func restore(frozen: State, elapsed: Double) -> Restore? {
        frozen.isBurntOut
            ? restoreFromEmbers(elapsed: elapsed)
            : restoreFromLit(frozenRemain: frozen.remain, elapsed: elapsed)
    }

    /// 火が点いていた蝋燭を止めたとき。消えた時点の丈を保ってから満丈へ戻す
    private static func restoreFromLit(frozenRemain: Double, elapsed: Double) -> Restore? {
        let frozen = min(max(frozenRemain, 0), 1)
        // 丈を保つ間。火が消えた直後なので芯は炭化した短いまま(lit: true)
        guard elapsed > restoreHold else {
            return Restore(state: State(remain: frozen, lit: true), waxOpacity: 1)
        }
        guard elapsed < restoreHold + restoreDuration else { return nil }
        let t = (elapsed - restoreHold) / restoreDuration
        // 出足で伸び、終わりへ向けて落ち着く。伸び切りで跳ね返すと蝋燭がゴムに見える
        let eased = 1 - pow(1 - t, 3)
        // 芯は新品の長さへ。ここで替えるのは丈が動き始める瞬間で、
        // 煙もまだ残っているため1pt弱の伸びは紛れる(戻し終えてから替えると最後に跳ねる)
        let restored = State(remain: frozen + (1 - frozen) * eased, lit: false)
        // 滲み出しは伸びより早く終える(最後まで薄いと幽霊のように透けて見える)
        return Restore(state: restored, waxOpacity: 0.72 + 0.28 * min(eased / 0.6, 1))
    }

    /// 燃え尽き(蝋だまりと熾火と煙)から止めたとき。
    /// 火が静まる → 煙が絶える → 新しい蝋燭が立つ、の順で片付ける
    private static func restoreFromEmbers(elapsed: Double) -> Restore? {
        // 熾火は止めた瞬間から沈み始める。ここを待たせると
        // 「まだ火の気があるのに新しい蝋燭が立つ」ことになる
        let ember = 1 - min(max(elapsed / emberFadeDuration, 0), 1)
        guard elapsed > emberRestoreHold else {
            return Restore(
                state: State(remain: 0, lit: true), waxOpacity: 1, emberOpacity: ember)
        }
        guard elapsed < emberRestoreHold + emberRestoreDuration else { return nil }
        let t = (elapsed - emberRestoreHold) / emberRestoreDuration
        let eased = 1 - pow(1 - t, 3)
        // 丈0は「燃え尽き」の姿そのものなので、立ち上がりでは0を跨がせない
        // (跨ぐと蝋だまりの絵へ戻り、せり上がりが一瞬途切れる)
        let restored = State(remain: max(eased, 0.01), lit: false)
        return Restore(
            state: restored,
            waxOpacity: 0.72 + 0.28 * min(eased / 0.6, 1),
            emberOpacity: 0)
    }

    /// 戻しの先頭で絵が動かない時間(秒)。ホストはこの間の描き直しを1秒tickに任せられる。
    /// 燃え尽きからは熾火が最初から沈んでいくため、静止する間は無い
    public static func restoreStillDuration(frozen: State) -> Double {
        frozen.isBurntOut ? 0 : restoreHold
    }

    /// 煙の幅(pt)。蝋燭の枠(38pt)の縮尺には縛らないが、細い一筋の儚さは保つ
    public static let smokeWidth = 30.0
    /// 煙の見える高さ(pt)。蝋燭の枠の2倍強(2026-07-25 タダシ指定)。
    /// 枠に収めていた頃は実表示10x16ptで燃え尽きに気づけなかったため、
    /// 上の計測リストへ突き抜けるのはタダシ許諾済み(「割り込みも上等」)
    public static let smokeVisibleHeight = 84.0
    /// くねり1周期の長さ(pt)。ホストはこの分だけ絵を上へ動かしてループさせる
    public static let smokeScrollPeriod = 40.0
    static let smokeStrokeWidth = 2.2
    static let smokeSubStrokeWidth = 1.5
    static let smokeBlur = 0.8
    /// 絵の下端に残す余白。丸端の線の半径とぼかしの裾(3σ)がラスタライズ範囲の外へ
    /// はみ出すと、そこで切れて断面になる。**この余白を確保するために絵を伸ばす**のが要点で、
    /// 筋の開始点を内側へ寄せて済ませると供給が足りず、流し切った先で根本が空く
    static let smokeArtFootroom = smokeStrokeWidth / 2 + smokeBlur * 3

    /// 煙の絵の高さ。見える範囲の**下**に1周期ぶん(＋裾の余白)を隠し持つ。
    /// 上へ流れた分を下から供給し続けるための余りで、これが無いと
    /// 流れた先で根本が空いてしまう(2026-07-25 タダシ指摘で修正)
    public static let smokeArtHeight =
        smokeVisibleHeight + smokeScrollPeriod + smokeArtFootroom
    /// 煙の根本を蝋だまりのどれだけ上に置くか(蝋燭側のSVG座標)
    static let smokeRootInset = 5.0
    /// 根本を蝋だまりへ沈める分(pt)。マスクの下端で煙が切れる縁を蝋だまりに隠す
    static let smokeRootSink = 4.0

    /// 煙の絵の置き方と流し方。枠(smokeBox)に対して絵をどこに置き、どれだけ動かすか。
    /// ホストのレイヤー操作に埋めるとテストが効かないため、値としてここに置く
    public struct SmokeScroll: Equatable, Sendable {
        /// 絵の高さ
        public let artHeight: Double
        /// 枠の上端から見た絵の上端のずれ。0 = 枠の上端に揃える
        public let artTopOffset: Double
        /// ひと巡りで動かす距離。視覚的な上方向が負
        public let translation: Double
    }

    /// 絵は枠の**上端に揃えて**置き、余りを枠の下(マスクの外)へはみ出させる。
    /// 上へ流れた分をその余りが下から供給するため、下揃えにすると流れた先で根本が空く
    /// (2026-07-25 タダシ指摘で修正した箇所そのもの)
    public static var smokeScroll: SmokeScroll {
        .init(artHeight: smokeArtHeight, artTopOffset: 0, translation: -smokeScrollPeriod)
    }

    /// 「上ほど薄れる」濃淡。ホストはこれをマスクとして**静止**させる。
    /// 絵ではなくマスクに持たせるのは、絵と一緒に濃淡が流れると根本の濃さが上下して
    /// 煙が絶える瞬間ができるため。locationは根本(0)から先端(1)まで
    public struct SmokeMaskStop: Equatable, Sendable {
        public let location: Double
        public let opacity: Double

        public init(location: Double, opacity: Double) {
            self.location = location
            self.opacity = opacity
        }
    }

    public static let smokeMaskStops: [SmokeMaskStop] = [
        // 下端は透かす。ここを不透明にするとマスクの縁で煙が切れて平らな断面が出る
        .init(location: 0, opacity: 0),
        .init(location: 0.06, opacity: 0.92),
        .init(location: 0.5, opacity: 0.6),
        .init(location: 1, opacity: 0),
    ]

    /// 煙の見える枠(マスクの領域)。蝋だまりの少し上を根本にして、そこから上へ伸ばす。
    /// 絵はこの枠より下に1周期ぶん長く、はみ出した分はマスクで隠れる。
    /// 燃え尽きていなければnil
    public static func smokeBox(_ state: State, in frame: PanelFrame) -> PanelFrame? {
        guard state.isBurntOut else { return nil }
        let side = min(frame.w, frame.h)
        let scale = side / canvas
        let originY = frame.y + (frame.h - side) / 2
        // 根本だけは蝋だまりに合わせる必要があるため、蝋燭側の縮尺で位置を求める
        let rootY = originY + (baseY - smokeRootInset) * scale + smokeRootSink
        return PanelFrame(
            x: frame.x + frame.w / 2 - smokeWidth / 2,
            y: rootY - smokeVisibleHeight,
            w: smokeWidth,
            h: smokeVisibleHeight)
    }

    /// 炎レイヤーの一辺(SVG内部座標)。和ろうそくの炎は胴に対して大きいうえ、
    /// 揺れの振れ幅とグローのにじみも収める必要があるため広めに取る
    static let flameBoxSize = 50.0
    /// 炎の周りに残す余白。ぼかしたグローが枠で切れると平らな断面が見えてしまう
    static let flamePadding = 5.0

    /// 炎レイヤーの回転軸(枠に対する縦位置の比)。炎の根本を軸に揺らすための値。
    /// ホストがisGeometryFlippedのためY方向は反転して読まれる前提で、
    /// 「下端から余白ぶん上」を指す
    public static var flameAnchorY: Double { 1 - flamePadding / flameBoxSize }

    /// 炎レイヤーを置く枠。蝋燭の描画枠(frame)を基準にした実座標へ変換して返す。
    /// 炎が無い状態ではnil。回転の軸は枠の下端中央(炎の根本)に置く前提
    public static func flameBox(_ state: State, in frame: PanelFrame) -> PanelFrame? {
        guard state.lit, state.remain > 0 else { return nil }
        // 蝋燭本体は正方形として枠内へ収めて描かれるため、同じ縮尺・原点を再現する
        let side = min(frame.w, frame.h)
        let scale = side / canvas
        let originX = frame.x + (frame.w - side) / 2
        let originY = frame.y + (frame.h - side) / 2
        // 炎の根本は芯の先端。蝋の上端よりわずかに上に置く。
        // 枠の下端ではなく「下端から余白ぶん上」が根本になるため、その分だけ下げて合わせる
        let rootY = waxTop(remain: state.remain) - 3
        return PanelFrame(
            x: originX + (centerX - flameBoxSize / 2) * scale,
            y: originY + (rootY - flameBoxSize + flamePadding) * scale,
            w: flameBoxSize * scale,
            h: flameBoxSize * scale)
    }

    private static func defs(blur: Double) -> String {
        """
        <defs><filter id="glow" x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur stdDeviation="\(blur)"/></filter></defs>
        """
    }

    private static func svg(_ body: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" \
        viewBox="0 0 \(canvas) \(canvas)">\(body)</svg>
        """
    }
}
