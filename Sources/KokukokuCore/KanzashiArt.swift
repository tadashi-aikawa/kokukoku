import Foundation

/// ヘッダー右上のPin(パネル固定)を表す玉簪(たまかんざし)。
///
/// 実物の玉簪の構造をなぞる: **軸の上端に金の小玉(ぷっくり)・途中に紅の大玉・下端が尖る**。
/// 大玉には蜻蛉玉(模様入りのガラス玉)の巻き模様を金の弧一本で入れる。
///
/// ここへ至るまでに形を3度変えている。捨てた案とその理由を残す。
/// 1. **二本足の花簪(梅花)**: 和の意匠としては綺麗だが「ピン」の記号が立たない。
///    📌 は *斜め・赤・一本針* で覚えられており、そこを外すと機能が読めない
/// 2. **一本足の花簪(紅の梅花)**: 記号性は立ったが、頭が花だと五弁の凹凸を読ませる必要があり
///    寸法を落としづらい(28pxが限界)
/// 3. **頭に玉+座金**: 押しピンに最も近いが、和の手がかりは座金だけで、その座金は
///    実寸では消えてしまう(モック検証)
/// 4. **実物の比率そのまま**(軸が長く玉が小さい): 40pxでも「斜めの線に点が乗った」だけになる
///
/// 採ったのは実物の構造をアイコン向けの比率に寄せた形。**上端の小玉が決め手**で、
/// これは押しピンには無い形なので「簪」と読めるうえ、失うピン感はごく僅か。
/// 玉は小さくても円と読めるため、花簪より寸法を落とせる(40px → 34px)。
///
/// 斜めは**記号であって状態ではない**。当初は on=直立 / off=傾き で状態を表す案を進めたが、
/// 実寸で並べて2つの理由から捨てた。
/// (1) 既定状態が off なので「倒れた簪」がほぼ常時表示され、直立した時計・デジタル時刻の
///     秩序を崩し続ける。変化は一時的な状態(on)に割り当てるのが筋
/// (2) 実寸では倒れた簪が「簪」と読めず、横向きの棒に塊が付いた絵になる
/// よって姿は固定し、状態は色(紅↔燻し)と金の有無だけで分ける。
///
/// 傾きの向きは頭が右上・先が左下。現行の押しピン実装と 📌 の向きに合わせており、
/// 意匠を替えても状態の読み方は作り替えない。
///
/// 蝋燭・時計と同じく、アセットを同梱せずSVG文字列をコードで組み立てる。
public enum KanzashiArt {
    /// 簪そのものの内部座標(回転前)
    static let bodyW = 26.0
    static let bodyH = 48.0
    static let tiltDegrees = 30.0

    /// 回転後の外接。bodyを中心まわりに30度倒すと縦横とも一回り膨らむため、
    /// 切れないぶんだけキャンバスを広げる(実表示サイズはPanelLayoutが決める)
    public static let canvasW = 47.0
    public static let canvasH = 55.0

    // MARK: - 部品の寸法(内部座標)

    /// 軸の上端を飾る小玉。34px表示では約1.6px相当まで細るため、
    /// 実物より一回り大きく取って消えないようにする
    static let capRadius = 2.6
    static let capMargin = 2.0
    /// 途中の大玉(蜻蛉玉)。軸の上寄りに置き、小玉との間に軸を見せる
    /// (くっつけると団子が2つ並んだ形になり、簪に見えない)
    static let beadRadius = 5.4
    static let beadCenterY = 14.0
    /// 巻き模様の弧の太さ。34pxで消えない下限
    static let stripeWidth = 1.7
    /// 軸。根元は太く、先は尖る
    static let shaftWidth = 2.0
    static let shaftTaperY = 43.0
    static let shaftTipY = 46.8
    /// 先端に向けて絞る割合
    static let shaftTaperRatio = 0.42

    /// 軸の上端(小玉の中心と同じ高さ)
    static var shaftTopY: Double { capMargin + capRadius }

    // MARK: - 描画

    /// 絵を一意に決めるキー。姿は固定で色だけが変わるので、状態の2通りしかない
    public static func cacheKey(pinned: Bool) -> String {
        "kanzashi:\(pinned ? "on" : "off")"
    }

    public static func svg(pinned: Bool) -> String {
        let colors = PanelLayout.Colors.self
        let bead = (pinned ? colors.kanzashiBeni : colors.kanzashiIbushi).hexString
        let gold = (pinned ? colors.kanzashiKin : colors.kanzashiIbushiShade).hexString
        let shaft = (pinned ? colors.kanzashiBekko : colors.kanzashiIbushi).hexString

        let cx = bodyW / 2
        let top = shaftTopY
        let half = shaftWidth / 2
        let tipHalf = half * shaftTaperRatio

        // 軸(上端の小玉の位置から先端まで)
        var body = """
        <path d="M\(f(cx - half)) \(f(top)) L\(f(cx + half)) \(f(top)) \
        L\(f(cx + tipHalf)) \(f(shaftTaperY)) L\(f(cx)) \(f(shaftTipY)) \
        L\(f(cx - tipHalf)) \(f(shaftTaperY)) Z" fill="\(shaft)"/>
        """
        // 上端の小玉。押しピンには無い形で、これが「簪」を決める
        body += """
        <circle cx="\(f(cx))" cy="\(f(top))" r="\(f(capRadius))" fill="\(gold)"/>
        """
        body += """
        <circle cx="\(f(cx))" cy="\(f(beadCenterY))" r="\(f(beadRadius))" fill="\(bead)"/>
        """
        // 蜻蛉玉の巻き模様。玉の赤道を金の弧一本で巡らせる
        let stripeHalf = beadRadius * 0.95
        body += """
        <path d="M\(f(cx - stripeHalf)) \(f(beadCenterY - 1.2)) \
        Q\(f(cx)) \(f(beadCenterY + 2.2)) \(f(cx + stripeHalf)) \(f(beadCenterY - 1.2))" \
        fill="none" stroke="\(gold)" stroke-width="\(f(stripeWidth))" stroke-linecap="round"/>
        """

        // 回転前のbodyをキャンバス中央へ寄せてから、中心まわりに倒す
        let dx = (canvasW - bodyW) / 2
        let dy = (canvasH - bodyH) / 2
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(f(canvasW))" height="\(f(canvasH))" \
        viewBox="0 0 \(f(canvasW)) \(f(canvasH))">\
        <g transform="translate(\(f(dx)) \(f(dy))) \
        rotate(\(f(tiltDegrees)) \(f(cx)) \(f(bodyH / 2)))">\(body)</g></svg>
        """
    }

    /// SVGは小数の桁が増えても見た目に効かず、キャッシュキーと同様に
    /// 文字列比較のテストが読みにくくなるため2桁に丸める(ClockArtと同じ方針)
    static func f(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
