# Mail Sync, Storage & Offline Engine

> Consolidates former ADRs `0022`, `0029`, `0030`, `0034`, `0043`, `0050`, `0052`, `0074`, `0076`, `0077`, `0087`, and `0090`.

## Goals

Brev is a **local-first, cache-first** mail client. Launching the app, switching folders, reading cached mail, and queuing mutations work immediately from local storage without waiting on remote IMAP or Gmail round-trips.

## Storage Architecture

- **IMAP SQLite header & page store:** `SQLiteSyncStore` is the canonical store for IMAP folder metadata, transactional page windows, UIDVALIDITY state, and message headers. Whole-folder JSON header caches are retired (no dual-cache drift).
- **Structured body & raw source caches:** Parsed `MessageBody` records (`FileIMAPMessageBodyCache`) and raw RFC 822 sources (`FileIMAPMessageSourceCache`) live separately under account-scoped Application Support directories with bounded byte budgets. `CachedMessageBodyProviding.cachedBody(for:sourceID:)` checks parsed bodies first and falls back to parsing cached raw MIME locally without triggering network fetches.
- **Legacy migration & quarantine:** Unverified pre-marker legacy JSON rows are quarantined locally—retained on disk, hidden from normal browsing and search until confirmed by the server—and failed or future-schema stores are never silently wiped.
- **Gmail local store:** `GmailAPIBackend` maintains an account-scoped SQLite store for labels, messages, threads, history cursors, and separate durable compose staging tables (surviving cache clears; cascade-deleted on account removal).
- **Durable local mail folders (`LocalMailBackend`):** User-created "On My Mac" / local archive folders store durable RFC 822 mail outside evictable provider caches, with MBOX/Maildir import and full-folder export.

## Sync & Session Lifecycle

1. **Cache-first session restore:** On launch, accounts mount their cached folder tree and first header pages immediately before IMAP authentication or remote `LIST`/`SELECT` completes.
2. **Incremental sync & push:** IMAP uses `UIDVALIDITY`, `CONDSTORE`/`QRESYNC` where advertised, bounded page fetches, `IMAP IDLE` on active folders, and configurable polling intervals. Gmail uses `history.list` delta sync with full-sync fallback on expired history IDs.
3. **Offline retention & Keep Offline:** Bounded per-account retention evicts stale cached bodies while honoring explicit per-message "Keep Offline" pins. Sync progress events report folder/backfill counts cleanly to the UI.
4. **Offline mutation queue (`PendingMutation`):** Read/unread, flag, archive, move, delete, junk, and send operations persist locally and replay in order on reconnect, surfacing unrecoverable conflicts clearly in the Outbox / status banner instead of silently dropping changes.
5. **Scheduled sends:** Explicit Send Later persists frozen MIME payloads and target send timestamps in account-owned SQLite rows. Delivery runs while Brev is open and connected; interrupted or uncertain sends are held for user review rather than blindly reissued.

## Threading & Complete Conversations

- **Client-side IMAP threading:** Derives `threadID` deterministically from `Message-ID`, `In-Reply-To`, `References`, and normalized subject fallback for servers without `THREAD` extension support.
- **Source-owned complete conversations:** Conversations belong to one `(account, source)` and resolve members across Inbox, Sent, and Archive using local reply-identifier indexes (`Message-ID` / `In-Reply-To` / `References`) for IMAP and native thread IDs for Gmail, with optional user-triggered or per-account remote header discovery (`Load related mail`).

## Workflow State Model

Workflow state (snoozes, done markers, no-reply follow-up reminders, pins, VIPs, local tags) uses an explicit three-tier model:

- **Provider-backed:** Synced natively when the backend supports it (e.g., Gmail labels, IMAP keywords).
- **Local:** Stored locally per account and optionally synced across the user's own devices via opt-in iCloud Key-Value preference sync.
- **Unsupported:** Hidden cleanly when neither provider nor local storage applies.

## Settings & Account Backup (`.brevbackup`)

- Versioned JSON backup format with schema validation, pre-import preview, and explicit merge vs. replace modes.
- **Security boundary:** Passwords, OAuth tokens, AI API keys, and device-local security consents (sign-in code detection, local MCP Agent access) are **excluded** from portable backups so restoring a backup on another Mac never silently transfers credentials or broadens access.
