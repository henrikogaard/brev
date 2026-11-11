# ADR-0038: Rich HTML compose MVP

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Supersedes:** ADR-0038

## Context

ADR-0038 kept v1 compose plain text to avoid a half-supported WYSIWYG
surface. The related feature request reopens that decision after comparing Brev with
Outlook, eM Client, and Apple Mail, where rich compose is expected.

Brev already hands drafts to backends as `Draft.htmlBody`, and the IMAP
send path emits `multipart/alternative` from that HTML. The missing
piece is the compose-side model: editing, serialization, sanitization,
and a plain-text escape hatch.

The change must preserve ADR-0006 and ADR-0028:

- no remote assets may be fetched or embedded without user intent;
- views still talk to provider-neutral draft models;
- the send path stays backend-agnostic through `MailBackend.send`;
- future PGP/MIME and S/MIME handling can still operate on explicit
  outbound body data.

## Decision

Brev accepts a staged rich HTML compose MVP.

1. **Automatic compose format resolves to rich HTML.** The existing
   `compose.messageFormat` setting remains the user-facing control.
   `Plain Text` continues to force escaped plain-text serialization.

2. **The first supported formatting subset is deliberately small.**
   The MVP supports native editor formatting that serializes to clean
   HTML for bold, italic, underline, links, paragraphs/divisions, lists,
   blockquotes, and line breaks. Unsupported tags and attributes are
   stripped rather than passed through.

3. **Remote images are not accepted by the sanitizer.** Inline image
   markup is only preserved for `cid:` sources. Building the UI for
   inserting local inline images and attaching matching MIME parts is a
   follow-up inside #251 rather than a hidden remote-load behavior.

4. **Plain text remains a first-class mode.** Plain mode uses the
   existing escape-and-line-break policy and does not preserve markup.

5. **The outbound contract stays `Draft.htmlBody`.** Backends continue
   to choose the actual transport representation. IMAP/SMTP may build
   `multipart/alternative`; other backends may map the same draft value
   to their native send API.

6. **Saved bodies and recovery must be proven safe before editing.**
   The editor resolves the canonical local draft in the bound account/mailbox,
   checks the supplied draft or recovery hint against it, and resolves complete
   owned attachment payloads through `LocalDraftAttachmentProviding`. Recovery
   never reconstructs a draft from provider body fetches or from the legacy
   text-only hint. Missing, stale, foreign, inline/CID, oversized or server-only
   payloads fail closed without changing the saved draft. (ADR-0093 amends how
   the recovery record is kept.)

   Restoration currently accepts bounded, resource-free text, line breaks,
   bold, italic, underline and semantic links. Preflight must leave the HTML
   unchanged under the compose sanitizer; native import and serialization must
   round-trip text, emphasis, link and paragraph attributes. Images, block
   containers, lists and blockquotes are refused, not flattened. Reply/forward
   drafts are also refused because their persisted model cannot prove the
   protected quote boundary. This restoration subset is deliberately narrower
   than the authored/sanitized subset above.

   Attributed storage is seeded before the first HTML publication. A no-edit
   Save/autosave retains the original HTML byte-for-byte; actual changes use
   the existing serializer. A formatted draft under an explicit plain-text
   preference is refused. A successfully restored session keeps its validated
   editor mode rather than flattening on a later preference change. HTML preview
   keeps the native editor mounted but read-only so returning cannot reimport
   stale content. Canonical threading, identity, scheduling, read-receipt,
   security and attachment metadata survive unchanged unless explicitly edited.

   Programmatic text changes such as selecting a signature replace only the
   differing Unicode-scalar-bounded range in native attributed storage, keeping
   the unchanged prefix/suffix attributes instead of resetting the entire body
   to plain text. Protected quote and inline-attachment attributes in an active
   authored composer remain intact; this does not enable their saved restoration.

   Save, Send, autosave and dismissal persistence are blocked while restoration
   is pending, failed or cancelled. Closing cancels pending work and leaves the
   original untouched; reopening starts a fresh validation attempt.

## Rationale

Rich compose is too visible a competitive gap to keep as a non-goal,
but the previous ADR's warning still applies: formatting controls must
not produce HTML that is lost, unsafe, or provider-specific. A narrow
sanitized subset gives users the core desktop affordance while keeping
privacy, security, and MIME behavior understandable.

Using the existing `Draft.htmlBody` surface avoids a backend protocol
change and preserves ADR-0028's outgoing abstraction. Keeping a
plain-text mode avoids forcing rich HTML on users who prefer minimal
mail.

## Consequences

- ADR-0038 is superseded. Its caution about sanitization, paste/import
  behavior, signatures/templates, and encryption remains relevant.
- Compose can autosave formatting-only changes because rich HTML is part
  of the compose fingerprint.
- Future #251 work should add link insertion UI, list controls, inline
  image insertion with generated `cid:` attachments, rich signatures,
  rich templates, paste sanitization tests, and iOS parity.
- The sanitizer rejects remote image URLs by default, so this change
  adds no new external network call and requires no ADR-0006 network
  table entry.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0038: Plain-text compose for v1
- The related feature request: Rich-text / HTML body editing
