# CLAUDE

## リポジトリ構成

macOS ネイティブアプリ (Swift) です。元は Hammerspoon Spoon (Lua) で、2026-07 に移行しました。

- `Sources/KokukokuCore/`: 純粋ロジック層 (ユニットテストの主戦場)
- `Sources/Kokukoku/`: 実行ターゲット (AppKit)
- `Tests/KokukokuCoreTests/`: ユニットテスト (swift-testing)
- `Resources/`: アプリバンドル用の Info.plist・アイコン
- `scripts/`: アプリバンドル組み立て (`make-app.sh`)・リリース成果物 (`build_release.sh`)・Homebrew tap 更新 (`update_tap.sh`)

設定は `~/.config/kokukoku/config.toml` (TOML)、タイマー状態は `~/.local/state/kokukoku/state.json` を使います。

## コミットメッセージ

Conventional Commits 形式で日本語で書く。

### フォーマット

```
<type>(<scope>): <description>
```

- `type`: `feat`, `fix`, `refactor`, `style`, `docs`, `chore`, `build`, `ci`, `test`
  - 破壊的変更がある場合は `feat!` のように `!` を付ける
  - 見た目だけの変更 (余白・色・サイズなど挙動が変わらないもの) は `feat` ではなく `style` を使う
  - 判定基準: **読み取れる情報や挙動が変わるなら `feat`、同じ情報の見せ方 (余白・色・サイズ・形・表現替え) だけなら `style`。迷ったら `feat`**
    - 例: 進行中の予定を区別表示できるようにする=新しい情報が読み取れる→ `feat` / 計測中ラベルをネオン縁取りに替える=同じ情報の表現替え→ `style`
    - 挙動変更と見た目調整が混在するコミットは `feat`
- ユーザーから見て1つの対応は1コミットにまとめる (タダシとのやりとりで生じた調整・手直しは分けず統合する)
- `scope`: `timer_engine`, `ui_panel`, `alert`, `persistence` など機能単位 (省略可)
- `description`: ユーザー視点で何が変わったかを簡潔に書く
- AI Agent (owlery) がコミットする場合は `--author="<名前> <slug@owlery.local>"` で author を自分の Agent 名にする (committer はデフォルトのまま)

### description の書き方

- ユーザーにとって何が変わるかを書く (実装詳細ではなく体験の変化)
- 「〜を追加」「〜を修正」「〜に変更」のように結果を述べる
- 内部的なリファクタリングの場合のみ実装視点で書いてよい

## テスト実行

ビルド・ユニットテストはリポジトリルートで以下を実行します。

```bash
swift build
swift test
```

動作確認は `swift run Kokukoku` (即パネル表示は `--show-panel` 付き) で行います。予定の開始前・終了前通知の見た目 (対象の点のハロー・入場パルス) は `--test-calendar-notification` 付きで起動すると、次の未開始予定 (開始前) と進行中の先頭予定 (終了前) を使って通知時刻を待たずに確認できます。
通知まわり (アイコン表示・クリックでパネル起動) はバンドル実行が前提のため、`./scripts/make-app.sh` で組んだ `.build/KOKUKOKU.app` で確認します (テスト通知は `--test-notification` 付きで起動)。日常利用も `.app` 起動を標準とします。

## リリース方法

GitHub Actions の `Release` workflow を `main` ブランチから手動実行します。

semantic-release が前回のタグ以降の Conventional Commits から次のバージョンを決定し、`v<バージョン>` タグ、リリースノート、`KOKUKOKU-<バージョン>.zip` (署名済み KOKUKOKU.app) を含む GitHub Release を作成し、homebrew-tap の Cask (`kokukoku`) を更新します。リリース対象となるコミットがなければ何も公開しません。

- 署名は自己署名証明書 `kokukoku-dev` で固定します (repo secrets: `MACOS_CERT_P12_BASE64` / `MACOS_CERT_PASSWORD`)。Keychain アクセスや TCC 許可をリリースをまたいで維持するためです
- tap 更新には repo secret `TAP_GITHUB_TOKEN` (homebrew-tap への Contents: Read and write 権限の fine-grained PAT) を使います
- `Resources/Info.plist` の追跡中のバージョンは `0.0.0-development` のまま維持し、リリースバージョンは配布 ZIP 内にだけ埋め込みます
