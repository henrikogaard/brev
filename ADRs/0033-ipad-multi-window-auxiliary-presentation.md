# ADR-0033: iPad multi-window / auxiliary presentation

- **Status:** Accepted
- **Date:** 2026-06-14
- **Deciders:** Henrik

## Context

The macOS app opens compose, reader, and other auxiliary surfaces in
separate `NSWindow`s via `MacMailAuxiliaryWindowPresenter` (in BrevMail,
`#if os(macOS)`), plus SwiftUI `Window(id:)` scenes for Settings and the
Keyboard-Shortcuts window. This gives macOS users detached, independently
resizable windows for composing and reading.

The iOS app presented every auxiliary surface as a `.sheet` via
`MailAuxiliaryPresentationModifier`, with no multi-window support. This
was intentional for iPhone (single-window form factor) but left iPad
behind: `UIApplicationSupportsMultipleScenes` was already `true` in the
iOS `Info.plist` and the deployment target (iOS 17) supports
`WindowGroup(for:)` / `openWindow`. The iOS app never used them.

The iOS↔macOS feature-parity initiative (design spec
`docs/specs/2026-06-14-ios-macos-parity-design.md`) requires
the iPad to reach parity with macOS's detached compose and reader windows.
The two candidate approaches were:

- **Approach A:** Unify macOS and iPad onto a shared SwiftUI
  `WindowGroup(for:)` scene system, retiring `MacMailAuxiliaryWindowPresenter`.
- **Approach B:** Add an iOS-only SwiftUI scene path; leave the macOS
  `NSWindow` code untouched.

## Decision

**Approach B.** Add `WindowGroup(for:)` scenes in the iOS app for a
detached reader and a detached compose window. The macOS
`MacMailAuxiliaryWindowPresenter` path is not modified.

Specifics:

1. **New scene payloads in BrevMail.** Two small `Codable & Hashable`
   structs, `DetachedReaderWindowPayload` and `ComposeWindowPayload`,
   carry the minimum identity needed to reconstruct scene state
   (account id + message id for the reader; a compose-intent enum
   referencing message ids for compose). They are defined in BrevMail so
   both the iOS app target and BrevMail views can reference them without
   creating a new package.

2. **iOS-only `WindowGroup(for:)` scenes.** The iOS app registers two
   `WindowGroup(for: DetachedReaderWindowPayload.self)` and
   `WindowGroup(for: ComposeWindowPayload.self)` scenes. Scene state is
   reconstructed from the payload via the backend; no in-memory parent
   state is shared across scene boundaries.

3. **`MailDetachWindowPolicy`.** A tested policy type,
   `MailDetachWindowPolicy.shouldDetach(idiom:horizontalSizeClass:)`,
   centralises the platform/size-class decision: detach into a window
   on iPad regular width; keep `.sheet` on iPhone and iPad compact.
   Views and modifiers call the policy rather than checking `idiom`
   directly.

4. **Detach decision at call sites, not inside the modifier.**
   `MailAuxiliaryPresentationModifier` is unchanged — it remains the
   macOS `NSWindow` branch vs. the `.sheet` branch, exactly as before.
   The iPad detach decision is applied at the compose call sites in
   `BrevMailRootView`: a `shouldDetachCompose` check guards
   `presentNewMessage`, `presentReply`, `presentReplyAll`, and
   `presentForward`, falling through to the existing `.sheet` path when
   `false`. A parallel guard lives in the reader toolbar in
   `MessageDetailView`. When detaching, those call sites invoke
   `openWindow(value:)` directly, bypassing the modifier. The shared
   decision function at all of these call sites is
   `MailDetachWindowPolicy.shouldDetach(idiom:horizontalSizeClass:)`.

5. **macOS is unchanged.** `MacMailAuxiliaryWindowPresenter` and its
   frame autosave, cascading, and toolbar-styling logic are not touched.

## Rationale

**Approach A was rejected.** It would retire tuned, working macOS window
code — frame autosave, window cascading, `NSWindowDelegate` toolbar
styling, toolbar-in-presenter-hosted-NSWindow workarounds — for no parity
benefit on macOS itself. The risk of introducing macOS regressions in
exchange for code unification is not justified. Per the ADR-0028
invariants and the project rule against refactoring working code that
wasn't asked for, macOS unification is out of scope and is explicitly
deferred to a future ADR.

**Id-based state handoff.** Detached scenes cannot share in-memory model
objects with the originating scene. Reconstructing state from small id
payloads via the backend is consistent with how SwiftUI multi-window
works and avoids lifecycle coupling between windows. It is the approach
that aligns with `UISceneSession` and iOS's process model.

**Policy type rather than inline checks.** Centralising the
detach/sheet decision in `MailDetachWindowPolicy` makes the policy
testable in isolation and prevents different call sites from drifting
out of sync.

**Call-site guards keep the existing seam clean.** Placing the detach
decision at compose and reader call sites rather than inside
`MailAuxiliaryPresentationModifier` means the modifier stays narrowly
scoped to macOS-vs-sheet. The call sites consult `MailDetachWindowPolicy`
so the policy remains testable in isolation and all call sites stay in
sync, consistent with ADR-0011's composite-view seam design.

## Consequences

### Accepted

- Three window systems coexist deliberately: macOS `NSWindow` (auxiliary
  presenter), iPad SwiftUI `WindowGroup(for:)` scenes, and iPhone/compact
  `.sheet`. This is accepted divergence; macOS→SwiftUI-scene unification
  is deferred to a future ADR if and when it earns its keep.
- State handoff into detached scenes is id-based. Detached compose must
  reconcile with the offline draft staging store so a draft is neither
  duplicated nor lost when a compose window is opened or closed.
- iPhone behavior is unchanged: no multi-window; `.sheet` everywhere.
- Only iPad regular-width size class detaches; compact iPad stays on
  `.sheet`.
- The decision preserves the ADR-0028 invariants (view-layer boundary,
  capability-driven UI, rendering-pipeline seam) and reuses the existing
  auxiliary-presentation seam rather than bypassing it.

### Accepted v1 limitations

The following are deliberate scope cuts for the first cut. Each is a
recorded decision, not a silent omission. Follow-up work will close them.

- **Detached compose feature parity.** *Resolved 2026-06-14.* The detached
  compose window now matches the sheet-based compose: it restores a
  previously-saved new-message recovery snapshot on open, wires AI Writer,
  applies end-to-end-encryption send defaults, and offers multi-identity
  ("From:" alias) sender selection. The feature providers (AI backends,
  security defaults, trusted-identity counts) are injected from the app
  layer, mirroring `BrevMailRootView`; the shared
  `ComposeSenderIdentity.resolution`, `DetachedComposeInputs`, and
  `DetachedWindowResolver` helpers keep the two paths from drifting.
  Originally it reused the live backend's offline draft staging and
  cleared/saved the recovery snapshot on completion (so no phantom
  recovered-draft appeared after sending) but did not restore a snapshot on
  open, nor wire AI Writer, encryption defaults, or alias sender selection —
  those remained available only in the sheet-based compose.
- **Detached reader `.toolbar` actions.** *Resolved 2026-06-14.*
  `DetachedReaderWindowView` now wraps its hosted `MessageDetailView` in a
  `NavigationStack`, supplying the toolbar host the scene root previously
  lacked, so Print, Export-PDF, and "Open in New Window" render in the
  detached window alongside the in-content action bar (close/reply/etc.).
  Originally these `.toolbar` items were silently dropped because the
  scene root had no `NavigationStack` host; they remained available only
  from the main window's reader.
- **Multiple `.new` compose windows are not de-duplicated.** Each call
  to `openWindow(value: .new)` on iPad spawns a new scene. Preventing a
  second compose window from opening when one is already on screen is not
  yet enforced.

### Risks

- **Draft reconciliation complexity.** Id-based compose payloads mean
  the detached compose scene must load the draft from the staging store
  on open and save changes back on close. A crash between open and save
  could leave an orphan draft. Mitigation: the staging store should be
  the single source of truth; the detached scene reads from and writes
  to it atomically.
- **Scene state on restoration.** iOS can restore scene sessions after
  a relaunch. If the account or message the payload references has been
  deleted, the scene must handle a missing-resource path gracefully
  rather than crashing.
- **macOS divergence grows over time.** Deferring Approach A means two
  code paths for auxiliary window management. Future compose and reader
  features must be implemented in both paths until unification happens.

## References

- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0011: BrevMail package — composite mail UI
- ADR-0028: Standards-first IMAP/SMTP roadmap
- Design spec: `docs/specs/2026-06-14-ios-macos-parity-design.md`
- `BrevMail/MacMailAuxiliaryWindowPresenter.swift` — macOS NSWindow path
- `BrevMail/MailAuxiliaryPresentationModifier.swift` — existing presentation seam
