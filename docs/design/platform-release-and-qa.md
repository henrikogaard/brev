# Platform Presence, Release Rings, Enforcement & QA

> Consolidates former ADRs `0005`, `0009`, `0037`, `0056`, `0075`, `0080`, `0091`, and `0092`.

## Mechanical Enforcement (Simplified from Former ADR-0005)

Brev enforces architectural and privacy invariants mechanically in CI and local scripts—**without** requiring a document update for routine code edits in UI or feature packages:

| Gate | Command / Workflow | What It Enforces |
| --- | --- | --- |
| **Formatting** | `scripts/format.sh` / `swiftformat --lint` | Deterministic Swift formatting |
| **Strict Lint** | `scripts/lint.sh` / `swiftlint --strict` | No literal colors in views, no banned telemetry imports, SwiftLint self-tests |
| **Privacy Audit** | `scripts/privacy-audit.sh` | Zero telemetry imports/artifacts, no Realm in views, no secret/body logging, defaults-off checks synced with [PRIVACY.md](../../PRIVACY.md) and [privacy-and-security.md](privacy-and-security.md) |
| **OpenPGP Retirement** | `scripts/test-openpgp-retired.sh` | Ensures retired OpenPGP code/docs do not reappear |
| **Build & Snapshot CI** | `.github/workflows/build.yml` | Reproducible Tuist projects, `BrevMacOS` + `BrevIOS` builds, all SPM test suites, macOS 26+ and iOS snapshot comparisons |

*(The former `adr-required` protected-path CI gate is retired. Update the matching doc in `docs/design/` when architecture, privacy, or protocols actually change.)*

## Distribution & Release Rings

- **macOS direct download (Developer ID + Notarization + Sparkle 2):**
  - **Stable ring (`eu.brevmail.brev`):** Tagged `vX.Y.Z` releases via `.github/workflows/release.yml`, EdDSA-signed Sparkle appcast on `gh-pages`.
  - **Nightly ring (`eu.brevmail.brev.nightly`):** Automated nightly pre-releases via `.github/workflows/nightly.yml` with distinct Nightly app icon and separate appcast feed.
  - Both rings build with the current macOS SDK (`>= 26`) to preserve native system chrome, embed signed `BrevMacWidgets` and `Contents/Helpers/brev-mcp`, and verify signatures via `scripts/release-artifact-verify.sh`.
- **iOS (App Store / TestFlight):** Released via `scripts/release-ios-beta.sh` and App Store Connect (`docs/release.md`).

## Background Mail & Notifications (Relaxed from Former ADR-0037)

- **macOS background presence:** Opt-in menu-bar/background mode with launch-at-login (`SMAppService`) keeps IMAP IDLE / Gmail sync, scheduled sends, actionable notifications (Archive / Mark as read / Reply), and the opt-in drop-down new-mail panel working when all windows are closed, with clean shutdown and no orphaned processes.
- **Closed-app notifications (iOS & generic IMAP):** Brev will **never** operate a cloud mail-proxy server that holds user credentials. For real-time closed-app delivery without a Brev proxy, Brev supports macOS background IDLE, iOS background fetch (`BGAppRefreshTask`), **future JMAP WebPush (`providers.md`)**, and optionally a user-hosted push relay for power users.

## iCloud Key-Value Preference Sync

- Opt-in (`Settings → Sync & Storage → Preferences`), off by default, syncing only allowlisted lightweight preferences (snoozes, done markers, VIPs, inbox category overrides, pins, blocked senders, follow-up reminders, signatures, templates, smart mailboxes, compose/sidebar preferences) via `NSUbiquitousKeyValueStore`.
- Remote absence never deletes local state. Mail content, credentials, and device-local security consents (sign-in codes, local MCP Agent access) are **never** synced.

## Local Development & Isolated Mock QA

- **Daily-driver protection (Hard Rule):** All local development and QA builds use `script/build_and_run.sh`'s dated Test identity (`Brev Test (YYYY-MM-DD).app`) and never replace or kill `/Applications/Brev.app`. Only an explicit `--release-main --live` run from clean `origin/main` updates `/Applications/Brev.app`.
- **Strict isolated mock (`--isolated-mock`):** Runs under a fresh per-run UUID bundle ID, pure App Sandbox entitlement (zero network, zero App Group, zero Contacts/Calendar), in-memory mock stores, and a private container so automated/UI tests cannot touch real user data.
- **Content-QA mock (`--isolated-mock-content-qa`):** Explicitly adds `network.client` and `files.user-selected.read-only` to the isolated UUID sandbox for native WebKit body and attachment-picker verification while still blocking App Groups, broad filesystem access, and live mail accounts.
