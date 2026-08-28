# ADR-0068: Default blue accent and system appearance bootstrap

- **Status:** Accepted
- **Date:** 2026-08-27
- **Deciders:** Henrik
- **Amends:** ADR-0002, ADR-0048
- **Amended by:** ADR-0069

## Context

Brev Paper is the default light theme and previously used forest green for its
interactive accent, muted accent, and selection surface. The same green also
represented semantic success. This made first-run actions and the wider light
interface feel overly green and left interaction color indistinguishable from a
successful state.

Appearance settings already defaulted to Follow System with Brev Paper and
Brev Slate as the saved light/dark pair. In practice, the root `.brevTheme`
modifier pinned the initial Brev Paper color scheme before the app-level
`colorScheme` environment could observe system dark. The asynchronous startup
task therefore saw light mode and could show or retain a light first frame even
when the operating system was dark.

A single persisted accent override is intentionally shared between light and
dark modes under ADR-0048. Using that override as the new default was rejected:
one blue value could not provide the intended contrast with both Brev Paper's
light on-accent text and Brev Slate's dark on-accent text.

## Decision

1. Brev Paper uses steel blue for interaction: `#3D6792` for `accent`,
   `#7898B7` for `accentMuted`, and `#DCE6EF` for `selection`.
2. Brev Paper keeps `#3B6B4C` for semantic success. Green therefore remains
   available for completed or positive state, not routine interaction.
3. Brev Slate keeps its existing `#7AA2C9` interaction accent. The default
   light/dark pair now has mode-appropriate blue values with adequate contrast.
4. Root appearance is applied by a shared SwiftUI view modifier inside each
   window's environment. Follow System injects the resolved Brev theme without
   pinning `preferredColorScheme`, so macOS/iOS own the active light/dark state.
5. Always Light, Always Dark, and legacy saved single-theme preferences continue
   to pin the selected theme mode intentionally.
6. Launch resolution remains synchronous for the first rendered frame. The
   asynchronous task then synchronizes `AppSession.theme` with the same resolved
   system theme for non-view consumers and persisted state.
7. A user's saved light/dark pair and optional custom accent override continue
   to take precedence over these defaults.

## Rationale

Mode-specific built-in accents preserve contrast without adding an on-accent
token or weakening ADR-0048's single user override. Reusing Brev Paper's
existing steel-blue information color keeps the palette restrained and aligns
the default light theme with Brev Slate without inventing a second color family.

Observing system appearance inside the window hierarchy avoids the feedback
loop created when the initial theme pins the same environment value used to
choose that theme. Keeping explicit modes pinned preserves the behavior users
selected in Settings.

## Consequences

ADR-0069 later changed the unsaved/new-installation default pair to Brev Mono
Light/Dark. Brev Paper's blue palette and the system-appearance bootstrap in
this decision remain active.

- Brev Paper sessions use a steel-blue primary action; follow-system sessions
  resolve their selected light/dark pair from the first rendered frame.
- Existing Brev Paper users without a custom accent see the new interaction
  blue. Existing custom accents and selected theme pairs remain unchanged.
- Semantic success remains green and is visually distinct from interaction.
- Light-theme visual baselines that expose accent, muted accent, or selection
  are updated across mail and settings surfaces.
- Root app scenes no longer use `.brevTheme` to pin Follow System mode; child
  sheets may still pin the already-resolved concrete theme for consistency.

## References

- ADR-0002: Theme system architecture
- ADR-0048: Configurable application accent color
- `packages/BrevThemes/Sources/BrevThemes/BuiltIns.swift`
- `packages/BrevMail/Sources/BrevMail/RootAppearance.swift`
- `packages/BrevMail/Sources/BrevMail/ThemePreferences.swift`
