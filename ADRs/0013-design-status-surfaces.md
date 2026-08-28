# ADR-0013: Design-system status surfaces

- **Status:** Accepted
- **Date:** 2026-05-29
- **Deciders:** Henrik
- **Implementation:** 2026-06-07 — `BrevStatusBanner`, `BrevEmptyState`, and
  `BrevProgressSurface` added to `packages/BrevDesign/Sources/BrevDesign/Components/`;
  smoke tests in `packages/BrevDesign/Tests/BrevDesignTests/StatusSurfaceSmokeTests.swift`.

## Context

Brev's desktop mail UI now has several recoverable states: folder
loads can fail, manual refresh can fail, mailbox switching can roll
back, and message-list pagination or mutation can expose retryable
errors. The current implementation repeats small inline banners in
feature packages instead of using a shared design-system primitive.

ADR-0002 requires all user-facing color decisions to come from the
active theme. ADR-0004 establishes `BrevDesign` as the shared component
package for macOS and iOS. ADR-0005 treats public `BrevDesign` API as a
protected path, so adding a new component needs an ADR.

## Decision

Add a small public inline status component to `BrevDesign`:

- `BrevInlineStatus` renders a compact horizontal status banner with a
  semantic tone, message text, optional action, and optional dismiss
  control.
- `BrevInlineStatusTone` maps semantic states (`info`, `success`,
  `warning`, `danger`) to existing theme tokens and platform-native SF
  Symbols.
- Message text defaults to a compact two-line limit, but callers may
  opt into a different limit, including unbounded text for first-run
  setup guidance where truncating the recovery instruction would make
  the error unactionable.
- The component is intentionally inline. It can be placed in
  `safeAreaInset`, list footers, settings panels, or other existing
  layout slots without introducing a global overlay coordinator.

## Rationale

This centralizes a repeated recovery surface while staying smaller than
a full notification system.

Alternatives considered:

- Keep local banners in each feature. This avoids a public API change
  but duplicates theme, icon, spacing, and accessibility decisions.
- Build a global toast/snackbar coordinator now. That would be useful
  later, but it introduces routing, queueing, timing, and focus
  behavior before the desktop app needs those decisions.
- Use platform-native alerts for every recoverable state. Alerts are
  too disruptive for mail triage flows where a retryable inline error
  should not steal focus from the list or reading pane.

## Consequences

### Accepted

- `BrevDesign` gains a new public component and tone enum.
- Desktop mail surfaces can share one themed status treatment for
  retry/dismiss flows.
- Snapshot coverage should include the component across built-in
  themes when UIKit snapshot tests are run.

### Risks

- The component may not cover every future status pattern. If Brev
  later needs queued transient toasts, that should be added as a
  separate component instead of stretching this inline primitive.
- SF Symbol choices may need refinement after visual review on both
  platforms. The semantic tone API keeps that internal to the design
  component.

## References

- ADR-0002: Theme system architecture
- ADR-0004: Build system and project layout
- ADR-0005: Enforcement, automation, and provider sync
- `packages/BrevDesign/Sources/BrevDesign/Components/`
- `packages/BrevMail/Sources/BrevMail/`
