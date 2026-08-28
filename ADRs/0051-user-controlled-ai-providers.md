# ADR-0051: User-controlled AI providers

- **Status:** Accepted
- **Date:** 2026-08-11
- **Deciders:** Henrik

## Context

Brev's AI Writer, thread summaries, and Mail Context can handle sensitive mail
content. A privacy-first mail client must not turn those actions into a Brev
operated inference service or make a hosted provider the implicit product
default. The previous AI Writer ADR anticipated BYOK, but its provider-hosted
v1 framing no longer matches Brev's standards-first mail direction.

Users also need a credible path to hosted API providers, OpenAI-compatible
self-hosted services, and same-device local models without Brev storing or
selling usage credits. A ChatGPT subscription and a provider API account are
different products, and Brev must not attempt to reuse browser sessions,
desktop-app credentials, or tokens owned by local developer CLIs.

## Decision

### Direct, user-controlled provider connections

- AI remains off by default and every request remains user initiated.
- Brev connects directly from the device to the endpoint selected by the user.
  It does not proxy prompts, operate an inference relay, sell credits, meter
  token usage, choose a provider, or silently fall back to another provider.
- A provider profile contains a user-visible name, OpenAI-compatible base URL,
  model identifier, enabled state, optional default status, and optional
  account assignment. Metadata stays local; bearer API keys stay in the OS
  Keychain. Constructing or saving a profile never makes a network request.
- The first interoperable contract is the OpenAI Chat Completions API. This
  permits a user's own compatible hosted endpoint or self-hosted/local server
  without pretending that every provider's native protocol is already
  supported.
- A profile can be the default for accounts without an override, or be assigned
  to one mail account. A selected profile whose key is missing or invalid is
  unavailable; Brev must not silently substitute the default or another
  provider.
- Per-action disclosure uses the configured provider name and endpoint host.
  The destination is shown before or alongside the compose, summary, and
  mailbox-chat action that sends content.

### Local models and transport safety

- Same-device local OpenAI-compatible servers, including Ollama on
  `http://localhost:11434/v1`, are supported without an API key. On iOS,
  `localhost` means the iPhone or iPad, not the user's Mac.
- Hosted and remote endpoints should use HTTPS. If a user deliberately enters
  another plaintext HTTP endpoint, Brev warns that its content and API key can
  be exposed on that network; it does not hide or normalize that choice.
- Local model downloads, LAN discovery, embedded model runtimes, and Brev
  operated model hosting are out of scope. A configured endpoint is all Brev
  needs to support a user-managed model.

### Authentication and future extensions

- The initial implementation supports a user-entered bearer API key or no key
  for a keyless local endpoint. Brev never implements “Log in with ChatGPT” by
  extracting or reusing a ChatGPT browser/session credential.
- A future provider OAuth integration must be a provider-specific adapter using
  that provider's supported authorization-code flow with PKCE. It must store
  only the resulting provider token in Keychain and receive its own privacy and
  protocol review.
- A future macOS local-CLI integration (for example Codex, Claude, Grok, or
  OpenCode) is a separate runtime decision. It may use an explicit local bridge
  chosen and authorized by the user, but it must not scrape CLI configuration,
  environment variables, browser cookies, or existing CLI tokens.

## Rationale

**Why direct BYOK instead of a Brev relay or token product.** A relay would
make Brev an AI data processor, create a billing/retention surface, and weaken
the mail client's privacy claim. Direct device-to-provider traffic keeps the
commercial and data-processing relationship between the user and their chosen
provider.

**Why OpenAI compatibility first instead of individual provider SDKs.** It is
the smallest useful interoperability seam for hosted APIs, Ollama, llama.cpp,
vLLM, and many self-hosted gateways. Native adapters may be added later when a
provider needs behavior that the compatible contract cannot represent.

**Why no generic ChatGPT login or CLI reuse.** Those credentials belong to a
different product and their terms, lifetime, scopes, and storage boundaries
are not Brev's to reinterpret. A supported OAuth adapter or explicit local
bridge is safer and more honest.

**Alternatives rejected.** Provider-hosted-only AI would unnecessarily bind
Brev to a mail-provider relationship; auto-routing between models obscures the
data destination; embedded local-model management grows the client well beyond
mail and configuration; and a generic credential-import feature would create a
high-risk secret-harvesting surface.

## Consequences

### Accepted

- Users bring their own provider account, API key, endpoint, and model. Brev
  offers no credits or subscription bundle.
- A provider's privacy, pricing, retention, availability, and model quality
  are the user's relationship with that provider. Brev presents the
  destination but cannot make a provider private by assertion.
- Some providers need a future native adapter or official OAuth flow. They are
  not excluded; they are simply not claimed as supported until implemented.
- Existing account-provided AI backends remain available where present, unless
  the user assigns a configured profile to that account.

### Risks

- A malformed or incompatible endpoint can fail at request time. Brev validates
  the local configuration shape and reports the provider error without logging
  credentials; it cannot prove arbitrary endpoint compatibility without a
  user-triggered test request.
- Users can choose a less-private hosted provider. Per-action endpoint labels,
  defaults-off consent, Keychain storage, and plaintext-transport warnings make
  that choice visible rather than preventing it.
- Per-account profiles add settings complexity. The configuration UI keeps a
  single default plus explicit overrides and refuses hidden fallback so the
  selected route stays understandable.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0008: AI Writer architecture (superseded only where it prescribes a
  provider-hosted default or deferred BYOK)
- ADR-0028: Standards-first IMAP/SMTP roadmap
- `packages/BrevAI/Sources/BrevAI/AIProviderBackendResolver.swift`
- `PRIVACY.md`
