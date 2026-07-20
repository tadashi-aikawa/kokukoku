import Foundation

public struct PanelColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct PanelPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// ローカルタイムゾーンの現在時刻(アナログ・デジタル時計の描画入力)
public struct ClockTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(hour: Int, minute: Int, second: Int) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

public struct PanelFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public enum PanelTextAlignment: Equatable, Sendable {
    case left
    case center
    case right
}

public enum PanelImageScaling: Equatable, Sendable {
    case shrinkToFit
    case scaleProportionally
}

public enum PanelElement: Equatable, Sendable {
    case rectangle(
        frame: PanelFrame,
        fillColor: PanelColor,
        cornerRadius: Double = 0,
        strokeColor: PanelColor? = nil,
        strokeWidth: Double = 0,
        id: String? = nil,
        tracksMouse: Bool = false)
    case circle(
        center: PanelPoint,
        radius: Double,
        fillColor: PanelColor? = nil,
        strokeColor: PanelColor? = nil,
        strokeWidth: Double = 0)
    /// ネオン管風の縁取り。芯は上下の炎色グラデーション、外側へ二層のグローがにじむ。
    /// 計測中行の合図に使う
    case neonRectangle(
        frame: PanelFrame,
        cornerRadius: Double,
        strokeWidth: Double,
        topColor: PanelColor,
        bottomColor: PanelColor,
        glowColor: PanelColor,
        glowRadius: Double)
    case line(from: PanelPoint, to: PanelPoint, color: PanelColor, width: Double)
    case text(
        frame: PanelFrame,
        text: String,
        fontName: String,
        fontSize: Double,
        color: PanelColor,
        alignment: PanelTextAlignment = .left)
    case image(
        frame: PanelFrame,
        iconKey: String,
        scaling: PanelImageScaling,
        cornerRadius: Double = 0)
    /// 非描画: ホバーでフルテキストを見せる領域。「…」で省略された文字列の全文を
    /// Platform側がネイティブのツールチップとして表示する
    case tooltip(frame: PanelFrame, text: String)
}

/// パネル上でインライン編集中の時間。編集中は該当の時刻テキストを描画せず、
/// Platform側がその位置に編集フィールドを重ねる。
public enum PanelEditingTarget: Equatable, Sendable {
    case project(id: String)
    case continuous
}

/// パネル幅とそれに連動する座標。幅は最長プロジェクト名の実測幅から決まるため、
/// 静的定数のPanelLayoutと分けてインスタンスとして持ち回る
public struct PanelMetrics: Equatable, Sendable {
    public let panelWidth: Double

    public init(panelWidth: Double) {
        self.panelWidth = panelWidth
    }

    /// 最長プロジェクト名がちょうど収まる幅を計算する。
    /// 名前が短ければminPanelWidthまで縮み、長くてもmaxPanelWidthで頭打ち
    /// (収まらない分は描画側が「…」で省略する)
    public static func compute(
        projectNames: [String],
        measureNameWidth: (String) -> Double
    ) -> PanelMetrics {
        let maxNameWidth = projectNames.map(measureNameWidth).max() ?? 0
        let width = PanelLayout.projectNameX + maxNameWidth.rounded(.up)
            + PanelLayout.nameTimeGap + PanelLayout.timeColumnWidth + PanelLayout.numberColumnX
        return PanelMetrics(
            panelWidth: min(max(width, PanelLayout.minPanelWidth), PanelLayout.maxPanelWidth))
    }

    /// 累積時間列は右端を行番号列と対称の位置(パネル右端-18px)に揃え、
    /// 行全体の左右バランスを保つ
    public var timeColumnX: Double {
        panelWidth - PanelLayout.numberColumnX - PanelLayout.timeColumnWidth
    }

    /// プロジェクト名の右端は累積時間列の左端に連動させる
    public var projectNameRight: Double {
        timeColumnX - PanelLayout.nameTimeGap
    }

    /// アナログ時計の中心(ヘッダーの中でデジタルと合わせて中央寄せ)
    public var clockCenter: PanelPoint {
        PanelPoint(
            x: (panelWidth - PanelLayout.clockRadius * 2 - PanelLayout.clockDigitalGap
                - PanelLayout.clockDigitalWidth) / 2 + PanelLayout.clockRadius,
            y: PanelLayout.clockSectionHeight / 2)
    }

    public var clockDigitalFrame: PanelFrame {
        PanelFrame(
            x: clockCenter.x + PanelLayout.clockRadius + PanelLayout.clockDigitalGap,
            y: PanelLayout.clockSectionHeight / 2 - 18,
            w: PanelLayout.clockDigitalWidth, h: 36)
    }

    /// フッター中央の連続稼働時間のインライン編集フィールド枠
    /// (ラベル自体は実測幅で中央寄せ描画するため、この枠は編集時にだけ使う)
    public func continuousTimeFrame(projectCount: Int, calendarSectionHeight: Double = 0)
        -> PanelFrame
    {
        let footerY = PanelLayout.clockSectionHeight + Double(projectCount) * PanelLayout.rowHeight
            + calendarSectionHeight
        return .init(
            x: (panelWidth - PanelLayout.continuousTimeWidth) / 2,
            y: footerY + 10, w: PanelLayout.continuousTimeWidth, h: 28)
    }

    /// プロジェクト行の累積時間テキストの枠(同上)。
    /// 行エリアは予定セクション(ヘッダー直下)の分だけ下へずれる
    public func accumulatedTimeFrame(rowOffset: Int, calendarSectionHeight: Double = 0)
        -> PanelFrame
    {
        .init(
            x: timeColumnX,
            y: PanelLayout.clockSectionHeight + calendarSectionHeight
                + Double(rowOffset) * PanelLayout.rowHeight,
            w: PanelLayout.timeColumnWidth, h: PanelLayout.rowHeight)
    }
}

public enum PanelLayout {
    /// パネル幅は最長プロジェクト名の実測幅に合わせてこの範囲で伸縮する(PanelMetrics.compute)
    public static let minPanelWidth = 420.0
    public static let maxPanelWidth = 480.0
    /// ヘッダー(現在時刻段: アナログ+デジタル時計)の高さ = プロジェクト行の開始位置。
    /// 時計(直径56px)の上下に14pxずつの余白を取り、下の記録エリアと視覚的に分離する
    public static let clockSectionHeight = 84.0
    public static let rowHeight = 40.0
    public static let footerHeight = 40.0
    public static let padding = 12.0
    public static let projectContentX = numberColumnX + 18
    /// プロジェクト名と累積時間列の間に確保する最小間隔
    public static let nameTimeGap = 12.0
    /// プロジェクト名の左端(行番号+アイコン列の右)
    public static let projectNameX = projectContentX + iconSlotWidth + iconGap
    public static let iconTextWidth = 24.0
    public static let iconImageSize = 24.0
    public static let iconGap = 8.0
    public static let iconSlotWidth = 24.0
    /// 画像アイコンの角丸半径。行カプセルの文法に合わせて円形に切り抜く
    public static let iconImageCornerRadius = iconImageSize / 2
    /// フッター中央の連続稼働時間の編集フィールド幅(HH:MM:SS入力が収まる幅)
    public static let continuousTimeWidth = 90.0
    /// 連続稼働ゲージの全幅。中央寄せで敷く
    public static let gaugeWidth = 180.0
    /// 行カプセル(ネオン・選択輪郭)のパネル端・行境界からのマージン。
    /// 端に密着させると窮屈に見えるため左右に余白を取る
    public static let capsuleInsetX = 8.0
    public static let capsuleInsetY = 3.0
    /// 行番号列の位置(カプセル輪郭の内側に収まるよう端から離す)
    public static let numberColumnX = 24.0
    public static let timeColumnWidth = 100.0
    public static let colors = Colors.self

    /// アナログ時計の文字盤半径(中心位置はPanelMetricsが幅から決める)
    public static let clockRadius = 28.0
    public static let clockDigitalFontSize = 30.0
    public static let clockDigitalWidth = 150.0
    public static let clockDigitalGap = 12.0

    public static func panelHeight(projectCount: Int, calendarSectionHeight: Double = 0) -> Double {
        clockSectionHeight + Double(projectCount) * rowHeight + calendarSectionHeight + footerHeight
    }

    // 予定セクション(ヘッダーの時計直下=「時間の世界」ゾーン)。パネル高は行数に応じて動的に変わる
    public static let calendarEventRowHeight = 26.0
    public static let calendarOverflowRowHeight = 18.0
    public static let calendarErrorRowHeight = 26.0
    /// 中止告知行(通知文脈)の高さ
    public static let calendarNoticeRowHeight = 20.0
    /// 鮮度表示行(通知モード)の高さ
    public static let calendarFreshnessRowHeight = 14.0
    public static let calendarSectionPaddingTop = 6.0
    public static let calendarSectionPaddingBottom = 8.0
    /// 予定ゾーンと計測行の間の「谷」: パネル地色を見せるゾーン間余白。
    /// ゾーン間の余白がゾーン内の行間と同格だと近接の原理で1つのリストに読まれるため、
    /// 行間より太い余白で世界の切れ目を作る(色・記号・ラベルは増やさない。2026-07-19 3人検討)
    public static let calendarSectionGap = 8.0
    /// nowマーカー帯(ヘッダーから降りるnowレール+未開始カウントダウン)の高さ。
    /// 行ではなく帯にする: カウントダウンの出没(表示閾値)で行が挿入・削除されると
    /// リスト全体が縦にずれるため、先頭予定が未開始の間は高さを確保し続ける。
    /// 進行中はnowレールもラベルも無い(リングが「いま」を語る)ため帯ごと詰める
    public static let calendarNowMarkerHeight = 18.0
    /// タイムラインのレール(縦線+予定ごとの点)のx座標
    public static let calendarRailX = 20.0
    /// 予定行の内容(開始時刻)の左端
    public static let calendarContentX = 32.0
    /// 時刻ブロック("01:00" - "02:00")の幅
    public static let calendarTimeWidth = 96.0
    /// 開始-終了の区切り「-」の左右の余白(等幅空白1文字では広すぎるため要素分解して詰める)
    public static let calendarTimeSeparatorPad = 3.0

    public static func calendarRowHeight(_ row: CalendarSectionRow) -> Double {
        switch row {
        case .event: return calendarEventRowHeight
        case .overflow, .collapse: return calendarOverflowRowHeight
        case .error: return calendarErrorRowHeight
        case .notice: return calendarNoticeRowHeight
        case .freshness: return calendarFreshnessRowHeight
        }
    }

    /// 予定セクションが行エリアを押し下げる高さ。行が無ければ0(セクションごと非表示)。
    /// 先頭の予定が未開始のときだけnowマーカー帯の分を含める。
    /// 末尾の「谷」(計測行とのゾーン間余白)も含む(ゾーン背景の塗りは谷の手前で止める)
    public static func calendarSectionHeight(rows: [CalendarSectionRow]) -> Double {
        guard !rows.isEmpty else { return 0 }
        return rows.map(calendarRowHeight).reduce(0, +)
            + (hasNowMarkerBand(rows: rows) ? calendarNowMarkerHeight : 0)
            + calendarSectionPaddingTop + calendarSectionPaddingBottom
            + calendarSectionGap
    }

    /// nowマーカー帯を置くか: 先頭の予定行が未開始のときだけ
    public static func hasNowMarkerBand(rows: [CalendarSectionRow]) -> Bool {
        for row in rows {
            if case .event(let event) = row { return !event.isInProgress }
        }
        return false
    }

    /// アイコン(墨絵の時計)由来のパレット:
    /// 墨 #2D2E27 / 生成り #F8ECD8 / 朱 #DA5932 / 金茶 #AB8A55
    /// 朱は面で使うと異常事態に見えるため警告(リセット確認)と秒針の点睛のみ。
    /// 計測中は炎色ネオンの縁取り(明るい橙金の芯+朱系グロー)で表し、
    /// 行背景はやや暗く沈めて光を際立たせる
    public enum Colors {
        public static let background = PanelColor(red: 0.13, green: 0.13, blue: 0.11, alpha: 0.95)
        public static let headerBg = PanelColor(red: 0.10, green: 0.10, blue: 0.09, alpha: 1)
        public static let rowBg = PanelColor(red: 0.16, green: 0.16, blue: 0.14, alpha: 1)
        public static let rowHoverBg = PanelColor(red: 0.22, green: 0.22, blue: 0.19, alpha: 1)
        public static let activeRowBg = PanelColor(red: 0.19, green: 0.15, blue: 0.10, alpha: 1)
        public static let activeRowHoverBg = PanelColor(red: 0.24, green: 0.19, blue: 0.12, alpha: 1)
        public static let footerBg = PanelColor(red: 0.10, green: 0.10, blue: 0.09, alpha: 1)
        public static let footerHoverBg = PanelColor(red: 0.19, green: 0.19, blue: 0.17, alpha: 1)
        public static let text = PanelColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 1)
        public static let subText = PanelColor(red: 0.62, green: 0.57, blue: 0.47, alpha: 1)
        public static let activeText = PanelColor(red: 1.0, green: 0.80, blue: 0.50, alpha: 1)
        /// ネオン縁取りの芯(上=淡い黄金→下=橙の炎色グラデ)とグロー(朱寄りの炎色)
        public static let neonCoreTop = PanelColor(red: 1.0, green: 0.96, blue: 0.82, alpha: 1)
        public static let neonCoreBottom = PanelColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        public static let neonGlow = PanelColor(red: 0.95, green: 0.33, blue: 0.12, alpha: 0.95)
        /// キーボード選択の輪郭(ネオンの「消灯版」: 生成りの細いカプセル輪郭)
        public static let selectionOutline = PanelColor(
            red: 0.95, green: 0.91, blue: 0.83, alpha: 0.5)
        public static let separator = PanelColor(red: 0.29, green: 0.28, blue: 0.24, alpha: 1)
        public static let resetConfirmBg = PanelColor(red: 0.48, green: 0.10, blue: 0.10, alpha: 1)
        /// パネル外周の縁取り(暗い背景でも輪郭が分かるよう生成りの低アルファ)
        public static let panelBorder = PanelColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 0.28)
        public static let clockSecondHand = PanelColor(
            red: 0.855, green: 0.349, blue: 0.196, alpha: 1)
        /// カウントダウン直前 (imminent) 用の明るい朱。
        /// 秒針の朱は暗背景上で activeText (橙) より輝度が低く、テキストに使うと
        /// 緊急度と目立ち度が逆転するため、色相は朱のまま輝度を橙と同格以上に上げた版
        public static let countdownImminent = PanelColor(
            red: 1.0, green: 0.42, blue: 0.25, alpha: 1)
        /// 開始前通知の対象の点のハロー(生成りの光。入場パルスと同じ「アラートの声」)。
        /// 予告であって警告ではないため朱を使わない。外側ほど淡い二層で光のにじみを描く
        public static let alertHaloOuter = PanelColor(
            red: 0.95, green: 0.91, blue: 0.83, alpha: 0.12)
        public static let alertHaloInner = PanelColor(
            red: 0.95, green: 0.91, blue: 0.83, alpha: 0.30)
        /// 予定タイムラインの連鎖(間なし)用の明るい生成り(テキストと同格のフル明度)。
        /// 連鎖は「危険」でも「いま」でもない構造情報のため炎色帯(金茶〜朱)を使わない。
        /// タイムライン内は「繋がりの強さ=明度、色相ジャンプ=異常(朱)」の一軸文法にする
        public static let calendarChain = PanelColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 1)
        /// 進行中予定のリングstroke(橙の炎色)とその単層グロー。
        /// 径3pxの点は色相変更だけでは一瞥で沈むため(実物確認)、淡い橙グローを添えて声量を足す。
        /// アラートハロー(生成り)とは色相で声を分け、alphaはハローの内層(0.30)より明確に低くして
        /// 常時状態の光が一時的な呼びかけを埋もれさせないようにする(2026-07-19 タダシ承認)
        public static let calendarOngoing = PanelColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        public static let calendarOngoingGlow = PanelColor(
            red: 1.0, green: 0.66, blue: 0.28, alpha: 0.18)
        /// 連続稼働ゲージ: 溝は沈めた無彩色、火は金茶から始まり閾値に近づくほど朱へ燃える
        public static let gaugeTrack = PanelColor(red: 0.20, green: 0.20, blue: 0.17, alpha: 1)
        public static let gaugeStart = PanelColor(red: 0.67, green: 0.54, blue: 0.33, alpha: 1)
        public static let gaugeEnd = PanelColor(red: 0.855, green: 0.349, blue: 0.196, alpha: 1)
    }
}

public enum IconKind: Equatable, Sendable {
    case url
    case filePath
    case text
    case empty

    public static func classify(_ icon: String?) -> IconKind {
        guard let icon, !icon.isEmpty else { return .empty }
        if icon.hasPrefix("http://") || icon.hasPrefix("https://") { return .url }
        if icon.hasPrefix("/") || icon.hasPrefix("~/") { return .filePath }
        return .text
    }
}
