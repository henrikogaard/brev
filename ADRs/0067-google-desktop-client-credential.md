# ADR-0067: Google Desktop client credential and native SSO

- **Status:** Accepted
- **Date:** 2026-08-26
- **Deciders:** Henrik
- **Supersedes:** ADR-0067
- **Amends:** ADR-0063, ADR-0064, and ADR-0065

## Context

Brev uses separate Google native OAuth clients: an iOS client with Google's
reversed-client-ID callback, and a macOS Desktop client with a random loopback
callback. Both flows use authorization-code PKCE and state validation.

Live testing of the macOS Desktop client proved that Google rejects the token
exchange with `invalid_request:missing_client_secret` unless the Desktop
client's generated credential is included. ADR-0067 prohibited packaging that
value in either native app because a distributed native binary cannot keep it
confidential. That confidentiality analysis remains correct, but treating the
Desktop credential as absent makes Google's macOS flow unusable.

The same testing also showed that an ephemeral authentication session discards
the user's browser SSO state, and that abandoning an external-browser loopback
flow can leave Brev waiting indefinitely.

## Decision

- macOS builds using a Google Desktop OAuth client include that client's
  generated credential in the token and refresh exchanges. The build receives
  it through `BREV_GOOGLE_OAUTH_CLIENT_SECRET`; local values remain in ignored
  `.env.local` files and release automation must inject the value explicitly.
- The Desktop credential is treated as a public client identifier, not as a
  confidential application secret. It may exist in the signed app bundle, but
  it must never be committed, printed by build tooling, written to logs, or
  stored with user account data.
- PKCE, state validation, the exact random loopback redirect, the one-callback
  receiver, and Keychain-backed user tokens remain the security controls. The
  bundled Desktop credential is not used as proof that the calling binary is
  trusted.
- iOS continues to use its platform-specific client, reversed callback, PKCE,
  and state without a client secret. macOS and iOS credentials are not
  interchangeable.
- Google's authentication session is non-ephemeral so existing system-browser
  Google cookies can provide SSO. Google still receives
  `prompt=select_account consent`, keeping account choice and refresh-token
  consent explicit.
- User cancellation must tear down the authentication session and, on macOS,
  the loopback receiver. A late result cannot install an account after the user
  returns to the account chooser.

## Rationale

Keeping the Desktop credential out of macOS was rejected because the live
Google token endpoint requires it for this client type. Moving the exchange to
a Brev server was rejected because it would add hosted credential and account
infrastructure to a local-first mail client without making the native binary a
confidential client. Reusing the iOS client on macOS was rejected because it
breaks the platform registration and callback model recorded in ADR-0063.

Treating the generated Desktop value as non-confidential is honest about the
native threat model: an attacker can extract a bundled value, while PKCE binds
the authorization code to the initiating app instance and the loopback/state
checks protect the callback. The iOS flow does not need the Desktop
compatibility credential and therefore does not receive it.

## Consequences

### Accepted

- A macOS release cannot complete Google OAuth unless its build environment
  supplies both the Desktop client ID and generated credential.
- Anyone with the app bundle can recover the Desktop credential. Google Cloud
  restrictions, consent configuration, PKCE, and provider-side monitoring must
  assume that fact.
- Local and release scripts validate presence without displaying values.
- Users can reuse Google browser SSO and can cancel a stalled sign-in without
  installing a late account result.

### Risks

- Google can change Desktop-client exchange requirements. Live OAuth smoke
  testing remains a release gate.
- A leaked Desktop credential can be copied, but it cannot replace the PKCE
  verifier, redirect URI, authorization code, user consent, or Keychain token.
- Gmail's restricted scope still requires Google verification and, for broad
  external distribution, any provider-required security assessment. This ADR
  does not waive those release requirements.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0067: Native OAuth public-client secret posture
- ADR-0063: Platform-specific Google native OAuth clients
- ADR-0064: First-class Gmail API backend
- ADR-0065: Google Desktop OAuth loopback callback
- [Google OAuth 2.0 for iOS and Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- RFC 7636: Proof Key for Code Exchange by OAuth Public Clients
