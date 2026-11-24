# Compose, Rich HTML & Draft Preservation

> Consolidates former ADRs `0024`, `0038`, and `0093`.

## Goals

Composing, replying, forwarding, and reopening drafts across devices must feel as fluid as Apple Mail or Mimestream while **never silently flattening formatting or losing attachments**.

## Compose Surface

- **Native text editors:** AppKit `NSTextView` on macOS and UIKit `UITextView` on iOS inside shared `ComposeView` orchestration, supporting both detached windows and the macOS inline docked reply bar under the reader (with quick reply starters, Send, Send Later, Undo Send countdown, and opt-in AI Writer).
- **Rich HTML compose (expanded beyond former ADR-0038 MVP):**
  - Supports bold, italic, underline, links, line breaks, lists, quoted replies, signatures, and multipart attachments today.
  - **Planned expansion:** Inline images (`cid:` / pasted images), clean rich-HTML paste, tables, and code blocks—moving past the narrow MVP subset while preserving clean MIME generation (`multipart/alternative` + `multipart/related`).
- **Recipient handling & safety:** Chip-based To/Cc/Bcc fields with local Contacts, CardDAV, and removable recent-recipient autocomplete, per-account signature selection (including explicit "No signature"), single-flight Save/Send guards, and optional Send Later / Undo Send / no-reply follow-up reminders.

## Draft Reopening & Quote Preservation (Relaxed from Former ADRs `0038`/`0093`)

- **Core safety rule:** Brev must never silently destroy existing rich formatting, quoted thread history, or attachments when reopening a draft saved by Brev or by another client (webmail, iOS Mail, Gmail).
- **Current implementation:** Restores canonical local drafts, Brev-generated lists, flat `<blockquote>` quotes, and server-sourced replies/forwards with locked quote boundaries and preserved attachments.
- **Relaxed direction (replacing refuse-by-default):** Instead of refusing to open drafts that contain nested/styled `<blockquote>` elements, complex webmail HTML attributes, or rich quoted layouts, Brev should **preserve unsupported quoted HTML intact below the editable reply area** (the Apple Mail / Mimestream model) so users can always edit and send their reply without hitting a dead-end refusal banner.
- **Fail-closed only on true data-loss risk:** Pending, failed, or cancelled draft loads still block Save/Send/autosave so partial state can never overwrite a remote draft.

## Crash Recovery

- Crash recovery snapshots exist strictly for **unsaved new messages** after an unexpected crash or force-quit (replies/forwards rely on normal Drafts autosave).
- Normal Send, Discard, or Close clears matching recovery state; stale async callbacks cannot overwrite newer drafts.
- Recovery requires matching owned local draft/attachment bytes and never triggers silent network reconstruction.

## iOS Share Extension Attachment Handoff

- `BrevShareExtension` writes shared files, images, PDFs, and mixed payloads into a scoped App Group handoff directory with a manifest token and launches the main app via a short `brev://compose?handoff=<id>` URL, avoiding URL-length limits and surviving cold launches cleanly. The main app imports the bytes into the draft and deletes the temporary handoff directory.
