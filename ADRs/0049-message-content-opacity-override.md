# ADR-0049: Message-content opacity override

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** Henrik

## Context

ADR-0015 gives translucent Brev windows one pane opacity for dense surfaces.
The message reader uses that value for both its surrounding pane and its
bounded content card. This preserves the selected window treatment, but a
wallpaper or theme combination can still leave the message itself less readable
than a user needs.

The existing pane control cannot solve that without also making message lists,
Settings, utility panes, and cards more opaque. Its upper bound is intentionally
95%, so it also cannot express an explicitly opaque reading surface. Brev needs
a narrow accessibility override for the surface directly behind a message while
keeping today's rendering as the default.

## Decision

Extend `WindowAppearancePreferences` with a message-content opacity policy:

- **Follow pane** is the default and resolves to the existing `surfaceOpacity`.
  Existing installs therefore retain the rendering established by ADR-0015.
- **Opaque** resolves the message-content surface to 100% opacity, providing a
  clear no-transparency option.
- **Custom** exposes an independently persisted opacity in `0.25...1.0`.

Add a dedicated `messageContent` surface role. The bounded single-message
reader card uses this role; unrelated cards, message-list chrome, Settings, and
utility surfaces continue to use their existing roles and pane opacity.

Appearance -> Window design exposes the three policies and shows the custom
slider only when Custom is selected. The preview includes the message surface
so the effect is visible before returning to mail.

Solid mode and macOS Reduce Transparency still resolve every surface to fully
opaque regardless of the saved override. The override adds no network access
and remains a local `UserDefaults` preference.

## Rationale

**Why a separate policy instead of widening pane opacity to 100%.** Users may
want translucent window chrome and lists while keeping only the message itself
opaque. Changing the shared range cannot express that distinction.

**Why Follow pane is explicit.** An optional or inferred value would preserve
the same behavior, but an explicit setting makes the inheritance visible and
lets users return to it after experimenting with an override.

**Why a dedicated surface role.** Reusing `card` would also change search
fields, profile controls, and other hierarchy surfaces. The accessibility need
is specific to the reading surface behind untrusted message content.

## Consequences

- `BrevDesign` gains public message-content preference keys, policy values, and
  a `WindowSurfaceRole.messageContent` case.
- The default visual result remains unchanged.
- The message-content override can reach 100% while the general pane and
  sidebar controls retain their current readability bounds.
- Focused preference, rendering-policy, and Settings rendering tests cover the
  migration and new choices.

## References

- ADR-0002: Theme system architecture
- ADR-0012: Settings surface
- ADR-0015: Window materials and translucency preferences
