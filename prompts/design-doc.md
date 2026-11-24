# Writing or Updating a Brev Design Document

Use this prompt template only when introducing a brand-new subsystem document under `docs/design/` that is not already owned by an existing document. For cross-cutting changes to existing subsystems, update the relevant documents in place.

> Note: Routine feature additions, UI tweaks, and bug fixes do **not** require a new document. Prefer updating the existing subsystem document in `docs/design/` in place.

## Before writing

1. Read `AGENTS.md` and `docs/design/README.md`.
2. Check whether an existing document in `docs/design/` already owns this area:
   - `architecture.md` — package boundaries, `MailBackend`, capabilities, plugins
   - `privacy-and-security.md` — zero telemetry, network calls, Keychain, encryption, S/MIME, sign-in codes
   - `mail-sync-and-storage.md` — IMAP/SMTP sync, SQLite storage, offline queue, conversations, backups
   - `providers.md` — Gmail, IMAP/SMTP, OAuth, Microsoft Graph, JMAP, ManageSieve
   - `search-and-inbox.md` — People/Updates, Subscriptions, search chips, attachment indexing
   - `compose-and-drafts.md` — rich HTML compose, draft reopening, crash recovery, iOS share handoff
   - `ai-and-agents.md` — Apple Intelligence, local models, BYOK AI, Assistant, local MCP (`brev-mcp`)
   - `calendar-contacts-tasks.md` — CalDAV/CardDAV, Google PIM, iMIP invites, recurrence, offline PIM queue
   - `design-system-and-ui.md` — themes, avatars, materials, workspace layout, Dynamic Type, widgets, l10n
   - `platform-release-and-qa.md` — CI enforcement, Sparkle/TestFlight releases, background mail, iCloud sync, isolated QA

## Template (for a new subsystem document)

```markdown
# <Subsystem Name>

## Goals

What user or engineering outcome this subsystem exists to deliver.

## Hard Invariants

Constraints that must always hold (privacy, security, platform boundaries).

## Architecture & Key Decisions

Concrete data flows, module ownership, protocols, and trade-offs.

## Privacy & External Network Impact

Any new network call, local persistence, or Keychain item (if applicable,
also update `docs/design/privacy-and-security.md` and `PRIVACY.md`).

## Open Work & Future Direction

Planned slices or known gaps not yet built.
```

## Checklist

- Keep copy direct, factual, and current—describe how Brev works today and where it is going, not historical commit chatter.
- If adding a new external network call, update both `docs/design/privacy-and-security.md` (External Network Calls Ledger) and `PRIVACY.md`, then run `scripts/privacy-audit.sh`.
- Add the new file to `docs/design/README.md` if creating a new subsystem doc.
