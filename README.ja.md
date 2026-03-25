<div align="center">
    <h1>KOKUKOKU</h1>
    <img src="./kokukoku.webp" width="256" />
    <p>
    <h3>刻刻</h3>
    <div>プロジェクトごとの作業時間を計測するHammerspoon Spoon</div>
    </p>
    <p>
        <a href="./README.md">English</a> | 日本語
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
- **カスタマイズ**: プロジェクトのアイコン（絵文字、URL、ファイルパス）、名前、フォントを設定可能

## セットアップ

### 前提準備

まだ Hammerspoon をインストールしていない場合:

```bash
brew install --cask hammerspoon
open -a Hammerspoon
```

続いて SpoonInstall をインストール:

```bash
mkdir -p ~/.hammerspoon/Spoons
curl -L https://github.com/Hammerspoon/Spoons/raw/master/Spoons/SpoonInstall.spoon.zip -o /tmp/SpoonInstall.spoon.zip
unzip -o /tmp/SpoonInstall.spoon.zip -d ~/.hammerspoon/Spoons
```

### SpoonInstall でインストール（推奨）

`~/.hammerspoon/init.lua` に以下を追加:

```lua
hs.loadSpoon("SpoonInstall")

spoon.SpoonInstall.repos.kokukoku = {
  url = "https://github.com/tadashi-aikawa/kokukoku",
  desc = "KOKUKOKU Spoon repository",
  branch = "spoons",
}

spoon.SpoonInstall:andUse("Kokukoku", {
  repo = "kokukoku",
  fn = function(s)
    s:setup({
      projects = {
        { id = "work", name = "Work", icon = "💼" },
        { id = "meeting", name = "Meeting", icon = "🗓" },
        { id = "break", name = "Break", icon = "☕", isBreak = true },
      },
      hotkey = { modifiers = { "alt" }, key = "t" },
    })
  end,
})
```

> [!TIP]
> 特定のバージョンをインストールするには、`branch` の値を `spoons-v{バージョン}` に変更してください（例: `"spoons-v0.3.0"`）。
> Spoonは初回インストール時のみダウンロードされ、以降の起動ではローカルからロードされます。

インストール済みの Spoon を更新する場合（Hammerspoon Console で1回だけ実行）:

```lua
spoon.SpoonInstall:updateRepo("kokukoku")
spoon.SpoonInstall:installSpoonFromRepo("Kokukoku", "kokukoku")
hs.reload()
```

> [!WARNING]
> この3行を `~/.hammerspoon/init.lua` に置くと、`hs.reload()` によって再読込のたびに再実行されてループします。`init.lua` には常駐設定のみを書き、更新時だけ Console から手動実行してください。

### ソースからインストール（開発向け）

```bash
git clone https://github.com/tadashi-aikawa/kokukoku /path/to/kokukoku
ln -sfn /path/to/kokukoku/Kokukoku.spoon ~/.hammerspoon/Spoons/Kokukoku.spoon
```

`~/.hammerspoon/init.lua` に以下を追加:

```lua
hs.loadSpoon("Kokukoku")

spoon.Kokukoku:setup({
  projects = {
    { id = "work", name = "Work", icon = "💼" },
    { id = "meeting", name = "Meeting", icon = "🗓" },
    { id = "break", name = "Break", icon = "☕", isBreak = true },
  },
  hotkey = { modifiers = { "alt" }, key = "t" },
})
```

更新する場合:

```bash
git -C /path/to/kokukoku pull
```

## 設定例

```lua
hs.loadSpoon("Kokukoku")

spoon.Kokukoku:setup({
  projects = {
    { id = "dev", name = "Development", icon = "💻" },
    { id = "review", name = "Code Review", icon = "👀" },
    { id = "meeting", name = "Meeting", icon = "🗓" },
    { id = "docs", name = "Documentation", icon = "📝" },
    { id = "break", name = "Break", icon = "☕", isBreak = true },
  },
  hotkey = {
    modifiers = { "alt" },
    key = "t",
  },
  ui = {
    fontName = "HackGen Console NF",
    monoFontName = "HackGen Console NF",
  },
  alert = {
    continuousWork = {
      thresholds = { 1500, 3000, 4500 },
      message = "%d分経過しました。休憩しましょう",
    },
  },
  persistence = {
    path = os.getenv("HOME") .. "/.kokukoku/state.json",
  },
  tickInterval = 1,
})
```

## 設定オプション

全設定を含むサンプル（デフォルト値）:

```lua
{
  -- プロジェクト定義（必須）
  projects = {
    {
      id = "work",       -- 一意の文字列識別子（必須）
      name = "Work",     -- 表示名（必須）
      icon = "💼",       -- 絵文字テキスト、画像URL (http/https)、ファイルパス (/ or ~/)（省略可）
      isBreak = false,   -- trueで休憩プロジェクト扱い（省略可）
    },
  },

  -- パネル表示/非表示のトグルホットキー（省略可。省略するとホットキー無効）
  hotkey = {
    modifiers = { "alt" }, -- 修飾キー
    key = "t",             -- キー
  },

  -- UI設定（省略可）
  ui = {
    fontName = ".AppleSystemUIFont",  -- テキスト用フォント（デフォルト: システムフォント）
    monoFontName = "Menlo",           -- 時間表示用等幅フォント（デフォルト: Menlo）
  },

  -- アラート設定（省略可）
  alert = {
    continuousWork = {
      thresholds = {},                              -- アラート閾値（秒）（例: { 1500, 3000 }）
      message = "%d分経過しました。休憩しましょう",    -- メッセージテンプレート（%d = 分数）
    },
  },

  -- 永続化設定（省略可）
  persistence = {
    path = "~/.kokukoku/state.json", -- タイマー状態の保存先ファイルパス
  },

  -- タイマーのティック間隔（秒、デフォルト: 1）
  tickInterval = 1,
}
```

### アイコンの種類

プロジェクト定義の `icon` フィールドは3つの形式に対応しています:

| 形式 | 例 | 説明 |
|------|-----|------|
| 絵文字 | `"💼"` | テキストとして表示 |
| URL | `"https://example.com/icon.png"` | ダウンロードして画像として表示 |
| ファイルパス | `"/path/to/icon.png"` or `"~/icons/work.png"` | ローカルファイルから読み込み |

## キーボードショートカット

パネル表示中に使用できるショートカット:

| キー | 動作 |
|------|------|
| `1`-`9` | 対応するプロジェクトを選択 |
| `j` / `Down` | 選択を下に移動 |
| `k` / `Up` | 選択を上に移動 |
| `Enter` | 選択中のアクションを実行 |
| `0` | 休憩 |
| `e` | 選択中プロジェクトの累積時間を編集 |
| `E` | 初期待機中や休憩中も含めて連続稼働時間を編集 |
| `c` | 測定結果を箇条書きテキストとしてクリップボードにコピー |
| `r` | リセット確認に入る。もう一度押すと全タイマーをリセット |
| `Escape` | パネルを閉じる |

休憩に入ると連続稼働時間は `00:00:00` にリセットされます。初期待機中や休憩中に編集した値は、次にプロジェクトを開始したときの連続稼働時間として引き継がれます。

## 開発

ソースから symlink で導入しておくと、`Kokukoku.spoon/` 配下の変更を Hammerspoon の `Reload Config` ですぐ確認できます。

## テスト

ユニットテストは `busted` で実行します。

```bash
busted
```

特定のテストだけ実行したい場合:

```bash
busted spec/timer_engine_spec.lua
busted spec/persistence_spec.lua
```

## ライセンス

MIT
