#!/bin/bash
# Builds CalmMeter.app from the SwiftPM release binary.
# Usage: scripts/build-app.sh [--install]
#   --install  also copy the app into /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CalmMeter"
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

# Localizations (en/cs). Shipped in the main bundle so NSLocalizedString /
# SwiftUI Text pick them up per the system language.
for lproj in "$ROOT"/Resources/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Sign with a stable identity. A Developer ID (if present) gives the app a
# stable designated requirement, so the keychain "Always Allow" grant sticks and
# macOS stops re-prompting on every launch. Ad-hoc signatures aren't trusted the
# same way and cause repeated keychain password prompts — hence we prefer a real
# identity here, matching what make-dmg.sh does. Override with $SIGN_IDENTITY.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
                | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "› codesign (ad-hoc — no Developer ID found; macOS may re-prompt for keychain access)"
else
    echo "› codesign ($IDENTITY)"
fi
codesign --force --sign "$IDENTITY" --identifier com.calmbit.CalmMeter "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped/failed — app still runs, login-item may need manual toggle)"

echo "✓ built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/$APP_NAME.app"
    echo "› installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "✓ installed. Open with: open \"$DEST\""
fi
