<div align="center">
    <h1>KOKUKOKU</h1>
    <img src="./kokukoku.webp" width="256" />
    <p>
    <h3>刻刻</h3>
    <div>プロジェクトごとの作業時間を計測するmacOSネイティブアプリ</div>
    </p>
    <p>
        <a href="https://github.com/tadashi-aikawa/kokukoku/actions/workflows/ci.yml">
          <img src="https://github.com/tadashi-aikawa/kokukoku/actions/workflows/ci.yml/badge.svg" alt="CI" />
        </a>
        <a href="https://github.com/tadashi-aikawa/kokukoku/blob/main/LICENSE">
          <img src="https://img.shields.io/github/license/tadashi-aikawa/kokukoku" alt="License" />
        </a>
    </p>
</div>

---

- **タイマー**: プロジェクトごとの作業時間を個別に計測
- **UIパネル**: マウスカーソルのあるスクリーン中央にパネルを表示し、プロジェクト選択と経過時間を確認
- **連続時間表示**: 連続作業時間は常に `HH:MM:SS` で表示し、初期待機・休憩中・リセット直後は `00:00:00`
- **アラート**: 連続作業時間が設定した閾値を超えるとmacOS通知を送信
- **永続化**: タイマーの状態をJSONに保存し、再起動後も継続
- **クリップボードコピー**: 測定結果を箇条書きテキストとしてクリップボードにコピー
- **キーボード操作**: 数字キーでプロジェクト選択、j/kや矢印キーで移動、0で休憩、rで確認付きリセット
- **インライン時間編集**: 累積時間・連続作業時間をパネル上で直接編集
- **カスタマイズ**: プロジェクトのアイコン（絵文字、URL、ファイルパス）、名前、フォントを設定可能

## セットアップ

### Homebrew でインストール（推奨）

```bash
brew install --cask tadashi-aikawa/tap/kokukoku
open -a KOKUKOKU
```

> [!NOTE]
> KOKUKOKU は自己署名（未公証）アプリです。初回起動がブロックされた場合は、
> システム設定 → プライバシーとセキュリティ → 「このまま開く」で許可してください。

ログイン時に自動起動するには、システム設定 → 一般 → ログイン項目と機能拡張 → ログイン時に開く に KOKUKOKU を追加してください。

アップデート:

```bash
brew upgrade --cask kokukoku
```

### 手動でインストール

[Releases](https://github.com/tadashi-aikawa/kokukoku/releases/latest) から `KOKUKOKU-<version>.zip` をダウンロード・展開し、`KOKUKOKU.app` を `/Applications` に移動します。その後、quarantine属性を除去してください:

```bash
xattr -dr com.apple.quarantine /Applications/KOKUKOKU.app
```

（Homebrew 経由なら不要）

## 設定

KOKUKOKU は起動時に `~/.config/kokukoku/config.toml` を読み込みます。編集後はステータスバーメニューの「設定を再読込」で反映できます。

```toml
[[projects]]
id = "dev"
name = "開発"
icon = "💻"

[[projects]]
id = "meeting"
name = "ミーティング"
icon = "🗓"

[hotkey]
modifiers = ["alt"]
key = "t"
```

### 設定オプション

全オプションを含む完全なサンプル（デフォルト値）:

```toml
# プロジェクト定義 (必須)
[[projects]]
id = "work"    # 一意な文字列ID (必須)
name = "Work"  # 表示名 (必須)
icon = "💼"    # 絵文字、画像URL (http/https)、ファイルパス (/ か ~/) (任意)

# パネル表示のホットキー (任意。省略時は無効)
[hotkey]
modifiers = ["alt"]  # 修飾キー: "command"/"cmd", "option"/"alt", "control"/"ctrl", "shift"
key = "t"            # キー: 文字 または "f18" などのキー名

# UI設定 (任意)
[ui]
fontName = ".AppleSystemUIFont"             # テキストのフォント (デフォルト: システムフォント)
copyTextFormat = "- {name}: {hh}:{mm}:{ss}" # クリップボードコピーの行フォーマット

# パネルのキーマップ設定 (任意)
[keymap]
startBreak = "0" # 休憩開始
reset = "r"      # リセット確認

# アラート設定 (任意)
[alert.continuousWork]
thresholds = [1500, 3000, 4500]              # アラート閾値 (秒)
message = "%d分経過しました。休憩しましょう" # メッセージテンプレート (%d = 分)

# カレンダー連携 (任意。省略時は連携無効・カレンダーへの権限要求もしない)
[calendar]
name = "一般"               # 対象カレンダー名 (必須。Googleカレンダー上の表示名と一致させる)
refreshIntervalMinutes = 5  # 定期更新の間隔 (分)
notificationLeadMinutes = 5 # 予定開始の何分前に通知するか
maxAttendees = 5            # 予定行に表示する参加者数の上限 (超過分は「他◯人」)
maxVisibleEvents = 3        # 展開前に表示する予定数の上限 (超過分は「他◯件」。クリックで全件展開)
selfEmail = "you@example.com" # 自分のメールアドレス (任意。参加者一覧から自分を除外)
```

カレンダー連携は macOS のカレンダー (EventKit) を経由します。システム設定 > インターネットアカウントに Google アカウントを追加しておいてください。Google カレンダー側の変更が反映されるまで数分 (実測 3〜4 分) かかるため、`notificationLeadMinutes` を 5 分より短くすると直前の予定変更を拾えない可能性があります。

タイマーの状態は `~/.local/state/kokukoku/state.json` に保存されます。

### コピーフォーマットのプレースホルダ

`copyTextFormat` で使用できるプレースホルダ:

| プレースホルダ | 説明 | 例 (3665秒の場合) |
|-------------|------|------------------|
| `{name}` | プロジェクト名 | `Work` |
| `{hh}` | 時間 (ゼロ埋め) | `01` |
| `{mm}` | 分 (ゼロ埋め) | `01` |
| `{ss}` | 秒 (ゼロ埋め) | `05` |
| `{h}` | 時間 | `1` |
| `{m}` | 分 | `1` |
| `{s}` | 秒 | `5` |

### アイコンの種類

プロジェクト定義の `icon` は3つの形式に対応:

| 形式 | 例 | 説明 |
|------|-----|------|
| 絵文字 | `"💼"` | テキストとして表示 |
| URL | `"https://example.com/icon.png"` | ダウンロードして画像表示 |
| ファイルパス | `"/path/to/icon.png"` や `"~/icons/work.png"` | ローカルファイルから読み込み |

## キーボードショートカット

パネル表示中に使用できるショートカット:

#### 固定キー

| キー | 動作 |
|------|------|
| `1`-`9` | 対応するプロジェクトを選択（計測中のプロジェクトなら休憩へ） |
| `j` / `Down` | 選択を下へ移動 |
| `k` / `Up` | 選択を上へ移動 |
| `Enter` | 選択中のアクションを実行 |
| `Escape` | パネルを閉じる |
| `e` | 選択中プロジェクトの累積時間を編集 |
| `E` | 連続作業時間を編集（初期待機・休憩中でも可） |
| `c` | 測定結果を箇条書きテキストとしてクリップボードにコピー |

#### 設定可能キー（`keymap` でカスタマイズ可能）

| キー (デフォルト) | 設定キー | 動作 |
|------------------|----------|------|
| `0` | `startBreak` | 休憩 |
| `r` | `reset` | リセット確認へ。もう一度押すと全タイマーをリセット |

計測中のプロジェクトを再選択（数字キー・`Enter`・クリックのいずれでも）すると、トグルとして休憩に入ります。

時間編集はパネル上のインライン編集です。`e` か `E` を押し、`01:23:45`（`83:45` や秒数だけでも可）のように入力して `Enter` で確定、`Escape` でキャンセルします。

休憩に入ると連続作業時間は `00:00:00` にリセットされます。初期待機・休憩中に連続作業時間を編集した場合、その値は次のプロジェクト開始時に引き継がれます。

## 開発

```bash
swift run Kokukoku               # 直接実行
swift run Kokukoku --show-panel  # 起動と同時にパネルを表示
./scripts/make-app.sh            # KOKUKOKU.app を .build/ に組み立て
```

通知のアイコン表示・クリックでのパネル起動はバンドル実行 (`KOKUKOKU.app`) でのみ有効です。直接実行では簡易通知 (osascript) になります。テスト通知は `--test-notification` 付きの起動で送れます。

## テスト

```bash
swift test
```

## ライセンス

MIT
