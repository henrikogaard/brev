# AI Features & Local Agent Access

> Consolidates former ADRs `0008`, `0026`, `0027`, `0047`, `0051`, `0094`, and `0095`.

## Core Principles

1. **User-controlled providers, never a Brev AI proxy.** Brev never operates a hosted AI proxy, never sells AI credits, and never switches providers behind the user's back.
2. **Clear processing transparency.** Every AI surface displays where text is processed: `"On this Mac"` / `"On this device"` for local models, `"Sent to: localhost (Ollama)"` for local servers, or `"Sent to: <host>"` for configured cloud/BYOK providers.
3. **Provider-neutral UI.** Views call `AIBackend` and inspect capabilities—never type-checking concrete backends.
4. **Prompt-injection boundary.** Incoming email content is untrusted input. Neither built-in AI nor external MCP agents may send mail, delete mail, or silently mutate mailbox state without explicit user confirmation.

## Two-Tier AI Policy (Relaxed from Former ADRs `0008`/`0026`/`0027`/`0047`)

Splitting **on-device** from **cloud/BYOK** lets Brev match modern native mail clients without compromising privacy:

| Tier | Examples | Network | Invocation Policy |
| --- | --- | --- | --- |
| **On-device AI** | Apple Intelligence (`FoundationModels`, macOS 26+ / iOS 26+), user-downloaded local models (Slice 2), local Ollama/LM Studio | Zero network (or localhost only) | Off until user enables AI; once enabled, **may optionally run proactively** for thread preview summaries, priority/needs-reply badges, and inbox triage because no mail leaves the device |
| **Cloud / BYOK AI** | User-configured OpenAI-compatible or provider-hosted endpoints (Keychain-backed API keys) | Sends selected text to user's chosen endpoint | **Always explicit user-invoked** (button click / prompt send) with visible destination badge |

## Built-In AI Surfaces

- **AI Writer (Compose & Inline Reply):** Rewriting shortcuts (shorten, expand, tone shifts), subject suggestions, quick reply starters, and `"Describe your reply"` drafting with a composer-local preview card (`Replace Draft` / `Insert` / `Copy` / `Retry` / `Cancel`) before mutating the draft.
- **Thread Summaries:** Concise grounded summaries in the thread header (`Summarize`), using on-device or configured cloud backends.
- **Proactive On-Device Summaries & Priority Triage (Opt-In):** Controlled by `AIWriterSettings.proactiveOnDeviceTriageEnabled` (`ai.proactiveOnDeviceTriageEnabled`, **off by default**, device-local only, excluded from backups and iCloud sync) in Settings → Writing → AI Writer. Strictly gated on `AIBackend.isOnDeviceZeroNetwork == true` so cloud, BYOK, provider-hosted, and localhost HTTP endpoints are never invoked automatically (failing closed to explicit clicks). `ProactiveOnDeviceTriageEngine` operates strictly on already-cached local headers/bodies (zero network fetches), excludes Trash and Spam, redacts sign-in codes and verification links before prompting, bounds concurrency (max 1–2 local inferences), caches structured `ThreadTriageInsight`s (one-sentence summary, `.normal` / `.needsReply` / `.urgent` priority, `"On this Mac"` / `"On this iPhone"` / `"On this iPad"` attribution) in a bounded in-memory LRU cache invalidated when a thread's message fingerprint changes, and clears the cache immediately when AI or proactive triage is disabled. Cached insights surface subtly in message list rows (`Urgent` / `Needs reply` pills and one-line local preview summaries) and in the thread conversation header while preserving the manual `Summarize` action.
- **Assistant Sidebar Destination:** Full-pane mailbox Q&A above Inbox that searches local cached mail across accounts and renders grounded conversation cards (**Needs you**, **Worth a look**, **Updates & newsletters**) linking directly to real messages, with confirmed action chips.
- **Supervised Mailbox Actions:** Natural-language filing/triage requests are parsed into an explicit local plan showing exact matched counts and target folders; execution runs through Brev's normal undoable mutation queue only after user confirmation.

## On-Device Local Models

- **Slice 1 (shipped):** `AppleIntelligenceAIBackend` via `FoundationModels` (`SystemLanguageModel.default`), zero bundled weights, zero network, `"On this Mac"` badges, per-account and default provider selection in Settings → Writing → AI.
- **Slice 2 (shipped foundation, #304):** `"On this Mac (download a model)"` (`AIProviderKind.onDeviceDownloadedModel`) for Macs without Apple Intelligence or users preferring open-weights models. Ships `LocalModelCatalog` (curated open-weights metadata pinned to immutable Hugging Face commit revisions with verified LFS byte counts and SHA-256 digests, SPDX licenses, parameter size, quantization, and RAM requirement), `LocalModelDownloadManager` (user-initiated HTTPS streaming downloads with non-HTTPS redirect blocking, live progress, cancellation, streaming `CryptoKit.SHA256` verification that deletes temp files on mismatch or cancel, advisory `flock`-guarded startup cleanup of abandoned `.part` staging files, and backup-excluded storage under `Application Support/Brev/LocalModels/<model-id>/`), `LocalDownloadedModelAIBackend` + pluggable `LocalModelInferenceRuntime` (strictly offline inference passing prompts via private `0600` temp files never exposed in CLI arguments, concurrent stdout/stderr pipe draining, Swift `Task` cancellation propagation, `"On this Mac"` attribution, `.onDevice` context budgets, and macOS platform gating until an iOS runtime ships), and the Local Models management UI in Settings → Writing → AI Writer. Documented in [privacy-and-security.md](privacy-and-security.md) and [PRIVACY.md](../../PRIVACY.md).

## Local MCP Server for External Agents (`brev-mcp`)

macOS-only, device-local Model Context Protocol (MCP) bridge letting local tools (Claude Desktop, Claude Code, Codex CLI, Cursor) work with Brev without exposing mail credentials or listening on any network port:

- **Transport:** User-private `0600` `AF_UNIX` socket scoped by app bundle identity (`mcp.sock` for Stable, `mcp-nightly.sock` for Nightly, hashed tag for Test builds) with `getpeereid` same-UID peer verification on **both** `LocalMCPUnixSocketServer` and the bundled `Contents/Helpers/brev-mcp` stdio bridge. Zero TCP/UDP ports.
- **Consent & visibility:** Master toggle and per-account grants default to off, are device-local only, and are excluded from `.brevbackup` and iCloud sync. Non-opted-in accounts are invisible.
- **Tools:**
  - *Read (cache-only, Trash/Spam excluded, sign-in codes redacted):* `list_accounts`, `list_folders`, `search_messages` (max 50/call), `read_message` (plain text + attachment names).
  - *Change (per-call in-app approval sheet, 60 s fail-closed timeout, single active prompt):* `archive_messages` and `label_messages` (max 25 messages, Trash/Spam blocked), plus `create_draft` (plain-text body up to 64 KiB, validated recipients, optional in-scope `in_reply_to_message_id`, draft preview in the approval sheet, saves a Draft for manual review in Brev and never sends).
  - *Permanently excluded:* `send_message`, `delete_message`, `move_to_trash`, `empty_trash`, credential access, and settings mutations.
- **Audit log:** Bounded 1,000-entry backup-excluded local ring buffer (`agent-access-audit.json`) viewable and clearable in Settings → Privacy & Security → Agent access; never logs message bodies, snippets, or unresolved caller-supplied IDs.
