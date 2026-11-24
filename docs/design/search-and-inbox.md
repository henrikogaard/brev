# Search, Inbox Organization & Conversations

> Consolidates former ADRs `0020`, `0035`, `0041`, `0044`, `0060`, and `0078`.

## Conversation View

- Threads group related messages into a stacked conversation in the reading pane (`ThreadConversationView`), auto-expanding unread/newest messages and collapsing read history with clear count indicators.
- Collapsed conversations in the message list preserve logical selection when an older child message is selected and restore child highlight cleanly on re-expansion.
- HTML bodies render through the shared sandboxed `WKWebView` pipeline with consistent typography, centered reading measure, attachment cards, and inline reply dock.

## Inbox Classification & Subscriptions

- **Two-way People / Updates split:** The inbox separates mail from real people (**People**) from receipts, notifications, and newsletters (**Updates**), plus an **All** tab with live unread/total counts.
- **Deterministic local classification:** Uses local signals (`List-Unsubscribe`, `Precedence: bulk`, no-reply addresses, transactional patterns, and reply history) with remembered per-sender overrides ("Move sender to People / Updates").
- **Updates sender bundling:** Multiple messages from the same automated sender fold into an expandable sender bundle with one-click undoable Archive.
- **Subscriptions view:** Dedicated sidebar mailbox built locally from cached `List-Unsubscribe` headers (`CachedListUnsubscribeProviding`), showing one row per newsletter sender with message count, last received date, undoable **Archive all**, and explicitly confirmed **Unsubscribe** (RFC 8058 One-Click POST, browser URL, or `mailto:` draft—never triggered automatically).

## Plain-Language Search & Query Chips

- **Cross-account by default:** Searching from a multi-account workspace searches across all visible accounts by default, with an explicit scope switcher (All accounts / Current account / This folder) and field filter (All / From / Subject) preserved across scope changes.
- **Bilingual query chips (`en` and `nb`):** Natural-language phrases (sender names, unread/flagged, date ranges, folder phrases like `in Sent` / `i Sendt`, and file filters like `pdf`) parse into removable visual chips.
- **Progressive execution:** Local cache results appear immediately (250 ms debounce) followed by server pages from IMAP/Gmail without disturbing the open reader; status chrome surfaces cached vs. server coverage and partial errors clearly.
- **Saved searches (Smart Views):** User-defined all/any rule combinations over sender, recipients, subject, date, status, attachment type, mailbox, and folder, runnable from the sidebar.

## Attachment Search & Background Indexing (Relaxed from Former ADRs `0041`/`0060`)

- **Metadata & content indexing:** `All Attachments` and PDF/attachment search combine cached attachment metadata (`CachedAttachmentMessage`) with local SQLite FTS indexing of downloaded attachment text (`BrevSyncEngine`).
- **Explicit server fetch:** Users can trigger on-demand server attachment fetches when searching beyond the local cache, with stale-request cancellation if the query changes mid-flight.
- **Background recent-mail indexing:** Opt-in **"Index recent mail & attachments in background"** (`BackgroundIndexingSettings`, strictly off by default, device-local and excluded from iCloud preference sync) in **Settings → Sync & Storage → Mail Storage**. When enabled, `BackgroundRecentIndexingCoordinator` politely backfills missing recent message bodies (30 / 90 / 365-day window, newest first, excluding Trash and Spam, never altering read flags) and optionally extracts text from eligible non-inline attachments up to 10 MiB (PDF, plain text, RTF, HTML) into the local SQLite FTS index (`LocalAttachmentTextIndexing`), automatically pausing on cellular/constrained networks or Low Power Mode when **Wi-Fi & power friendly** is enabled and cancelling cleanly on opt-out or account removal.
