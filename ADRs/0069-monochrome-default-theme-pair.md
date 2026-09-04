# ADR-0069: Monochrome default theme pair

- **Status:** Accepted
- **Date:** 2026-08-27
- **Deciders:** Henrik
- **Amends:** ADR-0002, ADR-0048, ADR-0068

## Context

ADR-0068 replaced Brev Paper's green interaction color with steel blue and
fixed Follow System appearance from the first rendered frame. Brev Paper and
Brev Slate still carry warm and cool tinted surfaces, so the default pair is
not monochrome even though the first-run composition is restrained.

The requested default is now a neutral black/white system in both light and
dark appearance. Existing Brev themes, custom accent overrides, and semantic
state colors must remain available. Changing Brev Paper and Brev Slate in place
would silently alter themes users may have selected intentionally.

## Decision

1. Add `Brev Mono Light` (`brev-mono-light`) and `Brev Mono Dark`
   (`brev-mono-dark`) as built-in themes.
2. The monochrome themes use neutral-channel surfaces, text, borders,
   selection, interaction accents, and fallback-avatar ramps. Light uses a near
   black primary accent over white; dark uses a near white primary accent over
   near black.
3. Semantic success, warning, danger, and information tokens retain distinct
   colors. Monochrome applies to interface chrome, not meaning-bearing state.
4. The Follow System defaults become Brev Mono Light + Brev Mono Dark. New or
   unsaved installations resolve that pair from the first frame through the
   root appearance policy established by ADR-0068.
5. Existing saved light/dark pairs and custom accent overrides are not migrated
   or overwritten. Brev Paper, Brev Slate, and the remaining themes stay
   selectable with their existing identities.
6. Explicit Light/Dark compose-body appearances use the monochrome pair so the
   default editor surface matches the default application chrome.
7. The bare `brevTheme` environment fallback becomes Brev Mono Light.

## Rationale

Adding a pair preserves the existing theme catalog and user intent while giving
first run a coherent neutral identity. Mode-specific accents maintain strong
contrast with each theme's on-accent foreground; a single shared default accent
override cannot do that safely across light and dark.

Semantic state and identity content remain colored because removing those
colors would reduce comprehension rather than improve restraint.

## Consequences

- New first-run light surfaces are white with black primary controls; dark
  surfaces are near black with light primary controls.
- Existing users keep their saved pair. They can choose the new monochrome
  themes from Appearance without losing custom accent support.
- The built-in catalog grows from 34 to 36 themes.
- Default-pair and compose-editor tests target the monochrome theme IDs.
- First-run light/dark visual baselines are updated; snapshots that explicitly
  request Brev Paper or Brev Slate remain unchanged.

## References

- ADR-0002: Theme system architecture
- ADR-0048: Configurable application accent color
- ADR-0068: Default blue accent and system appearance bootstrap
- `packages/BrevThemes/Sources/BrevThemes/BuiltIns.swift`
- `packages/BrevSettings/Sources/BrevSettings/AppearanceThemeSettings.swift`
- `packages/BrevMail/Sources/BrevMail/ComposeBodyAppearance.swift`

## Amendment (2026-09-05): readable mail interaction states

The default monochrome pair must retain at least 4.5:1 contrast for primary,
secondary, and tertiary text on its primary, secondary, tertiary, and selected
surfaces. Small metadata uses an opaque foreground. Selection uses the existing
`selection` token, with primary/secondary foregrounds and an opaque indicator;
an accent-opacity wash must not silently replace that background. Custom accent
overrides therefore cannot lower selected-row text contrast. Inactive selection
keeps readable text and uses a quieter indicator rather than dimming the row.

This refines existing palette values and mail presentation roles; it adds no
public theme fields, changes no saved theme IDs, and does not migrate custom
palettes. Snapshot coverage includes default light/dark selected states. New macOS windows prefer 1440 by 820 points while preserving saved window
geometry and the existing 960-point minimum. The mail
list receives a wider preferred column, while conversation content is bounded
and display-mode actions move into the message header.
