# Session: OAuth sign-in landed, first-run guide + manual update check; v2.0.0 released

**Date:** 2026-08-23 → 2026-08-24
**Branch:** main
**Participants:** Petr, Claude Fable 5 (Claude Code)
**Duration:** ~2 sessions across two days

## Context

The standalone OAuth sign-in (whole 1.1.0 working tree, built in prior
sessions) was finished but uncommitted and only dev-deployed. Goal: ship it,
then round the app out for first-time users — nothing appears on launch of a
menu-bar agent, and there was no way to force an update check.

## What was done

- Deployed the OAuth build locally, verified (81 tests, signed bundle,
  fallback path live), then committed it after a security review — the
  review found no Criticals; placeholder tokens in fixtures had to become
  `<angle-bracketed>` so the block-secrets hook passes (commits `e1fa864`,
  `a68b3b2`).
- **First-launch welcome guide** (`4e849c1`): one 440pt window, three steps
  driven by live store/auth state; opens once via `welcomeShown` +
  a `ViewModifier` on the MenuBarExtra label (only view alive at launch);
  re-openable from Preferences.
- **Manual "Check now" update check** (`72e3a7a`): Core `checkDetailed()`
  distinguishes upToDate/failed (TDD, 5 new tests → 86 total); silent
  `check()` unchanged as a wrapper; Preferences button + inline outcome.
- **v2.0.0 released** (`d3e525b`, tag `v2.0.0`): 1.1.0 was never released,
  so the OAuth feature ships as 2.0.0; AGENTS.md "since" note updated.

## Key decisions

- Version jumped 1.0.5 → 2.0.0 (Petr's call); 1.1.0 exists only in commit
  history.
- Release DMG was built **locally** (`make-dmg.sh --notarize claude-usage`)
  and uploaded via `gh release create` — CI's release.yml skipped green
  because signing secrets were never configured on the repo. Same as every
  release so far (all assets uploaded by hand).

## Open questions

- Security review (Important): a rotated refresh token that fails to persist
  lives only in memory (`pendingStore`); a crash before the next poll loses
  it → silent sign-out on next launch (`OAuthCredentialProvider.swift`).
  Accepted for 2.0.0; consider a synchronous persist retry.
- Nice-to-haves from review: https-only assert on `ReleaseInfo.url` in
  `UpdateChecker.decode()`; explicit `timeoutInterval` on the update fetch.
- Configure CI signing secrets, or drop the never-used workflow half?

## Next steps

- Decide on the CI secrets vs. local-release question above.
- Petr to sanity-check the welcome guide's not-logged-in branch on a Mac
  without Claude Code (untestable here).

## References

- Commits: `e1fa864`, `a68b3b2`, `4e849c1`, `72e3a7a`, `d3e525b` (tag `v2.0.0`)
- ADRs: [0001](../adr/0001-standalone-oauth-with-claude-code-client-id.md)
- Release: https://github.com/calmbit-sro/CalmMeter/releases/tag/v2.0.0
