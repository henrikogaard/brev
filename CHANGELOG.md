# Changelog

All notable changes to Brev are documented here.

## [Unreleased]

### Fixed

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

## [0.1.0] - 2026-08-28

### Added

- Initial public source baseline for the native macOS and iOS apps.
- Native Gmail API support for Gmail and Google Workspace accounts.
- Standards-based IMAP/SMTP support for other mail providers.
- Local-first mail storage, search, compose, settings, and privacy controls.

[Unreleased]: https://github.com/henrikogaard/brev/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/henrikogaard/brev/releases/tag/v0.1.0
