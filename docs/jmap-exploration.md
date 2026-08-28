# JMAP Exploration — Research Notes

**Issue:** #15  
**Date:** 2026-05-29  
**Status:** Research complete, ADR draft pending

## What is JMAP?

JMAP (JSON Meta Application Protocol) is a modern alternative to IMAP
for mail access. It uses HTTP/JSON instead of the IMAP text protocol,
which simplifies client implementations and improves performance.

Key RFCs:
- **RFC 8620** — JMAP Core (transport, API, session model)
- **RFC 8621** — JMAP for Mail (mailbox, message, identity objects)

## Target Providers

| Provider | JMAP Support | Auth | Notes |
|----------|-------------|------|-------|
| **Fastmail** | Full | OAuth/OIDC | Primary JMAP host, original spec authors |
| **Stalwart** | Full | OAuth/OIDC or password | Self-hosted, Rust-based |
| **Cyrus** | Partial | Password only (no OAuth) | Self-hosted, limited JMAP |
| **Mailbox.org** | Partial | Password | German provider, JMAP experimental |

## Swift/JMAP Library Options

| Library | Maintainer | Last Update | Notes |
|---------|-----------|-------------|-------|
| **JMAPSwift** (nicklama) | Community | 2023 | Basic types, incomplete |
| **swift-jmap** (aspect-build) | Aspect | 2024 | More complete, active |
| **Hand-rolled** | N/A | N/A | Full control, high effort |

**Assessment:** No mature, well-maintained Swift JMAP library exists.
Hand-rolling JMAP for v2/v3 is feasible because:
1. JMAP is JSON-based — no binary protocol parsing needed
2. The object model maps cleanly to Brev's domain types
3. We can implement incrementally (session → mailboxes → messages)

## Authentication constraints

Brev supports OAuth where a provider offers a suitable public-client flow and
secure password or app-password authentication for standards accounts.

- **Fastmail:** OAuth 2.0 with PKCE or an app password.
- **Stalwart:** OAuth 2.0 or password authentication over TLS.
- **Cyrus:** Password authentication over TLS when enabled by the server.

## Comparison: JMAP vs IMAP

| Aspect | JMAP | IMAP |
|--------|------|------|
| Transport | HTTP/2 + JSON | TCP + text protocol |
| State sync | Delta/changes API | Full resync or IDLE |
| Push | EventSource (SSE) | IDLE or QRESYNC |
| Concurrency | Built-in (multiple requests) | Limited (pipelining) |
| Auth | OAuth 2.0 native | OAuth via SASL XOAUTH2 |
| Library maturity | Low (Swift) | Moderate (MailCore2) |
| Provider adoption | Growing | Universal |

## Model Fit Assessment

JMAP's object model aligns well with Brev's existing abstractions:

| JMAP Concept | Brev Equivalent |
|-------------|-----------------|
| `Account` | `BrevAccount` |
| `Mailbox` | `Folder` |
| `Email` | `Message` / `MessageHeader` |
| `Identity` | Sender identity |
| `EmailState` (unread, flagged) | Message flags |

The JMAP session resource (`GET /jmap/`) returns capabilities, which
maps directly to Brev's capability-flag model (ADR-0001, ADR-0028
invariant 2).

## Dependency Order

Per ADR-0028 and the issue description:

1. **#8 IMAP-with-OAuth backend** — proves the provider boundary
2. **#26 Multi-source workspace** — defines account/source model
3. **#27 Unified Inbox** — requires multi-source first
4. **#15 JMAP exploration** — this research (done)
5. **JMAP implementation** — only after IMAP v2 is stable

## Recommendation

**JMAP should be a first-class backend implementation** (not a
provider-specific optimization), but deferred to v2/v3 after IMAP
is proven. The research output (this document) satisfies the
exploration requirement. No implementation code should be written
until:

1. IMAP-with-OAuth (#8) is stable
2. Multi-source workspace (#26) and Unified Inbox (#27) are defined
3. An ADR proposes JMAP implementation with explicit scope

## Next Steps

- [ ] This document satisfies the "capture provider demand" criterion
- [ ] This document satisfies the "compare library options" criterion
- [ ] This document satisfies the "verify auth constraints" criterion
- [ ] Draft ADR comparing JMAP implementation options (when ready to implement)
- [ ] Confirm JMAP accounts can produce `BrevAccount` values (deferred)
- [ ] Confirm JMAP mailboxes fit source identity/sidebar model (deferred)
- [ ] Confirm JMAP Inbox folders participate in Unified Inbox (deferred)
