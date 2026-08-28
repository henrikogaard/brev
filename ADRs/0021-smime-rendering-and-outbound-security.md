# ADR-0021: S/MIME rendering and outbound security

- **Status:** Accepted
- **Date:** 2026-08-28
- **Deciders:** Henrik

## Context

Brev needs to render signed and encrypted mail without exposing cryptographic
library types to views or provider adapters. Private identities must remain on
the device, and a requested security operation must never fall back to
plaintext without the user's explicit choice.

## Decision

1. Brev supports S/MIME through Apple's Security framework on macOS.
2. `BrevBackend` exposes plain security-state models. `BrevCrypto` owns
   certificate lookup, CMS processing, trust evaluation, and Keychain access.
3. Private identities and trust decisions stay in the Apple Keychain and are
   not synchronized or included in diagnostics.
4. Outbound signing or encryption fails closed when the requested identity or
   recipient certificate is unavailable.
5. SMTP delivery and the IMAP Sent copy use the same prepared MIME payload.
6. iOS keeps the limitation documented in ADR-0036 and fails closed for
   outbound S/MIME until Apple exposes a suitable public encoder.
7. The public baseline does not include an OpenPGP implementation. Adding one
   requires a new ADR and a commercially permissive, audited dependency.

## Rationale

The Security framework provides the native trust and identity boundary Brev
needs without adding a runtime cryptography dependency. Plain domain models
keep the UI and mail providers independent of CMS implementation details.
Failing closed prevents a secure compose request from silently becoming a
plaintext message.

## Consequences

- macOS can inspect, sign, and encrypt S/MIME messages with local identities.
- iOS can display security state but cannot perform outbound S/MIME encoding.
- Brev does not perform remote certificate or key discovery by default.
- Any future cryptographic format needs its own dependency and privacy review.

## References

- ADR-0006: Telemetry and privacy
- ADR-0036: iOS S/MIME outbound limitation
- RFC 8551: S/MIME 4.0 Message Specification
