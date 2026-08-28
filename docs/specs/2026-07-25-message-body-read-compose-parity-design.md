# Message body read/compose visual parity

- **Date:** 2026-07-25
- **Status:** Accepted
- **Branch context:** `feature/backend_rewrite`
- **Related:** ADR-0002 (theme), ADR-0006 (privacy / remote content), ADR-0028 (rendering pipeline invariant), ADR-0014 (surfaces); prior compose formatting design `2026-06-29-rich-compose-links-lists-images-design.md`

## Goal

One coherent visual language for mail bodies across **reading** (Detail + Thread), **print**, and **compose** (macOS + iOS), including stronger iOS rich editing — while keeping Brev’s privacy model and native compose editors (no `contenteditable` WKWebView).

## Non-goals

- Pixel-perfect WebKit layout inside the native text editor.
- Redesigning list/sidebar chrome or Settings IA.
- Changing MIME preference (HTML remains preferred when the rich reader is on).
- Word-class editing (tables, per-run font pickers, complex paste cleanup beyond allowlist).
- Enabling JavaScript in the reader WebView.

## Decisions already locked with Henrik

| Decision | Choice |
|---|---|
| Scope | **C** — visual polish + consistency across Detail / Thread / print, **plus compose** |
| Compose depth | **3** — write/read parity direction, including stronger iOS rich editing |
| Architecture | **A** — shared `MessageBodyStyle` + native rich editors (not contenteditable) |
| Remote content | Unchanged — opt-in per ADR-0006 |

## Problem statement

Evidence from current code:

1. **Different engines** — Compose uses `NSTextView` / `UITextView`; reading HTML uses sandboxed `HTMLBodyWebView` / `HTMLBodyDocument` CSS. No shared stylesheet.
2. **Different typography prefs** — Reader honors `MailboxFontFamily` / `MailboxTextSize`; compose uses system `.body` + `ComposeBodyAppearance`.
3. **Hardcoded reader dark CSS** — Dark / theme-adapted mode injects fixed hex (`#111114`, `#E5E7EB`, `#93C5FD`) instead of theme tokens.
4. **Detail vs Thread mismatch** — Plain/attributed Thread bodies use `.font(.body)` while Detail uses mailbox prefs; remote-content banners diverge in copy/actions.
5. **Print vs read preference** — Reader prefers HTML when present; print prefers plain when both exist.
6. **iOS “rich” is weak** — macOS rich serializes attributed HTML; iOS rich path is largely plain escape-to-HTML without a real formatting toolbar.
7. **Stale docs** — `MessageDetailView` still claims prefer-plainText; Settings default is rich HTML on.
8. **Chrome padding** — WebKit wrapper uses `padding:0` while SwiftUI reader cards use density padding.

## Architecture

### `MessageBodyStyle`

New shared style model (prefer `BrevMail`, reusing `BrevDesign` mailbox font/size types and `BrevTheme`):

**Inputs**

- `BrevTheme` (text primary/secondary, accent, surface as needed)
- `MailboxFontFamily` + `MailboxTextSize`
- Reader density / inset (align with `MessageReaderLayoutPolicy`)
- `HTMLBodyRenderingMode` (original vs theme-adapted)

**Outputs**

- CSS string for `HTMLBodyDocument.wrap` (reader + optional compose preview)
- Native typography for SwiftUI plain/attributed bodies and AppKit/UIKit editors (`NSFont` / `UIFont`, text/link colors, line-height ≈ 1.45)
- Print styling that follows the same body preference and tokens

### Surfaces

| Surface | After |
|---|---|
| Detail HTML (WKWebView) | CSS from `MessageBodyStyle` only (no hardcoded dark palette) |
| Detail plain / attributed | Same native fonts/colors/insets |
| Thread card body | Same style inputs as Detail |
| Print | Prefer the body the reader would show; style via `MessageBodyStyle` |
| Compose editor | Mailbox font/size + theme text/accent; shared inset rhythm |
| Compose HTML preview | Optional read-only WKWebView, same CSS, JS off (macOS first) |

### iOS rich compose

Keep native `UITextView`. Add a compact formatting toolbar (Bold, Italic, List, Link) producing attributed text, serialized through the shared HTML path used on macOS (`ComposeRichTextHTMLSerializer` / allowlisted tags).

This **is** the separate iOS rich-text design called out as out-of-scope in `2026-06-29-rich-compose-links-lists-images-design.md` (which remains authoritative for macOS links/lists/inline images). Slice 4 implements iOS essentials only (no inline images on iOS in this effort unless already trivial); macOS image/list work stays on the 2026-06-29 track if not already shipped.

### Invariants

- ADR-0006: remote images/CSS/fonts stay blocked until user opt-in.
- ADR-0028: body still flows through `BodyRenderer` / `RenderedBody`.
- AGENTS Rule 1: no literal colors in views; theme (and style derived from theme) owns color.
- Compose remains native editors — **not** WKWebView `contenteditable`.

## UX details

### Reader

- Shared body inset so WebKit content and plain text share the same visual margins.
- Theme-adapted / dark mode uses theme text, background, and accent.
- “Original” mode preserves sender colors when safe; force light canvas only when contrast requires it.
- Remote-content banners: aligned action labels; Thread may stay shorter copy.

### Compose

- Plain vs Rich toggle keeps current meaning; Rich on iOS gains real formatting.
- Optional **Preview** toggle (macOS first): read-only HTML with reader CSS.
- Reply/quote blocks use the same blockquote tokens as the reader.

### Settings / copy

- Fix stale prefer-plainText documentation on `MessageDetailView`.
- Mailbox View / Reading copy: font size applies to reading and composing.

## Rollout (PR slices)

1. **`MessageBodyStyle` + reader** — theme-faithful CSS; Detail/Thread plain+HTML parity; doc fixes; unit tests for token→CSS mapping  
2. **Print + body chrome insets** — print body preference matches reader; shared padding  
3. **Compose native chrome** — editor uses mailbox font/size/theme colors  
4. **iOS rich toolbar + serializer** — bold/italic/list/link; shared serialization tests  
5. **Compose HTML preview** — macOS first; read-only WKWebView, JS off  

## Testing / verification

- Unit: style resolution; dark/original CSS contains theme hexes and excludes banned hardcoded palette; print body selection; serializer round-trip for basic marks  
- Presentation: Detail and Thread receive the same font/size style inputs  
- Snapshots / smoke: reader chrome where feasible; full WKWebView pixel lock optional (artifacts OK)  
- Manual: theme switch, font size, HTML mail, plain mail, reply quote, compose rich → send → read back on macOS and iOS  

## Risks

| Risk | Mitigation |
|---|---|
| Native editor ≠ WebKit layout | Shared tokens + optional preview; no contenteditable |
| Paste / HTML garbage | Keep and extend serialize allowlist |
| iOS toolbar crowding | Compact bar; overflow menu if needed |
| Dark CSS regressions | Tests assert theme-derived colors |

## Success criteria

1. Switching theme or mailbox font size updates reader and compose together.  
2. Detail and Thread bodies look like one system (fonts, colors, insets, remote banner actions).  
3. Print shows the same preferred body the reader would.  
4. iOS can bold/italic/list/link and send HTML the reader renders cleanly.  
5. No new remote network behavior; reader JS stays off.

## Open questions (non-blocking)

- Exact package home for `MessageBodyStyle` (`BrevMail` vs small shared helper in `BrevDesign`) — default **BrevMail** next to `HTMLBodyDocument`.  
- Whether iOS compose preview ships in slice 5 or waits for a follow-up.

## References

- `packages/BrevMail/.../HTMLBodyWebView.swift` / `HTMLBodyDocument`
- `packages/BrevMail/.../MessageDetailPresentation.swift`
- `packages/BrevMail/.../ComposeBodyEditor.swift` / `ComposeView.swift`
- `packages/BrevMail/.../ThreadMessageCard.swift`
- `docs/specs/2026-06-29-rich-compose-links-lists-images-design.md`
