# ADR-0075: macOS background mail presence and launch at login

- **Status:** Proposed
- **Date:** 2026-09-16
- **Deciders:** Henrik

## Context

Issue #28 §6 asks for "an explicit, user-controlled macOS background-mail
option with visible status and safe termination behavior", and for the
background execution model to be agreed in an ADR before implementation.

What exists today on macOS (`apps/macOS/Sources/BrevApp.swift`):

- The process keeps running after the last window closes (AppKit default;
  Brev does not implement `applicationShouldTerminateAfterLastWindowClosed`).
- An `NSBackgroundActivityScheduler` fires `MailFetchScheduler.
  performBackgroundRefresh` roughly every 15 minutes while the process is
  alive, independent of window state.
- IMAP IDLE and the foreground fetch schedule run from `BrevMailRootView`,
  so they stop when the root view is gone.
- `applicationShouldTerminate` warns about pending scheduled sends and, since
  the 2026-09 performance pass, flushes deferred header-cache writes with a
  2-second budget before replying.

What is missing:

- The user cannot see that Brev is checking mail with no window open, when
  it last checked, or whether the last check failed. The only signal is the
  Dock indicator.
- The user cannot opt Brev in or out of this behavior; it is implicit.
- Brev cannot start with the session, so a daily driver that relies on
  notifications has nothing until the user launches it.
- ADR-0037 item 5 requires a new ADR before any helper or relay. This ADR is
  narrower than that: it changes nothing about where mail is fetched from.

Constraints: ADR-0006 (no new external network calls without opt-in and
disclosure), ADR-0028 invariants (capability-driven UI, provider-neutral
domain values), ADR-0037 (no hosted relay, no provider push, closed-app
delivery stays best-effort), Rule 7 (test builds never replace the daily
driver, which matters for launch-at-login registration).

## Decision

1. **Background mail is an explicit per-device preference, default off.**
   A "Keep checking mail in the background" toggle lives in Settings ›
   Notifications on macOS. It is a `UserDefaults`-backed setting in
   `NotificationSettings`, not synced through ADR-0056 key-value sync,
   because it describes a device's process behavior.

2. **When on, Brev shows a menu bar status item.** Implemented with SwiftUI
   `MenuBarExtra` in the macOS app target, consuming only Brev domain values
   (unread count from visible backends, last successful refresh time, last
   failure summary). The menu offers: current status line, "Check now",
   "Open Brev", and "Quit Brev". The status item is the visible proof that
   background checking is active; when the toggle is off, there is no status
   item and behavior is unchanged from today.

3. **When on, the fetch loop survives the last window closing.** The
   `MailFetchScheduler` tick loop and per-account IMAP IDLE ownership move
   from `BrevMailRootView` to a `@MainActor` `BackgroundMailCoordinator` in
   BrevMail owned by `AppSession`, so the root view becomes a subscriber
   rather than the owner. With the toggle off, the coordinator runs only
   while a mail window is open, preserving current behavior exactly.

4. **Launch at login is a separate opt-in sub-toggle**, enabled only when
   background mail is on, implemented with `SMAppService.mainApp`. Brev
   reads `SMAppService.mainApp.status` to render the true state (including
   `.requiresApproval`, with a button that opens System Settings › Login
   Items) rather than trusting its own flag. Test builds
   (`Brev Test (…).app`, Rule 7) must never register for login; the toggle is
   hidden unless the bundle identifier is the release identifier.

5. **Termination stays safe and unchanged in shape.** "Quit Brev" from the
   status item and ⌘Q both go through `applicationShouldTerminate`, which
   keeps the scheduled-send warning and the bounded cache flush. Closing the
   last window never quits, in either mode. Brev does not adopt
   `LSUIElement`/agent mode: the Dock icon remains, so the process is never
   invisible.

6. **Status honesty.** If the fetch schedule is "Manually", the status item
   says "Manual mode — IDLE only" and the Notifications toggle's subtitle
   explains that background checking follows the fetch schedule. Failures
   show the same provider-neutral summary the in-app sync health surface
   uses, never raw errors or account secrets.

7. **No new network behavior.** Background checking contacts the same
   IMAP/Gmail endpoints the foreground already uses, at the configured
   cadence. ADR-0006's network table is unchanged; `PRIVACY.md` gains one
   paragraph stating that, when enabled, Brev keeps running and checking
   mail with no window open and can start at login.

8. **iOS is unchanged.** ADR-0037's best-effort `BGAppRefreshTask` posture
   remains; nothing in this ADR applies to iOS.

## Rationale

- *Menu bar item vs. Dock-only:* the Dock indicator says "running", not
  "checking mail, last at 09:41, one account failing". A status item is the
  smallest surface that can say that, and it is where macOS users look for
  background agents.
- *Opt-in default off vs. on:* today's implicit behavior already runs; making
  it explicit and default-off is the honest baseline, and matches ADR-0006's
  opt-in principle even though no new network destination is introduced.
- *Moving the fetch loop to a coordinator vs. keeping a hidden window:* a
  hidden window is fragile (scene lifecycle, restoration, Dynamic Type
  layout passes for nothing). A session-owned coordinator makes the
  ownership explicit and testable without SwiftUI.
- *`SMAppService` vs. a LaunchAgent plist or helper:* `SMAppService.mainApp`
  is the sandbox- and notarization-friendly API for launching the main app
  at login; it needs no helper bundle, so ADR-0037 item 5's helper bar is
  not crossed.
- *Rejected: `LSUIElement` agent mode.* Hiding the Dock icon makes an
  always-running mail client invisible; it conflicts with decision 5 and
  with the transparency stance in ADR-0006.
- *Rejected: hosted push relay or APNS.* Already excluded by ADR-0037.

## Consequences

### Accepted

- One new Settings toggle pair (background mail, launch at login) with
  per-device semantics and a `PRIVACY.md` paragraph.
- A `BackgroundMailCoordinator` in BrevMail owned by `AppSession`; the root
  view stops owning the fetch tick loop. Existing foreground behavior must
  be preserved byte-for-byte when the toggle is off (regression tests on
  `MailFetchScheduler` cadence and IDLE start/stop).
- A `MenuBarExtra` scene in the macOS target, snapshot-tested through a
  BrevMail status view that renders the same model.
- Release-identifier gating for launch at login, verified by
  `scripts/test-build-run-env.sh` or a unit test on the gating predicate.

### Risks

- The coordinator move touches the hottest lifecycle code in
  `BrevMailRootView`; a mistake there regresses foreground refresh. Mitigate
  by landing the coordinator behind the toggle first, with the off path
  delegating to the existing code, and only then removing the old ownership.
- `SMAppService` approval state can lag; rendering the system's status
  rather than Brev's flag mitigates confusion but not the extra click.
- Users may expect the status item to imply push-like latency. Decision 6's
  cadence disclosure is the mitigation; closed-app delivery remains
  best-effort per ADR-0037.

## References

- ADR-0006 — telemetry and privacy; opt-in for behavior the user did not ask for.
- ADR-0028 — provider architecture invariants.
- ADR-0037 — generic IMAP closed-app notification posture (helper/relay bar).
- ADR-0056 — iCloud key-value preference sync (explicitly not used here).
- Issue #28 §6 — background notifications and delivery.
- `apps/macOS/Sources/BrevApp.swift` (`startBackgroundScheduler`,
  `applicationShouldTerminate`), `packages/BrevMail/Sources/BrevMail/
  BrevMailRootView.swift` (fetch tick loop), `MailFetchScheduler`,
  `NotificationSettings`.
