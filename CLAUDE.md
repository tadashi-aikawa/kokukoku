# CLAUDE

## コミットメッセージ

Conventional Commits 形式で日本語で書く。

### フォーマット

```
<type>(<scope>): <description>
```

- `type`: `feat`, `fix`, `refactor`, `style`, `docs`, `chore`, `build`, `ci`, `test`
  - 破壊的変更がある場合は `feat!` のように `!` を付ける
- `scope`: `timer_engine`, `ui_panel`, `alert`, `persistence` など機能単位 (省略可)
- `description`: ユーザー視点で何が変わったかを簡潔に書く

### description の書き方

- ユーザーにとって何が変わるかを書く (実装詳細ではなく体験の変化)
- 「〜を追加」「〜を修正」「〜に変更」のように結果を述べる
- 内部的なリファクタリングの場合のみ実装視点で書いてよい

## テスト実行

ユニットテストはリポジトリルートで以下を実行します。

```bash
busted
```

必要に応じて個別実行も可能です。

```bash
busted spec/timer_engine_spec.lua
busted spec/persistence_spec.lua
```

## リリース方法

GitHub Actions の `Release` workflow を `main` ブランチから手動実行します。

semantic-release が前回のタグ以降の Conventional Commits から次のバージョンを決定し、`v<バージョン>` タグ、リリースノート、`Kokukoku.spoon.zip` を含む GitHub Release を作成します。リリース対象となるコミットがなければ何も公開しません。

`Kokukoku.spoon/init.lua` の追跡中のバージョンは `0.0.0-development` のまま維持し、リリースバージョンは配布 ZIP 内にだけ埋め込みます。
