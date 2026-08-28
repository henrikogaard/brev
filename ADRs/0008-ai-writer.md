# ADR-0008: AI Writer architecture

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev ships an AI Writer that helps users draft, edit, shorten, expand, and
translate emails. It's wired to the provider's
`.ai(mailbox:)` endpoint, which routes requests to provider-hosted AI —
the provider's sovereign AI assistant launched in 2025.

provider-hosted AI is a credible privacy story for an AI backend:
- Hosted entirely in Swiss data centers.
- Open-source models running on local the provider infrastructure.
- GDPR and Swiss FADP compliant.
- No data used for training.
- No data shared with third parties.
- Ephemeral mode available (zero retention).

For Brev's positioning, provider-hosted AI is arguably the *strongest* default AI
backend available. Stripping the AI Writer or replacing it with a
generic LLM call would be a regression.

However, v2 will support other mail accounts (ADR-0001,
ADR-0028). Those accounts can't route through provider-hosted AI — the provider
doesn't AI-process mail it didn't receive. For those users, BYOK
(Bring Your Own Key) is necessary.

## Decision

### v1: provider-hosted AI-backed, opt-in, transparent

- AI Writer ships in v1 for the provider accounts using the existing
  `.ai(mailbox:)` endpoint via `provider-hosted AIBackend: AIBackend`.
- **Disabled by default.** First use shows a clear consent dialog
  explaining that message content will be sent to provider-hosted AI
  (the provider's Swiss AI infrastructure), what provider-hosted AI does and
  doesn't do, and how to disable.
- **Per-action transparency.** Every AI invocation shows a small
  persistent label: "Sent to: provider-hosted AI (the provider, Switzerland)". The
  user is never unaware where their data is going.
- **UI for other accounts.** When a user composes from a
  other account (theoretical in v1, real in v2), the AI
  Writer button is disabled with a tooltip: "AI Writer requires
  the provider in v1; BYOK support coming in v2."

### `AIBackend` protocol

Lives in `packages/BrevAI/`. Designed in v1 with `provider-hosted AIBackend` as
the only conforming implementation. `BYOKBackend` arrives in v2.

```swift
public protocol AIBackend: Sendable {
    var identifier: String { get }            // "provider-hosted", "openai", "anthropic", "ollama"
    var displayName: String { get }           // "provider-hosted AI", "OpenAI", etc.
    var transparencyLabel: String { get }     // Full string for per-action UI

    func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse

    func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse
}

public struct AIMessage: Sendable {
    public let role: AIRole               // .user | .assistant | .system
    public let content: String
}

public enum AIShortcutAction: String, Codable, Sendable {
    case shorten, expand, formal, casual, friendly,
         improveWriting, fixSpelling, translate
}
```

`provider-hosted AIBackend` wraps the existing `MailApiFetcher` AI endpoints.
`BYOKBackend` (v2) wraps an OpenAI-compatible API client (since
OpenAI's API shape is the lingua franca — Anthropic, Mistral,
Ollama, llama.cpp, and most others provide compatibility endpoints).

### v2: BYOK addition

Settings → AI → "Add custom provider" gives a form:

- **Provider name** (free text, displayed in transparency label)
- **API endpoint URL** (`https://api.openai.com/v1`, `http://localhost:11434/v1`, etc.)
- **API key** (stored in Keychain, never logged)
- **Model** (free text or fetched list if endpoint supports `/models`)

Per-account preference: users with multiple accounts choose which AI
backend each account uses. An the provider account defaults to provider-hosted AI;
a Gmail account defaults to "none" until the user configures BYOK.

### Capability flag

`BackendCapabilities.aiWriter` (ADR-0001) is set when the *mail
backend* supports server-side AI integration (provider-hosted AI via the provider).
For mail backends without it (IMAP), `BYOKBackend` is the only path
and the UI surfaces this clearly.

### Privacy and zero-data-retention promise

For provider-hosted AI specifically, the UI consent dialog states:

> AI Writer sends the text of your message (or the prompt you
> provide) to provider-hosted AI, the provider's Swiss AI assistant. provider-hosted AI does not
> use your data to train models, does not retain conversations beyond
> the response, and is hosted entirely in Switzerland under GDPR and
> Swiss FADP. Brev does not see or log the content you send. You can
> turn AI Writer off any time in Settings.

For BYOK (v2), the consent dialog states the configured endpoint
URL prominently and warns:

> The privacy of your message content depends entirely on the
> provider you configured. Review your provider's privacy policy.
> Brev does not see or log the content you send.

### What we don't ship

- **No AI in the message reading flow.** No "summarize this email",
  no "extract action items", no AI triage. Each of those would mean
  every received message getting sent to the AI backend, which is a
  much larger data flow than user-initiated compose assistance. v1
  scope rejects this category.
- **No AI auto-reply.** Users invoke the AI; the AI never acts on
  their behalf without explicit invocation.
- **No AI in the system tray, no AI-suggested folders, no AI-derived
  importance scores.** These all imply background processing of
  message content.

## Rationale

**Why keep AI Writer instead of stripping.** provider-hosted AI is a privacy-
positive AI backend. Stripping it would remove a useful feature for
no privacy gain. The right answer is "off by default with informed
opt-in", not "removed".

**Why `AIBackend` protocol now, BYOK UI in v2.** The protocol is
small and decisions about it affect data flow design. Defining it
during v1 prevents painting `provider-hosted AIBackend` into a corner. BYOK UI
would add account-management complexity that isn't justified until
other accounts exist.

**Why OpenAI-compatible API for BYOK.** It's the lingua franca.
Supporting it covers OpenAI directly, Anthropic via their compat
endpoint, Mistral, Together, Groq, Ollama, llama.cpp, vLLM, and
most local-LLM tooling. Single client implementation, broad reach.

**Why ban AI in reading/triage flows.** They imply sending every
received message to the AI backend. That's a *qualitatively different*
data flow from "user invokes AI on a draft they wrote." For a
privacy-positioned client, the difference matters. We may revisit in
v3+ with strict local-LLM-only paths.

## Consequences

### Accepted

- AI Writer is off by default. New users may not discover it. We
  surface it via the welcome screen and Settings; we don't push it.
- v2 BYOK adds Keychain entries and account-pairing UI. ~1-2 weeks
  of work in the v2 milestone.
- The UI explicitly distinguishes provider-hosted AI from BYOK at every
  invocation. Slight visual surface cost; high transparency value.

### Risks

- **provider-hosted AI API changes.** Same provider-dependency risk as other
  provider API surfaces. Same mitigation (ADR-0005 provider review
  agent catches and reports).
- **BYOK encourages users to use less-private AI providers.** True.
  Mitigation: provider transparency label, BYOK consent dialog warns
  about provider-specific policies. After that it's user choice.

## References

- ADR-0028: Project identity and scope
- ADR-0001: Backend abstraction (`aiWriter` capability)
- ADR-0006: Telemetry and privacy (provider transparency labels)
- ADR-0028: Roadmap to v2 (BYOK milestone)
