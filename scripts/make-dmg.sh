#!/bin/bash
# Builds a distributable, signed CalmMeter.dmg.
#
# Usage:
#   scripts/make-dmg.sh [--sign "Developer ID Application: NAME (TEAMID)"] \
#                       [--notarize <notary-profile>] [--identifier <bundle-id>]
#
# Signing identity resolution (first match wins):
#   1. --sign "..."           explicit identity string
#   2. $SIGN_IDENTITY         environment variable
#   3. auto-detect the single "Developer ID Application" in your keychain
#   4. fall back to ad-hoc ("-") — DMG will NOT pass Gatekeeper on other Macs
#
# Notarization (optional, needs an Apple ID):
#   First store credentials once:
#     xcrun notarytool store-credentials claude-usage \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#   Then pass:  --notarize claude-usage
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CalmMeter"
VOL_NAME="CalmMeter"
APP="$ROOT/$APP_NAME.app"
DMG="$ROOT/$APP_NAME.dmg"
IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE=""
BUNDLE_ID="com.calmbit.CalmMeter"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) IDENTITY="$2"; shift 2 ;;
        --notarize) NOTARY_PROFILE="$2"; shift 2 ;;
        --identifier) BUNDLE_ID="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

# --- resolve signing identity -------------------------------------------------
if [[ -z "$IDENTITY" ]]; then
    found="$(security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
    if [[ -n "$found" ]]; then
        IDENTITY="$found"
        echo "› auto-detected identity: $IDENTITY"
    else
        IDENTITY="-"
        echo "⚠ no Developer ID found — signing ad-hoc; the DMG will only run on THIS Mac."
        echo "  Pass --sign \"Developer ID Application: NAME (TEAMID)\" to sign for distribution."
    fi
fi

# --- build & assemble the .app ------------------------------------------------
echo "› building app bundle"
"$ROOT/scripts/build-app.sh" >/dev/null

# --- (re)sign with the distribution identity + hardened runtime ---------------
echo "› codesign app  ($IDENTITY)"
CS_OPTS=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$IDENTITY" != "-" ]]; then
    CS_OPTS+=(--options runtime --timestamp)
fi
codesign "${CS_OPTS[@]}" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP" || true

# --- build the DMG ------------------------------------------------------------
echo "› creating $APP_NAME.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ "$IDENTITY" != "-" ]]; then
    echo "› codesign dmg"
    codesign --force --sign "$IDENTITY" "$DMG"
fi

# --- optional notarization ----------------------------------------------------
if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "› notarizing (profile: $NOTARY_PROFILE) — this can take a few minutes"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "› stapling ticket"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

echo "✓ built $DMG"
[[ "$IDENTITY" == "-" ]] && echo "  (ad-hoc — for a shareable build, sign with a Developer ID and notarize)"
