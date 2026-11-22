import Foundation

/// 「設定ファイルを開く」で、設定ファイルが無いときに書き出す雛形。
/// 項目はすべてコメントアウトしてあり、そのまま読み込むとファイルが無いときと同じ既定の設定になる
public enum DefaultConfigTemplate {
    public static let text = """
        # KOKUKOKU の設定ファイル
        # 使う項目のコメントを外して編集し、メニューの「設定を再読込」で反映します。
        # 全オプションの説明: https://github.com/tadashi-aikawa/kokukoku#設定

        # プロジェクト定義
        # [[projects]]
        # id = "work"    # 一意な文字列ID (必須)
        # name = "Work"  # 表示名 (必須)
        # icon = "💼"    # 絵文字、画像URL (http/https)、ファイルパス (/ か ~/) (任意)

        # パネル表示のホットキー (省略時は無効)
        # [hotkey]
        # modifiers = ["alt"]  # 修飾キー: "command"/"cmd", "option"/"alt", "control"/"ctrl", "shift"
        # key = "t"            # キー: 文字 または "f18" などのキー名

        # UI設定
        # [ui]
        # fontName = ".AppleSystemUIFont"             # テキストのフォント (デフォルト: システムフォント)
        # copyTextFormat = "- {name}: {hh}:{mm}:{ss}" # クリップボードコピーの行フォーマット
        # panelMinWidth = 420                         # パネルの最小幅 (300以上)
        # panelMaxWidth = 480                         # パネルの最大幅 (panelMinWidth以上)

        # パネルのキーマップ設定
        # [keymap]
        # startBreak = "0"     # 休憩開始
        # reset = "r"          # リセット確認
        # toggleCalendar = "o" # 予定の展開/畳むトグル

        # アラート設定
        # [alert.continuousWork]
        # thresholds = [1500, 3000, 4500]              # アラート閾値 (秒)
        # message = "%d分経過しました。休憩しましょう" # メッセージテンプレート (%d = 分)

        # カレンダー連携 (省略時は連携無効・カレンダーへの権限要求もしない)
        # [calendar]
        # name = "一般"                     # 対象カレンダー名 (必須)
        # refreshIntervalMinutes = 5        # 定期更新の間隔 (分)
        # notificationLeadMinutes = 5       # 予定開始の何分前に通知するか
        # endNotificationLeadMinutes = 5    # 進行中予定の終了の何分前に通知するか (省略時は通知しない)
        # maxVisibleEvents = 2              # 展開前に表示する予定数の上限
        # gapRailMinutes = 1                # タイムラインのレールを表示する最小間隔 (分)
        # upcomingCountdownMaxMinutes = 120 # 未開始予定の「あと◯◯」を表示する残り時間の上限 (分)
        # ongoingCountdownMaxMinutes = 30   # 進行中予定の「終了まで◯◯」を表示する残り時間の上限 (分)
        # ignoreTitles = ["確保"]           # 無視する予定名 (完全一致)

        """
}

public enum ConfigFileError: LocalizedError, Equatable {
    case brokenSymlink(path: String)

    public var errorDescription: String? {
        switch self {
        case .brokenSymlink(let path):
            return "設定ファイルのシンボリックリンクのリンク先がありません: \(path)"
        }
    }
}

extension ConfigLoader {
    /// 設定ファイルがシンボリックリンクで、リンク先が無いか
    /// (dotfiles 管理などでリンクにしている場合、雛形で実体を作るとリンクを潰す)
    public static func isBrokenSymlink(_ url: URL) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeSymbolicLink
        else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// ファイルが無ければ雛形を書き出す。リンク切れのときは作らずにエラーにする
    public static func ensureConfigFileExists(at url: URL = defaultPath()) throws {
        if isBrokenSymlink(url) {
            throw ConfigFileError.brokenSymlink(path: url.path)
        }
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeTemplateWithoutOverwriting(to: url)
    }

    /// 同じディレクトリの一時ファイルへ最後まで書いてから、link(2) で最終のパスへ配置する。
    /// 途中までのファイルを最終のパスに残さず、存在を確かめてから配置するまでに
    /// 別のプロセスがファイルやリンクを作っても置き換えない。
    /// できていたファイルはそのまま使い、リンク先の無いリンクだけエラーにする。一時ファイルは必ず消す
    static func writeTemplateWithoutOverwriting(
        to url: URL, place: (_ from: URL, _ to: URL) throws -> Void = linkWithoutOverwriting
    ) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Data(DefaultConfigTemplate.text.utf8).write(
            to: temporaryURL, options: .withoutOverwriting)

        do {
            try place(temporaryURL, url)
        } catch POSIXError.EEXIST {
            if isBrokenSymlink(url) {
                throw ConfigFileError.brokenSymlink(path: url.path)
            }
        }
    }

    /// 既存のパス(リンク切れのシンボリックリンクも含む)を置き換えない原子的な配置。あれば EEXIST
    static func linkWithoutOverwriting(from source: URL, to destination: URL) throws {
        guard link(source.path, destination.path) != 0 else { return }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
