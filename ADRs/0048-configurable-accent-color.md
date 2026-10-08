# ADR-0048: Configurable application accent color

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** Henrik

## Context

Brev's built-in themes provide a semantic `accent` token, but the macOS
sidebar selection and other system controls also use the app's global accent
color. Users currently cannot change that interactive color from Brev, and
the native sidebar can therefore disagree with the active Brev theme.

The setting must remain shared by the macOS and iOS settings surfaces, local
only, and compatible with the existing light/dark theme pair and settings
transfer schema.

## Decision

1. Persist one optional user accent override in `AppearanceThemeSettings` as
   an sRGB `#RRGGBB` value. When absent, the active theme's built-in accent is
   used.
2. Apply the override to the resolved `BrevTheme` while preserving every
   other semantic token. Resetting the setting removes the override and
   restores the selected theme's native accent.
3. Expose the override in Appearance as a native SwiftUI `ColorPicker` with a
   reset action. The active theme remains the source of the picker preview
   when no override is stored.
4. Tint the macOS settings sidebar from the resolved theme so native list
   selection follows the configured accent instead of only the asset-catalog
   fallback.
5. Include the setting in the existing local settings export/import payload.

## Rationale

An optional override keeps existing themes and persisted settings backwards
compatible while making the setting independent of light/dark palette choice.
A single shared value matches the user's expectation of an application accent
and avoids maintaining two colors that can drift across appearance changes.

The override is applied at the theme boundary rather than in individual
views, preserving ADR-0002's semantic-token rule. A native `ColorPicker` is
more discoverable and accessible than a fixed list of swatches, while storing
the resolved sRGB hex keeps persistence deterministic and platform-neutral.

The alternative of changing only the asset-catalog `AccentColor` was rejected:
that value is static at build time and cannot reflect a per-user setting. The
alternative of adding per-view colors was rejected because it would bypass
the theme environment and leave native controls inconsistent.

## Consequences

### Accepted

- The theme model gains a small public transformation method for replacing its
  semantic accent token.
- Existing users retain each built-in theme's accent until they choose a new
  color.
- Imported settings carry the local accent override without introducing any
  network or telemetry behavior.

### Risks

- Color conversion is normalized to sRGB and drops alpha because the accent is
  used as an opaque UI tint. This is deterministic across macOS and iOS but
  does not preserve wide-gamut profile metadata.
- Native controls may still apply platform-specific contrast adjustments to
  the configured tint; the semantic theme token remains the source value.

## 2026-10-06 — Accent-source and contrast clarification

Henrik requested implementation of the sidebar/Settings/accent assessment.
Keep ADR-0069's quiet theme-matched default. Persist an explicit `theme`,
`system`, or `custom` accent source independently from the light/dark mode.
Legacy settings and backups with a valid accent but no source migrate to
Custom; those without an override migrate to Theme. Preserve the original
custom hex when changing sources.

System resolves macOS's control accent at the theme boundary and updates on
system-color changes. iOS does not expose this choice; imported System settings
use the theme accent until the user selects Theme or Custom.

Custom and System effective accents are contrast-adjusted against the theme's
primary, secondary and tertiary surfaces (4.5:1 target for normal text, 7:1
with Increased Contrast). If the stronger target is impossible, try the normal
target; themes with mutually incompatible surfaces use the strongest attainable
minimum contrast rather than claiming to meet an impossible target.
Keep the stored choice unchanged. Filled controls use a contrast-derived
on-accent foreground; selection and semantic status palettes remain independent.
Recovery actions use the theme's primary text, not the requested custom color.
All scenes use the shared root appearance policy. No new network behavior,
theme JSON keys, or telemetry is introduced.

## References

- ADR-0002: Theme system architecture
- ADR-0005: Enforcement and automation
- ADR-0012: Settings surface
- `packages/BrevThemes/Sources/BrevThemes/BrevTheme.swift`
- `packages/BrevSettings/Sources/BrevSettings/AppearanceThemeSettings.swift`
