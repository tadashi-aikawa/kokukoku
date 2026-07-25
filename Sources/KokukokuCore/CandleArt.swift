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

    static func waxHeight(remain: Double) -> Double {
        remain <= 0 ? 0 : max(5, fullWaxHeight * min(remain, 1))
    }

    /// 炎(揺らす部分)を除いた蝋燭本体のSVG。
    /// 台・蝋・溶けたたれ・芯を描き、燃え尽き時は蝋だまりと熾火と煙に変わる
    public static func bodySVG(_ state: State) -> String {
        let colors = PanelLayout.Colors.self
        let wax = colors.candleWax.hexString
        let shade = colors.candleWaxShade.hexString
        let holder = colors.candleHolder.hexString
        let wick = colors.candleWick.hexString
        let smoke = colors.candleSmoke.hexString
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
            return svg(
                defs(blur: 3)
                    + """
                    <path d="M35 \(baseY) q13 -9 26 0 z" fill="\(shade)" opacity="0.95"/>
                    <ellipse cx="\(centerX)" cy="\(baseY - 3)" rx="13" ry="6" fill="\(ember)"
                             opacity="0.75" filter="url(#glow)"/>
                    <ellipse cx="\(centerX)" cy="\(baseY - 3)" rx="7.5" ry="3" fill="\(ember)"/>
                    <ellipse cx="\(centerX)" cy="\(baseY - 3.5)" rx="3.4" ry="1.4" fill="\(wax)"
                             opacity="0.55"/>
                    """ + stand)
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
        // 和ろうそくは芯が太い。消灯中(休憩中)は長めに残して「まだ点けてへん新品」に見せ、
        // 点灯中は上端が炭化して短く見える
        let wickTop = state.lit ? top - 6 : top - 9
        return svg(
            """
            <defs>
              <linearGradient id="wax" x1="0" y1="0" x2="1" y2="0">
                <stop offset="0" stop-color="\(shade)"/>
                <stop offset="0.32" stop-color="\(wax)"/>
                <stop offset="1" stop-color="\(shade)"/>
              </linearGradient>
            </defs>
            <path d="M\(centerX) \(wickTop) v\(top - wickTop + 4)" stroke="\(wick)"
                  stroke-width="3.4" stroke-linecap="round"/>
            <path d="\(waxPath(top: top, height: height))" fill="url(#wax)"/>
            <ellipse cx="\(centerX)" cy="\(top + 1)" rx="\(topHalfWidth - 2)" ry="2.6"
                     fill="\(shade)" opacity="0.9"/>
            <path d="M\(centerX) \(wickTop + 1) v4" stroke="\(wick)"
                  stroke-width="3.4" stroke-linecap="round"/>
            \(drips)
            """ + stand)
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

    /// 燃え尽きた後に立ち上る煙。炎と同じくレイヤーへ分けて上へ流す。
    /// 静止した煙より動きのほうが周辺視野に引っかかり、「もう休め」に気づける
    /// (2026-07-25 タダシ要望)。燃え尽きていなければnil
    public static func smokeSVG(_ state: State) -> String? {
        guard state.isBurntOut else { return nil }
        let smoke = PanelLayout.Colors.candleSmoke.hexString
        let w = smokeBoxWidth
        let h = smokeBoxHeight
        let cx = w / 2
        // 下ほど濃く、上ほど薄れる二筋。太い筋と細い筋でくねりの位相をずらす
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        <defs>
          <linearGradient id="fade" x1="0" y1="1" x2="0" y2="0">
            <stop offset="0" stop-color="\(smoke)" stop-opacity="0.85"/>
            <stop offset="0.55" stop-color="\(smoke)" stop-opacity="0.45"/>
            <stop offset="1" stop-color="\(smoke)" stop-opacity="0"/>
          </linearGradient>
        </defs>
        <path d="M\(cx) \(h - 1) q-5 -\(h * 0.2) 0 -\(h * 0.34) q5 -\(h * 0.18) 0 -\(h * 0.32) \
        q-4 -\(h * 0.12) -1 -\(h * 0.26)" stroke="url(#fade)" stroke-width="2.8" fill="none"
        stroke-linecap="round"/>
        <path d="M\(cx + 4) \(h - 3) q4 -\(h * 0.18) 1 -\(h * 0.3) q-3 -\(h * 0.16) 0 -\(h * 0.28)"
        stroke="url(#fade)" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.7"/>
        </svg>
        """
    }

    /// 煙レイヤーの寸法(SVG内部座標)。立ち上る余地を取るため縦に長い
    static let smokeBoxWidth = 26.0
    static let smokeBoxHeight = 40.0

    /// 煙レイヤーを置く枠。蝋だまりの上端から上へ伸ばす。燃え尽きていなければnil
    public static func smokeBox(_ state: State, in frame: PanelFrame) -> PanelFrame? {
        guard state.isBurntOut else { return nil }
        let side = min(frame.w, frame.h)
        let scale = side / canvas
        let originX = frame.x + (frame.w - side) / 2
        let originY = frame.y + (frame.h - side) / 2
        // 煙の根本は蝋だまりの少し上
        let rootY = baseY - 6
        return PanelFrame(
            x: originX + (centerX - smokeBoxWidth / 2) * scale,
            y: originY + (rootY - smokeBoxHeight) * scale,
            w: smokeBoxWidth * scale,
            h: smokeBoxHeight * scale)
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
