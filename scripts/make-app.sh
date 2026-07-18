#!/usr/bin/env bash
# swift build → KOKUKOKU.app 組み立て → 署名
# 使い方: ./scripts/make-app.sh [debug|release] [version]
set -euo pipefail

CONFIG="${1:-debug}"
VERSION="${2:-0.0.0-development}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/KOKUKOKU.app"

swift build --package-path "$ROOT" -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/Kokukoku"
RESOURCE_BUNDLE="$ROOT/.build/$CONFIG/Kokukoku_Kokukoku.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KOKUKOKU"
sed "s/0\.0\.0-development/$VERSION/" "$ROOT/Resources/Info.plist" >"$APP/Contents/Info.plist"
cp "$ROOT/Resources/kokukoku.icns" "$APP/Contents/Resources/"
# SwiftPMのリソースバンドル(ロゴ画像)。Bundle.module が Contents/Resources から解決する
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

# 署名: CODESIGN_IDENTITY(デフォルト "kokukoku-dev")の自己署名証明書が Keychain に
# あればそれを使う(署名が固定され、KeychainアクセスやTCC許可が更新でも維持される)。
# なければ ad-hoc 署名(ローカル開発用)。
# 自己署名のコード署名証明書は「信頼」設定が無くても署名に使えるため、
# find-identity は -v(valid のみ)を付けずに検索する。
# --timestamp=none: 自己署名は Apple のタイムスタンプサーバを使えない
IDENTITY="${CODESIGN_IDENTITY:-kokukoku-dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" &&
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP" 2>/dev/null; then
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Signed with: ad-hoc"
fi

echo "Built: $APP"
echo "Run:   open '$APP'"
