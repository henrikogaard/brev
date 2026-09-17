# ADR-0073: Durable local mail archives and portable backups

- **Status:** Proposed
- **Date:** 2026-09-05
- **Deciders:** Henrik
- **Tracking:** #28

## Context

Provider caches can be evicted or rebuilt and are not a durable local archive.
Brev currently imports MBOX/Maildir into provider folders and exports folders,
but lacks a full migration and backup/restore workflow.

## Decision

1. Add a local-only archive adapter behind `MailBackend`. Its mailbox sources
   participate in profiles, stacked folders, conversations, search and attachment
   viewing, with capabilities that exclude send and provider network operations.
2. Keep archives in an explicit persistent store separate from evictable cache.
   No retention sweep or cache repair may delete archive content.
3. Import MBOX/Maildir with a preview, explicit destination, progress/cancel,
   durable checkpoints and duplicate policy. Preserve raw MIME, attachments,
   message identifiers, dates, flags, and folder hierarchy where represented.
4. Cross-source move to an archive first confirms a durable imported copy before
   removing the source. Failure/cancellation leaves the original intact and
   reports partial completion. Export/copy is always available separately.
5. Define a versioned portable backup containing a manifest, checksums, message
   files, folder hierarchy, archive state, and selected non-secret preferences.
   Tokens, passwords, Keychain items and account authorization are excluded.
6. Restore validates schema, paths, checksums and resource bounds before writing;
   shows a preview and explicit merge/replace choices; and rolls back or resumes
   partial writes. Restoring never authenticates or sends messages automatically.
7. Offer password-encrypted export using established platform cryptography and
   a versioned authenticated format; do not invent a cipher. Plain exports must
   visibly state that they contain readable mail. A secret-free backup can still
   contain private message content and must be treated accordingly.
8. Scheduled backups are optional, locally configured, and default off. Choosing
   a cloud-synced destination remains an explicit user filesystem choice, not an
   automatic upload or new Brev-hosted storage service.

## Alternatives

Treating the cache as an archive is unsafe because cache repair/retention can
remove it. Per-folder MBOX export is useful interchange but does not preserve
all workspace state or provide an atomic restore workflow. A cloud archive
would add a separate infrastructure, access and privacy contract.

## Consequences

A local backend and archive store require folder/message identity, MIME fidelity,
transaction, crash-recovery and search tests. Import/export/restore needs a
rendered wizard and fixtures with duplicates, malformed paths, corrupt archives,
large attachments and interrupted operations. Backup is separate from account
reconnection and release. The implementation must update local-data lifecycle
privacy documentation without introducing automatic external traffic.

## References

- [ADR-0001](0001-backend-abstraction.md)
- [ADR-0028](0028-mail-provider-architecture.md)
- `ImportExportSection`, `MailImporting`, `MailBackend`, offline retention policies
- eM Client local folders and backup behavior used as a workflow benchmark
