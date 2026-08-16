# Update check (variant A) — design

Date: 2026-08-16 · Status: approved (in-session) · Target release: 1.0.4

## Purpose

Tell the user a newer CalmMeter release exists. No self-updating: one menu row
that opens the GitHub release page. Zero new dependencies (project policy).

## Architecture

**Core — `Sources/CalmMeterCore/UpdateChecker.swift`** (all logic, unit-tested):

- `AppVersion: Comparable` — parses `"1.0.4"` / `"v1.0.4"` into numeric
  components; numeric per-component compare (`1.0.10 > 1.0.9`); missing
  components count as zero (`"1.0" == "1.0.0"`). Unparseable → `nil`.
- `ReleaseInfo` — `version`, `tagName`, `url` (release page).
- `UpdateChecker.decode(Data) throws -> ReleaseInfo` — decodes the GitHub
  `/repos/calmbit-sro/CalmMeter/releases/latest` response (`tag_name`,
  `html_url`). That endpoint never returns drafts or prereleases, so no
  filtering is needed.
- `UpdateChecker.check(currentVersion:) async -> ReleaseInfo?` — injected
  `fetchData` closure (URLSession by default); returns the release only when
  remote > current. **Every failure path returns nil** — the update check must
  never surface an error or interfere with the app's main function.

**App (thin glue):**

- `UpdateStore` (ObservableObject): check ~5 s after launch, then every 24 h;
  honours the `SettingsKey.checkForUpdates` toggle (default on).
- `MenuContent`: one extra footer row "Nová verze X – stáhnout", shown only
  when an update is available; click opens the release page.
- `PreferencesView`: toggle "Automaticky kontrolovat aktualizace".
- Strings in en + cs.

## Error handling

Silent. Network failure, malformed JSON, unparseable versions → no row, retry
at the next scheduled check.

## Testing

Fixture `github_release_sample.json` (realistic API response). Tests: version
parsing/compare edge cases, decode, and check() outcomes (newer / equal /
older / fetch error / garbage).

## Explicitly out of scope (YAGNI)

Manual "check now" button, DMG auto-download, notifications, Sparkle.
