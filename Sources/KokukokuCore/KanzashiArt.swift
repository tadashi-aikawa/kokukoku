import Foundation

/// ヘッダー右上のPin(パネル固定)を表す玉簪(たまかんざし)。
///
/// 実物の玉簪の構造をなぞる: **軸の上端に金の小玉(ぷっくり)・途中に紅の大玉**。
/// 大玉には蜻蛉玉(模様入りのガラス玉)の巻き模様を金の弧一本で入れる。
/// 軸は先端を尖らせず、**途中で断って薄墨へ溶かす**(手前から奥へ挿し込んだ姿)。
///
/// ここへ至るまでに頭の形を3度変えている。捨てた案とその理由を残す。
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
///
/// ## 軸を溶かして「刺さっている」を出すまで(2026-07-27)
///
/// 先端まで尖った軸を全部見せていた頃は**「机に置いた簪」**に見えていた。挿した簪は軸が隠れ、
/// 奥へ向かう分だけ細く霞むので、そこが抜けると「置いてある」に読める。
/// 実寸のモックで潰した案:
/// 1. **軸を短くするだけ**: 小玉と大玉が団子2つに寄り、簪と読めなくなる(上記4の穴と同根)
/// 2. **刺し口の穴(黒い楕円)**: 実寸では汚れに見える。そもそもパネルには刺さる面の絵が
///    描かれていないので、穴を置く先が無い
/// 3. **落ち影**: 「面から浮いている」を語る表現で、刺さり感には効かない
/// 4. **玉のハイライト(洋画式の球の陰影)**: 玉は実寸13pxしかなく、光ではなく点に読まれる。
///    加えて時計・そろばん・蝋はすべてフラットなので、玉だけ質感が浮く
///
/// 採ったのは**濃淡**。和の絵は奥行きを陰影ではなく墨の濃淡で作る(遠山を薄墨で描くあれ)ため、
/// 軸を先へ向けて薄墨に溶かせば「奥へ入っていく」と意匠の作法が同時に立つ。
/// 副産物として、軸が短くなったぶんキャンバスの縦が縮み、同じ枠でも玉が大きく見える。
///
/// **この構図にしたことで、上記4(実物比率=玉を小さく)の却下が覆った**。当時の欠点
/// 「斜めの線に点が乗っただけになる」は長い軸あってのもので、軸が消えた今は成り立たない。
/// 玉を実物寄りに落とすと小玉との間に軸が見えるようになり、簪の構造もむしろ読みやすくなった。
/// **案の当否はそれ単体では決まらず、周りの構図と一組でしか判定できない**(2026-07-27 タダシ提案)。
///
/// 「挿す前(off)=軸が全部見える / 挿した(on)=軸が奥へ消える」と**状態へ割り当てる案も出したが、
/// タダシ判断で採らなかった**(2026-07-27)。姿は常に刺さった絵で固定する。
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
    /// 簪そのものの内部座標(回転前)。丈は軸を断つ位置で決まる
    static let bodyW = 26.0
    static var bodyH: Double { shaftSunkY + 1.2 }
    static let tiltDegrees = 30.0

    /// 回転後の外接。bodyを中心まわりに30度倒すと縦横とも一回り膨らむため、
    /// 切れないぶんだけキャンバスを広げる(実表示サイズはPanelLayoutが決める)
    public static let canvasW = 39.0
    public static let canvasH = 41.0

    // MARK: - 部品の寸法(内部座標)

    /// 軸の上端を飾る小玉。実物より一回り大きく取って、実寸で消えないようにする
    static let capRadius = 2.6
    static let capMargin = 2.0
    /// 途中の大玉(蜻蛉玉)。軸の上寄りに置き、小玉との間に軸を見せる
    /// (くっつけると団子が2つ並んだ形になり、簪に見えない)。
    /// 5.4から実物寄りに落とした値。**軸が全長だった頃は却下した縮小**で、当時は玉を落とすと
    /// 「斜めの長い線に点が乗った」だけになっていた。刺さった構図でその線が消えたので成立する。
    /// 小玉との間に見える軸が1.4→2.4に開き、玉が軸に通っている構造が読めるようになる
    static let beadRadius = 4.4
    static let beadCenterY = 14.0
    /// 巻き模様の弧の太さ。実寸で消えない下限
    static let stripeWidth = 1.7
    /// 巻き模様の反り。玉の径に対する比で持つ
    /// (固定値のままだと玉を縮めたときに弧の反りだけが強く残り、玉が歪んで見える)
    static let stripeEndRiseRatio = 0.222
    static let stripeControlDropRatio = 0.407
    /// 軸。根元は太く、面に入る位置へ向けて細る
    static let shaftWidth = 2.0
    /// 軸を断つ位置(ここから先は挿し込まれていて見えない)。
    /// これ以上詰めると大玉と小玉が団子2つに寄り、簪の構造が読めなくなる
    static let shaftSunkY = 30.0
    /// 断つ位置での軸の絞り具合(遠近で細る)
    static let shaftTaperRatio = 0.42
    /// 軸の見える長さのうち、下から何割を薄墨へ溶かすか。
    /// これを上げすぎると軸全体が霞んで「弱った線」に見える(0.85で確認)
    static let shaftFadeRatio = 0.55

    /// 軸の上端(小玉の中心と同じ高さ)
    static var shaftTopY: Double { capMargin + capRadius }
    /// 薄墨へ溶け始める高さ
    static var shaftFadeStartY: Double {
        shaftTopY + (shaftSunkY - shaftTopY) * (1 - shaftFadeRatio)
    }

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
        let sunkHalf = half * shaftTaperRatio

        // 軸が奥へ入っていく濃淡。断つ位置で透明になり、刺し口を描かずに貫通を語る
        var body = """
        <defs><linearGradient id="kanzashi-shaft" gradientUnits="userSpaceOnUse" \
        x1="0" y1="\(f(shaftFadeStartY))" x2="0" y2="\(f(shaftSunkY))">\
        <stop offset="0" stop-color="\(shaft)" stop-opacity="1"/>\
        <stop offset="1" stop-color="\(shaft)" stop-opacity="0"/>\
        </linearGradient></defs>
        """
        // 軸(上端の小玉の位置から、面に入る位置まで)
        body += """
        <path d="M\(f(cx - half)) \(f(top)) L\(f(cx + half)) \(f(top)) \
        L\(f(cx + sunkHalf)) \(f(shaftSunkY)) L\(f(cx - sunkHalf)) \(f(shaftSunkY)) Z" \
        fill="url(#kanzashi-shaft)"/>
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
        let stripeEndY = beadCenterY - beadRadius * stripeEndRiseRatio
        let stripeControlY = beadCenterY + beadRadius * stripeControlDropRatio
        body += """
        <path d="M\(f(cx - stripeHalf)) \(f(stripeEndY)) \
        Q\(f(cx)) \(f(stripeControlY)) \(f(cx + stripeHalf)) \(f(stripeEndY))" \
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
