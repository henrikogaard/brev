# Mail window opacity and material spec

- **Status:** Living UI spec
- **Date:** 2026-05-30
- **Owner:** Brev UI
- **Related ADRs:** ADR-0002, ADR-0028, ADR-0014, ADR-0015

## Intent

The macOS mail window should feel like one continuous translucent object:
calm, readable, and native, with the desktop subtly present behind the
app. It should not look like separate opaque strips have been stacked on
top of a blurred window.

The visual rule is: one surface owns opacity for each region. Child chrome
may draw separators and controls, but it must not paint a competing pane
background.

## Surface Ownership

### Main Window Container

The scene root owns the transparent titlebar and toolbar region through
`BrevWindowSurfaceBackground(role: .mainWindow)`.

- The main window surface must extend into safe areas so transparent
  titlebar chrome never reveals the default AppKit window background.
- The AppKit window background remains clear when transparent chrome is
  enabled.
- The native toolbar must not draw its own baseline separator; Brev-owned
  separators use theme tokens.

Reference implementation:

- `apps/macOS/Sources/BrevApp.swift`
- `packages/BrevDesign/Sources/BrevDesign/Components/BrevWindowSurfaceBackground.swift`
- `packages/BrevMail/Sources/BrevMail/BrevMailNativeToolbar.swift`

### Sidebar Pane

The folder sidebar owns its readable backing through
`brevMailPaneSurface(.sidebar)`.

- Sidebar material may be more translucent than dense content.
- Rows may use token-based selection and hover surfaces.
- The sidebar must provide a full-height backing surface, including empty
  areas.

Reference implementation:

- `packages/BrevMail/Sources/BrevMail/MailPaneSurface.swift`
- `packages/BrevMail/Sources/BrevMail/BrevMailRootView.swift`

### Message List And Reading Pane

The message list and reading pane own their readable backing through
`brevMailPaneSurface(.content)`.

- Dense mail content does not receive live blur directly.
- Message list scroll backgrounds stay hidden.
- Reading pane scroll backgrounds stay hidden.
- Empty list/detail states must still show the same full-height content
  surface.

Reference implementation:

- `packages/BrevMail/Sources/BrevMail/MailPaneSurface.swift`
- `packages/BrevMail/Sources/BrevMail/MessageListView.swift`
- `packages/BrevMail/Sources/BrevMail/MessageDetailView.swift`
- `packages/BrevMail/Sources/BrevMail/ThreadConversationView.swift`

## Chrome Rules

### Transparent Strips

The following message-list chrome must inherit the pane surface and use
`Color.clear` or no explicit background:

- bulk action bars
- quick-filter bar
- date and pinned section headers, except intentional token accents
- folder statistics footer

These strips may draw thin separators with `theme.border.color` or
equivalent design-system tokens.

### Control Surfaces

Controls inside transparent strips may draw their own small surfaces when
the surface is part of the control affordance.

Examples:

- active quick-filter chips use `theme.accent.color.opacity(...)`
- inactive quick-filter chips may use a subdued token surface
- selected message rows and cards use the selection token
- cards use tokenized backgrounds and borders for readability

The control surface must be local to the control. It must not span the
entire pane width unless the component is intentionally selected or
expanded.

## Do And Don't

| Do | Don't |
| --- | --- |
| Let `BrevWindowSurfaceBackground` own root window material. | Add ad hoc `.regularMaterial`, `.ultraThinMaterial`, or raw AppKit blur in feature views. |
| Let `MailPaneSurface` own sidebar/content pane opacity. | Put `theme.bgPrimary.color` or `theme.bgSecondary.color` behind whole top/bottom bars. |
| Use `Color.clear` for structural transparent chrome. | Use opacity layers as decorative patches over pane surfaces. |
| Hide platform scroll backgrounds in mail panes. | Let default list/scroll backgrounds show through short content. |
| Keep separators tokenized and thin. | Rely on AppKit toolbar baseline separators or unthemed dividers. |
| Test against bright, saturated wallpaper. | Validate only on a flat dark desktop. |

## Acceptance Checklist

Before shipping mail-window visual changes:

- The titlebar, toolbar, list pane, reading pane, and footer feel like
  parts of one continuous object.
- No top or bottom strip appears more opaque than the pane it belongs to.
- The message-list top bar does not visually stretch under the sidebar as
  a separate band.
- The right reading pane does not show an extra unblurred top strip.
- The folder statistics footer inherits the pane translucency.
- Pinned/date section headers preserve hierarchy without becoming opaque
  bars.
- Solid mode remains fully readable.
- Reduce Transparency falls back to solid surfaces.
- The implementation uses theme/design-system tokens and respects the
  no-literal-colors rule.

## QA Notes

Use the mock mailbox and a bright, saturated desktop image when checking
this UI. The wallpaper should be visible enough to expose mismatched
opacity, but message text must remain readable.

Check all of these states:

- normal mailbox with no selection mode
- bulk selection mode
- expanded threaded list rows
- selected child thread message
- empty folder or loading state
- bottom reading pane layout
- Reduce Transparency enabled
- solid, subtle, frosted, and glass window-design modes
