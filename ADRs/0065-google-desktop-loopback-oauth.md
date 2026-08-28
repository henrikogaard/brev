# ADR-0065: Google Desktop OAuth loopback callback

- **Status:** Accepted
- **Date:** 2026-08-25
- **Deciders:** Henrik
- **Amends:** ADR-0063 macOS callback selection

## Context

ADR-0063 allowed a reverse-DNS custom callback for Brev's macOS Google OAuth
client and deferred a loopback listener. Live verification showed that the
configured Google client is a `Desktop app` client: Google rejects
`eu.brevmail.brev:/oauth2redirect` with `redirect_uri_mismatch`, while the same
client accepts an ephemeral `http://127.0.0.1:<port>/oauth2redirect` callback.

Google's current installed-app guidance recommends a loopback IP callback for
macOS, Linux, and Windows Desktop clients. The redirect URI must be identical
in the authorization and token-exchange requests. Brev is sandboxed, so a
local listener also requires the macOS network-server entitlement.

## Decision

- macOS uses a Google `Desktop app` OAuth client and starts an ephemeral HTTP
  listener bound only to `127.0.0.1` before opening the system authentication
  session.
- The listener chooses a random available port and exposes exactly
  `http://127.0.0.1:<port>/oauth2redirect`. That exact URI is carried through
  both authorization and token exchange with the existing PKCE verifier and
  state check.
- `ASWebAuthenticationSession` remains the user-facing browser surface. The
  local listener completes the session after one valid callback and returns a
  small completion page; cancellation tears down both surfaces.
- The listener accepts only bounded `GET` requests on the callback path, never
  logs the authorization code, and is not active outside an explicit Google
  sign-in attempt.
- Both macOS entitlement variants include
  `com.apple.security.network.server`; the listener still binds only to the
  IPv4 loopback address.
- iOS remains on its separate iOS client and Google's reversed-client-ID
  custom scheme. Microsoft OAuth is unchanged.

## Rationale

Loopback is the redirect method Google explicitly supports for Desktop app
clients and avoids custom-scheme interception by another local application.
Keeping the native authentication sheet preserves cancellation and account
selection while the local listener provides the callback transport Google
expects.

Using the iOS client and reversed-client-ID scheme in the macOS build was
rejected because it would mix client types and contradict the platform split.
A fixed loopback port was rejected because concurrent runs and stale processes
could collide; the port must be allocated at runtime.

## Consequences

- macOS Google OAuth configuration now uses the loopback base
  `http://127.0.0.1` and callback scheme `http`; it no longer registers that
  value as an application URL scheme.
- The sandbox permits inbound connections, but Brev opens a listener only on
  loopback and only during user-initiated Google sign-in.
- Release verification must prove the signed app contains the network-server
  entitlement and that the runtime redirect reaches Google's sign-in page.

## References

- [Google OAuth 2.0 for iOS and Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google OOB migration guide](https://developers.google.com/identity/protocols/oauth2/resources/oob-migration)
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0067: Native OAuth public-client secret posture
- ADR-0063: Platform-specific Google native OAuth clients
- ADR-0064: First-class Gmail API backend
