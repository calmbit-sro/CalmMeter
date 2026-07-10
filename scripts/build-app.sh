#!/bin/bash
# Builds ClaudeUsage.app from the SwiftPM release binary.
# Usage: scripts/build-app.sh [--install]
#   --install  also copy the app into /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClaudeUsage"
APP="$ROOT/$APP_NAME.app"

echo "› swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "error: built binary not found at $BIN" >&2
    exit 1
fi

echo "› assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  (no AppIcon.icns — run scripts/make-icon.py to generate it)"
fi

# Ad-hoc signature: required for SMAppService (launch-at-login) to register,
# and keeps the keychain ACL stable across rebuilds of the same path.
echo "› codesign (ad-hoc)"
codesign --force --sign - --identifier cz.petrhlozek.ClaudeUsage "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped/failed — app still runs, login-item may need manual toggle)"

echo "✓ built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/$APP_NAME.app"
    echo "› installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "✓ installed. Open with: open \"$DEST\""
fi
