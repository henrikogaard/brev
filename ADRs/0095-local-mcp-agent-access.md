# ADR-0095: Local MCP server for read-only and user-approved agent mail access

- **Status:** Proposed
- **Date:** 2026-11-22
- **Deciders:** Henrik
- **Relates to:** [ADR-0006](0006-telemetry-and-privacy.md) (telemetry and privacy), [ADR-0026](0026-ai-mailbox-action-agent.md) (supervised mailbox action agent), [ADR-0028](0028-mail-provider-architecture.md) (mail provider architecture), [ADR-0058](0058-string-catalog-localization.md) (string catalogs), [ADR-0075](0075-macos-background-mail-presence.md) (macOS background mail presence), [ADR-0076](0076-settings-backup-and-export.md) (settings backup), [ADR-0088](0088-sign-in-code-and-link-panel.md) (sign-in code privacy boundary)
- **Issue:** #305

## Context

Users increasingly run local coding and personal AI agents (Claude Desktop, Claude Code, Codex, Cursor, and other Model Context Protocol clients) on their Mac and want those agents to search and read mail already cached in Brev without handing mail-account credentials, OAuth tokens, or IMAP passwords to external tools.

Exposing mail to local agents carries sharp security and privacy risks:

- **Untrusted email content (prompt injection):** Any email body an agent reads can contain adversarial instructions attempting to exfiltrate other messages, delete mail, or send spoofed replies.
- **No listening network ports (ADR-0006):** Binding a `localhost` HTTP/SSE server exposes Brev to browser-based DNS rebinding, CSRF probes, and local multi-user port access.
- **Supervised mutations (ADR-0026):** Agents must never mutate mailbox state silently or irreversibly.
- **Device-local explicit opt-in:** Agent access must stay off by default and scoped to explicitly enabled accounts, never silently enabled by backup restore or iCloud preference sync (ADR-0076).

## Decision

Introduce a macOS-only, local-only Model Context Protocol (MCP) surface built on four boundaries:

### 1. Transport — stdio and user-private Unix domain socket only (zero network ports)

- Brev never binds TCP, UDP, `127.0.0.1`, or `0.0.0.0`.
- When enabled, the running Brev app listens on a single user-private Unix domain socket inside its local Application Support / App Group directory with `0600` file permissions and verifies peer credentials (`LOCAL_PEERCRED` / `LOCAL_PEERPID`) so only processes owned by the same macOS UID can connect.
- A tiny bundled stdio bridge helper (`brev-mcp`, speaking MCP JSON-RPC 2.0 over stdin/stdout) forwards requests to the local socket so standard MCP clients (Claude, Codex, Cursor) configure it as a normal `stdio` command without any network port or API token.
- If Brev is not running or Agent access is turned off, the bridge fails closed with a clear structured MCP error and never opens Realm/SQLite stores directly.

### 2. Off by default, per-account consent, and visible tool inventory

- Add a macOS-only **Settings → Agent access** section:
  - Master toggle **off by default**.
  - Per-account opt-in toggles (all **off by default**). Accounts not opted in are completely invisible to MCP clients (returning empty/not-found without confirming account existence).
  - Read-only list of every exposed tool, its permission level (`Read` or `Approval required in Brev`), and a copyable stdio client configuration snippet.
- Agent access settings are **device-local only**: excluded from settings backups (ADR-0076) and the iCloud preference sync allowlist (ADR-0056).

### 3. Strictly bounded tool surface & per-call in-app approvals

#### Read tools (allowed only on opted-in accounts, cache-only)

- `list_accounts`: returns opaque Brev account IDs and display labels for opted-in accounts only. Never exposes credentials, tokens, server hosts, or non-opted-in accounts.
- `list_folders`: returns folder IDs, names, roles, and unread counts for an opted-in account from local state.
- `search_messages`: runs cache-only local search (`SearchQuery.execution = .cacheOnly`) scoped to opted-in accounts, bounded to a hard page cap (e.g. max 50 headers per call). Never triggers unrequested IMAP/Gmail network fetches.
- `read_message`: returns sanitized plain-text body, basic headers (`from`, `to`, `cc`, `date`, `subject`), and attachment filenames/sizes for one locally cached message on an opted-in account. Does not return raw HTML scripts, raw authentication headers, or binary attachment bytes in v1.
- **ADR-0088 privacy guard:** Messages matching `SignInCodeDetector` on accounts that have not explicitly enabled agent reading of security codes are redacted or omitted from automated search snippets to reduce accidental OTP exposure. (Exact opt-in nuance to confirm during implementation.)

#### Change tools (every call requires an explicit in-app approval prompt per ADR-0026)

- `archive_messages(account_id, message_ids)`: bounded batch cap (e.g. max 25 messages per request). Brings up an in-app approval prompt in Brev showing the requesting client process name, account, exact message count, and sender/subject preview. Fails closed (denied) on Cancel, timeout (60 seconds), or if Brev cannot display UI. Approved mutations execute through the standard `MailBackend` mutation queue with Undo support.
- `label_messages(account_id, message_ids, folder_id)` (or move to an existing non-Trash/non-Spam folder): same bounded batch cap and mandatory per-call in-app approval prompt.
- **No "Approve all" or session-wide auto-approval:** Every change tool invocation requires its own explicit user click so a prompt injection cannot piggyback on an earlier approval.

#### Permanently excluded tools (never exposed over MCP)

- **No `send_message`, `reply`, `forward`, or `send_draft`.**
- **No `delete_message`, `move_to_trash`, or `empty_trash`.**
- **No account, credential, rule, or settings mutations.**
- **No live network fetch / arbitrary URL fetch.**

### 4. Local audit log visible in Settings

- Every MCP request — allowed, approved, denied, or blocked — records one structured audit entry locally:
  - timestamp (UTC)
  - client identifier (process name + PID, and MCP `clientInfo.name` when provided)
  - tool name
  - opted-in account ID (or `none` when blocked before account resolution)
  - bounded parameter summary (e.g. query length or message count / IDs — **never** message bodies, snippets, or sign-in codes)
  - outcome (`allowed`, `approved`, `denied`, `timed_out`, `blocked_disabled`, `blocked_account`)
- Stored in a bounded local ring buffer (e.g. last 1,000 entries in Application Support, excluded from backups, iCloud sync, and diagnostic exports).
- Displayed directly in **Settings → Agent access** with filtering and a one-click **Clear log** button.

## Rationale

- **Stdio + user-private Unix socket instead of `localhost` HTTP/SSE:** Zero listening TCP ports eliminates browser DNS-rebinding attacks, local port scanners, and firewall prompts, and satisfies Brev's zero-network-by-default posture (ADR-0006).
- **In-process broker via socket instead of direct SQLite/Realm file reads by a CLI:** Routing through the running Brev process enforces per-account opt-in, ADR-0028 domain boundaries, per-call in-app approval UI, Undo/mutation-queue semantics, and a single authoritative audit log.
- **Per-call in-app approval instead of pre-authorized write scopes:** Email is adversarial untrusted input. Requiring a human click in Brev showing the exact affected messages before any archive/label mutation matches ADR-0026's supervised-action guarantee.
- **Excluding send and delete completely:** Even with approval prompts, accidental approval of a malicious send or permanent delete has irreversible external impact. Users who want AI help drafting replies already have AI Writer's explicit draft review flow (ADR-0008).

## Consequences

### Accepted

- macOS-only feature initially (iOS sandboxing does not support cross-app stdio/Unix-socket MCP servers).
- Adds a small stdio bridge helper executable (`brev-mcp`) to the macOS app bundle (requiring code signing / notarization validation in `Project.swift` and release scripts when implemented).
- Touches ADR-0006 (documents local IPC surface with zero network ports) and extends ADR-0026 (reuses supervised approval principles for external local agents).
- First implementation milestone targets the mock mailbox with unit/integration tests covering read tools, per-account isolation, approval/denial/timeout flows, and audit-log persistence before enabling against live IMAP/Gmail accounts.

### Risks

- **App Sandbox socket path restrictions (Mac App Store vs Developer ID builds):** A sandboxed macOS app can only expose Unix sockets inside its App Group container, and external unsandboxed CLIs (`claude`, `codex`, `cursor`) need read/write access to that socket path. Mitigation: verify socket path and sandbox entitlements in the first spike; document any App Store vs direct-download distribution difference explicitly before shipping.
- **Prompt injection exfiltration via read tools:** Once an agent reads an email, the agent itself may send that text to its own cloud LLM provider. Mitigation: make the Settings → Agent access copy state plainly that connected external agents may send read mail to whichever AI provider those agents use, keep access off by default per account, and make every read visible in the audit log.
- **Approval fatigue / rapid request flooding:** A buggy or compromised agent could spam approval prompts. Mitigation: allow only one active approval prompt at a time, immediately reject concurrent write requests with a rate-limit error, and log every blocked attempt.
- **Audit log growth or sensitive-data leakage:** Storing raw query text or message snippets in the audit log could persist sensitive terms. Mitigation: cap the ring buffer at 1,000 entries, never log message bodies or credentials, and provide one-click clearing.

## References

- [ADR-0006: Telemetry and privacy](0006-telemetry-and-privacy.md)
- [ADR-0026: AI mailbox action agent](0026-ai-mailbox-action-agent.md)
- [ADR-0028: Mail provider architecture](0028-mail-provider-architecture.md)
- [ADR-0075: macOS background mail presence](0075-macos-background-mail-presence.md)
- [ADR-0076: Settings backup and export](0076-settings-backup-and-export.md)
- [ADR-0088: Show sign-in codes and links on screen](0088-sign-in-code-and-link-panel.md)
- Model Context Protocol specification: https://modelcontextprotocol.io/specification
- Issue #305
- Affected paths (upon acceptance): `packages/BrevMail/`, `packages/BrevSettings/`, `apps/macOS/`, `Project.swift`, `PRIVACY.md`, `ADRs/0006-telemetry-and-privacy.md`
