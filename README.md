# CalmMeter

*A calm read on how much Claude Code you have left — right in your menu bar.*

CalmMeter is a tiny macOS **menu-bar app** that keeps your current **Claude Code
usage** in view — the same data as the `/usage` command: how much of your
**5-hour** and **weekly** rate-limit windows you've used, when they reset, and
optionally a per-model breakdown and spend. No more opening a terminal to check.

A [CalmBit](https://calmbit.cz) app.

![menu bar item: a coloured dot + percentage, with a dropdown showing 5h and weekly bars]

## Requirements

- **macOS 13** (Ventura) or newer.
- **Claude Code** installed and logged in on this Mac. CalmMeter reads the OAuth
  token Claude Code stores in your login keychain — if you've never signed in,
  run `claude` once first.
- To **build from source:** the Swift toolchain (Xcode or the Command Line Tools —
  `xcode-select --install`).

## Install

### Option A — download the DMG (easiest)

1. Grab `CalmMeter.dmg` from the [Releases](../../releases) page.
2. Open it and drag **CalmMeter** to **Applications**.
3. Launch it from Applications. If macOS warns it's from an unidentified
   developer, right-click the app → **Open** → **Open** (only needed once, and
   not at all if the DMG was notarized).

### Option B — build from source

```bash
git clone <this-repo> && cd calmmeter
swift test               # optional: run the unit tests
./scripts/build-app.sh   # produces ./CalmMeter.app
open ./CalmMeter.app

# or install into /Applications:
./scripts/build-app.sh --install
```

### First launch — keychain prompt

The first time it runs, macOS may show a keychain dialog asking for access to
**`Claude Code-credentials`**. Click **Allow**. CalmMeter then copies the token
into its **own** keychain item (`com.calmbit.CalmMeter.credentials`) and reads
from there afterwards, so it won't keep prompting on every launch — it only goes
back to Claude Code's item when the token stops working (roughly once per token
rotation).

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
xcrun notarytool store-credentials calmmeter \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

./scripts/make-dmg.sh --sign "Developer ID Application: Your Name (TEAMID)" \
                      --notarize calmmeter
```

Notes:
- App-specific password: create one at <https://account.apple.com> → Sign-In & Security.
- Change the bundle id with `--identifier your.bundle.id` if you like
  (default `com.calmbit.CalmMeter`).
- Without a Developer ID the script falls back to an **ad-hoc** signature — that
  DMG runs only on the Mac that built it.

## The app icon

`scripts/make-icon.py` renders the icon (a warm coral squircle with a usage-gauge
ring and a centre sunburst) at 1024px and builds `Resources/AppIcon.icns`. Tweak
the colours / fill in that script and re-run it to regenerate.

## How it works

- Reads the OAuth token from the login keychain (service `Claude Code-credentials`),
  then caches it in its own item so it doesn't re-prompt on every launch (see
  "First launch" above).
- Calls `GET https://api.anthropic.com/api/oauth/usage` with the bearer token.
- It does **not** refresh the token itself — Claude Code keeps it fresh. On a 401
  it re-reads Claude Code's item once; if that still fails it shows a
  "run `claude`" hint.
- On errors it backs off (honouring `Retry-After` for HTTP 429) and keeps showing
  the last known values instead of hammering the server.

> **Dev builds & signing:** `build-app.sh` signs with your Developer ID if it can
> find one (falling back to ad-hoc). A stable signature matters — ad-hoc builds
> get less predictable keychain behaviour.

## Project layout

- `Sources/CalmMeterCore/` — models, API client, keychain, polling store (unit-tested)
- `Sources/CalmMeter/` — the SwiftUI menu-bar app (`MenuBarExtra`)
- `Tests/CalmMeterCoreTests/` — unit tests + a sample API response fixture
- `scripts/build-app.sh` — assemble `CalmMeter.app`
- `scripts/make-dmg.sh` — build a signed (and optionally notarized) DMG
- `scripts/make-icon.py` — regenerate the app icon

## Uninstall

Quit the app, delete `CalmMeter.app`, and remove it from **System Settings →
General → Login Items** if you enabled launch-at-login.

---

CalmMeter is an independent tool and is not affiliated with or endorsed by Anthropic.
"Claude" and "Claude Code" are trademarks of Anthropic.
