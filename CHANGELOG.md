# Changelog

All notable changes to Brev are documented here.

## [Unreleased]

### Fixed

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
