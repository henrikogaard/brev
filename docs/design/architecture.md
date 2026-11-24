# Architecture & Module Boundaries

> Consolidates former ADRs `0001`, `0004`, `0011`, `0012`, `0028`, `0031`, and `0045`.

## Core Invariants

These architectural boundaries are permanent across macOS and iOS:

1. **`MailBackend` is the single domain boundary.** Every mail adapter (`IMAPSMTPBackend`, `GmailAPIBackend`, `MockBackend`, and future Graph/JMAP backends) conforms to `MailBackend` and translates provider DTOs into plain Swift domain models (`BrevAccount`, `Folder`, `MessageHeader`, `MessageBody`, `Draft`, `SearchQuery`, `MailEvent`).
2. **Capability-driven UI, never backend type-checks.** Views inspect `backend.capabilities`, `extendedCapabilities`, and `extensionService(_:)` rather than switching on concrete backend types (`if backend is GmailAPIBackend` is forbidden).
3. **Zero persistence types in views.** View targets and UI packages never import `RealmSwift`, SQLite drivers, or provider SDKs, and never see `Object`, `Results<>`, or `@ObservedResults`.
4. **Shared UI lives in packages, not app targets.** `apps/macOS/` and `apps/iOS/` are thin platform shells (windowing, AppKit/UIKit bridges, entitlements, lifecycle, embedded helpers/extensions). Reusable mail, settings, and design-system views live in SPM packages.
5. **Honest action surfaces.** Context menus, toolbar actions, and settings controls either work end-to-end via an explicit backend seam or stay hidden by capability.

## Build System & Repository Layout

Brev uses **Tuist** for Xcode project generation (`Workspace.swift`, `apps/*/Project.swift`) and **Swift Package Manager** for all modular code under `packages/`. Tool versions are pinned in `.mise.toml`.

| Path | Role |
| --- | --- |
| `apps/macOS/` | Native macOS AppKit/SwiftUI shell (`BrevMacOS`), `BrevMacWidgets`, and bundled `BrevMCPHelper` (`Contents/Helpers/brev-mcp`) |
| `apps/iOS/` | Native iOS/iPadOS SwiftUI shell (`BrevIOS`), `BrevMailWidgets`, `BrevShareExtension`, `BrevNotificationContent` |
| `packages/BrevBackend/` | Domain models, `MailBackend` protocol, extension services (`CachedMessageBodyProviding`, raw-source/copy seams, search progress), `IMAPSMTPBackend`, `LocalMailBackend`, `MockBackend` |
| `packages/BrevGmail/` | Native Gmail API adapter (`GmailAPIBackend`) and Google OAuth/account wiring |
| `packages/BrevSyncEngine/` | IMAP sync orchestration, SQLite storage, CONDSTORE/IDLE/polling, offline mutation queue |
| `packages/BrevMail/` | Composite mail UI (folder sidebar, message list, conversation reader, compose, search, triage, assistant, local MCP broker/socket) |
| `packages/BrevSettings/` | Shared typed settings persistence, backup codec, iCloud preference sync, macOS/iOS Settings UI |
| `packages/BrevDesign/` | Shared SwiftUI design primitives (cards, banners, toasts, buttons, spacing/radius/typography tokens) |
| `packages/BrevThemes/` | `BrevTheme`, `BrevColor`, semantic theme tokens, built-in and JSON theme loader |
| `packages/BrevAvatars/` | Cascading sender avatar resolution and privacy-gated lookup pipeline |
| `packages/BrevCalendar/` | Provider-neutral CalDAV/CardDAV/Google Calendar/Contacts/Tasks sync, authoring, ICS/vCard parsing |
| `packages/BrevAI/` | `AIBackend` protocol, Apple Intelligence backend, OpenAI-compatible/Ollama BYOK backends, AI Writer/Summary/Assistant plumbing |
| `packages/BrevCrypto/` | Local S/MIME verification/signing/encryption and at-rest store encryption helpers |
| `packages/BrevWidgets/` | Dependency-free App Group snapshot models and shared widget views |
| `packages/BrevPlugins/` | Build-time UI extension plugin API (toolbar, message actions, reader cards, sidebar slots) |
| `Plugins/BrevExamplePlugin/` | Reference build-time plugin exercising `BrevPlugins` |
| `themes/` | Built-in and user JSON theme definitions |

## Backend Extension Seams

Optional provider capabilities extend `MailBackend` through `backend.extensionService(_:)` rather than bloating the base protocol for one provider:

- **Cache-only reads (`CachedMessageBodyProviding`, `CachedListUnsubscribeProviding`):** Let Triage preloading, Subscriptions, and the local MCP server read cached bodies/headers without ever triggering network fetches.
- **Message copy & raw source (`MessageCopyProviding`, `RawMessageSourceProviding`):** Back context-menu actions (`Copy to Folder`, `View Source`, `Show Headers`, `Save As…`, full-folder export) cache-first and fail honestly when unsupported.
- **Progressive search (`MailProgressiveSearchProviding`):** Streams cached hits first, then server pages, without destabilizing the active reader.
- **Cross-folder conversations, drafts, scheduled send, sign-in trust:** Exposed via dedicated extension protocols queried through `extensionService(_:)`.

## Settings Surface (`BrevSettings`)

Settings lives in its own SPM package shared between macOS (`Settings` window + in-window sheet) and iOS (grouped push navigation), organized by user task: Accounts & Connections, Appearance, Mailboxes & Reading, Writing, Notifications, Rules & Organisation, Privacy & Security, Sync & Storage, and About & Updates. Section visibility is driven by platform capabilities so macOS-only panels (e.g. local MCP Agent access) stay hidden on iOS.

## UI Extension Plugin API (`BrevPlugins`)

Build-time plugins register typed extension points (message actions, reader cards, compose accessories, sidebar destinations) against domain models only. Plugins never receive credentials, raw provider clients, or persistence handles, and follow the same theme-token and zero-telemetry rules as first-party code.
