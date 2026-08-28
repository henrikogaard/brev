# Brev App Icon Family Redesign

## Context

The current Graphite default app icon is polished at large sizes but is
hard to spot in the macOS Dock. Its dark rounded body blends into
neighboring dark icons, and the detailed white envelope/document stack
collapses into a generic light block at small sizes.

Brev already ships ten selectable app icon variants through
`AppIconVariant`, with Graphite as the default primary icon. The
redesign should refresh the whole family so Settings previews remain
coherent and existing saved preferences keep resolving to the same
variant identifiers.

## Goals

- Make the primary Dock icon recognizable at 32-64 px in a crowded Dock.
- Refresh all ten existing icon variants as one coherent family.
- Preserve the current variant IDs, display names, default variant, and
  iOS alternate-icon behavior.
- Use a deterministic asset-generation path so future icon updates are
  reproducible from source code.

## Non-Goals

- Do not rename, add, or remove app icon variants.
- Do not change Settings storage keys or app-icon preference behavior.
- Do not redesign the in-app mail UI, theme system, or brand copy.
- Do not introduce new binary source artwork as the canonical icon
  source.

## Design Direction

Use a high-contrast mail icon system with an accent badge. Each variant
uses the same simplified envelope geometry:

- A large, front-facing envelope that fills the icon body enough to read
  at Dock size.
- A reduced set of folds and highlights, avoiding the current detailed
  document/envelope stack.
- A small accent badge near the lower or upper corner, colored per
  variant. The badge provides personality and a quick visual hook, but
  must remain subordinate to the envelope silhouette.
- Background palettes derived from the existing variant concepts:
  Classic, Paper, Slate, Gradient, Aurora, Ocean, Forest, Ember,
  Graphite, and Ink.

Graphite remains the default. Its redesign should use a brighter
background field or stronger rim contrast than the current Graphite icon
so the app is visible against dark Dock backdrops and dark neighboring
icons.

## Implementation Plan

Update `scripts/generate-app-icon-variants.swift` so the generated
CoreGraphics renderer is the canonical icon source again. The renderer
should:

- Keep the existing `IconVariant` list and `defaultAppIconAssetName`.
- Draw one shared simplified envelope mark from vector primitives.
- Draw per-variant backgrounds and accent badges from variant color
  fields.
- Generate the existing macOS primary `AppIcon.appiconset`, iOS primary
  `AppIcon.appiconset`, iOS alternate app icon sets, and macOS/iOS
  preview image sets.
- Stop preferring `assets/app-icons/source/Brev_*.png` as canonical
  inputs for this family. The old PNG source pack may remain as history
  or be removed in the implementation if the resulting diff stays
  reviewable.

No ADR is required for this change because it touches app assets and an
asset-generation script, not a protected architecture path from
`ADRs/README.md`.

## Verification

The implementation is complete when:

- Running the icon-generation script regenerates all expected app icon
  and preview assets.
- Generated PNG dimensions match the current asset catalogs.
- The macOS primary 1024 px asset matches the Graphite preview output.
- `swift test --package-path packages/BrevSettings --filter AppIconPreferencesTests`
  passes.
- `scripts/lint.sh` and `scripts/format.sh` are run if feasible; any
  skipped verification is recorded in `WORKLOG.md`.
- The resulting icons are visually checked at Dock-like sizes, not only
  at 1024 px.

## Acceptance Criteria

- In a Dock-like row, the new Graphite icon is noticeably easier to
  locate than the current icon.
- The ten Settings previews read as a family rather than ten unrelated
  illustrations.
- The icon remains clearly mail-related without depending on detailed
  small text, paper lines, or shadows.
- Existing users with saved app-icon preferences keep their selected
  variant after the refresh.
