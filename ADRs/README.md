# Architecture Decision Records

This directory contains the current architectural decisions for Brev's public
source baseline. ADRs are append-only from this baseline onward: superseding a
decision means adding a new ADR that references the old one.

The format is based on Michael Nygard's ADR template and adapted for Brev's
repository checks.

## Index

| # | Title | Status |
| ---: | --- | --- |
| 1 | MailBackend domain boundary | Accepted |
| 2 | Theme system architecture | Accepted |
| 3 | Sender avatar resolution | Accepted |
| 4 | Build system and project layout | Accepted |
| 5 | Enforcement and automation | Accepted |
| 6 | Telemetry, privacy, and GDPR compliance | Accepted |
| 7 | Calendar invitation handling | Accepted |
| 8 | AI Writer architecture | Accepted |
| 9 | Distribution and code signing | Accepted |
| 10 | MailResources compatibility shim | Accepted |
| 11 | BrevMail package — composite mail UI lives outside apps | Accepted |
| 12 | Settings surface — `BrevSettings` package, v1 sections | Accepted |
| 13 | Design-system status surfaces | Accepted |
| 14 | Design-system surface primitives | Proposed |
| 15 | Window materials and translucency preferences | Proposed |
| 16 | Expand the built-in IDE theme pack | Accepted |
| 17 | Multi-source mail workspace | Proposed |
| 18 | Folder mutation capabilities and sidebar context actions | Proposed |
| 19 | Message flag colors and provider-agnostic tagging | Proposed |
| 20 | Thread Conversation View | Accepted |
| 21 | S/MIME rendering and outbound security | Accepted |
| 22 | Offline mutation queue and local cache evolution | Accepted |
| 23 | Mailbox arrival timestamp preference | Accepted |
| 24 | iOS share extension attachment handoff | Accepted |
| 25 | Dense mail chrome Dynamic Type bounds | Proposed |
| 26 | Supervised mailbox action agent | Proposed |
| 27 | Manual thread summary AI | Proposed |
| 28 | Mail provider architecture and invariants | Accepted |
| 29 | IMAP/SMTP backend foundation | Accepted |
| 30 | Full IMAP sync and cache engine | Proposed |
| 31 | UI Extension Plugin API | Accepted |
| 32 | Server-side filters with ManageSieve | Proposed |
| 33 | iPad multi-window / auxiliary presentation | Accepted |
| 34 | Offline retention enforcement, sync-progress events, search correctness, and new-mail notifications | Accepted |
| 35 | Local inbox classification and category tabs | Accepted |
| 36 | iOS S/MIME outbound limitation | Accepted |
| 37 | Generic IMAP closed-app notification posture | Accepted |
| 38 | Rich HTML compose MVP | Accepted |
| 39 | Read-only calendar and contacts scope | Accepted |
| 40 | Native Exchange and Microsoft 365 scope | Accepted |
| 41 | Search folders and attachment search scope | Accepted |
| 42 | Enterprise and admin policy scope | Accepted |
| 43 | Provider-backed workflow state | Accepted |
| 44 | Read-only cached-attachment enumeration seam | Accepted |
| 45 | Message copy and raw-source backend seams for context-menu actions | Accepted |
| 46 | Capability-driven AI routing and generic DAV discovery | Proposed |
| 47 | Mailbox chat Q&A AI for sender-scoped cached mail | Proposed |
| 48 | Configurable application accent color | Accepted |
| 49 | Message-content opacity override | Accepted |
| 50 | Cache-first IMAP session restore | Accepted |
| 51 | User-controlled AI providers | Accepted |
| 52 | Client-side IMAP threading | Accepted |
| 53 | Separator hairlines are a text-colour wash, not the `separator` token | Accepted |
| 54 | Mailbox arrival timestamp format and default | Proposed |
| 55 | The demo mailbox never accesses system Contacts | Accepted |
| 56 | Opt-in iCloud key-value sync for local preferences (phase 1) | Accepted |
| 57 | Gmail labels over IMAP (X-GM-EXT-1) | Proposed |
| 58 | Localization via String Catalogs | Accepted |
| 59 | Malformed domain-derived DAV endpoint handling | Proposed |
| 60 | Explicit user-triggered attachment search fetching | Accepted |
| 61 | Bounded caches for render and backend hot paths | Proposed |
| 62 | Localization and extension lint coverage | Proposed |
| 63 | Platform-specific Google native OAuth clients | Accepted |
| 64 | First-class Gmail API backend | Accepted |
| 65 | Google Desktop OAuth loopback callback | Accepted |
| 66 | Current provider scope | Accepted |
| 67 | Google Desktop client credential and native SSO | Accepted |
| 68 | Default blue accent and system appearance bootstrap | Accepted |
| 69 | Monochrome default theme pair | Accepted |
| 70 | Opt-in background mail on macOS | Proposed |
| 71 | Native Microsoft Graph mail and shared mailboxes | Proposed |
| 72 | Provider-neutral calendar and contact authoring | Proposed |
| 73 | Durable local mail archives and portable backups | Proposed |

## Conventions

- Filenames use `NNNN-kebab-case-title.md`.
- Each ADR records status, date, deciders, context, decision, rationale,
  consequences, and references.
- Status is one of `Proposed`, `Accepted`, `Superseded`, or `Deprecated`.
- ADR numbers never change after publication.

## When an ADR is required

An ADR is required before a change that:

- adds, removes, or replaces a top-level package under `packages/`;
- changes a public type or method in `BrevDesign`, `BrevThemes`,
  `BrevAvatars`, `BrevCalendar`, or `BrevAI`;
- adds a new `MailBackend` or `AIBackend` implementation;
- changes the license, name, or distribution model;
- introduces a new external service dependency or network call;
- modifies enforcement rules in `.swiftlint.yml`, `.swiftformat`, or
  `.mise.toml`;
- touches `LICENSE`, `NOTICE`, or `THIRD_PARTY_LICENSES.md`.

The `adr-required.yml` CI check enforces these paths under ADR-0005.

## Drafting a new ADR

Use `prompts/new-adr.md`. The next ADR number follows the highest number in this
index.
