# ADR-0016: Expand the built-in IDE theme pack

- **Status:** Accepted
- **Date:** 2026-05-30
- **Deciders:** Henrik

## Context

ADR-0002 established Brev's theme architecture and listed twelve
built-in palettes for v1. That set covers the first baseline, but it
leans conservative: brand defaults plus a handful of well-known
editor palettes. The settings surface now has enough structure to make
theme choice a real user-facing feature, and the product direction is
explicitly developer-adjacent.

Users should be able to reach for familiar moods: forge-style light
and dark neutrals, One Dark-style editor colors, command-palette dark
surfaces, Blurple-adjacent social dark UI, and a few saturated code
editor nights. At the same time, ADR-0002's trademark and license
notes still apply: Brev should not ship official "GitHub", "Discord",
or "Cursor" branded themes unless there is a deliberate legal review.

## Decision

Expand the built-in theme list from twelve to thirty-four by adding
two original developer packs plus a small terminal-classics pack:

- Nordic — warmer, deeper Nord-adjacent terminal palette.
- Forge Light — light, GitHub-style forge UI without the GitHub name.
- Forge Dark — dark forge UI without the GitHub name.
- One Dark Pro — dark IDE theme in the One Dark family of contrast and
  accent relationships.
- Command Dark — dark command-palette/editor surface inspired by
  modern AI coding tools.
- Blurple Night — dark chat/workspace surface with a blue-violet
  accent.
- Midnight Terminal — very dark terminal-forward palette with green
  and amber status tones.
- Cobalt Night — saturated blue IDE palette.
- Code Candy Dark — high-energy syntax-inspired dark palette.
- Pearl Light — cool low-glare light IDE palette.
- Evergreen Night — calm forest dark palette.
- Ink Wave — indigo ink-and-wave editor palette.
- Mirage Ember — smoky navy palette with ember highlights.
- Oceanic Dark — blue-green material-style dark palette.
- Amber Terminal — vintage amber terminal palette.
- Owl Blue — late-night blue editor palette.
- Synthwave Dusk — restrained retro-future purple dark palette.
- Zenwritten Light — Zenbones-inspired minimal bone-gray light palette.
- Zenwritten Dark — Zenbones-inspired minimal bone-gray dark palette.
- Tender — Tender's warm graphite terminal palette.
- Tomorrow Day — classic Tomorrow light palette.
- Tomorrow Night — classic Tomorrow dark palette.

The original developer-tool palettes are authored by Brev contributors
and licensed under MIT with the app. Zenwritten, Tender, and
Tomorrow are MIT-licensed source palettes mapped into Brev's semantic
theme tokens.

## Rationale

- **Chosen: original Brev palettes with familiar moods.** This gives
  users the requested developer-tool feel while avoiding the legal and
  maintenance cost of reproducing product palettes exactly.
- **Rejected: official product-branded themes.** Names such as
  "GitHub Dark", "Discord Dark", and "Cursor Dark" would be more
  immediately recognizable, but ADR-0002 already calls out trademark
  risk for GitHub-style themes. The same caution applies to other
  current product names.
- **Rejected: user themes only.** ADR-0002 supports JSON user themes,
  but built-ins matter for first-run delight and for snapshot coverage
  of the design system.

## Consequences

### Accepted

- Built-in theme QA grows from twelve to thirty-four palettes.
- Snapshot suites that iterate over `BrevTheme.brevBuiltIns` cover a
  broader range of contrast, accent, and surface combinations.
- The app gets more dark IDE options without introducing new theme
  tokens or a schema migration.

### Risks

- The theme picker can feel crowded. Mitigation: keep the additions to
  one focused pack and revisit grouping/search only if theme selection
  becomes hard to scan.
- "Inspired by" palettes may not satisfy users who expect exact brand
  replicas. Mitigation: the JSON user-theme path remains the outlet for
  exact personal palettes.

## References

- ADR-0002: Theme system architecture
- ADR-0005: Enforcement, automation, and provider sync
- ADR-0028: Roadmap to v2 and architectural invariants
- `packages/BrevThemes/Sources/BrevThemes/BuiltIns.swift`
- Nordic Ghostty palette on TerminalColors
- Zenbones Ghostty palettes on TerminalColors
- Tender Ghostty palette on TerminalColors
- Tomorrow Ghostty palettes on TerminalColors
