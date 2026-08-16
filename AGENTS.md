# AGENTS.md

<!-- claude-leverage:agents-md START -->

## Project

`CalmMeter` is a macOS menu-bar app that shows Claude Code usage — the same data as the `/usage` command (5-hour / weekly rate-limit windows, reset countdowns, per-model breakdown) — read via the OAuth token Claude Code stores in the login keychain. A CalmBit app.
**Stack**: Swift 5.9, pure SwiftPM (no Xcode project), SwiftUI `MenuBarExtra`, macOS 13+. **Runtime**: native macOS menu-bar agent, distributed as a signed + notarized DMG (bundle id `com.calmbit.CalmMeter`).

## Reading order for new agents

1. **This file** (you're here).
2. [`docs/adr/`](docs/adr/) — the *why* of the architecture (`/adr-new`; none written yet).
3. [`docs/sessions/`](docs/sessions/) — the last 1–3 session logs (`/session-log`; none yet).
4. The code — start at `Sources/CalmMeter/CalmMeterApp.swift` and follow imports into `CalmMeterCore`; don't read directories alphabetically.

## Repo layout

```
Sources/CalmMeterCore/     All logic: models, API client, keychain, polling store (unit-tested)
Sources/CalmMeter/         Thin SwiftUI MenuBarExtra app
Tests/CalmMeterCoreTests/  Unit tests + API-response fixture (Fixtures/usage_sample.json)
Resources/                 Info.plist (version lives here), app icon, en/cs .lproj strings
scripts/                   build-app.sh (app bundle), make-dmg.sh (signed DMG), make-icon.py
.github/workflows/         release.yml — push tag v* → build/sign/notarize DMG on the release
```

## Build / test commands

```bash
swift build                                  # compile
swift test                                   # run all unit tests
swift test --filter CredentialCacheTests     # one test class
swift test --filter UsageStoreTests/testBackoff  # one test method
swift run CalmMeter                          # run the app directly (dev; behaves like the bundle)
./scripts/build-app.sh [--install]           # release build → ./CalmMeter.app (--install → /Applications)
./scripts/make-dmg.sh [--sign "…"] [--notarize <profile>]  # signed (optionally notarized) DMG
```

Releasing: bump `CFBundleShortVersionString` **and** `CFBundleVersion` in `Resources/Info.plist`, then push a `v*` tag — `.github/workflows/release.yml` builds/signs/notarizes the DMG and attaches it to the GitHub release (skips green if signing secrets are absent).

## Architecture

Two-target split, enforced by `Package.swift`:

- **`Sources/CalmMeterCore/`** — all logic: models, API client, keychain access, polling store. No UI imports. Everything testable lives here; parsing/decoding are deliberately split into static funcs (`Keychain.parse`, `UsageClient.decode`) so tests run against fixtures without touching the real keychain or network.
- **`Sources/CalmMeter/`** — thin SwiftUI `MenuBarExtra` app. One shared `UsageStore` in `AppEnvironment`; `AppDelegate` opts out of App Nap and refreshes on system wake.

New logic goes in Core with tests; the app target should stay thin.

### Credential flow (the load-bearing part — don't simplify it away)

`CachedCredentialProvider` (CredentialCache.swift) exists because of two macOS/API quirks:

1. Reading the secret *data* of Claude Code's keychain item (`Claude Code-credentials`) via SecItem triggers a password prompt — and no grant survives, because Claude Code rewrites the item with `security add-generic-password -U` on every token rotation, which resets the item's partition list to `("apple-tool:")` and revokes any "Always Allow" (proven live 2026-08-16). So the secret is read by spawning `/usr/bin/security find-generic-password -w` (`Keychain.readSecretViaSecurityTool`): the `security` binary is itself partition `apple-tool:`, so that read never prompts — precisely *because* Claude Code keeps resetting the list to that value. The token is then cached in CalmMeter's own item (`com.calmbit.CalmMeter.credentials`) so polls don't spawn a subprocess.
2. A rotated (stale) token is rejected by the API as **429, not 401**, so auth failures can't drive cache refresh. Instead, every call does an attribute-only query (which does NOT prompt) for the source item's modification date and re-reads the token data only when it changed.

`UsageClient.fetch()` additionally retries once with `forceRefresh` on 401/403. If you touch this flow, preserve the invariant: the normal polling path must never trigger a keychain prompt.

### Polling (`UsageStore`)

`@MainActor` ObservableObject with one-shot scheduling — after each attempt it decides the next delay: normal interval on success, exponential backoff (capped 5 min) on failure, honouring `Retry-After` on 429. Last good `usage` is kept across errors. `start()` is idempotent and `refreshNow()` is re-entrancy-guarded; UI triggers go through `refreshIfStale()`.

## Project conventions

- **Localization:** en + cs. Every user-facing string needs entries in both `Resources/en.lproj/Localizable.strings` and `Resources/cs.lproj/Localizable.strings`. Static labels use SwiftUI `Text("key")`; anything interpolated goes through the `Localized` helper in `Sources/CalmMeter/AppInfo.swift`.
- **Settings:** keys and defaults are centralized in `Sources/CalmMeter/Settings.swift` (`SettingsKey.registerDefaults()`).
- **Signing:** even dev builds prefer a real Developer ID (auto-detected; override with `$SIGN_IDENTITY`) — a stable signature is what makes the keychain grant stick; ad-hoc builds re-prompt.
- **Tests:** SwiftPM convention — tests live in `Tests/CalmMeterCoreTests/` (co-location isn't idiomatic for SwiftPM targets).

## Code conventions

These are the conventions claude-leverage documents and enforces.

### AIDEV-* anchor comments

Three grep-able prefixes for load-bearing facts in code:

- `AIDEV-NOTE:` — why this constraint exists / non-obvious invariant
- `AIDEV-TODO:` — known follow-up with enough context to resume
- `AIDEV-QUESTION:` — genuine unknown for the next person (or agent)

Rules: ≤120 chars per line, all-caps prefix. **Before editing a module, run `grep -rn 'AIDEV-' <module>` first.** Do not silently remove anchors — removing one requires an explicit decision in the commit / PR message.

`AIDEV-TODO` and `AIDEV-QUESTION` accept an optional ISO-8601 deadline:

```swift
// AIDEV-TODO(by: 2026-08-01): replace the polling loop with push   // preferred
// AIDEV-TODO(2026-08-01): …                                        // short
```

Free-form notes in the parens (e.g. `AIDEV-TODO(after migration)`) are **not** parsed as deadlines — those anchors fall under age-based tracking instead. `/stack-check` periodically flags overdue / due-soon / stale anchors.

### Structured JSON-lines logging

When code emits logs an agent will later read:

```json
{"ts":"2026-01-01T12:00:00.000Z","level":"info","trace_id":"a1b2","span_id":"4d5e","service":"<svc>","event":"<snake_case>","attrs":{"<key>":"<value>"}}
```

Required fields: `ts`, `level`, `trace_id`, `span_id`, `service`, `event`, `attrs`. **Do not interpolate values into messages** — put `user_id` in `attrs.user_id`, not in the message string. (This app currently emits no logs; the convention applies if that changes.)

### Per-directory AGENTS.md

For modules with non-obvious public surface or gotchas, drop an `AGENTS.md` at the module root with: what lives here, public surface, gotchas, test command. Codex merges nested AGENTS.md from git root down to cwd automatically.

## Security

- Never commit secrets, including in test fixtures. Use placeholder strings the `block-secrets-precommit` hook recognizes as safe (or the `claude-leverage-allow-secret` marker comment per line if you must).
- Run `/security-review` before committing changes in `Sources/CalmMeterCore/` (keychain / credential / network code: `Keychain.swift`, `CredentialCache.swift`, `UsageClient.swift`) or `.github/workflows/`.
- There are currently **no third-party dependencies** (`Package.swift` declares none) — keep it that way unless there's a strong reason; if one is added, wire CVE scanning into CI.

<!-- claude-leverage:agents-md END -->
