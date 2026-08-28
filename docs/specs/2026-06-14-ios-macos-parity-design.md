# iOS feature parity with macOS — design

- **Date:** 2026-06-14
- **Status:** Approved (scope + architecture locked with Henrik)
- **Related ADRs:** ADR-0028 (invariants), ADR-0011 (BrevMail composite UI),
  ADR-0028 (standards-first roadmap), ADR-0029 (IMAP/SMTP backend).
  Introduces a new ADR-0033 (iPad multi-window / auxiliary presentation).

## Goal

Bring the iOS app to behavioral parity with macOS for the agreed
workstreams, *adapted for touch and for iPhone/iPad form factors*.
"Fully functional" here means feature parity — not a bigger feature
backlog. Each workstream is independently shippable and ends at a
build-and-run verification gate.

## Background

Both apps are thin shells over shared packages (`apps/iOS` is 6 Swift
files; the UI lives in `BrevMail` and friends). A parity audit found
that core mail (compose, reader, sync, settings, account setup, push,
background refresh, offline replay) is already at parity via
platform-adaptive code. The genuine gaps are narrow, and several are
already half-built on the shared side:

- The `@FocusedValue` command plumbing in `FocusedMailValues.swift`
  (navigation, message actions, compose presentation, print/export) is
  **shared and published unconditionally** by `BrevMailRootView`. Only
  the *consumer* — `apps/macOS/Sources/BrevMailCommands.swift` — is
  macOS-only. Keyboard shortcuts and print on iOS are largely a matter
  of adding consumers/implementations for values that already exist.
- `UIApplicationSupportsMultipleScenes` is already `true` in
  `apps/iOS/Resources/Info.plist`; the app simply never opens a second
  scene.
- iOS deployment target is **17.0**, so `WindowGroup(id:for:)`,
  `openWindow`, `UIPrintInteractionController`, `UIGraphicsPDFRenderer`,
  and the document picker are all available.

## Scope

In scope (confirmed):

1. **Settings cleanup** — hide inert macOS-only controls on iOS.
2. **iPad keyboard shortcuts** — port the macOS command menu.
3. **Print / Export PDF** — message and thread.
4. **iPad multi-window** — detached compose/reader (Approach B).
5. **Verification & QA** — build/run matrix + iOS smoke checklist.

Explicitly out of scope:

- Mail import/export (mbox/eml).
- Sparkle auto-update (App Store handles iOS updates).
- `NSVisualEffectView` materials, transparent titlebar, drag-to-desktop,
  native `NSToolbar` — macOS chrome with no sensible iOS analogue.

Noted as a **dependency, not parity work:** Gmail/Outlook OAuth shows
"Coming soon" in the *shared* `LoginView` (affects macOS equally). It is
externally gated on OAuth client credentials (issues #185 / #187) and is
tracked separately.

## Architecture

### 1. Settings cleanup

`AppearanceSection` renders window-translucency and "Transparent title
bar" controls on iOS where they do nothing. Wrap those controls in
`#if os(macOS)` so iOS only shows controls that have an effect. The
`UpdatesSection` already degrades correctly on iOS
(`SettingsUpdateActions.unavailable`); leave it.

- **Files:** `packages/BrevSettings/Sources/BrevSettings/Sections/AppearanceSection.swift`
- **Risk:** near zero. No new behavior; removes misleading UI.

### 2. iPad keyboard shortcuts — shared `MailCommands`

Extract the command **definitions** from
`apps/macOS/Sources/BrevMailCommands.swift` into a shared
`MailCommands: Commands` builder in `BrevMail` that reads the existing
focused values (`mailNavigation`, `mailMessageCommandActions`,
`mailComposePresentationActions`, `refreshSelectedMailFolder`,
`mailPrintExportActions`). Both app shells attach it via
`.commands { MailCommands() }` on their root scene.

- Cross-platform commands: New Message (⌘N), Get New Mail (⌘⌥R),
  Reply (⌘R), Reply All (⌘⇧R), Forward (⌘⇧F), Toggle Read (⌘⇧U),
  Toggle Flag (⌘⇧L), Archive (⌘E), Delete (⌫), Move (⌘M),
  Junk (⌘⇧J), Previous/Next message (⌘↑/⌘↓), Focus Search (⌘/).
- macOS-only commands stay behind `#if os(macOS)` inside the shared
  builder (or remain in the macOS shell): Import/Export panels,
  Print/Export-PDF *menu wiring* (the iOS print action attaches
  directly — see §3), Check for Updates, Keyboard-Shortcuts window,
  window management.
- iPhone: commands are harmless without a keyboard. iPad: surfaced as
  hardware-keyboard shortcuts and in the ⌘-hold discoverability HUD.

- **Files:** new `packages/BrevMail/Sources/BrevMail/MailCommands.swift`;
  edit `apps/iOS/Sources/BrevApp.swift` (attach `.commands`),
  refactor `apps/macOS/Sources/BrevMailCommands.swift` to consume the
  shared builder.
- **Risk:** low. Focused-value scaffolding already ships and is
  exercised by macOS; the refactor must preserve every existing macOS
  binding (covered by the macOS smoke pass).

### 3. Print / Export PDF — shared HTML, platform drivers

The macOS path is `MessagePrintExportRenderer` (`NSPrintOperation` +
`NSAttributedString`/HTML). Factor the message/thread → print-HTML
generation into a shared producer (reusing the reader's existing HTML
pipeline), then drive it per platform:

- **Print (iOS):** `UIPrintInteractionController` with the rendered HTML
  (via a `UIPrintPageRenderer` or an offscreen `WKWebView`'s
  `viewPrintFormatter()`).
- **Export PDF (iOS):** render to PDF data (`WKWebView.createPDF` or
  `UIGraphicsPDFRenderer`) and present a share sheet / document-export.
- Supply an iOS implementation of `MailPrintExportActions` so the
  already-published `mailPrintExportActions` focused value is non-nil;
  hook it to the print command (§2) and to a reader toolbar action.

- **Files:** new shared print-HTML producer in `BrevMail`
  (e.g. `MailPrintDocument.swift`); iOS print driver; edits to
  `MessageDetailView` / `ThreadConversationView` toolbar wiring;
  keep `MessagePrintExportRenderer` macOS-only.
- **Risk:** medium. `WKWebView.createPDF` is async and requires the
  HTML to finish loading before rendering — gate render on
  `didFinish` navigation. Verify long threads paginate.

### 4. iPad multi-window — Approach B (ADR-0033)

macOS opens compose/reader/aux surfaces through
`MacMailAuxiliaryWindowPresenter` (`NSWindow`). **Leave that untouched.**
Add an iOS-only SwiftUI scene path:

- Define `WindowGroup(id:for:)` scenes in `apps/iOS/Sources/BrevApp.swift`
  for **compose** and **reader (detached message)**, parameterized by a
  small `Codable`/`Hashable` payload (e.g. message id + account id, or a
  compose-draft handle).
- Extend the shared `MailAuxiliaryPresentationModifier` seam: it already
  branches `#if os(macOS)` (NSWindow presenter) vs `#else` (`.sheet`).
  Add, inside the `#else`, an idiom/size-class branch: on iPad regular
  width, route through `@Environment(\.openWindow)`; on iPhone (and iPad
  compact) keep `.sheet`.
- iPhone is unaffected (no multi-window) — `openWindow` is only invoked
  on iPad regular.

- **Files:** `apps/iOS/Sources/BrevApp.swift` (new scenes),
  `packages/BrevMail/Sources/BrevMail/MailAuxiliaryPresentationModifier.swift`
  (iPad branch), supporting payload types in `BrevMail`.
  New **ADR-0033** recording the decision and the deliberate
  three-window-system state (macOS NSWindow, iPad SwiftUI scenes,
  iPhone sheets), with macOS unification noted as future work.
- **Risk:** medium. State handoff into a fresh scene (the new scene has
  no in-memory parent state) must reconstruct from ids via the backend,
  matching how the detached macOS window resolves its message. Drafts
  opened in a detached compose scene must reconcile with the offline
  draft staging store so a draft isn't duplicated or lost.

## Phasing

Ordered smallest-blast-radius first; every phase ends at a build + run +
smoke gate before the next begins.

| Phase | Workstream | Rough size |
|------:|------------|-----------|
| 1 | Settings cleanup | ~½ day |
| 2 | Shared `MailCommands` + iPad keyboard shortcuts | 1–2 days |
| 3 | Print / Export PDF (message + thread) | 2–3 days |
| 4 | iPad multi-window (ADR-0033 + scenes) | 3–5 days |
| 5 | Verification & QA matrix + iOS smoke checklist | 1 day |

## Verification

- Build the `BrevIOS` scheme via Tuist generate + `xcodebuild` for both
  an iPhone simulator and an iPad simulator destination.
- Run on iPhone + iPad simulators; exercise each workstream manually
  (iPad keyboard shortcuts require attaching a hardware keyboard / the
  simulator's "Capture Keyboard").
- Author `docs/smoke-checklist-results-2026-06-14-ios.md` mirroring the
  existing macOS smoke checklists, with a row per parity feature.
- Keep SwiftFormat/SwiftLint clean and verify against the stricter CI
  Xcode toolchain locally (see memory: CI Xcode 16.4 is stricter than
  local) before pushing.

## Risks & mitigations

- **Strict concurrency:** new `@MainActor` UIKit/WebKit print and scene
  code must satisfy `SWIFT_STRICT_CONCURRENCY = complete`. Build locally
  under the pinned recipe before each PR.
- **Async PDF render:** gate on `WKWebView` load completion (§3).
- **Detached-scene state:** reconstruct from ids; reconcile drafts with
  the staging store (§4).
- **macOS regression from the commands refactor:** preserve every macOS
  binding; the macOS smoke pass is the backstop (§2).

## Invariant check (ADR-0028)

No view imports provider-typed models; no new external network calls;
the rendering-pipeline and capability-driven-UI seams are untouched.
Multi-window reuses the existing auxiliary-presentation seam rather than
bypassing it. No invariant conflict — no escalation required.
