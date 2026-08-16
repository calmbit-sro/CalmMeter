# Session: keychain prompts root-caused + fixed for good; update check; v1.0.4 released

**Date:** 2026-08-16
**Branch:** main
**Participants:** Petr, Claude Fable 5 (Claude Code)
**Duration:** ~5 h (with monitoring gaps)

## Context

The 2026-08-12 "durable grant" fix for recurring keychain password prompts did
not hold — Petr saw dialogs again (2× within an hour that morning). The prior
theory (one-shot "Povolit" clicks + dead cdhash ACL entries) explained only
part of the story.

## What was done

- **Root cause proven by live monitoring:** Claude Code rewrites its
  `Claude Code-credentials` item via `security add-generic-password -U` on
  every token rotation, which resets the item's partition list to
  `("apple-tool:")` and revokes any user-granted "Always Allow". A grant that
  survived ~5 h of keychain traffic died within 3 s of a rotation write.
  Full forensics in memory file `calmmeter-keychain-prompt-saga.md`.
- **Fix shipped:** `Keychain.readCredentials()` now reads the secret via a
  `/usr/bin/security find-generic-password -w` subprocess (partition
  `apple-tool:` always matches → silent forever). TDD; security review found
  an stderr-pipe deadlock risk → stderr now goes to `FileHandle.nullDevice`.
- **Update check added (variant A):** Core `UpdateChecker` polls GitHub
  `/releases/latest` at launch + daily, silent on any failure; menu shows a
  "New version — download" row; Preferences toggle (default on). Spec in
  `docs/superpowers/specs/2026-08-16-update-check-design.md`.
- **v1.0.4 released:** notarized DMG built locally, GitHub release published.

## Key decisions

- Read the token through the `security` CLI rather than SecItem — the only
  path immune to Claude Code's partition resets. Documented in AGENTS.md
  credential-flow section + AIDEV-NOTE in Keychain.swift. (ADR candidate.)
- Update check stays dependency-free (no Sparkle); full auto-update was
  deliberately deferred — revisit only if the user base grows.
- Release CI has no signing secrets by design; DMGs are built locally via
  `./scripts/make-dmg.sh --notarize claude-usage` + `gh release create`.

## Open questions

- One partition wipe (08:28→08:33) happened with **no** mdat change — wiper
  never identified. Doesn't affect the fix; worth revisiting only if prompts
  ever return.
- Should the `security`-CLI read path get an ADR? (`/adr-new` next session.)

## Next steps

- Watch that no keychain prompt appears across the next few days of rotations.
- On the next release (1.0.5+), verify the update row appears for 1.0.4 users.
- Petr's uncommitted `.gitignore` + `CLAUDE.md` changes are still local.

## References

- Commits: e3a5763 (keychain fix), 612dc9a (update check, 1.0.4), tag v1.0.4
- Release: https://github.com/calmbit-sro/CalmMeter/releases/tag/v1.0.4
- Spec: `docs/superpowers/specs/2026-08-16-update-check-design.md`
- Diagnostics cheat-sheet: memory `calmmeter-keychain-prompt-saga.md`

---

*Distillate, not transcript.*
