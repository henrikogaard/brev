# UI Workbench

Credential-free UI iteration for mailbox, search, sync, and compose states (#303).

## What it is

`MockBackendWorkbench` provides named `MockBackend` scenarios for SwiftUI previews,
snapshot tests, and local design review. Scenarios are typed against existing
`MailBackend` contracts and never open Keychain or network paths by default.

## Scenarios

| Scenario | Purpose |
| --- | --- |
| `emptyInbox` | Startup / empty mailbox gate |
| `populatedInbox` | Default preview inbox |
| `syncInProgress` | Folder backfill progress + syncing health |
| `importIndexing` | Index rebuild / import continuing |
| `recoverableSyncFailure` | Retryable sync failure with cached mail retained |
| `offlineRetained` | Offline banner + pending mutations |

## Using in SwiftUI previews

```swift
import BrevBackend
import BrevMail

#Preview("Import indexing") {
    let backend = MockBackendWorkbench.backend(for: .importIndexing)
    Task { await MockBackendWorkbench.activate(.importIndexing, on: backend) }
    return BrevMailRootView(backend: backend, backends: [backend])
}
```

For static snapshots, call `MockBackendWorkbench.activate` in the preview setup task
or test harness before capturing.

## Adding a scenario

1. Add a case to `MockBackendWorkbenchScenario`.
2. Seed fixtures in `MockBackendWorkbench.backend(for:)`.
3. Apply delayed events or sync-health overrides in `activate(_:on:)`.
4. Add a preview or snapshot that references the new scenario.

## Safety rules

- Do not import production account stores into workbench code.
- Keep workbench helpers in `MockBackend` / `MockBackendWorkbench` only; production
  app targets should not branch on workbench flags.
- Prefer injected backends in previews over `#if DEBUG` conditionals in views.
