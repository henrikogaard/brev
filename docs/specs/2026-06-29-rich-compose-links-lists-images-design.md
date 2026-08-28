# Rich-text compose — links, lists, inline images (macOS) — #251

- **Date:** 2026-06-29
- **Issue:** #251 (rich-text / HTML body editing)
- **Governing ADR:** ADR-0038 (Rich HTML compose MVP, Accepted) — this spec
  implements part of that ADR's enumerated follow-up work; **no new ADR is
  required.**
- **Status:** Proposed (awaiting review)

## Goal

Round out the macOS rich-compose experience by adding the three most visible
remaining formatting affordances on top of the existing bold/italic/underline
toolbar: **link insertion, bulleted/numbered lists, and inline images** (local,
embedded as `cid:` parts). The composed message must serialize to the clean,
sanitized HTML subset ADR-0038 already defines and send as standards-compliant
MIME that Brev's own reader (and other clients) render correctly.

## Scope

**In scope (this slice, macOS only):**

- Toolbar buttons + commands for: insert/edit/remove link, bulleted list,
  numbered list, insert image.
- Inline image insertion via an explicit **Insert Image** button **and** via
  paste/drag-and-drop of an image into the editor.
- Attributed-string → HTML serialization for links, single-level lists, and
  inline images.
- Outbound MIME: emit inline images as `multipart/related` parts with
  `Content-ID` + `Content-Disposition: inline`.
- Paste/drop sanitization for the above.
- Tests for every non-view unit (serializer, staging registry, MIME builder,
  sanitizer, paste→cid conversion).

**Out of scope (explicit, YAGNI — tracked as #251 follow-ups):**

- iOS rich-text parity (separate design; UITextView needs a WebView/3rd-party
  WYSIWYG decision or an accepted plain-text gap).
- Nested lists, tables, text/background colors, font family, font size.
- Rich signatures and rich templates.
- Remote images (sanitizer continues to reject them; ADR-0038 #3, ADR-0006).

## Background — what already exists

- **Editor:** `ComposeBodyEditor` wraps `NSTextView` on macOS with
  `isRichText = (bodyFormat == .richTextHTML)`; the Coordinator publishes
  `richHTML` via `ComposeRichTextHTMLSerializer.html(from:)`
  (`ComposeBodyEditor.swift`).
- **Format toggle:** `compose.messageFormat` (`automatic` → rich, `plainText` →
  escaped plain text); `ComposeBodyFormat` enum in `ComposeDraftBuilder.swift`.
- **Existing toolbar commands:** `ComposeRichTextCommandSelectors` +
  bold/italic/underline command enum dispatch responder-chain actions to the
  `NSTextView` (`ComposeView.swift`).
- **Serializer (partial):** `ComposeRichTextHTMLSerializer`
  (`ComposeBodyEditor.swift:192`) is a run-based walker handling
  bold (`<strong>`), italic (`<em>`), underline (`<u>`), and link (`<a>`).
  It does **not** handle paragraph-level lists or `NSTextAttachment` images,
  and extracts hrefs via `String(describing:)`.
- **Sanitizer:** `ComposeHTMLBodyPolicy.richHTML(fromEditorHTML:)` already
  allowlists `a, blockquote, br, div, em, img (cid: only), li, ol, p, strong,
  u, ul` and strips everything else (`ComposeDraftBuilder.swift`).
- **Outbound contract:** `Draft.htmlBody` (HTML string) + staged attachments.
  `MIMEMessageBuilder` (`IMAPOAuthConfiguration.swift`) builds
  `multipart/alternative` (text+HTML) and `multipart/mixed` when attachments
  exist, but emits attachments only as `Content-Disposition: attachment` — **no
  `Content-ID`, no `multipart/related`** (the inline-image send gap this spec
  closes).
- **Reader:** `MessageInlineCIDRenderPolicy` resolves `cid:` image sources from
  inline attachments that carry `isInline == true` + a `contentID` — so once the
  send side emits those, the loop is closed.

## Approach decision — serialization

Extend the **existing custom walker** rather than adopting AppKit's
`NSAttributedString → .html` writer.

- AppKit's writer would give lists/links/images "for free" but emits
  Cocoa-specific HTML (inline `style=` runs, `<span>` noise, `<o:p>`-style
  cruft) that fights ADR-0038's narrow allowlist and would need aggressive,
  brittle normalization — and it gives no clean hook for `cid:` mapping.
- The custom walker already produces allowlist-aligned output and is the right
  place to add paragraph-awareness and attachment→`cid:` mapping under our
  control.

The serializer becomes **paragraph-aware**: it iterates paragraphs (so
`NSTextList` runs group into `<ul>`/`<ol>` with `<li>` children) and, within
each paragraph, keeps the existing run-based inline wrapping for
bold/italic/underline/link, plus attachment→`<img>` emission.

## Architecture & components

Each unit is testable in isolation except the `NSView`-backed editor surface,
which is exercised by testing the policies/serializers it delegates to.

### 1. Formatting toolbar & commands
Extend the macOS command set (`ComposeView.swift`) with `insertLink`,
`bulletedList`, `numberedList`, `insertImage`. Buttons appear only in rich
(`richTextHTML`) mode and only on macOS; iOS compose is unchanged. Commands
dispatch to the editor via the responder chain / Coordinator, mirroring the
existing B/I/U pattern.

### 2. Link insertion
A small link sheet (`ComposeLinkSheet`) collects URL + optional display text,
prefilled from the current selection. Applying sets the `.link` attribute on the
selection (inserting display text if the selection is empty); editing an
existing link prefills from the caret's `.link`; remove clears it. URL
validation/normalization lives in a pure `ComposeLinkPolicy` (scheme allowlist:
`http`, `https`, `mailto`; reject `javascript:` etc.). The serializer already
emits `<a href>`, hardened to read the `.link` value as `URL`/`NSURL`/`String`.

### 3. List controls
Toggle `NSTextList` (markerFormat `disc` for bulleted, `decimal` for numbered)
on the selected paragraphs via the editor Coordinator. Toggling off removes the
list. Single level only. The serializer maps consecutive list paragraphs of the
same kind into one `<ul>`/`<ol>` with `<li>` items.

### 4. Inline-image staging registry
A `ComposeInlineImageRegistry` (per compose session, owned by the compose
presentation) maps a generated `Content-ID` (`<uuid@brev>`) to a staged inline
attachment record (image data, contentID, `isInline = true`, filename, MIME
type from a small image-type allowlist: png/jpeg/gif). On insert/paste/drop it:
(a) stages the attachment, (b) inserts an `NSTextAttachment` (showing the image)
tagged with a custom `.brevInlineContentID` attribute. A reconcile step on body
change drops staged entries whose `NSTextAttachment` no longer appears in the
text, so the staged inline set always matches the body. Inline images are
**not** shown in the regular attachment list.

### 5. Serializer extension (`ComposeRichTextHTMLSerializer`)
Paragraph-aware rewrite:
- Group `NSTextList` paragraphs → `<ul>`/`<ol>` + `<li>`.
- Non-list paragraphs keep current inline run wrapping; separate paragraphs with
  `<br>`/`<div>` consistent with the existing plain-text policy.
- A run whose `.attachment` carries `.brevInlineContentID` → `<img src="cid:ID">`
  (alt from filename). Untagged attachments are dropped (can't be referenced).
- Harden link href extraction (`URL`/`NSURL`/`String`).
Output remains within the ADR-0038 allowlist.

### 6. Outbound MIME — inline images (`MIMEMessageBuilder`)
Add inline-attachment support:
- Inline attachments (those with `isInline == true` + a `contentID`) are emitted
  with `Content-ID: <id>` and `Content-Disposition: inline` (base64).
- When the HTML body references inline images, the HTML part + its inline image
  parts are wrapped in a `multipart/related` (type="text/html") entity; that
  related entity takes the place of the bare `text/html` part inside the existing
  `multipart/alternative`. Regular (non-inline) attachments stay in the outer
  `multipart/mixed` as today.
- Resulting tree when both exist:
  `mixed( alternative( text/plain, related( text/html, image/* … ) ), attachment… )`.
- Verify the outbound security preparer (`OutboundMessagePreparer*` /
  `MIMEEntitySplit`, ADR-0021) signs/encrypts the assembled content entity
  unchanged — it operates on the top content entity, so `multipart/related`
  nests cleanly (RFC 3156).

### 7. Paste / drop handling
Override paste/drop in the macOS editor wrapper:
- Image data on the pasteboard / drag → route through the staging registry
  (component 4) → inline `cid:` attachment.
- Pasted rich text keeps only attributes the serializer understands; everything
  else (colors, fonts, sizes) is naturally dropped at serialize time, so no
  separate attribute scrubber is required for text.
- Remote image references in pasted HTML are not converted (no network fetch;
  ADR-0006) — they are dropped.

### 8. Sanitizer alignment
`ComposeHTMLBodyPolicy.richHTML` already allows `a/ul/ol/li/img(cid)`; confirm
serializer output passes through unchanged and add round-trip tests. Any
attribute the serializer would emit that the sanitizer would strip is a bug to
fix in the serializer, not the sanitizer.

## Data flow

```
NSTextView (rich)
  ├─ user formats / inserts link / toggles list / inserts·pastes·drops image
  │     └─ image → ComposeInlineImageRegistry: stage inline attachment + tag NSTextAttachment
  └─ Coordinator.publishRichHTML
        └─ ComposeRichTextHTMLSerializer (paragraph-aware) → richHTML
              └─ ComposeDraftBuilder → ComposeHTMLBodyPolicy.richHTML (sanitize) → Draft.htmlBody
                    └─ backend.send → MIMEMessageBuilder
                          └─ multipart/mixed( alternative( text/plain, related( text/html, inline image/* ) ), attachments )
                                └─ reader: MessageInlineCIDRenderPolicy resolves cid: → renders
```

## Error handling & edge cases

- **Empty selection + link:** insert the URL (or provided display text) as new
  linked text at the caret.
- **Invalid/blocked URL scheme:** link sheet rejects with inline validation; no
  attribute applied.
- **Oversized image:** enforce a per-image size cap (e.g. reject > a sane bound,
  surfaced as an inline compose error) to avoid unbounded MIME bloat.
- **Unsupported pasted image type:** rejected (allowlist png/jpeg/gif); other
  pasteboard content falls back to text paste.
- **Image deleted in the editor:** reconcile drops its staged attachment so no
  orphan inline part is sent.
- **Plain-text mode:** images/links/lists controls are disabled/hidden; existing
  escape-and-`<br>` policy is unchanged.
- **Send with inline images but recipient strips HTML:** the `text/plain`
  alternative (image markup removed) still carries the message body.

## Invariants honored

- **ADR-0028 view-layer boundary:** all logic lives in testable policies
  (`ComposeLinkPolicy`, `ComposeInlineImageRegistry`, serializer, MIME builder);
  views stay backend-agnostic and consume `Draft.htmlBody`.
- **ADR-0028 rendering seam:** send path stays behind `MailBackend.send`;
  reader path is unchanged (already resolves `cid:`).
- **ADR-0006 privacy:** no new external network call; remote images rejected;
  inline images are local→`cid:` only.
- **ADR-0038:** output stays within the defined allowlist; plain-text remains
  first-class; outbound contract stays `Draft.htmlBody`.
- **ADR-0021 crypto:** the security preparer wraps the assembled MIME entity
  unchanged.

## Testing strategy

- **Serializer:** attributed-string fixtures → expected HTML for link, bulleted
  list, numbered list, mixed list+inline run, inline image (`<img src=cid:>`),
  and combinations; assert output is allowlist-clean.
- **Sanitizer round-trip:** serializer output passes `richHTML` unchanged.
- **Staging registry:** insert N images → N staged inline attachments with
  unique Content-IDs; remove one → reconcile drops it; tagged-attachment mapping.
- **Link policy:** scheme allowlist accept/reject; selection vs caret behavior.
- **MIME builder:** inline attachment → `Content-ID` + `Content-Disposition:
  inline`; `multipart/related` nesting with and without outer attachments;
  `text/plain` alternative present; round-trip parse where practical.
- **Paste→cid:** pasted/dropped image data produces a staged inline attachment
  and a `cid:` reference; remote `<img>` dropped.
- The `NSTextView` editing surface itself is not headlessly testable (per repo
  convention); it is kept thin and delegates to the tested units.

## Files (anticipated)

- **Modify:** `ComposeBodyEditor.swift` (serializer extension, attachment tag,
  paste/drop), `ComposeView.swift` (toolbar commands), `ComposeDraftBuilder.swift`
  / `ComposeHTMLBodyPolicy` (confirm/align sanitizer), `IMAPOAuthConfiguration.swift`
  (`MIMEMessageBuilder` inline parts + `multipart/related`), the compose
  presentation that owns attachments (wire the inline registry).
- **Add:** `ComposeLinkPolicy.swift`, `ComposeInlineImageRegistry.swift`,
  `ComposeLinkSheet.swift` (view), and matching test files.

## Follow-ups (not this slice)

iOS rich-text parity; rich signatures/templates; nested lists; colors/fonts;
paste of remote images as fetched inline (would need an ADR-0006 entry).
