# Changelog

All notable changes to Brev are documented here.

## [Unreleased]

### Added

- Conversation metadata foundation: source-owned members, explicit cached coverage,
  conservative RFC reply-link resolution and indexed Gmail cached-thread lookup.
  This prepares cross-folder reading; reader integration and related-mail loading
  are still pending. Gmail's cache migration preserves existing mail and scheduled
  drafts. The IMAP cache also indexes existing reply identifiers across folders,
  with explicit partial coverage when traversal reaches its bounds.
- Cross-folder conversations: the reader now shows related messages from other
  folders (including Sent and Archive) using cached metadata, with an explicit
  "Load related mail" action that asks the provider for related headers across
  all eligible folders in the account. A per-mailbox "Automatically load related
  mail" preference in Settings › Folder Sync can enable the same metadata-only
  lookup on conversation open; it defaults off, fetches no bodies or
  attachments, and never marks mail read.
- Optional background mail on macOS: keep checking mail with no window open,
  see status in the menu bar, and open Brev at login (Settings ›
  Notifications; off by default).
- Back up and restore Brev settings and account setup from Settings ›
  Import / Export. Backups never include passwords or tokens; restored
  accounts ask you to sign in. Backups can now include local folders as
  `mail/*.mbox` payloads (on by default when local folders exist).
- Durable local folders ("On My Mac" / "On My iPhone") keep mail on this
  device outside every cache — nothing is evicted, uploaded, or removed
  until you delete a folder. On macOS, create folders from the sidebar and
  use Copy/Move to Local Folder on any message; on iOS local folders are
  readable. Local folders are searchable and browsable like any account.
- Optional attachment-content indexing per account (Settings › Folder Sync ›
  "Search inside attachments"): Brev extracts text locally from attachments
  already cached on this device — nothing is downloaded for indexing — so
  message search can match attachment text and label the hit with "Found in
  <name>". Turning the toggle off deletes the account's attachment index;
  Mail Storage shows its size with Rebuild/Remove actions.
- Brev Nightly: a separate pre-release app (`Brev Nightly.app`,
  `eu.brevmail.brev.nightly`) with its own app icon, preferences, and
  Sparkle feed. Update feeds are now hosted on GitHub Pages with DMGs on
  GitHub Releases; Settings › Updates shows the installed release ring and
  links to the other ring's download.

### Changed

- The Beta update channel is retired in favour of the Stable/Nightly
  release rings (ADR-0080). The Stable/Beta picker is gone — the ring is
  fixed per build — and update checks moved from `updates.brevmail.eu` to
  `henrikogaard.github.io` / `github.com`.
- Signed releases are now automated: pushing a `vX.Y.Z` tag builds, signs,
  notarizes, and publishes a Stable release, and a Nightly build ships from
  `main` each night (00:30 UTC) when main has moved (ADR-0080).

- Mail import now defaults to a new local folder named after the imported
  file; provider folder destinations remain available in the destination step.
- Related-mail auto-loading is now set per mailbox under Settings › Folder Sync;
  Smart Views has its own sidebar icon.

### Fixed

- iOS: the account-restore error alert now also appears when every account
  fails to restore, and its "Open Settings" action is reachable from the
  login screen, so accounts no longer vanish silently behind the login page.
- iOS: notifications that offer a quick reply now also show the rich
  sender/subject/snippet preview.
- iOS: sharing very large text into Brev now explains that the text was left
  out (with any links and attachments still included) instead of silently
  failing to open the app.
- iOS: the app's privacy manifest now declares its UserDefaults required-reason
  API usage, preventing App Store Connect ITMS-91053 warnings.

- Nightly release archives now receive the configured Google OAuth values, so
  scheduled and manually dispatched builds can pass the archive preflight.

- Nightly release planning now scopes its GitHub Actions Build lookup
  explicitly, allowing the no-checkout gate to run on scheduled builds.

- Gmail search now publishes results page by page without the former 5,000-result
  cap. Cached-only searches work disconnected and respect secondary labels.
  Auto search previews one bounded cache page before contacting Gmail, while
  offline fallback walks all cache pages.
- Gmail custom-label filters use stable IDs, negative read/star/attachment filters
  are preserved, and All Mail excludes Spam/Trash consistently. Cancellation,
  retired-account responses, repeated cursors and later-page errors cannot report
  successful completion; authentication and retry errors retain their types.

- IMAP search shows cached matches and server pages as they arrive in folder and
  unified lists. A shared compact status row identifies cached-only coverage,
  incomplete results and Retry. Open messages stay selected while paging.
- Repeated searches reject stale progress and completion callbacks. Late mailbox
  failures preserve already loaded rows. Attachment-presence and absence searches
  both disclose possible message-data downloads while fetching.
- Faster folder and list performance: header-cache writes are coalesced instead
  of rewriting a folder's JSON on every page load or flag update, "load more"
  merges append without re-sorting the whole folder, CONDSTORE flag deltas only
  re-index the messages that changed, all-folders local search issues one
  scoped index query instead of one per folder, and list/thread projections are
  reused across unrelated redraws instead of being re-derived.

- IMAP searches use server pages to return matches beyond the previous
  50-result display limit. Ordinary searches follow server pages without
  downloading message bodies, and cached matches no longer hide older online
  results. Cache-only search remains local and returns all cached matches.
- Search rejects canceled responses, repeated cursors, and interrupted later
  pages instead of reporting incomplete server results as success. Legacy
  nonpaged ordinary adapters report when their bounded limit prevents completion.

- IMAP scheduled messages now offer Outbox time changes, cancellation, and
  reviewed retry. Interrupted or uncertain delivery and unavailable local drafts
  remain visible for review. Reconnect respects backoff, and automatic retries
  stop after ten failures. Active delivery blocks edits only to that message.
- Account teardown drains local schedule edits and rejects stale delivery cleanup,
  preserving replacement drafts. Scheduling reports a failed local staging write
  instead of claiming the message was queued.

- Gmail Send Later stores submitted content and delivery intent durably. Outbox
  shows waiting, delivering and review states, with time changes, cancellation
  and an explicit reviewed retry. Interrupted delivery is not retried silently.
- Outbox counts update for the selected account without reloading message bodies.
  Unsupported signing/encryption requests are rejected instead of sent as plaintext.

- Gmail draft and attachment staging survives app restarts in the local SQLite
  store. Cache refreshes preserve unsent compose content, account removal clears
  it, and local storage failures no longer turn confirmed sends into failed sends.

- Folder exports include every page and preserve original message bodies and
  attachments. Shared progress and cancellation controls identify the mailbox
  being exported; failed or canceled work leaves existing output intact.
- Settings offers an independent export mailbox selector, and EML exports create
  a new folder without overwriting previous files. Export privacy copy now
  explains when original messages are downloaded.

- Save As writes the original MIME bytes for a message, preserving non-UTF8
  content and attachments. It is offered only by backends with byte-preserving
  export support.

- IMAP and Gmail original-message retrieval preserves MIME encodings and
  attachment bytes through the source cache. Byte-preserving reads refresh
  older text-only entries and support cached source access while offline.

- Undo reopens the restored message with its current provider ID, including older
  mail outside the first refreshed page. It preserves a different folder or
  message selected while the reversal was running.

- Mail Undo covers toolbar, row and bulk flag/move/trash actions using provider
  destination identities. IMAP validates mailbox generations before reversing
  moves; Gmail preserves unrelated labels. Native macOS Undo keeps text editing
  separate, and account retirement invalidates pending Undo.
- Partial bulk moves retain Undo for confirmed folder operations and restore only
  failed rows. Moving to the current folder leaves the list unchanged.
- MBOX escaping preserves non-UTF8 message bytes while quoting separator lines.

- Failed mail Undo actions now show an error with Retry Undo instead of silently
  discarding the failure. Reversals run once at a time and refresh mail on success.

- Selecting an unflagged reply inside a filtered conversation keeps the reader
  open with that reply and the conversation context.
- Smart Views share a compact condition editor in Mail and Settings, with
  all/any matching, text comparisons, dates, status, mailbox, and folder rules.
  Existing saved filters retain their scope when edited.
- Smart Views settings can hide the entire sidebar section, show or hide each
  built-in/custom view, and reorder them together without deleting definitions.
- Saved message views search cached folders across the active profile, with
  explicit Sent/Trash inclusion and duplicate handling for label providers.
  They use all cached IMAP headers rather than the ordinary search-result cap,
  and preserve complete Gmail label membership for positive/negative folder rules.

- Profiles now sit above independently collapsible mailbox groups. Multiple
  inbox/folder trees can stay open together, and expansion choices are saved
  locally across profile changes and relaunches.
- Mailbox headers are compact single lines, with addresses available on hover
  and unread counts on collapsed groups. All Inboxes uses the active profile.
- Folder rows use source-scoped identities so identical provider folder IDs
  remain distinct when several mailboxes are expanded together.

- Mail split gaps and the AI Sidebar resize gutter now paint themed backdrops,
  preventing bright window backing from showing as thick white dividers.
- AI Sidebar resizing uses stable pointer coordinates, responds immediately
  when reversing from a width limit, and commits the final release position.
- Settings groups Accounts with Appearance under App. Advanced and Extensions
  use the same section headings and flat row alignment as the other groups.

- Settings follows the selected mailbox with an explicit source selector in
  Folder Sync. New retention overrides are isolated by account, mailbox, and
  folder; legacy preferences remain available until overridden.
- Folder Sync uses compact hierarchical rows, a folder filter, and labeled
  retention and visibility controls. Settings navigation shares Mail's
  selection palette, with clearer account and mailbox defaults.
- Settings search finds control names and opens the matching location.
  Appearance includes a sample-mail preview and expandable window details;
  Mailbox View separates reading, list, folder, and sender-image preferences.

- Default Mono Light and Mono Dark metadata now meets 4.5:1 contrast across
  normal, hover, and selected surfaces. Mail rows use opaque selection fills
  with separate indicators; custom accents no longer wash out selected text.
- New macOS windows prefer a 1440x820 layout and a 420-point message list.
  Conversations use a bounded 840-point reading column, tighter headers, and
  a message display menu. Dark reading canvases match the app background.
- Split the root view's modifier chain to avoid hosted-compiler type-check
  timeouts while preserving its lifecycle and presentation behavior.

- Reading a message keeps Unified Inbox, smart views, and saved searches open.
  Late list/page responses no longer replace a different profile or search.
- Bulk actions retain successful account changes when another account fails;
  failed messages remain selected with partial-success feedback.
- Profiles retain unavailable mailbox memberships and their active selection.
  Account restoration updates the workspace without resetting navigation.
- Pins are now scoped to account, mailbox, and message. Profile loads never
  prune pins elsewhere. Legacy unscoped records are retained; an in-app notice
  explains that older messages must be pinned again to assign their mailbox.
- Gmail lists cached headers before reconciliation and bounds missing-message
  requests to four at a time. Unified Inbox publishes healthy sources as they
  finish, keeps cached content readable during refresh, and debounces searches.

- The inbox category bar now floats over the message list instead of
  sitting above it, so rows scroll beneath it and fade out behind its
  translucent chrome — restoring the "list hides behind the blur"
  reading at the top of the list on accounts with Gmail categories.

- The message list's scroll-edge blur now sits on the list's own scroll
  viewport instead of the pane top, so rows fade out where they actually
  clip — below the inbox category, bulk-action, and search bars when
  those are shown. On accounts without those bars the band keeps its
  previous position under the toolbar.

- Gmail accounts on the native Gmail API adapter no longer open messages
  as an empty body showing only the list snippet. Label sync stores
  metadata-format messages (headers without body parts), and the body
  read wrongly treated any stored payload as complete; it now performs
  a full-format fetch whenever the stored payload yields no content.

- Opening a message no longer poisons the shared IMAP session. Cancelling
  an in-flight background read (which every message open does) tore down
  the connection while leaving it marked authenticated, so the next body
  fetch ran on a dead socket and the reader silently kept the list
  snippet. The cancellation teardown now invalidates the session so the
  next operation reconnects and logs in again. The structured-body
  fallback path also logs the error it previously swallowed (subsystem
  `eu.brevmail.brev`, category `IMAPBodyFetch`).
- The reader now shows a visible "Showing a preview only" notice with a
  retry action when the full message body fails to download; previously
  the failure was silent and the cached snippet looked like the whole
  message. The underlying error is logged to the `eu.brevmail.brev`
  subsystem (category `MessageBodyLoad`).
- macOS reader and message-list panes no longer lose their translucent
  look when SwiftUI rebuilds split-view chrome after the last layout
  pass: the transparency repair now verifies its own settled pass and
  re-arms while it keeps finding restored opaque fills. The scroll-edge
  blur band also retries briefly while the material's layer tree is
  still building, and logs (subsystem `eu.brevmail.brev`, category
  `ScrollEdgeBlur`) if it has to disable itself.

## [0.1.0] - 2026-08-28

### Added

- Initial public source baseline for the native macOS and iOS apps.
- Native Gmail API support for Gmail and Google Workspace accounts.
- Standards-based IMAP/SMTP support for other mail providers.
- Local-first mail storage, search, compose, settings, and privacy controls.

[Unreleased]: https://github.com/henrikogaard/brev/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/henrikogaard/brev/releases/tag/v0.1.0
