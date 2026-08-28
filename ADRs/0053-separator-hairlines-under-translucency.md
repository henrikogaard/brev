# ADR-0053: Separator hairlines are a text-colour wash, not the `separator` token

- **Status:** Accepted
- **Date:** 2026-08-12
- **Accepted:** 2026-08-12
- **Deciders:** Henrik
- **Amends:** ADR-0002

## Context

`BrevDivider` filled with `theme.separator.color` at full opacity, and
three call sites (`AccountsSection`, `SettingsSeparator`, and the AI
Sidebar before an earlier implementation) drew their own hairlines the same way. A second
group — the rules under the search strip, the filter strip and the
message-list footer, and the short vertical rules that group toolbar
chips — filled with `theme.border.color` instead, fourteen sites in all.
Every built-in palette defines both tokens as opaque colours tuned
against that palette's own background.

That tuning assumes the theme's background is what the hairline sits on.
Under Brev's window translucency it is not.

`BrevWindowSurfaceBackground` composes each pane as an
`NSVisualEffectView` material with the themed colour painted **over** it
at `surfaceFillOpacity`. With translucency enabled, the surface blends
toward neutral system grey — at the shipped sidebar default that fill is
a minority of the result, and users can take it lower still. The
hairline, drawn opaque, does not blend at all.

So the separator was the only element in the window not participating in
translucency, and no palette value could be correct: whatever hue the
token carried showed at full saturation against a surface that had lost
its own.

Measured on a running build (Tender theme, frosted mode):

| Element | Sampled | Bias (B−R) |
| --- | --- | --- |
| Sidebar surface | (64, 64, 64) | 0 — neutral |
| Content surface | (48, 48, 48) | 0 — neutral |
| Message-list footer rule | (63, 75, 81) | **+18** |
| Search-strip rule | (66, 78, 85) | **+21** |

The surfaces resolved to neutral system grey; the rules did not. Tender
declares `separator` `#293B44` and `border` `#3A4B52`, both toned against
a `#282828` background that translucency means is never painted.

The same audit found a rule that is *correctly* blue and must stay that
way: the divider inside an expanded reader card samples (66, 78, 85) on a
(46, 59, 67) card fill — a uniform +19 lift on Tender's `selection`
surface. That surface is deliberately tinted, so a hairline resolving
against it should be tinted too. This is the behaviour a wash gives for
free and an opaque token cannot.

An audit of all 34 built-in palettes found the token is *usually* toned
correctly against its own background — the hue of `separator` tracks the
hue of `bgPrimary` within a few degrees almost everywhere. Tender is an
outlier where it does not (a perfectly neutral `#282828` background with
a chroma-27 separator, copy-identical to that theme's `selection` and
`bgTertiary`). But fixing outliers would not address the general case:
even a correctly toned token is wrong once the surface it was toned
against is composited away.

## Decision

`BrevDivider` fills with a low-alpha wash of `theme.textPrimary` rather
than with `theme.separator`. A new public `BrevSeparator` in `BrevDesign`
owns that colour and its two weights:

- `interiorOpacity` (0.10) — rules between rows and sections.
- `edgeOpacity` (0.16) — boundaries between panes.

This is what `NSColor.separatorColor` is, and for the same reason: a wash
resolves against whatever the surface actually became. It stays neutral
on a system material and picks up a tinted theme's hue wherever that
theme's colour is genuinely painted.

Every site that drew a hairline directly now calls
`BrevSeparator.color(for:)` — both the `theme.separator` group and the
`theme.border` group — so all hairlines in the app share one mechanism.
`MailContextSeparator`, added in an earlier implementation for the AI Sidebar, becomes a
thin alias for the shared weights instead of a second copy.

The line between a hairline and an outline is what the shape belongs to.
A `Rectangle` one point thick, separating two regions of a pane, is a
hairline and takes the wash. A `.stroke` around a chip, card, text field
or callout outlines an element whose own fill is themed, so it keeps
`theme.border` and stays tinted. `SettingsInfoCallout` is on the outline
side of that line; on Tender it still reads blue, correctly.

`theme.separator` stays in `BrevTheme`'s public API. It remains the token
for a hairline an author deliberately places on an opaque themed surface,
and removing it would break user-authored themes for no gain.

## Consequences

- Hairlines are neutral wherever the surface under them is neutral, which
  under translucency is most of the window.
- A theme can no longer set divider colour independently of its text
  colour. This is a real reduction in theme expressiveness, accepted
  because the token was not reliably honoured in the first place: the
  visible hairline was already a function of the translucency settings
  rather than of the palette.
- The wash tracks `textPrimary`, so a theme with a warm text colour gets a
  warm hairline and a cool one gets a cool hairline, preserving palette
  character without the saturation that caused the defect.
- Themes whose `separator` is mis-toned relative to their own background
  (Tender) are no longer visibly wrong, so those palettes are left
  unchanged rather than re-authored.
- `theme.border` keeps its meaning for element outlines, which is what
  the token is named for. It loses only the hairline duty it had picked
  up in fourteen places.

## Alternatives considered

**Desaturate the `separator` token in the built-in palettes.** Rejected.
It fixes only the built-ins, leaves user-authored themes broken, and does
not address the mechanism: an opaque hairline on a composited surface is
wrong regardless of which opaque colour it is. It would also force
neutrality onto palettes whose backgrounds are genuinely saturated
(Solarized Dark, Gruvbox, Owl Blue), where a chromatic separator is
correct when that background is actually drawn.

**Blend `theme.separator` toward the surface by the same
`surfaceFillOpacity`.** Rejected. `BrevDivider` does not know which
surface role it is drawn on, and threading that through every call site
buys accuracy the eye cannot resolve at one point.
