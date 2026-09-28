# ADR-0083: Home-screen widgets share a snapshot file, never the Realm store

- **Status:** Proposed
- **Date:** 2026-09-28
- **Deciders:** Henrik

## Context

Brev has no glanceable surface outside the app: no Home Screen / Lock
Screen / Notification Center widgets. Every paid mail client ships at
least an unread-count or latest-messages widget, and the feature is a
frequent request for first release.

Two hard constraints shape the design:

1. **Protected build files.** A widget is a `WidgetKit` app extension,
   which means new targets in `apps/iOS/Project.swift` and
   `apps/macOS/Project.swift` — protected paths per ADR-0005. This ADR
   is the required accompanying decision.
2. **ADR-0006 zero-network-by-default and the shared-store boundary.**
   A widget extension must not open network connections and must not
   couple itself to BrevBackend's Realm files: Realm's multi-process
   story requires a specifically configured shared container, would drag
   the whole backend dependency graph into the extension, and a crashed
   or migrating Realm can take the extension down with it.

The options for feeding a widget:

- **Shared Realm in an App Group container.** Real-time data, but the
  extension imports BrevBackend + RealmSwift, file-locking between the
  app and extension becomes a failure mode, and schema migrations must
  consider the extension host.
- **Provider writes a compact snapshot.** The app serializes a
  deliberately small `WidgetSnapshot.json` (folder counts, a handful of
  message previews, generated-at timestamp) into the App Group container
  after each sync/UI materialization; the widget decodes and renders.
  Extension depends on nothing but `WidgetKit` + the snapshot's `Codable`
  types.

## Decision

1. **Widgets read a snapshot file, never Brev's stores.** The app writes
   `WidgetSnapshot.json` into the App Group container
   (`group.eu.brevmail.brev.shared`) after each successful sync pass and
   whenever account/unread state changes. The widget extension renders
   that file only. BrevBackend, Realm, and sync are not linked into the
   extension.

2. **The extension performs no network requests and no IMAP/SMTP work.**
   Freshness comes from the app's own sync cadence plus
   `WidgetCenter.reloadTimelines` calls the app issues when it writes a
   new snapshot. WidgetKit's `getTimeline` may also fire on system
   schedule and simply re-renders the latest snapshot — staleness is
   shown as the `generatedAt` caption, not hidden.

3. **First widget scope is deliberately narrow:** a "Mail" widget in
   small/medium families on iOS and macOS showing unified-inbox unread
   count + top three message previews (avatar initials, sender, subject).
   Calendar-today and task widgets are follow-ups, not part of this ADR.

4. **Preview content honors privacy posture.** The snapshot contains
   only what the user could already see in a notification preview
   (sender + subject, never body). A Settings → Notifications toggle
   ("Show message previews in widgets and notifications") gates previews;
   off = counts only. `PRIVACY.md` and the ADR-0006 network table are
   updated to state the extension makes zero network calls.

5. **Entitlements.** Both app targets and the new extension targets
   carry the `com.apple.security.application-groups` entitlement for
   `group.eu.brevmail.brev.shared`. Test builds inherit the group under
   the test bundle prefix (per Rule 7 the test app is a separate
   identity); release builds use the real group id. This is the only
   signing surface change.

## Rationale

- **Snapshot over shared Realm:** the extension stays a ~200-line
  Codable renderer — cold-start cost, crash surface, and Tuist graph all
  stay trivially small. The alternative buys real-time data Brev cannot
  deliver to widgets anyway (the extension has no sync engine).
- **No network in the extension** keeps ADR-0006 airtight: the widget
  literally cannot phone home, and Apple's `NSExtension` network surface
  never enters the picture.
- **Preview gating with notifications** reuses an existing mental model
  and setting rather than inventing a widget-only privacy switch.

## Consequences

### Accepted

- `apps/iOS/Project.swift` and `apps/macOS/Project.swift` gain a widget
  extension target each (protected-path change justified by this ADR).
- A `BrevWidgets` extension product plus a tiny shared
  `WidgetSnapshotStore` type — the Codable snapshot schema lives in a
  leaf package both the app and extension can see without pulling in
  BrevBackend.
- Stale data: a user who never opens Brev sees last-synced content with
  a timestamp. Accepted — matches every other mail widget's behavior.

### Risks

- App Group entitlement changes require regenerated provisioning for
  signed builds; unsigned/test builds must not crash when the container
  is unavailable (write failures degrade silently to no widget content).
- Snapshot schema changes must be backward-compatible or versioned —
  the widget may render a file written by an older app version.

## References

- ADR-0006 — telemetry/privacy; the extension adds zero network calls.
- ADR-0028 — provider architecture; widgets sit outside backend seams.
- ADR-0005 — protected paths; this ADR accompanies the Project.swift
  changes.
- ADR-0037 — closed-app notification posture; widgets share the
  best-effort freshness model.
