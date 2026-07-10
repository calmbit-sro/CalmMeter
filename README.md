# ClaudeUsage

A tiny macOS **menu-bar app** that keeps your current **Claude usage** in the menu
bar — the same data as Claude Code's `/usage` command: how much of your **5-hour**
and **weekly** rate-limit windows you've used, when they reset, and optionally a
per-model breakdown and spend.

![menu bar item: a coloured dot + percentage, with a dropdown showing 5h and weekly bars]

## Requirements

- **macOS 13** (Ventura) or newer.
- **Claude Code** installed and logged in on this Mac. The app reads the OAuth
  token Claude Code stores in your login keychain — if you've never signed in,
  run `claude` once first.
- To **build from source:** the Swift toolchain (Xcode or the Command Line Tools —
  `xcode-select --install`).

## Install

### Option A — download the DMG (easiest)

1. Grab `ClaudeUsage.dmg` from the [Releases](../../releases) page.
2. Open it and drag **Claude Usage** to **Applications**.
3. Launch it from Applications. If macOS warns it's from an unidentified
   developer, right-click the app → **Open** → **Open** (only needed once, and
   not at all if the DMG was notarized).

### Option B — build from source

```bash
git clone <this-repo> && cd claude-usage
swift test               # optional: run the unit tests
./scripts/build-app.sh   # produces ./ClaudeUsage.app
open ./ClaudeUsage.app

# or install into /Applications:
./scripts/build-app.sh --install
```

### First launch — keychain prompt

The first time it runs, macOS shows a keychain dialog asking for access to
**`Claude Code-credentials`**. Click **Always Allow**. (The app has a different
code signature than Claude Code, so macOS asks once.)

Nothing is sent anywhere except a request to the Anthropic API asking for *your
own* usage — the same call `/usage` makes. No analytics, no third parties.

## Using it

Click the menu-bar item to open the panel:

- **5h window** and **Weekly** utilization bars with reset countdowns
- **Refresh now**, **Preferences…**, **Quit**

### Preferences (everything is configurable)

- **Menu-bar format:** dot + 5h % (default) · 5h % only · `5h % · weekly %` · dot only
- **Refresh interval:** 30 s · 60 s (default) · 5 min
- **Launch at login** (on by default)
- **Per-model breakdown** in the panel (Opus/Sonnet…)
- **Colour thresholds** (green / orange / red)

## Building a signed DMG for distribution

`scripts/make-dmg.sh` builds, signs, and packages a `.dmg`. Sign it with your own
Apple **Developer ID** so it runs on other Macs.

```bash
# Auto-detects a "Developer ID Application" identity in your keychain:
./scripts/make-dmg.sh

# …or specify it explicitly:
./scripts/make-dmg.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

**Notarize** (recommended so users don't see Gatekeeper warnings). Store your
Apple ID credentials once, then pass the profile name:

```bash
xcrun notarytool store-credentials claude-usage \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

./scripts/make-dmg.sh --sign "Developer ID Application: Your Name (TEAMID)" \
                      --notarize claude-usage
```

Notes:
- App-specific password: create one at <https://account.apple.com> → Sign-In & Security.
- Change the bundle id with `--identifier your.bundle.id` if you like.
- Without a Developer ID the script falls back to an **ad-hoc** signature — that
  DMG runs only on the Mac that built it.

## How it works

- Reads the OAuth token from the login keychain (service `Claude Code-credentials`).
- Calls `GET https://api.anthropic.com/api/oauth/usage` with the bearer token.
- It does **not** refresh the token itself — Claude Code keeps it fresh; when it
  expires the app just shows a "run `claude`" hint.

## Project layout

- `Sources/ClaudeUsageCore/` — models, API client, keychain, polling store (unit-tested)
- `Sources/ClaudeUsage/` — the SwiftUI menu-bar app (`MenuBarExtra`)
- `Tests/ClaudeUsageCoreTests/` — unit tests + a sample API response fixture
- `scripts/build-app.sh` — assemble `ClaudeUsage.app`
- `scripts/make-dmg.sh` — build a signed (and optionally notarized) DMG

## Uninstall

Quit the app, delete `ClaudeUsage.app`, and remove it from **System Settings →
General → Login Items** if you enabled launch-at-login.
