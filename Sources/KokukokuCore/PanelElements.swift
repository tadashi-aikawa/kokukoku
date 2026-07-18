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
    /// ネオン管風の角丸縁取り(芯のstroke+外側ににじむグロー)。計測中行の合図に使う
    case neonRectangle(
        frame: PanelFrame,
        cornerRadius: Double,
        strokeColor: PanelColor,
        strokeWidth: Double,
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
    case image(frame: PanelFrame, iconKey: String, scaling: PanelImageScaling)
}

/// パネル上でインライン編集中の時間。編集中は該当の時刻テキストを描画せず、
/// Platform側がその位置に編集フィールドを重ねる。
public enum PanelEditingTarget: Equatable, Sendable {
    case project(id: String)
    case continuous
}

public enum PanelLayout {
    public static let panelWidth = 420.0
    /// ヘッダー(現在時刻段: アナログ+デジタル時計)の高さ = プロジェクト行の開始位置
    public static let clockSectionHeight = 72.0
    public static let rowHeight = 36.0
    public static let footerHeight = 40.0
    public static let padding = 12.0
    public static let projectContentX = padding + 22
    public static let projectNameRight = 232.0
    public static let iconTextWidth = 24.0
    public static let iconImageSize = 20.0
    public static let iconGap = 8.0
    public static let iconSlotWidth = 24.0
    public static let headerLogoSize = 28.0
    public static let headerLogoTextGap = 6.0
    public static let headerTimeWidth = 90.0
    public static let timeColumnX = 240.0
    public static let timeColumnWidth = 100.0
    public static let colors = Colors.self

    /// アナログ時計の文字盤半径と中心(ヘッダーの中でデジタルと合わせて中央寄せ)
    public static let clockRadius = 28.0
    public static let clockDigitalFontSize = 30.0
    public static let clockDigitalWidth = 150.0
    public static let clockDigitalGap = 12.0
    public static let clockCenter = PanelPoint(
        x: (panelWidth - clockRadius * 2 - clockDigitalGap - clockDigitalWidth) / 2 + clockRadius,
        y: clockSectionHeight / 2)
    public static let clockDigitalFrame = PanelFrame(
        x: clockCenter.x + clockRadius + clockDigitalGap,
        y: clockSectionHeight / 2 - 18, w: clockDigitalWidth, h: 36)

    /// フッター中央の連続稼働時間テキストの枠(インライン編集フィールドもここへ重ねる)
    public static func continuousTimeFrame(projectCount: Int) -> PanelFrame {
        let footerY = clockSectionHeight + Double(projectCount) * rowHeight
        return .init(
            x: (panelWidth - headerLogoSize - headerLogoTextGap - headerTimeWidth) / 2
                + headerLogoSize + headerLogoTextGap,
            y: footerY + 10, w: headerTimeWidth, h: 28)
    }

    /// プロジェクト行の累積時間テキストの枠(同上)
    public static func accumulatedTimeFrame(rowOffset: Int) -> PanelFrame {
        .init(
            x: timeColumnX, y: clockSectionHeight + Double(rowOffset) * rowHeight,
            w: timeColumnWidth, h: rowHeight)
    }

    public static func panelHeight(projectCount: Int) -> Double {
        clockSectionHeight + Double(projectCount) * rowHeight + footerHeight
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
        public static let switchSuccessBg = PanelColor(red: 0.42, green: 0.33, blue: 0.17, alpha: 1)
        public static let footerBg = PanelColor(red: 0.10, green: 0.10, blue: 0.09, alpha: 1)
        public static let footerHoverBg = PanelColor(red: 0.19, green: 0.19, blue: 0.17, alpha: 1)
        public static let text = PanelColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 1)
        public static let subText = PanelColor(red: 0.62, green: 0.57, blue: 0.47, alpha: 1)
        public static let activeText = PanelColor(red: 1.0, green: 0.80, blue: 0.50, alpha: 1)
        /// ネオン縁取りの芯(明るい橙金)とグロー(朱寄りの炎色)
        public static let neonStroke = PanelColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1)
        public static let neonGlow = PanelColor(red: 0.92, green: 0.38, blue: 0.16, alpha: 0.9)
        public static let separator = PanelColor(red: 0.29, green: 0.28, blue: 0.24, alpha: 1)
        public static let resetConfirmBg = PanelColor(red: 0.48, green: 0.10, blue: 0.10, alpha: 1)
        /// パネル外周の縁取り(暗い背景でも輪郭が分かるよう生成りの低アルファ)
        public static let panelBorder = PanelColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 0.28)
        public static let clockSecondHand = PanelColor(
            red: 0.855, green: 0.349, blue: 0.196, alpha: 1)
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
