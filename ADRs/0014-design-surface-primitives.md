# ADR-0014: Design-system surface primitives

- **Status:** Proposed
- **Date:** 2026-05-29
- **Deciders:** Henrik

## Context

ADR-0002 requires all visual color decisions to flow through semantic
theme tokens. ADR-0004 makes `BrevDesign` the shared SwiftUI component
package for macOS and iOS. ADR-0005 marks public `BrevDesign` APIs as
protected, so new primitives need a recorded decision.

The desktop mail UI now has repeated needs for small framed surfaces:
settings groups, transient command feedback, and hover hints for icon
controls. Leaving each feature to compose these ad hoc would duplicate
border, radius, spacing, accessibility, and theme choices across
`BrevMail` and future iOS surfaces.

ADR-0013 deliberately kept `BrevInlineStatus` scoped to persistent
inline recovery states. That does not cover neutral containers,
transient snackbars, or tooltips.

## Decision

Add three small public primitives to `BrevDesign`:

1. `BrevCard` for neutral framed surfaces using theme background,
   border, selection, spacing, and radius tokens.
2. `BrevToast` with `BrevSnackbar` as an alias for transient feedback
   surfaces with semantic tone, optional action, and optional dismiss.
3. `BrevTooltip` plus `View.brevTooltip(_:edge:)` for compact hover
   hints that also populate native accessibility help.

These are only visual primitives. They do not introduce a global toast
queue, presentation coordinator, or app-level routing.

### Amendment (2026-08-12): `BrevToast` sizing

`BrevToast` hugs its content instead of filling the width offered by its
container. The message text is capped at 320pt before it wraps (two
lines maximum), and the surface uses `BrevRadius.lg` with compact
padding.

Presented as a bottom overlay over a full mail window, the previous
full-width bar covered the message list, the reading pane, and the
mailbox status footer at once for a two-word message such as
"Unflagged". A content-hugging pill keeps transient feedback legible
without masking the surface the action was performed on. The width cap
still shrinks to the container, so narrow inline call sites — the
attachment save toast in `MessageDetailView` — are unaffected.

## Rationale

Centralizing the primitives keeps the public visual language consistent
without forcing feature packages to know low-level surface treatments.

Alternatives considered:

- Keep building cards, snackbars, and tooltips locally in feature
  views. This minimizes public API but repeats token choices and makes
  later visual tuning expensive.
- Add a full global notification system now. That is premature; queue
  policy, persistence, timing, and focus behavior should be designed
  when a concrete app flow needs them.
- Use only native platform help and alerts. Native help is valuable,
  but it does not provide a previewable themed tooltip bubble. Alerts
  are too disruptive for ordinary mail command feedback.

## Consequences

### Accepted

- `BrevDesign` gains public surface primitives that both app targets
  can compose.
- Feature packages can avoid literal colors and repeated border/radius
  decisions for these common surfaces.
- Snapshot coverage can render the primitives across built-in themes.

### Risks

- `BrevToast` may later need a coordinator for queueing and automatic
  dismissal. That should be a separate type layered above this surface.
- Tooltip hover behavior is most useful on macOS. iOS can still consume
  the native help and accessibility hint, but richer touch behavior may
  require a future modifier.
- Public APIs may need naming refinements after real app adoption.

## References

- ADR-0002: Theme system architecture
- ADR-0004: Build system and project layout
- ADR-0005: Enforcement, automation, and provider sync
- ADR-0013: Design-system status surfaces
- `packages/BrevDesign/Sources/BrevDesign/Components/`
