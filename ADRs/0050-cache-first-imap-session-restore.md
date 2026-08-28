# ADR-0050: Cache-first IMAP session restore

- **Status:** Accepted
- **Date:** 2026-08-10
- **Deciders:** Henrik

## Context

An existing IMAP account may already have an account-scoped folder snapshot and
cached message headers, yet session restoration waited for a remote IMAP
authentication and `LIST` before installing that local state. On a slow or
rate-limited server this made the app launch with a blank mailbox despite
having a usable local snapshot.

ADR-0029 permitted cache fallback after a transient remote-listing failure but
kept remote connection on the restoration critical path. That ordering no
longer meets Brev's offline-first and responsive-startup requirements.

## Decision

For a previously configured IMAP/SMTP account with a non-empty, account-scoped
folder snapshot, Brev installs the local folder and header caches before
starting remote reconciliation. The connection, folder listing, IDLE watcher,
draft hydration, scheduled-send delivery, and other deferred network work run
only after remote reconciliation succeeds.

Fresh accounts and accounts whose cache is absent or empty still validate and
install from the remote server before becoming visible. A failed background
reconciliation keeps cached read state available and records sync health; it
does not discard the mailbox. OAuth recovery refreshes the credential and
retries on the same visible backend.

This changes startup ordering only. It adds no new network endpoint, sends no
message content or account identifiers to diagnostics, and does not alter the
capability-driven `MailBackend` boundary.

### 2026-08-10 implementation safeguards

Deferred IMAP work must not reintroduce startup or reader contention. Remote
Drafts discovery stages metadata only; clean local drafts reconcile their body
when the user opens them, while dirty local drafts retain content-aware conflict
protection. A foreground reader request cancels stale page refresh and
non-critical remote-Drafts work, then retries that discovery after the final
foreground read completes; it never cancels a scheduled-send delivery. Cache
size diagnostics run their filesystem walks outside cache actors, so reporting
them cannot serialize cached source/body reads.

The initial Unified Inbox gathers independent source pages concurrently and
applies the completed results in source order. Sender avatar data is decoded
and downsampled off the main actor, with a bounded decoded-image cache, so
list-row redraws do not repeatedly decode raw image bytes.

## Rationale

Local folder and header snapshots are already the fastest path for message
lists. Installing them first gives the user an immediate, deterministic first
frame, while delaying only nonessential remote work prevents early connection
bursts from competing with foreground reading.

## Consequences

### Accepted

- Restored accounts can be read from their last persisted snapshot before the
  IMAP provider answers.
- Remote reconciliation remains authoritative and replaces cached folder state
  when it completes.
- Non-critical remote work yields to a foreground reader request; essential
  scheduled send delivery continues independently.
- Inbox aggregation and sender-avatar rendering stay off the critical path for
  the first interactive frame.
- Startup instrumentation records only timing and execution-path fields, and a
  local trace script exports only the existing `Performance` log category.

### Risks

- The visible snapshot may be stale until reconciliation completes. Sync health
  communicates a background failure rather than blanking the cached inbox.
- Cached startup needs an explicit remote-availability gate; starting IDLE or
  draft work from cache alone would unnecessarily consume provider connections.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0029: IMAP/SMTP backend foundation (amended for restore ordering)
- ADR-0030: Full IMAP sync and cache engine
