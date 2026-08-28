# ADR-0063: Platform-specific Google native OAuth clients

- **Status:** Accepted
- **Date:** 2026-08-25
- **Deciders:** Henrik
- **Amends:** ADR-0067
- **Amended by:** ADR-0065 (macOS Desktop callback selection)

## Context

Google's OAuth policy requires a client appropriate to each application
platform. A single client ID cannot safely describe both Brev's macOS/Desktop
and iOS binaries: iOS clients are bound to an iOS bundle and expose a
Google-generated reversed-client-ID callback scheme, while Desktop clients use
the installed-app loopback redirect.

The previous configuration injected one `BREV_GOOGLE_OAUTH_CLIENT_ID` and one
callback into both targets. That could select the wrong Google client type or
produce a `redirect_uri_mismatch` failure despite the app's URL scheme being
registered.

## Decision

Brev configures separate public Google OAuth clients and platform callbacks:

- macOS uses `BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID` plus the configured
  `BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI` and
  `BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME`. As amended by ADR-0065, those
  values identify the `http://127.0.0.1` loopback base and `http` scheme; Brev
  allocates the runtime port and `/oauth2redirect` path before opening
  `ASWebAuthenticationSession`. The resulting URI is the exact redirect reused
  in both the authorization and token-exchange requests.
- iOS uses `BREV_GOOGLE_OAUTH_IOS_CLIENT_ID`. Its callback scheme must equal
  the reversed client ID Google provides for that iOS client; the exact
  redirect defaults to `<reversed-client-id>:/oauth2redirect` and may be
  explicitly set when the Cloud Console registration uses another exact path.
- Both flows use authorization-code PKCE (S256). No Google client secret is
  injected into either app target or stored in the bundle.
- The legacy `BREV_GOOGLE_OAUTH_CLIENT_ID` is ignored unless
  `BREV_LOCAL_QA=1` (or the explicit `BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK`
  override) is set for a local compatibility check. It is not a release
  configuration.

Configuration loading validates the client/callback pair before opening
`ASWebAuthenticationSession`, and the OAuth preflight validates callback shape,
exact scheme matching, and target plist substitutions without printing values.
Microsoft OAuth and Google Workspace custom-domain onboarding remain
unchanged.

## Rationale

This follows Google's native-app guidance: each platform receives the client
type that can identify it, iOS receives Google's reversed-client-ID callback,
and installed apps use PKCE because a bundled secret cannot be confidential.
Keeping the callback in explicit target configuration makes a Console mismatch
visible during preflight instead of during a user's sign-in attempt.

## Consequences

- Local setup must provide two Google client IDs for cross-platform OAuth QA.
- Existing one-ID local setups continue only when explicitly marked local QA;
  they cannot accidentally become release settings.
- The macOS loopback implementation preserves the exact URI and listener port
  through authorization and token exchange; no loopback is inferred from an
  iOS configuration.

## References

- [Google OAuth 2.0 for iOS and Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google Sign-In iOS URL scheme](https://developers.google.com/identity/sign-in/ios/start-integrating)
- ADR-0067: Native OAuth public-client secret posture
- ADR-0065: Google Desktop OAuth loopback callback
- RFC 7636: Proof Key for Code Exchange by OAuth Public Clients
