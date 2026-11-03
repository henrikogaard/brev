# ADR-0093: Reopening reply, forward and server-sourced Drafts

- **Status:** Proposed
- **Date:** 2026-11-03
- **Deciders:** Henrik
- **Amends:** ADR-0038 decision 6 (saved-body restoration)

## Context

ADR-0038 decision 6 stopped reopened Drafts from being flattened by refusing
anything restoration cannot prove safe. That guard prevents data loss, but it
runs for every existing Draft, including plain text, and it refuses Drafts that
`main` can open today:

- **Saved replies and forwards.** `ComposeDraftBodyRestoration.prepare` rejects
  any Draft with `inReplyToMessageID` or `forwardedMessageID`. Removing that
  check alone is not enough: Brev's own reply bodies contain `<blockquote>` in
  both plain and rich mode, and that tag is refused too. The refusal exists
  because `Draft` does not persist the protected quote boundary.
- **Drafts with no local canonical copy.** `openDraft` falls back to the server
  body, then `resolveExisting` gets nil from the canonical lookup and refuses.
  This covers Drafts written in webmail or on another device.
- **Gmail Drafts generally.** `GmailAPIBackend` implements neither `draft(for:)`
  nor `LocalDraftAttachmentProviding`, so the protocol default returns nil even
  for Drafts Brev saved. Its staging store already has the required lookups.
- **`<p>` and `<div>`.** These are refused, and webmail Drafts commonly use them.

These findings come from reading the code and one characterization test. The
Gmail and no-local-copy refusals have not been run end to end. Issue #282 tracks
this work, and these cases block merging the #271–#277 stack.

## Decision

1. **Persist the quote boundary as optional local metadata.** `Draft` gains an
   optional `quoteBoundary` holding the existing `ComposeQuoteProtection` values:
   the marker text and the top or bottom edge. Decoding stays backward compatible.
   The field is not sent, uploaded or added to the content fingerprint.
2. **Restore quote protection only from that proof.** If the field is present and
   its marker is found in the restored text, the quote is locked again. If the
   field is absent, the Draft opens with the quote unlocked, as on `main`. Brev
   never infers a boundary from the HTML.
3. **Accept Brev's own flat blockquotes.** Restoration accepts attribute-free,
   unnested `<blockquote>` elements containing only text and `<br>`, converting
   them to `> ` lines through the existing quote-marker path before native import.
   Nested or attributed quotes stay refused.
4. **Let Gmail answer local lookups.** `GmailAPIBackend` implements `draft(for:)`,
   its source-scoped variant and `LocalDraftAttachmentProviding` from its staging
   store, under the same ownership checks as IMAP.
5. **Allow server bodies only for an explicit open.** When the user opens a Draft
   from the Drafts folder and no canonical copy exists, the composer receives a
   value marking it as server-sourced, and `resolveExisting` skips only the
   canonical comparison. All body validation still runs. Drafts with attachments
   stay refused. Crash recovery never uses this path and still requires canonical
   local proof.
6. **Accept `<p>` and `<div>` as line structure only.** They are accepted only if
   the visible text survives the import and serialization round trip unchanged.
   The only attribute tolerated on them is `dir`, which Gmail's web composer adds;
   any other attribute is refused, so some webmail Drafts stay refused. Lists,
   images and other block markup stay refused.
7. **Keep the existing guarantees.** An unedited Save or autosave keeps the original
   HTML byte for byte. Pending, failed or cancelled restoration still blocks Save,
   Send and autosave. Nothing is silently flattened.

Unsaved-recovery coverage and list support remain open in #282.

## Rationale

- **Optional field versus no protection on reopen.** Reopening every reply unlocked
  is smaller, but a saved reply would lose the protection it had before saving, and
  quoted text could change unnoticed. The field is small, local and backward
  compatible.
- **Inferring the boundary from HTML.** Rejected because webmail and user-typed
  quotes would make a guess look like proof, which is what ADR-0038 ruled out.
- **Keeping server-sourced Drafts refused.** Rejected because it strands those
  Drafts in Brev, and Gmail would depend on a local copy from the same device.
- **Allowing server bodies in recovery.** Rejected because recovery runs without an
  explicit user choice, and a stale server body could look like the lost work.
- **Flattening `<p>` and `<div>` without a check.** Rejected because it would bring
  back silent loss. The round-trip check keeps the failure closed.

## Consequences

### Accepted

- `Draft` in `BrevBackend` gains one optional persisted field.
- An edited Draft with `<p>` or `<div>` is saved with `<br>`, so its structure
  changes but its text does not.
- A reply reopened on another device, or one saved before this change, has an
  editable quote.
- No new network call or data category. The server body fetch already exists in
  `openDraft`, and the marker is stored with the Draft that already contains it.

### Risks

- **Server-sourced Drafts skip the canonical comparison,** so the body checks carry
  the safety burden. Mitigation: refusal tests for resources, nested quotes, lists
  and attachments.
- **Last write wins.** Saving a server-sourced Draft can replace a newer copy edited
  elsewhere, as `main` already can. This ADR does not add conflict detection.
- **The blockquote round trip is unproven.** The native editor must return the same
  text and regenerate quotes correctly. If it cannot, implementation stops and
  this decision is revisited rather than weakening the check.

## Acceptance

Failing tests come first and cover, on macOS and iOS where the editor is hosted:

- Plain and rich replies and forwards reopen, keep their threading, relock the quote
  when the field is present, and keep original HTML on an unedited Save.
- Older replies without the field open unlocked without changing the Draft.
- Gmail Drafts saved in Brev reopen with their owned attachments.
- Server-sourced Drafts open only through the explicit path, never through recovery.
- Attachments, resources, nested quotes and lists stay refused with English and
  Norwegian messages.

Native acceptance stays with #279 and #281, and live-provider checks with #284.

## References

- ADR-0006: privacy and network calls (no new entry required)
- ADR-0038: rich HTML compose, decision 6
- Issues #278, #279, #281, #282 and #284; PR #277
