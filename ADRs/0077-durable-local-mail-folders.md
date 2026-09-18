# ADR-0077: Durable local mail folders

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Henrik
- **Supersedes:** ADR-0073
- **Amends:** ADR-0034, ADR-0076
- **Related:** ADR-0028, ADR-0030, ADR-0041, ADR-0045

## Context

Every byte of mail Brev holds today is a cache of a server. Header snapshots
(`FileBackedIMAPMailboxHeaderCache`), message sources
(`FileBackedIMAPMessageSourceCache`) and parsed bodies
(`FileBackedIMAPMessageBodyCache`, 20 MB per account with LRU pruning) are
all evictable by design: the retention sweep in ADR-0034 drops bodies outside
the offline window, Mail Storage lets the user clear them, and removing an
account removes all of it. Pinning (#268) exempts individual bodies from the
sweep, but a pinned message still disappears when the server deletes it or the
account is removed.

Issue #28 §9 asks for "durable local archives distinct from an evictable
cache". ADR-0076 shipped settings/account backup and explicitly named local
archives as phase 2, pending a decision on storage and eviction exemption.
The user jobs are the ones Apple Mail's "On My Mac" and Thunderbird's "Local
Folders" serve:

- Keep mail after leaving an employer or provider, without keeping the
  account.
- Get large old mail out of a quota-limited mailbox while keeping it
  searchable.
- Import an MBOX/Maildir export from another client without uploading it to
  any server (today `importMessages(_:into:)` APPENDs to a server folder).
- Carry that mail between Macs inside a `.brevbackup`.

Existing seams this builds on: `MailBackend` (provider-neutral; the sidebar,
unified inbox, search and reader already iterate `AppSession.backends`),
`rawSource(for:sourceID:)` (ADR-0045), the MBOX/EML/Maildir readers and
`MailFolderExporter` (`MailImport.swift`, `MailFolderExporter.swift`), the
SQLite local search index (`MailLocalSearchIndex` in `BrevSyncEngine`), and
the capability flags in `BackendCapabilities`.

## Decision

1. **Local folders are a `MailBackend`, not a cache mode.** A
   `LocalMailBackend` in `BrevBackend` implements `MailBackend` for one
   synthetic account per device (`backendIdentifier: "local"`, display name
   "On My Mac" / "On My iPhone" via localized strings). It is registered in
   `AppSession.backends` like any other backend so the sidebar, unified
   inbox, search, reader, threading and Mail Storage work without new view
   branches. It appears in the sidebar only once it has at least one folder;
   "New Local Folder…" creates the first one.

2. **Storage is Maildir on disk, headers indexed in SQLite.** Messages live
   as raw RFC 5322 files under
   `~/Library/Application Support/Brev/LocalFolders/<folder-uuid>/{cur,new,tmp}`
   with flags encoded in the Maildir info suffix (the same grammar
   `MaildirReader.parseFilename` already parses). Folder names and hierarchy
   live in a small `folders.json` manifest next to them. Headers, threading
   metadata and search text are indexed into the existing local search index
   under the local account ID and rebuilt from the Maildir if the index is
   missing or stale. The Maildir is the authority; everything else is derived.
   This directory is **outside** every cache root, so no retention sweep,
   body-cache prune or "Clear cache" action can touch it; only deleting a
   local folder or the account-data cleanup for the local account removes
   files. Files are plain and per message, so Time Machine and Spotlight
   handle them without Brev's help.

3. **Capabilities are honest.** The local backend advertises `folderCreate`,
   `folderRename`, `folderDelete` and nothing that implies a server:
   no `serverSideSearch`, `idleSync`, `aliases`, `snooze`, sending or
   provider API. Capability-driven UI (ADR-0028 rule 3) therefore hides
   Send Later, snooze, server rules and sync-health rows for it. Replies to a
   local message compose from the user's default sending account; the local
   account never appears in "From".

4. **Getting mail in: Copy, Move and Import.** Message context menus and the
   menu bar gain "Copy to Local Folder…" and "Move to Local Folder…" for any
   selection from a server account. Both fetch the raw source through the
   ADR-0045 seam, write it to `tmp/`, fsync, rename into `cur/`, index it,
   and only then — for Move — run the existing undoable delete on the server
   copy, so Undo works exactly as it does for delete today and a failed local
   write never loses the server copy. The existing MBOX/EML/Maildir import
   gains a destination picker whose default is a new local folder named after
   the file; APPEND to a server folder remains available.

5. **Getting mail out: export and backup.** `MailFolderExporter` already
   exports a folder to MBOX or an EML directory; it works unchanged on local
   folders. ADR-0076 phase 2 lands here: the backup preview gains an
   "Include local folders" checkbox (default on when local folders exist,
   with the size shown) that writes one MBOX per local folder into `mail/`
   inside the `.brevbackup` package, hashed in the manifest like every other
   payload. Restore recreates the folders by importing those MBOX files
   through the reader in decision 2; Merge skips messages whose Message-ID
   already exists in the target folder, Replace recreates the folder.

6. **Sizing and limits.** Mail Storage shows the local account's size next
   to the cache sizes with copy that says it is not a cache and is not
   cleared automatically. There is no size cap. Backup writing streams
   messages so a multi-GB local folder does not need to fit in memory.

7. **Privacy.** No network call is introduced; the local backend never
   opens a connection and the ADR-0006 table is unaffected. `PRIVACY.md`
   gains one paragraph under local data: what a local folder stores, where,
   that it survives cache clearing and account removal, and how to delete
   it. Diagnostics log counts and durations only, as today.

8. **Platform sequencing.** The store, backend and backup payload are
   platform-neutral and ship together. Copy/Move/Import/New Local Folder UI
   shipped on macOS first with iOS read-only; the write actions — Copy/Move
   to Local Folder, New/rename/delete local folder — have since been
   enabled on iOS through the same shared surfaces (message context menus,
   `LocalFolderDestinationSheet`, the sidebar account and folder menus,
   `MailCommands`). MBOX/Maildir import remains macOS-only until the
   Files-app/share-sheet import path is designed; the shared
   import-destination step already defaults to a new local folder and needs
   no change once an iOS entry point lands.

## Rationale

- *Backend vs. a "durable" flag on the cache:* a flag would need every
  eviction path, every storage view and every account-removal path to check
  it, forever. A separate backend gets isolation for free and reuses every
  view Brev already has for accounts.
- *Maildir vs. rows in `SQLiteSyncStore`:* the archive's whole purpose is to
  outlive Brev's schema, machines and the app itself. One file per message is
  the format users can open in another client, back up with Time Machine, and
  that Brev already parses. SQLite is the right place for the derived index,
  which can always be rebuilt from the files.
- *Move as Copy + existing delete:* reuses the undo receipt and offline
  mutation queue instead of inventing a second undo path, and makes the
  failure ordering (local write must succeed before the server copy is
  touched) trivial to reason about.
- *No size cap:* the user chose to keep this mail; silently dropping it
  would betray the one guarantee the feature exists to give. Disk pressure
  is surfaced in Mail Storage, not enforced.

## Consequences

- New protected-path surface in `BrevBackend` (`LocalMailBackend`,
  `LocalMaildirStore`), new `mail/` payload in the ADR-0076 backup format
  (format version bump with backward-compatible reading), and a restore
  path that can be slow for large archives and must report progress.
- `AccountDataCleanup` must treat the local account specially: removing it
  is a destructive, confirmed action that deletes user-owned mail, not a
  cache.
- The import flow changes its default destination from "current server
  folder" to "new local folder"; the CHANGELOG entry must say so.
- Search across all mailboxes now includes local folders through the
  existing multi-folder index query; no new search UI.
- Tests: Maildir round-trip (write → read → header parity), flag persistence
  in the filename, index rebuild from files, Copy/Move ordering with an
  injected failing writer, backup include/restore Merge/Replace with the
  Message-ID dedupe, and snapshot coverage for the sidebar row, the
  destination picker and the Mail Storage row.

## References

- ADR-0028: architectural invariants (capability-driven UI, backend-neutral
  views)
- ADR-0034: offline retention and cache eviction
- ADR-0045: message copy and raw-source seam
- ADR-0041: attachment search scope (local folders feed the same index)
- ADR-0076: versioned settings and account backup (phase 2 named there)
- Issue #28 §9; pinning #268
