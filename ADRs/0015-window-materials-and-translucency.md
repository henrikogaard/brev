# ADR-0015: Window materials and translucency preferences

- **Status:** Proposed
- **Date:** 2026-05-29
- **Deciders:** Henrik

## Context

Brev's current theme system is fully token-driven and mostly opaque.
That keeps mail readable and makes the no-literal-colors rule easy to
enforce, but it leaves no first-class path for a more native macOS
translucent window treatment.

Apple's current macOS design direction favors system materials and,
on newer platforms, Liquid Glass. Brev should let users choose that
style without making message text hard to read, without scattering
ad hoc `.ultraThinMaterial` calls across feature views, and without
forcing newer SDK-only effects onto older supported macOS versions.

## Decision

Add a shared window appearance preference model in `BrevDesign`:

- `WindowTranslucencyMode`
  - `solid`
  - `subtle`
  - `frosted`
  - `glass`
- `WindowTranslucencyScope`
  - `sidebarOnly`
  - `mainWindow`
  - `allWindows`
- `WindowSurfaceRole`
  - `mainWindow`
  - `sidebar`
  - `content`
  - `settings`
  - `utility`
  - `card`

The default is solid windows scoped to the main window. Solid remains
the readability-first baseline. It uses the same unified, full-size
title-bar geometry as the material modes when Unified title bar is
enabled, but retains fully opaque themed surfaces and an opaque AppKit
window backing. Changing material style must not reshape the main or
Settings window.

`BrevDesign` owns the public model and the reusable surface helpers.
Feature packages consume the model rather than choosing raw materials
locally. On macOS, material rendering uses system materials and a
narrow AppKit bridge where SwiftUI alone cannot express the desired
window background. Behind-window transparency follows the selected
scope independently of title-bar layout. Settings follows the Main
window scope (and All windows); other secondary utility windows stay
opaque unless users choose All windows.

Live material is limited to window chrome, sidebar, Settings window
containers, and utility roles that opt into live material. Dense reading and editing
surfaces — message detail, message list content, compose content,
utility content panes, and cards — do not receive live blur, but they
do participate in the same scoped opacity layer so "main window" and
"all windows" visibly affect the panes users are looking at. The
Settings window follows the same composition rule as mail: its root
`settings` role provides material and transparent chrome, while its
sidebar and `content` roles each provide one themed readability layer.
This makes Appearance → Window design visible without stacking the pane
opacity beneath every Settings column and group. On other platforms, or
when macOS Reduce Transparency is enabled, the effective mode is solid.

Translucency-capable surfaces render a theme-colored readability layer
above live material when material is present, or as the pane backing
when live material is intentionally withheld. Users can tune that layer
with a `surfaceOpacity` preference clamped to `0.25...0.95`; the
default `0.82` keeps wallpaper visible while preventing bright or
saturated desktop images from overpowering mail panes, settings, and
cards. Sidebar roles use a separate `sidebarOpacity` preference
clamped to `0.10...0.95`; the default `0.59` keeps sidebars visibly
more translucent than dense panes. When the sidebar-specific key is
missing, it initializes from the previous derived sidebar value so
existing installs keep their current visual balance.

Settings groups and cards may add a bounded contrast overlay for hierarchy,
but they inherit the pane's configured opacity instead of painting another
window-sized readability layer.

The AppKit window background stays fully clear when transparent chrome
is enabled. It must not reuse `surfaceOpacity`, because that would add a
second compositor layer behind SwiftUI panes and make user-visible
opacity much closer to solid. The `mainWindow` and `settings` roles
represent window chrome/containers and can host live material, while
sidebar and content roles own the readable tint. Settings and main-window
containers use the same lighter base material in Frosted and Glass modes.

Mail split-view panes must also provide themed backing surfaces that
extend through the titlebar/toolbar safe area and hide platform default
scroll backgrounds. On macOS,
`NavigationSplitView` can insert opaque AppKit column fills above those
materials; Brev clears those fills via
`BrevSplitViewColumnTransparencyFixer` so behind-window vibrancy remains
visible (`containerBackground(for: .navigationSplitView)` is iOS-only).
Transparent window chrome must never reveal AppKit's default window color
behind short or empty mailbox/sidebar content.

Because SwiftUI can restore those opaque fills after the last layout
trigger, the coalesced repair is self-verifying: each settled pass
reports whether it actually cleared a restored fill, and while it keeps
finding work it re-arms itself, bounded per external trigger, until a
pass finds a clean tree. Repair passes must reach a fixpoint rather than
poll on a timer, and translucency machinery that has to disable itself
(for example the scroll-edge blur reduction when the material's layer
tree never exposes a backdrop) must log the fail-closed reason instead
of degrading silently.

The `glass` mode is a user-facing design choice, but implementation
must be availability-gated. When newer Liquid Glass APIs are not
available, Brev falls back to the strongest supported system material
instead of failing to render.

Settings exposes this under Appearance as "Window design" so users can
choose style, scope, pane opacity, and sidebar opacity.

## Rationale

**Why not encode translucency in themes.** Translucency is a rendering
behavior, not a color token. Keeping it separate avoids multiplying
every theme by material variants and preserves ADR-0002's fixed token
schema.

**Why scope.** A full frosted mail reader can hurt readability. Scope
lets users pick a subtle native sidebar effect without forcing blur
behind dense message content.

**Why system materials.** System materials respect active/inactive
window state, vibrancy, accessibility settings, and platform changes
better than hand-rolled blur or alpha overlays.

**Why fallback to solid on Reduce Transparency.** Accessibility
settings are user intent. Brev should never fight them for style.

## Consequences

### Accepted

- Public `BrevDesign` APIs grow to include window appearance
  preferences and surface helpers.
- Major root surfaces must move from direct `theme.bgPrimary.color`
  backgrounds to `BrevWindowSurfaceBackground` where translucency is
  user-configurable.
- Snapshot baselines may need updates when material-aware surfaces are
  included in snapshot suites.

### Risks

- Translucency-heavy mail windows can reduce contrast on busy wallpapers.
  Mitigation: solid remains default, scope defaults conservatively,
  a clamped opacity control adds a themed readability layer, and
  message bodies keep theme-colored foregrounds.
- Newer Liquid Glass APIs may change while SDKs settle. Mitigation:
  gate usage by availability and keep AppKit material fallback.
- Overusing materials can make the app feel inconsistent. Mitigation:
  keep one shared surface helper and expose only a small set of
  user-facing modes.

## References

- ADR-0002: Theme system architecture
- ADR-0004: Build system and project layout
- ADR-0005: Enforcement, automation, and provider sync
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0014: Design-system surface primitives
- Apple Developer Documentation: `NSVisualEffectView`
- Apple Developer Documentation: `containerBackground(_:for:)`
- Apple Developer Documentation: Liquid Glass
