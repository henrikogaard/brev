# Brev

Modern, open-source mail client for macOS and iOS.
Local-first, standards-friendly, and free of telemetry.

**Status:** Pre-alpha. Not yet released.

## What this is

Brev is an open-source mail client for macOS and iOS. The current
app is built as a standalone Brev-owned product for both platforms,
with:

- A real Mac app (not iPad-on-Mac via Catalyst): three-column layout,
  menu bar, keyboard shortcuts, hover states, translucent sidebar.
- An iOS app rebuilt with modern SwiftUI.
- Thirty-four IDE-inspired themes out of the box (Nord, Nordic, Gruvbox, Solarized,
  Catppuccin, Tokyo Night, Rosé Pine, Brev's own Paper / Forest /
  Slate, and a developer-tool theme pack), plus user themes via JSON.
- Sender avatars with a cascading resolution chain: Contacts →
  Gravatar → BIMI → favicon → generated initials.
- Zero telemetry. No analytics, no crash reporting. Verifiable.
- MIT licensed.

## What this is not

- **Not finished.** v1 ships when Henrik can use it as a daily
  driver on both platforms for 30 days.
- **Not release-proven across providers yet.** The launch backend is
  standards-first IMAP/SMTP with built-in profiles, autodiscovery,
  manual setup, and OAuth/XOAUTH2 where provider credentials are
  configured. Real-provider QA is still in progress before v1.
- **Not a calendar client.** Brev handles incoming calendar
  invitations; it doesn't replace Calendar.app.
- **Not an AI product.** The optional AI Writer exists but is off by
  default and limited to compose assistance.

## Features

Brev is pre-alpha. The list below reflects what's actually wired up
in the current `main`. Things marked _partial_ work in the common
path but still have known gaps tracked on the GitHub project board.
Anything not listed is roadmap, not release-blocker.

### Platforms

- macOS app, AppKit-anchored: three-column layout, native menu bar
  and `NSToolbar`, keyboard shortcuts on every common action, hover
  states, translucent sidebar, drag-and-drop, Quick Look on
  attachments.
- iOS app, modern SwiftUI: phone and iPad layouts, compact-width
  reading pane stacked below the message list, iOS alternate app
  icons.
- Shared `BrevDesign` package (cards, toasts/snackbars, tooltips,
  skeletons, inline status banners) used by both targets.

### Mail — read, organize, compose

- Folder sidebar with capability-gated right-click actions: create
  subfolder, rename, delete, empty trash/junk, refresh.
- Smart Views with all/any conditions for sender, recipients, subject/preview,
  date, message status, mailbox, and folder. Searches use cached mail from the
  active profile; Sent and Trash inclusion is explicit. Manage visibility and
  mixed built-in/custom display order in Settings > Smart Views or the sidebar.
- Message list with: thread grouping, inline thread expansion,
  Outlook-style date sections (Today / Yesterday / Last week / …),
  pinned section, quick-filter chips (Unread, Flagged, …),
  per-folder stats footer (Compact / Detailed).
- Per-row swipe actions, context menus, and bulk actions for
  read/unread, flag/unflag, archive, move, delete, with single-flight
  guards across every entry point (toolbar, menu, swipe, drag).
- Native `.searchable` search bar with server-side search and a
  local fallback (snippets, sender, recipients) on a 250 ms debounce.
- Reading pane: lazy body load, automatic mark-as-read, attachment
  preview via Quick Look, RSVP banner for calendar invites,
  Previous / Next message keyboard navigation (`⌘↑` / `⌘↓`).
- Sandboxed `WKWebView` HTML renderer with JavaScript disabled,
  `WKContentRuleList`-blocked subresources by default, and an
  explicit "load remote images" override per message or per
  sender/domain.
- Threaded conversation view (Gmail / Apple Mail style) for backends
  that advertise `serverSideThreading`. Newest message auto-expands;
  HTML bodies render through the shared safe-body pipeline.
- Compose: chip-style recipient fields with separate Cc/Bcc rows, recipient
  autocomplete from local Apple Contacts (read-only), a separate removable
  recent-recipient list, and available CardDAV sources; attachment picker with
  multipart upload, Reply / Reply All /
  Forward with quoted-text placement preference, signature
  selection per account (with explicit "No signature" persistence),
  Save Draft, single-flight send/save, AI preview before apply.
- Drag-and-drop messages onto sidebar folders.

### Calendar invites

- `BrevCalendar` ICS parser (RFC 5545 line-unfolding, escaped text,
  UTC / floating / all-day, ORGANIZER / ATTENDEE parsing) — used as
  the local invite parser for standards-based mail backends.
- Inline invite banner in the reading pane (summary, start–end,
  location, organizer) with single-flight Accept / Maybe / Decline
  buttons gated on `serverSideCalendarReply`.

### Avatars

- Cascading resolution chain: Contacts → in-memory cache → Gravatar
  → BIMI → favicon → generated initials with the active theme
  palette.
- Every external lookup is gated by an opt-in privacy toggle, and
  toggling any source re-resolves visible avatars immediately.
- BIMI SVG payloads that embed remote image or style references are
  rejected before render so an opt-in logo fetch can't trigger
  hidden follow-up loads.

### Theming & appearance

- 34 built-in themes: Nord, Nordic, Gruvbox Light/Dark, Solarized
  Light/Dark, Catppuccin Latte/Mocha, Tokyo Night, Rosé Pine, Brev
  Paper / Forest / Slate, plus the developer-tool and
  terminal-classic packs (One Dark Pro, Tomorrow Day/Night,
  Synthwave Dusk, Cobalt Night, Amber Terminal, and others).
- Light/dark pairing modes: follow system, always light, always
  dark — with independent light and dark theme choices.
- User themes via JSON files in `themes/`.
- Window material modes: solid, subtle, frosted, glass-style,
  scoped to sidebar, mail window, or all Brev windows.
- Independent pane and sidebar opacity sliders, a message-content override
  with an opaque accessibility option, transparent titlebar toggle, and
  material-aware compose/Settings windows.
- Twenty selectable Brev app icon variants; macOS Dock icon switching
  and iOS alternate icons.

### AI Writer (opt-in)

- `AIBackend` protocol with eight shortcut actions (shorten,
  expand, formal, casual, …) plus subject suggestions and reply
  drafting.
- `ProviderHostedAIBackend` is the provider-hosted implementation,
  resolved per active mailbox when the signed-in provider supports it.
- Off by default. Consent gate, per-action transparency label,
  selection-aware rewriting, composer-local preview panel with
  replace/insert/copy/retry/cancel before any draft mutation.
- User-controlled AI providers are configured in Settings: direct
  OpenAI-compatible, Ollama/local, and custom endpoints with Keychain-only
  API-key storage, a default provider, and explicit per-account overrides.
  Brev never proxies prompts, sells credits, or selects a different provider
  on the user's behalf.

### Privacy

- Zero telemetry. Matomo, Sentry, Firebase, Mixpanel, and Amplitude are
  banned imports.
- Zero-network-by-default invariant verified by `BrevTesting` and
  `scripts/privacy-audit.sh`; every external lookup (Gravatar, BIMI,
  favicon, Contacts) is opt-in and listed in `PRIVACY.md` and
  ADR-0006.
- Optional cross-device preference sync through your own iCloud
  Key-Value Storage (snoozes, VIPs, inbox category choices, pinned
  messages, signatures, templates, and similar small preferences —
  never mail, accounts, or passwords). Off by default; Settings →
  Privacy → "Sync preferences with iCloud" (ADR-0056).
- HTML remote-content detection covers `src` / `srcset` / `poster`
  / `background` / stylesheet URLs (quoted and unquoted) and the
  non-rich fallback skips attributed-HTML import for remote-asset
  messages unless the user explicitly allows.

### Settings

- Native macOS Settings window, iOS Settings screen, and an
  in-window settings sheet on macOS, all driven by a shared typed
  persistence boundary.
- Sections: Appearance (theme mode, themes, materials, opacity,
  app icon), Mailbox View (renderer, remote images, grouping,
  avatars, preview lines, font, density), Compose (signatures,
  quoted-text placement, Cc/Bcc defaults), Privacy (avatar sources,
  remote-content allowlist, iCloud preference sync), AI Writer (consent, provider editor),
  Accounts (add, sign out, per-account backend badge), Browser
  (external-link app preference), Updates (macOS Sparkle).
- Section availability is gated by an explicit feature-flag model
  so roadmap-only panels stay hidden by default.

### Multi-account & multi-mailbox

- Multiple connected mailboxes in the sidebar header switcher,
  unified inbox across sources with source-scoped backend
  operations, source-aware paged loading, partial source-load
  warnings, safe source-scoped drag/drop, and ordered local
  Profiles that filter visible mailboxes without disconnecting
  accounts.
- Mailbox switching is single-flight across sidebar, in-window
  Settings, and root paths; pending sign-out and pending mailbox
  states are surfaced inline.

### Backends today

- `IMAPSMTPBackend` (macOS and iOS): standards-first IMAP receive/sync
  and SMTP send, with provider profiles, RFC 6186 DNS SRV probing,
  provider-local autoconfig, manual setup, Keychain-backed credentials,
  OAuth/XOAUTH2 where configured, server-side search, local cache/index
  repair, offline mutation recovery, IDLE/polling refresh, draft
  persistence, attachment handling, and capability-driven settings.
- `GmailAPIBackend` (macOS and iOS): Gmail-native message and thread identity,
  labels, history synchronization, search, drafts, send-as identities, and
  provider errors behind the same `MailBackend` interface.
- `MockBackend`: two preview mailboxes with distinct folder/message
  stores, mailbox-change events, draft persistence with attachment
  bytes, demo calendar invite, useful Trash/Sent semantics. Used by
  `BREV_USE_MOCK=1` on both platforms.

### Distribution & updates

- Direct download macOS builds ship an in-app Updates surface with
  Sparkle 2 integration, stable/beta appcasts, manual update
  checks, release-machine public-key injection, and a release
  preflight script.

### Developer experience

- Tuist + SPM project generation, `mise`-pinned toolchain,
  custom SwiftLint rules enforcing the ADR-0028 invariants, ADR
  required-paths CI gate.
- Snapshot tests for every BrevDesign primitive and BrevMail
  surface across every built-in theme; Swift Testing for behavior;
  `scripts/desktop-smoke-mock.sh` and `scripts/privacy-audit.sh`
  for working-app validation without OAuth.
- `script/build_and_run.sh` with `--mock` / `--live` / `--verify` /
  `--logs` / `--telemetry` / `--debug` / `--setup-env` /
  `--preflight` / `--print-config` for fast desktop iteration. Normal runs
  produce an isolated `Brev Test (YYYY-MM-DD).app`; only explicit
  `--release-main --live` from clean current main can replace `Brev.app`.

## Roadmap

The roadmap is governed by [ADR-0028](ADRs/0028-mail-provider-architecture.md)
(provider architecture and invariants) and
[ADR-0029](ADRs/0029-imap-smtp-backend-foundation.md)
(IMAP/SMTP backend foundation).
The lists below are the user-facing shape of those decisions, not
commitments to dates.

### Toward v1 release

v1 ships when Henrik can use Brev as a daily driver on macOS and
iOS for 30 days each without falling back to another client
(ADR-0028). The current focus is closing the remaining gaps:

- Real-provider QA under realistic mailbox volumes, including Gmail API,
  Gmail IMAP fallback, Fastmail/profile autodiscovery, and generic IMAP/SMTP.
  Microsoft OAuth-over-IMAP/SMTP remains a compatibility path while native
  Graph/Exchange support stays deferred.
- Full-mail download/indexing, server-side search, and local storage
  visibility QA with redacted live-provider evidence.
- Real-device QA on iOS (compact reading pane, alternate icons, and
  local/background notifications) — currently driven by snapshot and unit
  coverage.
- macOS notarization, Sparkle release-machine hardening, and the
  first signed beta (`docs/release.md`).
- App Store submission for iOS; macOS App Store is a v1.1 concern.

See `docs/github/issue-drafts.md` for the working list.

### Provider support status

Current:

- Standards-first IMAP/SMTP account setup with built-in provider
  profiles, DNS SRV probing, provider-local autoconfig, manual setup,
  Keychain-backed credentials, STARTTLS/implicit TLS, IMAP IDLE, SMTP
  send, and capability-driven UI.
- OAuth/XOAUTH2 for Gmail and Microsoft accounts when the app build is
  generated with the required provider client IDs.
- Native Gmail API support alongside the standards-first IMAP/SMTP path.

Live-QA pending before v1:

- End-to-end onboarding for Gmail, Fastmail, and generic IMAP/SMTP accounts.
- Server-side search, Download all mail / local index rebuild, storage
  accounting, retention, reset, and restart/offline behavior against
  real or disposable provider accounts.

Future/deferred:

- Native Exchange / Microsoft 365 Graph or EWS support, shared
  mailboxes, delegated mailboxes, and enterprise/admin policy controls.
- JMAP backend (Fastmail and beyond).
- S/MIME parity beyond the current macOS-only outbound implementation. iOS
  remains fail-closed until a public, standards-compliant CMS encoder is
  available or an audited permissive implementation is adopted.
- Client-side calendar invite handling via iMIP plus optional
  CalDAV write target. `BrevCalendar`'s ICS parser is already the
  fallback path.
- AI Writer for user-configured providers (OpenAI-compatible, Ollama / local
  LLM, and custom endpoints), directly connected from the device with a
  visible destination label and no Brev-operated token/credit service.

### v3+ — recorded, not architected

These appear in ADR-0028 so v1 and v2 decisions don't foreclose
them. They are not committed.

- Self-hosted JMAP backend support (Stalwart, Cyrus).
- Privacy-proxy infrastructure on `brevmail.eu` so optional
  avatar / favicon / BIMI lookups go through Brev instead of
  directly to third parties.
- End-to-end-encrypted backend for cross-device settings sync, if
  it ever becomes desirable.
- Read-side AI features (summarize, triage) gated on local-LLM-only
  paths and separate consent.

### Permanent non-goals

- Windows or Linux ports.
- A calendar app, a contacts app, or kDrive integration. Mail
  only.
- Automatic AI on read or compose. AI is always user-initiated,
  per ADR-0008 and ADR-0028 invariant 6.
- Telemetry of any kind, even "anonymous" or "crash-only".

## Architecture

See `ADRs/` for the architectural decisions. Start with:

- [ADR-0001: MailBackend domain boundary](ADRs/0001-backend-abstraction.md)
- [ADR-0028: Mail provider architecture and invariants](ADRs/0028-mail-provider-architecture.md)
- [ADR-0029: IMAP/SMTP backend foundation](ADRs/0029-imap-smtp-backend-foundation.md)
- [ADR-0064: First-class Gmail API backend](ADRs/0064-first-class-gmail-api-backend.md)

## Building

Brev builds with Xcode 16.2+ on Apple Silicon Macs. Tool versions are
pinned via [mise](https://mise.jdx.dev/).

```sh
# One-time setup
mise trust .mise.toml              # allows mise to read the repo-pinned tools
mise install                       # installs pinned tuist / swiftlint / swiftformat / swiftgen
scripts/install-hooks.sh           # installs the pre-commit lint hook

# Generate workspace
scripts/prepare-xcode-workspace.sh # resolves deps, overlays, and generates Brev.xcworkspace

open Brev.xcworkspace
```

Direct builds without Xcode:

```sh
scripts/prepare-xcode-workspace.sh

xcodebuild -workspace Brev.xcworkspace -scheme BrevIOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipMacroValidation build

xcodebuild -workspace Brev.xcworkspace -scheme BrevMacOS \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipMacroValidation build
```

Run the prepare script again after changing Tuist manifests, package
dependencies, or generated project files. Direct Xcode and
XcodeBuildMCP builds need the generated `Tuist/.build/tuist-derived`
module maps; if those are stale or missing, builds can fail with
missing module map errors and then a cascade of unresolved package
modules.

### Running the macOS app locally

The Codex app Run action is wired to:

```sh
./script/build_and_run.sh
```

That script builds `BrevMacOS`, stops any previously running copy,
and launches the fresh app. It defaults to `BREV_USE_MOCK=1` so the
desktop UI opens against `MockBackend` without needing network or
OAuth configuration.

Debug builds launched in live mode also show a "Use demo mailbox"
button on the login screen. It opens the same local `MockBackend`
without making a network call, which is useful when you want to test
the real login screen or settings flow without provider accounts.

Live mode uses the standards-first IMAP/SMTP account setup path.
Server settings and credentials are entered in the app. Gmail and
Microsoft OAuth buttons appear when the app receives the corresponding
provider client IDs from `.env.local` / `.env.example`; otherwise users can
still use supported manual IMAP/SMTP setup.

You can ask the run script to create an ignored `.env.local`
placeholder and then run:

```sh
./script/build_and_run.sh --setup-env
./script/build_and_run.sh --preflight --live
./script/build_and_run.sh --print-config --live
./script/build_and_run.sh --live
```

`.env.local` is ignored by git and is loaded by the run script before
launching the app. The file is parsed as simple dotenv-style
`KEY=VALUE` assignments, not as a shell script, and only the
run-script keys shown in `.env.example` are imported. The run script passes
the current platform OAuth values as explicit Xcode build settings, so a
stale tracked/generated project cannot retain an old client ID. Direct
Xcode or `xcodebuild` builds still need
`scripts/prepare-xcode-workspace.sh` after changing OAuth values so Tuist
regenerates the target settings. Google native OAuth
uses separate native clients for macOS/Desktop and iOS, both protected by
PKCE and state validation. macOS uses a Google Desktop client, its generated
non-confidential client credential, and an ephemeral
`http://127.0.0.1:<port>/oauth2redirect` listener; its configured redirect base
and callback scheme default to `http://127.0.0.1` and `http`. The generated
Desktop value is required by Google's token endpoint and may be recoverable
from the app bundle, so it is never treated as proof of app identity, committed,
or printed. Brev uses `ASWebAuthenticationSession` for the system web session.
On macOS, the session asks the user's default browser to handle sign-in and
falls back to Safari when needed. On iOS, Brev uses the configured callback
scheme and redirect URI when present; otherwise it passes Google's
reversed-client-ID scheme to the session and derives
`<reversed-client-ID>:/oauth2redirect`. iOS does not receive the Desktop
credential. The non-ephemeral session may reuse system
browser cookies for SSO, but Brev cannot access those cookies. Cancelling stops
the web session on both platforms and also stops the loopback listener on
macOS. `scripts/check-imap-oauth-setup.sh`
fails fast when the credential, scheme, exact callback, or effective plist keys
are inconsistent. Microsoft OAuth continues to use `brev://oauth`.

The script also supports:

```sh
./script/build_and_run.sh --mock
./script/build_and_run.sh --live
./script/build_and_run.sh --preflight
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
./script/build_and_run.sh --setup-env
./script/build_and_run.sh --help
```

After every `tuist install` (or when package dependencies change), run
`scripts/prepare-xcode-workspace.sh` before direct `xcodebuild` or
XcodeBuildMCP builds from a fresh checkout.

## Linting

```sh
scripts/lint.sh        # CI-equivalent: swiftformat --lint + swiftlint --strict + ADR gate
scripts/format.sh      # apply swiftformat fixes
```

Custom lint rules enforce the invariants in
[ADR-0028](ADRs/0028-mail-provider-architecture.md) — see
[ADR-0005](ADRs/0005-enforcement.md) for the full list.

## Localization

Brev uses Xcode String Catalogs (`.xcstrings`) for user-visible text.
Both app targets set `SWIFT_EMIT_LOC_STRINGS = YES`, so building in
Xcode extracts new strings into the target's `Localizable.xcstrings`
(and `InfoPlist.xcstrings` for `Info.plist` values) automatically —
no separate extraction step to run.

- **App targets** (`apps/macOS`, `apps/iOS`,
  `apps/iOS/BrevShareExtension`): use `String(localized: "...")` for
  non-SwiftUI strings (`NSAlert`, `NSSavePanel`/`NSOpenPanel`,
  `UILabel.text`) and plain `Text("...")` for SwiftUI — both resolve
  against the main app bundle, so no `bundle:` argument is needed.
- **SPM packages**: use `Text("...", bundle: .module)` for SwiftUI and
  `String(localized: "...", bundle: .module)` for everything else
  (`LocalizedError.errorDescription`, `.accessibilityLabel`,
  disclosure copy). Omitting `bundle: .module` in a package silently
  falls back to resolving against the host app's bundle instead of the
  package's own catalog. Each localized package carries
  `Sources/<Package>/Resources/Localizable.xcstrings` and declares
  `resources: [.process("Resources")]` on its target in
  `Package.swift`.
- Protocol strings, log lines, storage keys, identifiers, and wire
  formats (MIME, ICS, CalDAV XML) are never wrapped — only
  user-visible text is localized.

See [ADR-0058](ADRs/0058-localization-via-string-catalogs.md) for the
full rationale.

**Adding a language:** open the relevant `.xcstrings` file in Xcode
and add the locale there — Xcode manages per-string translation state
in the same file, no new file to create per language.

## Snapshot tests

`packages/BrevDesign/Tests/BrevDesignTests/` covers the design
primitives with [`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing).
UIKit snapshots run on iOS and AppKit snapshots run on macOS; references live
next to the test file under `__Snapshots__/`.

```sh
# Run the required iOS snapshot lane. The helper selects the newest installed
# runtime/device; CI pins the pair below while refreshing the supported
# baseline.
BREV_IOS_RUNTIME=27.0 BREV_IOS_DEVICE="iPhone 17 Pro" \
  scripts/check-ios-snapshot-baselines.sh
BREV_IOS_RUNTIME=27.0 BREV_IOS_DEVICE="iPhone 17 Pro" \
  xcodebuild test -scheme BrevMail \
  -destination "$(scripts/ios-simulator-destination.sh)" \
  -testLanguage en -testRegion en_US \
  '-only-testing:BrevMailTests/BrevMailRootViewSnapshotTests/rootViewWideLayout()' \
  '-only-testing:BrevMailTests/MessageDetailViewSnapshotTests/bodyLoadErrorState()'

# macOS-only AppKit snapshot suites run against a macOS destination; they are
# compiled out of the iOS package test bundle.
xcodebuild test -scheme BrevMail \
  -destination 'platform=macOS,arch=arm64' \
  -testLanguage en -testRegion en_US \
  -only-testing:BrevMailTests/FolderSidebarSnapshotTests \
  -only-testing:BrevMailTests/MailContextColumnSnapshotTests \
  -only-testing:BrevMailTests/MailRootStatusRailSnapshotTests \
  -only-testing:BrevMailTests/MessageListRowSnapshotTests \
  -only-testing:BrevMailTests/ThreadInlineChildRowSnapshotTests

# Re-record only after reviewing a visual diff and confirming the change is
# platform rasterization drift, not changed copy/layout/state. See
# `docs/qa/ios-snapshot-baselines.md` for the required/deferred suite policy.
RECORD_SNAPSHOTS=YES xcodebuild test ...
```

Commit the regenerated PNGs alongside the change that produced
them, and mention the visual delta in the PR description.

## Contributing

Focused bug fixes, accessibility improvements, tests, and documentation are
welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.

If you're an AI agent (Claude Code, Codex CLI, etc.) working in
this repo, read [`AGENTS.md`](AGENTS.md) first.

## License

MIT. See [`NOTICE`](NOTICE) and [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)
for bundled third-party notices.

## Privacy

Brev collects no data. See [`PRIVACY.md`](PRIVACY.md) for the
specifics.

## Author

Henrik Øgård — [`@henrikogaard`](https://github.com/henrikogaard)
