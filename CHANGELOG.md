# Changelog

All notable changes to Brev are documented here.

## [Unreleased]

### Fixed

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
