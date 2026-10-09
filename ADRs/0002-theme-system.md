# ADR-0002: Theme system architecture

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev ships with light and dark mode as a baseline requirement. Beyond
that, the brand positioning (modern, developer-adjacent, European,
quietly opinionated) is well served by IDE-inspired theming: Nord,
Gruvbox, GitHub-style, Solarized, Catppuccin, Tokyo Night, Rosé Pine.
These palettes are well-loved, well-designed, and signal craft.

Two architectural decisions need to be made before any view code:

1. How themes are defined and stored.
2. How views consume the active theme.

Getting this wrong is expensive: once hardcoded colors leak into
views, extracting them is a months-long refactor. We have one chance
to make the rule before the codebase grows.

## Decision

### Theme definition

A theme is a `Codable, Sendable` value type with a fixed set of
semantic tokens. Themes are not arbitrary color lists; they're
explicit mappings to UI roles.

Themes live in `packages/BrevThemes/`. The view layer in `packages/
BrevDesign/` consumes themes via SwiftUI environment.

```swift
public struct BrevTheme: Identifiable, Codable, Sendable {
    public let id: String              // "nord", "gruvbox-dark"
    public let name: String            // "Nord"
    public let mode: ColorScheme       // .light or .dark
    public let author: String
    public let license: String         // "MIT" usually

    // Surfaces
    public let bgPrimary: BrevColor
    public let bgSecondary: BrevColor
    public let bgTertiary: BrevColor

    // Text
    public let textPrimary: BrevColor
    public let textSecondary: BrevColor
    public let textTertiary: BrevColor

    // Accents
    public let accent: BrevColor
    public let accentMuted: BrevColor
    public let success: BrevColor
    public let warning: BrevColor
    public let danger: BrevColor
    public let info: BrevColor

    // Structure
    public let border: BrevColor
    public let separator: BrevColor
    public let selection: BrevColor

    // Avatar fallback palette (see ADR-0003)
    public let avatarPalette: [BrevColor]
}

public struct BrevColor: Codable, Sendable {
    public let hex: String   // "#2E3440"
    public var color: Color { Color(hex: hex) }
}
```

Fifteen tokens covers the entire mail UI without ballooning into
per-component theming. New UI roles get new tokens (with a new ADR),
not per-view colors.

### View consumption

Views read the active theme via `@Environment`, never via literal
colors:

```swift
@Environment(\.brevTheme) var theme

Text(message.subject)
    .foregroundStyle(theme.textPrimary.color)
```

The hard rule, enforced by SwiftLint custom rule (ADR-0005):

> No `Color(...)`, `Color.<systemName>`, or hex literal anywhere in
> `apps/macOS/`, `apps/iOS/`, `packages/BrevDesign/`,
> `packages/BrevMail/`, or `packages/BrevSettings/`. All colors
> come from `theme.<token>.color`. Only exception: `Color.clear`,
> which is structural.

(2026-09: the rule's `included` list grew to cover `BrevMail` and
`BrevSettings` — the packages where most view code lives — and the
regex now also matches `Color(hex:`.)

Built-in `textSecondary` and `textTertiary` values used for small metadata must
maintain at least 4.5:1 contrast against both `bgPrimary` and `bgSecondary`.
Palette calibration may adjust those role values without adding a token or
changing the theme schema; focused tests cover every built-in palette.

(2026-10: contrast contract extended. The audit of all 37 built-ins
found that the base text roles passed but derived styles did not: accent
as text failed 4.5:1 in 6 themes, danger in 9, warning in 7, and every
`border` was below 3:1. The contract is now, for every built-in theme and
measured on both `bgPrimary` and `bgSecondary`:

| Role | Used as | Minimum |
|---|---|---|
| `textSecondary`, `textTertiary` | small text | 4.5:1 (unchanged) |
| `accent`, `warning`, `danger` | text and text-sized glyphs | 4.5:1 |
| `success`, `info` | status glyphs (non-text, WCAG 1.4.11) | 3:1 |
| `controlBorder` | outline that is the only cue to a control's boundary | 3:1 |

`border` itself stays a quiet decorative hairline colour (card edges,
dividers; exempt under WCAG 1.4.11 as decoration), so no theme's overall
look is flattened. `BrevTheme.controlBorder` is a computed accessor, not a
new token and not a schema change: it returns `border` when that already
reaches 3:1 and otherwise mixes `border` toward `textPrimary` by the
smallest amount that does. Outlined controls (`BrevButton` secondary, text
fields) use it. `BuiltInThemeTests` enforces the whole table over
`BrevTheme.brevBuiltIns`, so a new built-in cannot ship below it.
Built-in palettes were recalibrated by changing only HSL lightness of the
failing role, keeping hue and saturation; the per-theme changes are listed
in the PR. Two further rules: text is never dimmed with `.opacity(_:)` to
make it quieter (use `textTertiary`; opacity is allowed for disabled
controls, which WCAG exempts), and text on an accent tint (selected
`brevChip`) uses `BrevTheme.accentTextOnTint(opacity:)`, because accent
text on its own 18% tint failed 4.5:1 in 15 themes. It returns `accent`
when that already passes and otherwise mixes it toward `textPrimary` (or
black/white when `textPrimary` is itself too weak on the tint, as in
Solarized) by the smallest amount that does. User accent overrides keep
going through `withReadableAccent()`.)

(2026-10: shared controls scale and respect motion. `BrevIconButton`,
`BrevButton`, `BrevChip` and `BrevStatusBanner` size their glyphs, padding
and hit targets with `@ScaledMetric`, never below the 44 pt iOS floor
(`BrevHitTarget`). `BrevMotion` / `brevWithAnimation` /
`.brevAnimation(_:value:)` drop animations when Reduce Motion is on; new
animated code uses them instead of `withAnimation` / `.animation`.)

(2026-09: `BrevSelectionPalette` gained the focused-pane contract —
`isActive: false` demotes the selected-row fill from `selection` to
`bgSecondary` and dims the leading indicator. macOS call sites drive it
from `controlActiveState` *and* the pane's keyboard-focus state so the
focused column owns the selection tint, the Apple Mail cue that
replaces a drawn focus ring. iOS call sites leave `isActive` at its
default `true`.)

### Shared component surfaces

Recurring view recipes live in `BrevDesign` so call sites cannot drift
on opacity, spacing, or hit-area values:

- `BrevButton` — the only sanctioned button; keeps a 44 pt minimum
  height on iOS (32 pt on macOS) that grows with Dynamic Type.
- `BrevIconButton` — icon-only actions; glyph and hit area scale with
  Dynamic Type, 44 pt minimum hit area on iOS, mandatory accessibility
  label.
- `brevQuietSurface()` — the one "quiet card" recipe (secondary fill at
  0.42, border hairline at 0.45); replaces hand-rolled copies.
- `brevChip(selected:)` — capsule styling for filter/toggle chips.

The public `BrevChipStyle(isSelected:)` and `BrevQuietSurface(cornerRadius:)`
initializers document their selection and corner-radius inputs, and their
modifier methods document the visual treatment. These API comments preserve
the shared recipes above without changing theme tokens or rendering behavior.

**iOS Settings forms (2026-10-09).** `BrevButton` and `brevQuietSurface()`
remain the standalone recipes. Inside an iOS Settings pane the rows live in
an inset-grouped `Form` whose `Section`s are themed with tokens only
(`scrollContentBackground(.hidden)`, `theme.bgSecondary` behind the form,
`theme.bgPrimary` row backgrounds), so a pane never draws a quiet card or a
bordered `BrevButton` pill inside a row. `SettingsButton` is the pane-level
wrapper: it delegates to `BrevButton` on macOS and renders a plain accent
row on iOS (`Button(role: .destructive)` for destructive actions, with a
`confirmationDialog` where the action is not already confirmed). macOS
Settings keeps the card layout unchanged.

### Theme distribution

Three tiers:

1. **Built-in.** Compiled into `packages/BrevThemes/`. Twelve themes
   at v1 (see below).
2. **User themes.** JSON files in
   `~/Library/Application Support/Brev/Themes/` (macOS) or the iOS
   Documents directory. Match the `BrevTheme` `Codable` schema.
   Hot-reloaded on file change in development.
3. **Community themes (v2 stretch).** Possible repository at
   `github.com/henrikogaard/brev-themes`. Not v1.

### Built-in themes at v1

| Theme | Mode | License | Source |
|---|---|---|---|
| Brev Forest | light | MIT (own) | Brand default |
| Brev Paper | light | MIT (own) | Brand light |
| Brev Slate | dark | MIT (own) | Brand dark |
| Nord | dark | MIT (Arctic Ice Studio) | nordtheme.com |
| Gruvbox Light | light | MIT (morhetz) | github.com/morhetz/gruvbox |
| Gruvbox Dark | dark | MIT (morhetz) | github.com/morhetz/gruvbox |
| Solarized Light | light | MIT (Ethan Schoonover) | ethanschoonover.com/solarized |
| Solarized Dark | dark | MIT (Ethan Schoonover) | ethanschoonover.com/solarized |
| Catppuccin Latte | light | MIT (Catppuccin) | catppuccin.com |
| Catppuccin Mocha | dark | MIT (Catppuccin) | catppuccin.com |
| Tokyo Night | dark | MIT (enkia) | github.com/enkia/tokyo-night-vscode-theme |
| Rosé Pine | dark | MIT (Rosé Pine) | rosepinetheme.com |

License texts in `THIRD_PARTY_LICENSES.md`. Per ADR-0005, each theme
JSON file declares its `author` and `license` fields.

GitHub-style themes are *not* shipped under that name — GitHub's
trademark territory. Brev Paper and Brev Slate fill the
"GitHub-inspired" niche with original palettes.

### Appearance modes

Three modes in settings:

- **Follow system** (default). User picks a light theme and a dark
  theme separately. Auto-switches with macOS appearance.
- **Always light.** Single chosen light theme, ignores system.
- **Always dark.** Single chosen dark theme, ignores system.

Default pair: Brev Mono Light (light) + Brev Mono Grey (dark).

Brev Mono Grey is the softer neutral dark default: charcoal primary surfaces,
lighter secondary/tertiary surfaces, and a distinct neutral selection fill.
Small primary, secondary, and tertiary text must retain at least 4.5:1 contrast
on normal, hover, and selected surfaces. Brev Mono Dark remains selectable.
The new default applies to unsaved or invalid theme choices; existing saved
light/dark choices and accent overrides remain intact. This adds a built-in
palette using the existing token schema, with no migration or new token.

## Rationale

**Why semantic tokens, not raw colors.** Raw color lists invite "use
color #3 for this label, #5 for that one" decisions in views. That
produces visually busy UI and locks the schema to the view's current
shape. Semantic tokens force "what *role* does this color serve?" —
the right question.

**Why JSON for user themes.** Codable + JSON is the lowest-friction
format. A theme is a flat ~20-line file. Anyone who can read JSON
can legacy implementation and recolor. A binary format or custom DSL gains nothing.

**Why pair light and dark instead of one auto-adapting theme.** The
IDE themes we're modeling (Nord, Gruvbox, GitHub-style) ship explicit
light and dark variants because the design intent differs between
them, not just inverted values. Treating them as pairs respects the
original designs.

## Consequences

### Accepted

- View code is gated behind the "no literal colors" rule from day one.
  SwiftLint custom rule enforces (ADR-0005).
- Theme schema changes require migration. Adding a new token (e.g.
  `tagBackground`) means every existing theme either gains a default
  for the new token or fails to load. Handled by a `version` field
  in the JSON and a migrator. Out of scope to design fully until
  the second schema change.
- Performance: themes are pure data; switching is instant. No
  recompilation, no asset catalog regeneration.

### Risks

- **License compatibility.** Most IDE theme palettes are MIT — we ship
  LICENSE copies and credit, names preserved. GitHub themes are
  trademark-risky; we use original palettes (Brev Paper/Slate)
  instead.
- **Theme proliferation.** Twelve built-ins is a lot of surface to QA
  across both platforms. We freeze the built-in list at v1; new
  themes arrive via user theming.

## References

- ADR-0028: Project identity and scope
- ADR-0003: Avatar resolution (consumes `avatarPalette`)
- ADR-0005: Enforcement (SwiftLint rule)
- Nord: https://www.nordtheme.com/
- Gruvbox: https://github.com/morhetz/gruvbox
- Catppuccin: https://catppuccin.com/
- Tokyo Night: https://github.com/enkia/tokyo-night-vscode-theme
- Rosé Pine: https://rosepinetheme.com/
