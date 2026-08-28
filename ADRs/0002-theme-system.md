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
> `apps/macOS/`, `apps/iOS/`, or `packages/BrevDesign/`. All colors
> come from `theme.<token>.color`. Only exception: `Color.clear`,
> which is structural.

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

Default pair: Brev Paper (light) + Brev Slate (dark).

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
