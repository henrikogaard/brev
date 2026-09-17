# ADR-0078: Local attachment content indexing

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Henrik
- **Amends:** ADR-0041, ADR-0034
- **Related:** ADR-0006, ADR-0044, ADR-0077

## Context

ADR-0041 made attachment search metadata-first: the All Attachments view and
message search match attachment names, types and senders, and the ADR
explicitly deferred "search within attached document contents" to "a
local-only indexer [that] needs its own tests before any UI claims that
capability". Issue #28 §4 lists that deferral as the remaining search gap
against eM Client and Thunderbird, both of which find a PDF by a word inside
it.

What exists now:

- The SQLite search index in `BrevSyncEngine` has an FTS5 table
  `message_search(subject, snippet, participants, body, …_normalized)`
  written when headers/bodies are indexed; text queries short-circuit on an
  FTS miss (`SQLiteSyncStore.swift:883-898`).
- ADR-0044's read-only `cachedAttachmentMessages(in:)` already parses
  attachments out of the *cached raw source* without connecting; a message's
  attachment bytes are therefore available on disk exactly when its source
  is cached, and never otherwise.
- ADR-0034 retention evicts bodies/sources by age; Mail Storage lets the
  user clear caches per account.
- Apple frameworks can extract text on-device: `PDFDocument.string`
  (PDFKit, both platforms), `NSAttributedString(url:options:)` for RTF,
  plain text, HTML and — on macOS only — Office Open XML.

The constraints: zero network by default (ADR-0006), no automatic downloads
(ADR-0041), views branch on capabilities not backends (ADR-0028), untrusted
document parsing must be bounded, and the user must be able to see and
reverse what the index costs on disk.

## Decision

1. **Opt-in, per account, default off.** A "Search inside attachments"
   toggle lives in Settings › Folder Sync under the mailbox context bar next
   to Related mail, stored in `FolderSyncSettings`. Off means no extraction
   runs and no attachment-content rows exist for that account. Turning it
   off deletes that account's rows.

2. **Index only what is already cached; never download for indexing.** The
   indexable set for an account is the messages whose raw source is in the
   source cache (the same set ADR-0044 enumerates) plus every message in an
   ADR-0077 local folder. Indexing is triggered after a source is cached and
   on a low-priority sweep at launch; it never calls `downloadAttachment`
   or opens a connection. A message that is evicted by retention loses its
   attachment rows with its source.

3. **Extraction is on-device and bounded.** `AttachmentTextExtractor` in
   `BrevBackend` maps MIME type/extension to an extractor: PDF via
   `PDFDocument.string` (encrypted or non-text PDFs yield nothing — no OCR);
   `text/*`, `.csv`, `.md`, `.rtf`, `.html` via `NSAttributedString`;
   `.docx/.xlsx/.pptx` via `NSAttributedString` with `.officeOpenXML` on
   macOS only. Limits: attachments over 25 MB are skipped, extracted text is
   truncated at 512 KB, each document runs under a 10 s cooperative
   cancellation budget, and one extraction runs at a time per account.
   Failures are counted, not surfaced per file. Anything not in the table
   above is not indexed; there is no plug-in mechanism.

4. **Storage is a second FTS5 table in the existing index.**
   `attachment_search(account_id, message_id, folder_id, attachment_id
   UNINDEXED…, name, content, content_normalized)` added by a schema
   migration in `SQLiteSyncStore`. Rows are keyed by message ID so the
   existing purge paths (folder purge, account removal, clear cache,
   UIDVALIDITY reset) delete them with the message rows. The index is not
   part of the ADR-0076 backup; it is derived and rebuilt from cached
   sources.

5. **Search surfaces the hit honestly.** Ordinary message search over the
   local index unions `attachment_search` matches into its candidates and
   marks each such result with the matching attachment's name ("Found in
   report.pdf"); a message that also matches on subject/body shows no badge.
   The All Attachments view's query filter matches content as well as name
   for indexed attachments. Results carry `MailSourceID`, folder, message and
   attachment identity per ADR-0041 so routing is unchanged. Server-side
   search paths are untouched: when a query runs on the server the badge
   cannot appear, and the existing cache/server status row already says
   where the search ran.

6. **Cost is visible and reversible.** Mail Storage shows "Attachment
   index" size per account with "Rebuild" and "Remove" actions. The
   Folder Sync toggle's subtitle states the disk cost in one line and that
   nothing is downloaded for it.

7. **Privacy.** No network call is introduced; ADR-0006's table is
   unaffected. `PRIVACY.md` gains a paragraph under local data: extracted
   text is stored only in the local index, only for accounts where the user
   turned it on, only from attachments already on the device, and is removed
   with the cache or the toggle. Diagnostics log counts, byte sizes and
   durations only — never attachment names or text.

8. **Capability, not backend, gates the UI.** A backend that can supply
   cached attachment bytes (IMAP/SMTP, Gmail, local) advertises
   `.localAttachmentIndex`; the Settings toggle and the Mail Storage row
   appear only for accounts whose backend has it.

## Rationale

- *Opt-in over default-on:* the index can be a meaningful fraction of the
  cache for attachment-heavy mailboxes, and parsing third-party documents is
  the one place Brev runs untrusted input through a large framework. The
  user should choose that.
- *Cache-bound over download-for-indexing:* keeps ADR-0041's "no automatic
  downloads" and ADR-0006's zero-network-by-default intact without a second
  consent model. Users who want everything indexed already have the
  "keep bodies offline" retention setting to make everything cached.
- *Apple frameworks over bundled parsers:* no new dependency, sandbox-safe,
  covers the formats users actually search (PDF, Office, text); OCR and
  exotic formats are explicitly out until someone asks.
- *Second FTS table over widening `message_search.body`:* keeps the badge
  possible (we know *which* attachment matched), keeps per-attachment
  truncation simple, and lets the whole feature be removed by dropping one
  table.

## Consequences

- `SQLiteSyncStore` schema version bumps; migration creates the table and
  leaves it empty (population is lazy and only for opted-in accounts).
- `MailLocalSearchIndex` gains `indexAttachmentText(…)`, `removeAttachmentText(messageIDs:)`,
  `attachmentIndexSize(accountID:)` and a query hook; `SearchQuery` results
  gain an optional `matchedAttachmentName`.
- A new background `AttachmentIndexer` per account in `IMAPSMTPBackend` (and
  the Gmail backend, using its cached raw messages) coordinated with the
  existing source-cache write path; it must respect `flushLocalCaches()` /
  disconnect and stop promptly.
- iOS indexes PDF and text only; the Settings copy on iOS must not claim
  Office documents.
- Tests: extractor per format with fixtures (small PDF, RTF, plain text,
  docx on macOS), size/time limits, schema migration, purge cascades, search
  union with badge, toggle-off deletion, capability gating, and snapshots for
  the toggle, the Mail Storage row and the badge.

## References

- ADR-0006: telemetry and privacy (zero network by default)
- ADR-0028: architectural invariants
- ADR-0034: offline retention
- ADR-0041: search folders and attachment search scope (metadata-first
  deferral amended here)
- ADR-0044: read-only cached-attachment enumeration seam
- ADR-0077: durable local mail folders
- Issue #28 §4
