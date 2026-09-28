# ADR-0081: JMAP mail backend

- **Status:** Proposed
- **Date:** 2026-09-28
- **Deciders:** Henrik
- **Related:** ADR-0001, ADR-0006, ADR-0017, ADR-0019, ADR-0028,
  ADR-0079; issue #15; `docs/jmap-exploration.md`

## Context

Brev's provider set is standards-first IMAP/SMTP plus the native Gmail
API adapter (`packages/BrevGmail`). ADR-0017 anticipated JMAP accounts
without committing to them; `docs/jmap-exploration.md` (issue #15)
researched the protocol and recommended a first-class JMAP backend once
IMAP was stable — which it now is (live-verified IMAP/SMTP including
CONDSTORE/polling, offline queue, unified inbox).

Why JMAP belongs on the roadmap:

- **Fastmail** — the largest independent paid-mail provider and the
  spec's author — exposes JMAP as its only modern API. A JMAP backend
  is the difference between "works via generic IMAP" and a native
  experience (delta sync, push via `EventSource`, identities).
- **Stalwart / Cyrus / mailbox.org** extend the same reach to
  self-hosted and privacy-focused users — exactly the audience a free,
  open-source, no-telemetry client attracts.
- JMAP's HTTP/JSON model maps cleanly onto Brev's existing seams: the
  session resource's `capabilities` (protocol-extension URNs) plus the
  selected account's `accountCapabilities` get translated into
  `BackendCapabilities` flags — capability-driven UI (ADR-0028
  invariant 2) consumes the translated flags, never the raw URNs.
  `Email/changes` is a natural fit for the sync reconciler.

Constraints: ADR-0006 (new provider traffic needs explicit opt-in and
a table row), ADR-0028 invariants (capability-driven UI; provider types
never reach views; views consume plain domain models), and the same
OAuth-public-client rules that bind Gmail (ADR-0065/0067).

## Decision

1. **A new package `packages/BrevJMAP` with `JMAPMailBackend:
   MailBackend`**, structured like `BrevGmail`: `JMAPTransport`
   (protocol, URLSession default, test double), `JMAPClient` (typed
   `methodCalls` requests per RFC 8620), `JMAPModels` (Codable DTOs
   kept inside the package — views never see them), a
   `JMAPAccountStore`, and `JMAPSyncReconciler` driving
   `Mailbox/changes` + `Email/changes` delta sync into the shared
   cache. `BrevBackend` gains no JMAP-specific types.

2. **Hand-rolled protocol layer, no third-party JMAP library.** The
   exploration found no maintained Swift JMAP library; JSON method
   calls keep the surface small and auditable, which suits the
   zero-telemetry posture better than a large dependency.

3. **Scope for the first cut:** RFC 8620 session discovery — an
   authenticated `GET https://<host>/.well-known/jmap` returns the
   session resource, and every subsequent request goes to its `apiUrl`
   (plus `uploadUrl`/`downloadUrl`/`eventSourceUrl` as needed) —
   `Mailbox/get`, `Email/get` + `Email/query` for the list,
   `Email/changes` for sync, `Email/set` for flag/mailbox mutations and
   `EmailSubmission/set` for sending, `Identity/get` for send-as, and
   `Blob/download` + `Email/import` for attachments/drafts. Push via
   `EventSource` is deferred — the fetch cadence (polling +
   `PIMSyncScheduler`-style scheduling) applies first, matching the
   IMAP posture under ADR-0037.

4. **Auth:** OAuth 2.0 authorization-code PKCE where the provider
   offers it (Fastmail, Stalwart), TLS app-password basic auth
   otherwise — same public-client rules as Gmail, tokens/passwords in
   the existing credential store, nothing logged.

5. **Opt-in and disclosure.** Adding a JMAP account is the explicit
   user opt-in; the backend's traffic is recorded in the ADR-0006
   table before merge (per-package rows like the Gmail adapter's).

6. **Sequencing gate.** Implementation starts only after (a) this ADR
   reaches Accepted, (b) a JMAP-capable test account exists (a
   Fastmail trial suffices — flag for Henrik to provision as a repo
   secret), and (c) CI can exercise the transport with a stubbed
   session document. No UI work until the backend passes `MailBackend`
   conformance plus capability probing.

## Rationale

Alternatives considered:

- **Do nothing (generic IMAP only for Fastmail/Stalwart).** Works
  today but leaves delta sync, push, and identity management on the
  table forever; JMAP is also the only path these providers actively
  invest in.
- **Adopt a community JMAP library.** Rejected: the candidates are
  incomplete or unmaintained, and a networked protocol dependency is
  a supply-chain cost with little benefit for a JSON/HTTP API.
- **Fold JMAP into `BrevGmail` / `BrevBackend`.** Rejected: provider
  adapters live in their own packages so `BrevBackend` stays
  provider-neutral (ADR-0028).

## Consequences

### Accepted

- A fourth top-level package (`BrevJMAP`) — protected-path change, hence
  this ADR.
- Delta sync makes large-mailbox refreshes cheaper than IMAP polling;
  the unified inbox gains another first-class source kind.
- JMAP push (`EventSource`) stays deferred, consistent with the
  no-relay posture in ADR-0037.

### Risks

- Provider coverage beyond Fastmail/Stalwart is thin; the backend must
  degrade gracefully on partial `capabilities` (capability-driven UI
  absorbs this by design).
- `EmailSubmission` semantics differ from SMTP send (e.g. scheduled
  send is client-side anyway, so the existing outbox path applies).

## References

- `docs/jmap-exploration.md` — research notes (issue #15).
- ADR-0001 (backend seam), ADR-0006 (privacy), ADR-0017 (multi-source
  workspace), ADR-0019 (keyword/tag mapping), ADR-0028 (invariants),
  ADR-0037 (closed-app notification posture), ADR-0065/0067 (OAuth
  public-client flow), ADR-0079 (parallel native-provider precedent).
- RFC 8620 (JMAP Core), RFC 8621 (JMAP for Mail).
