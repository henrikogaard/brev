# Brev Design Documents

Brev uses **living design documents** instead of append-only ADRs. Each subsystem has one canonical document here that describes how it works today, which invariants must hold, and where future work is headed. Update the relevant document in place when a design changes.

> Historical ADRs (`ADRs/0001`–`0095`) were consolidated into this set in November 2026 and remain preserved in git history.

## Index

| Document | Scope |
| --- | --- |
| [architecture.md](architecture.md) | Package graph, `MailBackend` domain boundary, capability-driven UI, Realm isolation, extension and plugin seams |
| [privacy-and-security.md](privacy-and-security.md) | Zero telemetry, external network-calls ledger, at-rest encryption, Keychain rules, S/MIME, sign-in code trust, demo isolation |
| [mail-sync-and-storage.md](mail-sync-and-storage.md) | IMAP/SMTP sync engine, SQLite header/page store, offline mutation queue, cache-first restore, threading, durable local folders, backup/restore, legacy quarantine |
| [providers.md](providers.md) | Gmail API, Google native OAuth, IMAP/SMTP + OAuth, plus future specs for Microsoft Graph, JMAP, and ManageSieve |
| [search-and-inbox.md](search-and-inbox.md) | Conversation view, People/Updates classification & sender bundling, plain-language/chip/folder/PDF search, background & attachment indexing |
| [compose-and-drafts.md](compose-and-drafts.md) | Rich HTML compose, lossless draft reopening & quote preservation, crash recovery, iOS share extension handoff |
| [ai-and-agents.md](ai-and-agents.md) | On-device AI (Apple Intelligence & local models), BYOK/cloud AI providers, Writer/Summaries/Assistant, supervised actions, local MCP server (`brev-mcp`) |
| [calendar-contacts-tasks.md](calendar-contacts-tasks.md) | Provider-neutral CalDAV/CardDAV and Google Calendar/Contacts/Tasks browsing & authoring, iMIP invites, bounded recurrence, offline PIM write queue |
| [design-system-and-ui.md](design-system-and-ui.md) | Theme token architecture, sender avatars, window materials, multi-source workspace, flags & folder actions, Dynamic Type, iPad multi-window, widgets, localization |
| [platform-release-and-qa.md](platform-release-and-qa.md) | Mechanical lint & privacy enforcement, Stable/Nightly Sparkle release rings, TestFlight, macOS background presence, iCloud preference sync, isolated mock QA |

## Updating a Design Document

- **Routine changes & UI polish:** No design-doc update required. Code, tests, and snapshots are the source of truth for component defaults, density, colors, and formatting.
- **Architectural, privacy, or protocol changes:** Update the relevant document in `docs/design/` in the same PR.
- **New external network calls:** Always update both [privacy-and-security.md](privacy-and-security.md) and [PRIVACY.md](../../PRIVACY.md) and run `scripts/privacy-audit.sh`.
- **New subsystem document:** Use [prompts/design-doc.md](../../prompts/design-doc.md) only when introducing a brand-new subsystem not owned by the 10 documents above; for cross-cutting changes to existing subsystems, update the relevant documents in place.
