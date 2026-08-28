# Settings deep rebuild (Brev-native + System Settings IA)

- **Date:** 2026-07-24
- **Status:** Proposed — awaiting maintainer review of this spec
- **Branch context:** `feature/backend_rewrite`
- **Related:** ADR-0012 (settings surface), ADR-0002 (theme), ADR-0014 (surfaces), ADR-0015 (window materials / translucency)

## Goal

Rebuild Brev Settings so it feels like a modern System Settings window while staying fully Brev-themed: one information architecture on macOS and iOS, dense quiet rows, progressive disclosure for power tools, and working window translucency/vibrancy in the Settings window.

## Non-goals

- Redesigning the mail three-column workspace (except removing the legacy overlapping settings sheet).
- Inventing a second theme system for translucency (ADR-0015 stays the model).
- Shipping Liquid Glass–only APIs without fallbacks.

## Decisions already locked with Henrik

| Decision | Choice |
|---|---|
| Depth | **C** — deep rebuild (System Settings density + progressive disclosure) |
| Visual language | **3** — Brev theme/surfaces; System Settings IA/hierarchy |
| Platforms | **B** — macOS + iOS together (shared IA/components) |
| Architecture | **1** — evolve `BrevSettings` in place (no parallel Settings 2 package) |
| Legacy sheet | **Delete** `BrevMail.SettingsView` as a second settings UI; gear always opens full Settings |

## Problem statement

### Messiness

1. Dual UIs: `BrevSettings.SettingsView` vs oversized `BrevMail.SettingsView` sheet with overlapping controls (ADR-0012 sibling boundary already strained).
2. Triple nesting: scaffold background → `SettingsGroup` opaque cards → inner callout cards (Mail Storage is the worst offender).
3. Phone list drops sidebar group headers; iOS has Done + floating close.
4. Power tools (Download all mail / Reset) compete on the first screen.
5. Literal spacing and parallel row components (`SettingsPanel` in Mail vs `SettingsGroup` in Settings).

### Vibrancy / transparency does not work in Settings today

Root causes (current code + ADR-0015):

1. **Scope gate:** default scope is `.mainWindow`. `WindowTranslucencyScope.applies(to:)` returns **`false` for `.settings`** under `.mainWindow`, so Settings ignores Style/opacity unless the user picks **Apply to → All windows**. Most users never do that, so Settings stays solid while mail may look frosted.
2. **Opaque card stack:** even when scope is `.allWindows`, detail panes paint full-opacity `SettingsGroup` / card fills over `BrevWindowSurfaceBackground(role: .settings)`, so wallpaper/vibrancy is invisible behind content.
3. **ADR vs intuition:** ADR-0015 allows settings material when scope includes it, but copy and defaults make “Window design” look broken for the Settings window itself.

Fixing vibrancy is **in scope** for this rebuild (not a drive-by).

## Target experience

### Information architecture (shared)

Sidebar / iPhone grouped list (same labels):

- **Accounts**
- **General** — Appearance · Notifications · Updates *(gated)*
- **Mail** — Mailbox View · Compose · Signature · Templates · VIP & Reminders · Rules · Vacation / Forwarding
- **Data** — Folder Sync · Mail Storage · Import / Export *(rename Sync & Storage → Data for brevity; keep section IDs stable where possible)*
- **Calendar & Contacts** — Calendar & Contacts · CalDAV *(flagged)*
- **Privacy & Security** — Privacy · Security · AI Writer
- **About** (+ Developer when gated; Advanced stays roadmap/hidden)

### Chrome

- **macOS:** existing Settings window; transparent title bar follows Appearance toggle when translucency is active.
- **iOS:** root swap into Settings; **single** dismiss (toolbar Done only).
- Detail: title + one-line subtitle; inset row groups; **no** card-in-card for ordinary rows.
- Callouts only when they change a user decision (retention before download, Reduce Transparency warning).

### Progressive disclosure — Mail Storage (showcase)

**Collapsed (default):**

- Size on disk (tabular nums) · object count  
- Cache location (truncated, full path on hover/long-press)  
- Reveal Cache in Finder *(macOS only)*  
- Disclosure: **Advanced storage…**

**Expanded:**

- Breakdown rows (mail cache / drafts / offline / search index)  
- Local retention / cache lookback  
- Search index status  
- **Download all mail** (primary)  
- **Reset & re-download** (destructive, separate row + confirmation; never beside Download)

### Vibrancy policy (product + technical)

| Rule | Behavior |
|---|---|
| Style `solid` or Reduce Transparency | Settings fully opaque (unchanged) |
| Style translucent + scope **Sidebar** | Settings stays opaque (sidebar-only) |
| Style translucent + scope **Main window** | **Settings follows main-window translucency** (change from today) |
| Style translucent + scope **All windows** | Settings + mail + utility (unchanged intent) |
| Live material | Window chrome + settings sidebar/detail *backing* may use `NSVisualEffectView` / material; row groups use **tinted translucent fills** at `surfaceOpacity`, not solid `bgPrimary` slabs |
| Cards | Prefer hairline / grouped list density; if a group needs a surface, use `BrevWindowSurfaceBackground`-aware fill or low-opacity theme tint — never a second full opaque window color |

Update **ADR-0015** so `.mainWindow` scope explicitly includes `.settings` (and keep stronger readability floor for settings than for mail sidebar).

Appearance “Window design” copy should state that Settings follows Main window / All windows scopes.

## Architecture

```text
apps/macOS|iOS
  └─ open Settings → BrevSettings.SettingsView only

packages/BrevSettings
  ├─ SettingsView (split / stack)
  ├─ SettingsNavigationState (groups; phone headers restored)
  ├─ SectionScaffold (translucent-aware background; titlebar scrim)
  ├─ Settings row primitives (flatten nesting)
  └─ Sections/* (port content; Mail Storage progressive disclosure)

packages/BrevDesign
  └─ WindowAppearancePreferences.applies(to:)  // include .settings in .mainWindow
  └─ BrevWindowSurfaceBackground / Settings group fill helpers

packages/BrevMail
  └─ Delete SettingsView sheet UI; gear → onOpenSettings only
  └─ Keep MailboxStorageInfo / presentation helpers used by BrevSettings
```

## Migration plan (implementation phases — detail in writing-plans later)

1. **Vibrancy fix + Appearance copy** (small, shippable, unblocks “broken today”)  
2. **Chrome rebuild** — SectionScaffold / SettingsGroup density, iOS dismiss, phone group headers  
3. **Mail Storage progressive disclosure** + snapshot refresh  
4. **Delete `BrevMail.SettingsView`** + inventory/ADR-0012 notes  
5. **Remaining sections** ported to new row chrome; compact smoke artifacts updated  

Phases 1–2 can land as focused PRs; 3–5 may be one or more PRs but must not leave two competing Settings UIs at the end.

## Testing / verification

- Unit: `WindowAppearancePreferences` — `.mainWindow` scope applies to `.settings`; Reduce Transparency still forces solid.  
- Unit: Mail Storage disclosure collapsed/expanded presentation.  
- `AppearanceControlsPolicy` unchanged (macOS-only window design).  
- Compact Settings smoke artifacts: Appearance + Mail Storage (collapsed).  
- Manual macOS: frosted + Main window → Settings window shows wallpaper bleed / vibrancy; opaque cards gone.  
- Manual iOS: grouped list headers; single Done; no Reveal.  
- Accessibility: Reduce Transparency → solid Settings.

## Success criteria

1. One Settings surface on both platforms.  
2. Mail Storage first screen fits ~1100×760 without scrolling for the summary.  
3. iPhone list group headers match sidebar.  
4. Themes still own all colors (no literal colors).  
5. With Style ≠ solid and Apply to = Main window (or All windows), Settings vibrancy is visibly working unless Reduce Transparency is on.

## Open questions (none blocking)

- Exact rename “Sync & Storage” → “Data” vs keep label (prefer **Data** in UI, keep enum cases if renames are noisy).  
- Whether Settings *sidebar* uses `.sidebar` role material vs `.settings` for the whole window (prefer whole-window `.settings` role + split chrome).

## References

- Assessment: dual UI, Mail Storage nesting, iOS double dismiss  
- `ADRs/0015-window-materials-and-translucency.md`  
- `ADRs/0012-settings-surface.md`  
- `packages/BrevDesign/.../WindowAppearancePreferences.swift` (`applies(to:)` settings exclusion)  
- `packages/BrevSettings/.../SectionScaffold.swift` / `AppearanceSection.swift`
