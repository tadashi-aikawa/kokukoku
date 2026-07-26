import Foundation

/// フッター右下のリセットを表すそろばん。
///
/// 「ご破算」はリセットの日本語の語源そのもので、説明が要らない。加えて道具立てが揃う:
/// 時計=時を見る / 蝋燭=時の経過を見せる / そろばん=数を数える。
/// どれも「時と数を扱う和の道具」なので、パネルに並んでも喧嘩しない。
///
/// 描くのは**上珠が上枠へ・下珠が下枠へ払われ、梁から離れた「零」の姿**。
/// 珠が梁に寄っていれば数を表すが、離れていれば何も置かれていない=ご破算になる。
///
/// 縦横比は道具の実比率(22:14)に倣う。最初は正方形で描いたが、実寸では格子の塊にしか
/// 見えずそろばんと読めなかった(モック検証)。横長にすると桁が並んで見え、16pxでも通じる。
public enum SorobanArt {
    /// SVGの内部座標。実表示サイズはPanelLayoutが決める
    public static let canvasW = 22.0
    public static let canvasH = 14.0

    // MARK: - 部品の寸法(内部座標)

    static let frameInset = 0.9
    static let frameStroke = 1.15
    static let cornerRadius = 1.3
    /// 梁(読みの基準線)。珠がここから離れているのが「ご破算」
    static let beamY = 5.9
    /// 桁の軸。3本あれば「桁が並んでいる」と読め、2本では算盤に見えない
    static let rodXs = [5.5, 11.0, 16.5]
    static let rodStroke = 0.6
    static let rodOpacity = 0.45
    /// 払われた珠の位置(上珠は上枠寄り・下珠は下枠寄り)と大きさ
    static let upperBeadY = 3.3
    static let lowerBeadY = 10.6
    static let beadHalfW = 2.0
    static let beadHalfH = 1.5

    // MARK: - 描画

    /// 姿は状態に依らず一定で、色だけがホバー・確認で変わるためキーは色で分ける
    public static func cacheKey(color: PanelColor) -> String {
        "soroban:\(color.hexString)"
    }

    public static func svg(color: PanelColor) -> String {
        let ink = color.hexString
        var body = """
        <rect x="\(f(frameInset))" y="\(f(frameInset + 0.2))" \
        width="\(f(canvasW - frameInset * 2))" height="\(f(canvasH - frameInset * 2 - 0.4))" \
        rx="\(f(cornerRadius))" fill="none" stroke="\(ink)" stroke-width="\(f(frameStroke))"/>
        """
        body += """
        <line x1="\(f(frameInset))" y1="\(f(beamY))" x2="\(f(canvasW - frameInset))" \
        y2="\(f(beamY))" stroke="\(ink)" stroke-width="\(f(frameStroke))"/>
        """
        for x in rodXs {
            body += """
            <line x1="\(f(x))" y1="\(f(frameInset + 0.2))" x2="\(f(x))" \
            y2="\(f(canvasH - frameInset - 0.2))" stroke="\(ink)" \
            stroke-width="\(f(rodStroke))" opacity="\(f(rodOpacity))"/>
            """
            for cy in [upperBeadY, lowerBeadY] {
                body += """
                <path d="M\(f(x)) \(f(cy - beadHalfH)) L\(f(x + beadHalfW)) \(f(cy)) \
                L\(f(x)) \(f(cy + beadHalfH)) L\(f(x - beadHalfW)) \(f(cy)) Z" fill="\(ink)"/>
                """
            }
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(f(canvasW))" height="\(f(canvasH))" \
        viewBox="0 0 \(f(canvasW)) \(f(canvasH))">\(body)</svg>
        """
    }

    static func f(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
