# ADR-0036: iOS S/MIME outbound limitation

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amended by:** ADR-0021

## Context

The related feature request asks Brev to either implement S/MIME signing/encryption on
iOS or document why it cannot be done with the available iOS APIs.
Outbound S/MIME on macOS is implemented in `BrevCrypto` with Apple's
CMS encoder APIs, producing detached `multipart/signed` signatures and
`application/pkcs7-mime` enveloped data.

The active implementation depends on `CMSEncoder`, which is public on
macOS through Security but is not a public iOS API. Brev's ADR-0021
requires outbound encryption to fail closed and use standards-compliant
MIME; it must not substitute a partial or non-standard transform just so
the iOS control appears available.

## Decision

1. **S/MIME outbound send remains macOS-only for now.** Brev will not
   advertise iOS S/MIME signing or encryption until there is a public,
   standards-compliant CMS encoder path or an audited bundled CMS
   implementation.

2. **The limitation is represented explicitly.** `BrevCrypto` exposes
   `SMIMEOutboundPlatformSupport` so app/UI layers can distinguish
   "unsupported on this platform" from "missing local key material".

3. **iOS outbound message security is unavailable for now.** iOS must fail
   closed when stale state requests signing or encryption while S/MIME CMS
   generation is unavailable.

4. **Future iOS S/MIME work needs a new implementation decision.** A
   future change may use a MIT-compatible CMS library or newly available
   Apple APIs, but it must include tests equivalent to the macOS S/MIME
   structure and round-trip coverage.

## Consequences

- The related feature request is resolved as a documented platform limitation rather than
  a hidden conditional compilation gap.
- iOS must not silently fall back to plaintext when the user explicitly
  requests S/MIME; unavailable S/MIME send should be presented as a
  platform limitation.
- No new network calls, provider APIs, telemetry, or key-discovery
  behavior are introduced.

## References

- ADR-0006 (telemetry and privacy)
- ADR-0028 (roadmap and invariants)
- ADR-0021 (compose and send encryption with local key management)
- The related feature request (S/MIME signing and encryption on iOS)
- RFC 5751 (S/MIME Version 3.2 Message Specification)
