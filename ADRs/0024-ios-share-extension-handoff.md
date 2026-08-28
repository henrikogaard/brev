# ADR-0024: iOS share extension attachment handoff

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Henrik

## Context

The iOS share extension originally handed plain text and URLs to the main
app through a `brev://compose?shared=...` URL. The related feature request requires
files, images, PDFs, and mixed payloads to survive cold-launch handoff
into compose without sending attachment bytes over the network.

Share extensions receive files in their own extension sandbox. A plain
temporary URL from the extension is not a reliable contract for the main
app, especially if Brev is cold-launched after the extension completes.

## Decision

The iOS app target and `BrevShareExtension` target share the app group
`group.eu.brevmail.brev`.

The share extension copies supported file representations into
`ShareHandoff/<UUID>/` inside the app-group container, then encodes those
local file URLs into the existing `brev://compose` shared payload as
`attachment` query items. The main app decodes the payload into
`ComposePrefill.attachmentFileURLs` and imports those files through the
existing compose attachment import path.

The app group is local-only storage. Attachment bytes are read into
pending compose attachment rows, but they are not uploaded to the mail
provider until the user explicitly saves or sends the draft.

## Consequences

- Cold-launch share handoff can preserve attachments because both targets
  can read the copied files.
- The target structure now requires iOS entitlements, so this ADR
  accompanies the protected `apps/iOS/Project.swift` change per ADR-0005.
- Handoff staging is bounded to 20 files / 25 MiB per share (10 MiB per
  attachment). Stale directories older than 24 hours are pruned before a new
  handoff, and the imported directory is removed after compose copies its
  attachments into local draft state; failed or partial imports retain the
  handoff directory so the user can retry.

## References

- ADR-0005: Enforcement and protected paths
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap and architectural invariants
