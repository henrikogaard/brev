# ADR-0082: Encryption at rest for the local mail store

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** Henrik
- **Related:** ADR-0006, ADR-0030, ADR-0076

## Context

Brev's local mail store is raw SQLite (`SQLiteSyncStore`,
`FileBackedIMAP*` caches) plus file caches and the draft staging store.
Today confidentiality rests entirely on OS volume encryption
(FileVault / iOS data protection) and default file-protection classes.
Paid-client competitors ship an explicit "encrypt local data" story;
for an OSS client pitching privacy, at-rest encryption is the expected
follow-through on ADR-0006's posture.

Two viable layers:

- **SQLCipher** (page-level AES-256 inside SQLite): encrypts the DB
  itself, survives the file leaving the device, key in the Keychain.
  Cost: a new third-party dependency (BSD-licensed, mature), page-size
  migration for existing stores, and a small per-op overhead.
- **`NSFileProtectionComplete`** on the store directory: zero
  dependency, zero migration cost; protects only while the device is
  locked, and macOS ignores file-protection classes entirely.

## Decision

1. **Layer A (now): apply the strongest file protection available.**
   On iOS, write the store and caches under
   `NSFileProtectionCompleteUntilFirstUserAuthentication` at minimum
   (Brev needs access in BGAppRefresh windows, so `Complete` is wrong —
   it would break background fetch). On macOS this layer is a no-op;
   document that.

2. **Layer B (next): SQLCipher behind a per-install Keychain key,**
   gated by a Settings toggle ("Encrypt local mail database"), default
   **off for existing installs, on for new installs**. Migration = open
   plaintext DB, `sqlcipher_export` into an encrypted DB, fsck, swap —
   run once on toggle, with a progress sheet and rollback on failure.

3. **Credentials never migrate.** Keychain/Secrets stay in the system
   Keychain; Layer B covers the SQLite stores (`SQLiteSyncStore`, the
   Gmail cache DB) — not passwords/tokens, which are already
   encrypted. File-backed caches outside the SQLite store
   (`IMAPMessageBodyCache`, `IMAPDraftStagingStore`, `FileBackedIMAP*`
   header caches, the BrevCalendar event/contact/task caches) stay at
   Layer A protection on iOS and FileVault on macOS for now; encrypting
   them (per-file encryption vs. relocating bodies/drafts into the
   encrypted DB) is the named follow-up, and the Settings copy must say
   exactly which stores the toggle covers until then.

4. **Not in scope:** encrypting backup exports (ADR-0076's own
   decision), iCloud-synced data (none), or the screenshots/logs the OS
   keeps.

## Rationale

- SQLCipher is the only maintained SQL-encryption path that fits
  SQLite3 without abandoning the existing store; hand-rolled page
  crypto would be strictly worse.
- A Keychain-held random key (128 bits) needs no passphrase UX; the
  device unlock already gates access. A passphrase option can follow
  later without changing the format.
- File-protection layer first because it is free, and the class choice
  (…UntilFirstUserAuthentication, not Complete) is load-bearing for
  ADR-0037 background refresh.

## Consequences

### Accepted

- New dependency (SQLCipher) at Layer B — vetted, BSD-licensed, static
  archive; pin to a release ≥7 days old.
- One-time migration duration scales with store size; must be
  resumable/cancellable.
- Performance: page crypto adds measurable but small overhead on large
  folders (existing performance-budget CI will catch regressions).

### Risks

- Forgetting the Keychain key = losing the encrypted DB. ADR-0076's
  backup covers settings and account metadata only — it cannot recover
  the store. The real mitigation is that the mail store is a
  rebuildable mirror of server-side state: key loss means wipe the
  local DB and re-sync. Unsent staged drafts and queued-but-unsynced
  edits are the only non-recoverable data; the pre-migration prompt
  must say that plainly and let the user export/cancel first.
- `NSFileProtection…UntilFirstUserAuthentication` vs BGAppRefresh
  timing needs a device check (part of the Phase B background-verify
  leg).

## References

- ADR-0006 (privacy), ADR-0030 (sync engine / store layout),
  ADR-0037 (background refresh posture), ADR-0076 (backup format).
