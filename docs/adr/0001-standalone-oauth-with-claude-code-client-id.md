# 0001. Standalone OAuth sign-in using Claude Code's public client id

**Date:** 2026-08-20
**Status:** accepted
**Deciders:** Petr Hlozek

## Context

A client without Claude Code on their Mac has no `Claude Code-credentials`
keychain item, so CalmMeter had no token source at all. Worse, CalmMeter never
refreshed tokens — the access token lives 8 hours, so even a one-time
`claude` login dies the same day unless Claude Code itself keeps refreshing
it. CalmMeter must work for Claude subscribers who never install Claude Code.
The usage endpoint (`/api/oauth/usage`) accepts only OAuth tokens; there is no
public OAuth client registration for this flow.

## Decision

CalmMeter performs its own OAuth authorization-code flow with PKCE using
Claude Code's public client id (`9d1c250a-e61b-44d9-88ed-5944d1962f5e`),
via the manual-paste callback (`CODE#STATE` from
`platform.claude.com/oauth/code/callback`), and refreshes the access token
itself. Own credentials live in a separate keychain item
(`com.calmbit.CalmMeter.oauth`) — the authoritative source, distinct from the
`…CalmMeter.credentials` item that is only a cache of Claude Code's token.
Source priority: own OAuth first, Claude Code keychain as zero-config
fallback (`AutoCredentialProvider`).

## Consequences

### Positive

- Works for anyone with a Claude subscription; Claude Code not required.
- Self-refresh removes the 8-hour dead-token failure mode for app-only users.
- The never-prompt polling invariant is preserved: with own credentials, polls
  never touch Claude Code's partition-listed item or spawn `security`.
- Sign-out is trivial: delete the own item, fall back to Claude Code's.

### Negative

- Unofficial API surface: Anthropic may rotate or block the client id or
  change the flow without notice (accepted trade-off — the usage endpoint
  itself carries the same exposure; common practice among usage-meter tools).
- CalmMeter presents to the OAuth server as Claude Code (scope includes
  `user:sessions:claude_code`).
- Rotating refresh tokens create a persistence invariant: the new refresh
  token must be written before the new access token is first used
  (see AIDEV-NOTE in `OAuthCredentialProvider.swift`).

## Alternatives considered

- **Require Claude Code install + one-time login** — fails the actual need:
  without Claude Code running regularly, nobody refreshes the token past 8h.
- **Register CalmMeter's own OAuth client** — no public registration exists
  for this flow.
- **Localhost-redirect callback** — the redirect URI is fixed per client id;
  a local server adds a firewall prompt and port handling for nothing (the
  manual-paste page is the flow Claude Code itself uses).
- **API key instead of OAuth** — the usage endpoint rejects API keys; it is
  OAuth-only.

## References

- Flow parameters verified 2026-08-20 against Claude Code's own captured
  OAuth traffic; encoded (with tests) in `Sources/CalmMeterCore/ClaudeOAuth.swift`.
- Keychain partition-list pathology that shaped the fallback path:
  AIDEV-NOTE in `Sources/CalmMeterCore/Keychain.swift`.
