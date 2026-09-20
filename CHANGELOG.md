# Changelog

All notable changes to Brev are documented here.

## [Unreleased]

### Added

- Calendar/Contacts source foundation (ADR-0072): provider-neutral source
  records, a serial lifecycle coordinator covering connect / reconnect /
  sync opt-in / removal, and CalDAV/CardDAV setup validation (manual
  endpoints and RFC 6764 discovery with HTTPS enforcement and
  credential-safe redirect handling). No user-facing surface yet —
  settings UI, Google reauthorization and sync scheduling land in later
  slices.
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
  Import / Export, on macOS and iOS. Backups never include passwords or
  tokens; restored accounts ask you to sign in. Backups can now include
  local folders as `mail/*.mbox` payloads (on by default when local
  folders exist).
- Durable local folders ("On My Mac" / "On My iPhone") keep mail on this
  device outside every cache — nothing is evicted, uploaded, or removed
  until you delete a folder. On macOS and iOS, create folders from the
  sidebar and use Copy/Move to Local Folder on any message. Local folders
  are searchable and browsable like any account. MBOX/Maildir import into
  a local folder remains macOS-only for now.
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

- Desktop sidebar uses compact account headings, aligned top-level folders,
  regular-weight labels, quieter counts and a single rounded selection fill.
  A compact scope menu sits above All Inboxes on Mac and in the navigation
  bar on iPhone; custom profiles keep their names. Smart Views uses a quiet
  section heading with one menu for create/manage actions.
- Reader headers group secondary conversation controls into one menu, with
  larger message controls on iOS. Message bodies follow iOS Dynamic Type,
  and built-in themes use more legible secondary text colors.
- Mail toolbars emphasize the primary actions. Desktop columns start with a
  narrower sidebar and wider message list, while narrow rows keep sender and
  date readable. The iPhone inbox shows account context and groups its status
  with Compose at the bottom.
- Compose puts attachments and Send first, shows the compose mode on iPhone,
  and groups formatting and delivery options in secondary menus. Account
  settings show the fetch-interval explanation once.

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
- Performance: message lists and unified inbox no longer rescan every header
  per render pass (blocked senders, follow-ups, snooze/done state, last-week
  counts, and search chips are indexed once per change); expanding a long
  thread shares a bounded pool of renderers and fetches instead of one
  WebKit view and parallel fetch per card; Gmail refresh diffs lightweight
  message summaries instead of decoding the whole table twice; local search
  skips redundant index joins and rewrites; and launch does less blocking
  work (local search index opens on first use, the key-material migration
  runs once, and several settings payloads decode once instead of per
  evaluation).
- Automatic mail fetching now backs off after consecutive failures instead
  of polling a stuck account at full rate.
- Cross-platform consistency: the iOS reader now exposes the same
  capability-gated action menu as the message list (Reply All, Mark
  Read/Unread, Move To, Snooze, Done, Block Sender, Print, Export PDF),
  thread cards offer the same menu per message, and iPad can open a
  detached reader window from list context menus. Sheets no longer carry
  macOS minimum sizes on iOS, icon buttons meet the 44 pt touch target,
  iPad hardware keyboards get ⌘⌥Z mail undo without replacing native text Undo/Redo, action labels share one
  canonical wording, and shared `BrevIconButton`/quiet-surface/chip
  components replace hand-rolled copies.

### Fixed

- Keep the Create Folder field visible in short folder destination sheets.
- Preserve supplied plain-text paragraphs while attributed HTML import is pending
  or fails.
- Stop the iPhone conversation reader from repeatedly invalidating its command
  environment and remaining stuck at Loading message.
- Keep compose recipient fields within the available width and allow the form
  to scroll at accessibility text sizes while Close, Send and More stay visible.
- Simplify the desktop compose toolbar by grouping duplicate secondary actions
  in its menu and giving Send a visible label.

- Keep the iPhone conversation account address secondary at accessibility text
  sizes and label the compact message-loading indicator.

- Align iOS account headers with top-level mailbox folders; keep disclosure
  arrows at the trailing edge and indentation only for nested folders.

- iOS compose overflow retains registered plug-in contributions, and opening
  a unified-inbox message in another window preserves the original selection.

- Keep Offline runs in detached readers without opening extra mailbox windows; busy readers disable Reply and Forward.

- Cancelling permanent Delete preserves the conversation; confirmed deletion retains its source and folder.

- iPad shortcut help no longer advertises the macOS-only Settings shortcut.

- Detached-reader controls and thread-summary Retry use 44-point touch targets on iOS.

- Reader actions reserve space for snooze/delete/block confirmations and reject Block Sender while the mailbox is busy.

- macOS detached readers stay open when their mailbox cannot accept an action or present another dialog.

- Offline detached readers resolve exact cached folder membership even when the folder catalog is unavailable.

- Cancelling Block Sender preserves the current conversation; folder activation waits for confirmation.

- Reader presentation actions preserve the current conversation and remain available during transient folder-load errors.

- Detached readers preserve their originating folder, including Gmail labels; cross-folder actions activate the correct mutation context.

- Native Gmail detached readers look up cached messages by ID without decoding whole folders.

- iPad detached reader commands reach their mailbox even when Settings is open in another scene.

- Unified Inbox reader navigation applies the same category, mailbox and saved
  search filters as the list when reconciling Snooze, Done and Undo.

- Detached readers can resolve native Gmail headers through the cache-only
  backend contract. Removed accounts no longer fall back to another account.
- iPhone template, signature and local-rule rows keep their text and primary controls
  visible, with reorder and Delete actions in an accessible overflow menu.

- TestFlight/App Store Release builds now ignore demo-mailbox requests even if
  a future app integration accidentally injects one; CI compiles and tests this
  path under Release optimization.
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
- Mail import on macOS: the file picker accepts choosing a Maildir
  folder again. The content-type filter was disabling directory
  selection, making the advertised Maildir import unreachable;
  non-Maildir folders are still rejected by the importer itself.
- Opening a `mailto:` link and a `brev://` deep link in the same open
  event no longer drops the deep link; both are handed to the app
  instead of only the last matching URL.

- Reader and conversation-card actions execute in one owning window. Detached
  sheet actions return to a visible mailbox window; iPad handoffs execute once
  and do not replay when restoring a window. Snooze, Done, and undo keep folder
  and unified-inbox reader navigation aligned with visible messages.
- Thread-card PDF export errors use localized package strings on both platforms.
  The detached reader overflow icon follows the theme text color.

- iPhone mailboxes: keep search at one-row height, use larger sender and subject
  text with previews and two-line subjects, label Mailboxes/Inbox navigation,
  move Compose to the bottom toolbar, and remove duplicate Settings controls.
  Folder rows no longer reserve an empty desktop disclosure column; nested
  folders retain indentation and a separate expand/collapse target.

## [0.1.0] - 2026-08-28

### Added

- Initial public source baseline for the native macOS and iOS apps.
- Native Gmail API support for Gmail and Google Workspace accounts.
- Standards-based IMAP/SMTP support for other mail providers.
- Local-first mail storage, search, compose, settings, and privacy controls.

[Unreleased]: https://github.com/henrikogaard/brev/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/henrikogaard/brev/releases/tag/v0.1.0
