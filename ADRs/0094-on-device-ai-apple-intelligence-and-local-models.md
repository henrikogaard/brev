# ADR-0094: On-device AI with Apple Intelligence and user-downloaded local models

- **Status:** Proposed
- **Date:** 2026-11-22
- **Deciders:** Henrik
- **Relates to:** [ADR-0006](0006-telemetry-and-privacy.md) (telemetry and privacy), [ADR-0008](0008-ai-writer.md) (AI Writer), [ADR-0026](0026-supervised-mailbox-action-agent.md) (supervised mailbox actions), [ADR-0028](0028-mail-provider-architecture.md) (mail provider architecture), [ADR-0047](0047-mailbox-chat-q-and-a-ai.md) (mailbox chat Q&A), [ADR-0051](0051-user-controlled-ai-providers.md) (user-controlled AI providers), [ADR-0058](0058-localization-via-string-catalogs.md) (string catalogs)
- **Issue:** #304

## Context

Brev's AI features — AI Writer (ADR-0008), thread summaries, and the Assistant / mailbox Q&A surface (ADR-0047) — run behind the provider-neutral `AIBackend` protocol in `packages/BrevAI/` and user-controlled provider profiles (ADR-0051). Today, running AI locally without sending mail content to a cloud API requires the user to install and run an external local server such as Ollama or LM Studio and configure a local OpenAI-compatible endpoint.

On Apple silicon Macs running macOS 26+, Apple's `FoundationModels` framework provides a built-in on-device language model with zero API keys, zero network calls, and zero bundled model weights. For users on Macs where Apple Intelligence is unavailable or turned off (or who prefer an open-weights model), downloading a small quantized model on demand is a second fully local option.

Constraints from existing ADRs:

- **Zero network by default (ADR-0006):** No model download, telemetry, or check may run automatically on install or launch. Any weight download is an explicit, user-started network call that must be documented in `PRIVACY.md` and ADR-0006 before shipping.
- **Explicit AI opt-in & provider transparency (ADR-0008, ADR-0051):** AI stays off by default. Every AI surface must display where text is processed (`"On this Mac"` rather than `"Sent to: …"`).
- **Provider-neutral views (ADR-0028):** Views must never type-check concrete `AIBackend` implementations.
- **Supervised mutations (ADR-0026):** Local models are untrusted with respect to prompt injection in incoming email; mailbox actions still require local planning and explicit confirmation.

## Decision

Extend ADR-0051's provider model with two first-class on-device `AIBackend` implementations in `packages/BrevAI/`, delivered in two independent slices:

### 1. Slice 1 — Apple Intelligence (`FoundationModels`, macOS 26+ / iOS 26+)

- Add `AppleIntelligenceAIBackend: AIBackend` behind `#if canImport(FoundationModels)` and `@available(macOS 26.0, iOS 26.0, *)`.
- **Zero network:** Uses `SystemLanguageModel.default` strictly on-device; never invokes Private Cloud Compute or external endpoints.
- **Availability gating:** Check `SystemLanguageModel.default.availability` at runtime. In Settings → AI, list `"On this Mac (Apple Intelligence)"` on macOS (and `"On this iPhone (Apple Intelligence)"` / `"On this iPad (Apple Intelligence)"` on iOS):
  - Selectable when the system model is `.available`.
  - Shown disabled with a plain-language explanation when unavailable — including older OS versions (`< macOS 26` / `< iOS 26`), `.unavailable(.deviceNotEligible)`, `.unavailable(.appleIntelligenceNotEnabled)`, or `.unavailable(.modelNotReady)` — rather than a broken switch.
- **Transparency label:** Reports `"On this Mac"` on macOS (and `"On this iPhone"` / `"On this iPad"` on iOS), localized through String Catalogs (ADR-0058).
- **Context budget:** Expose a provider-neutral token/byte context budget on `AIBackend` (defaulting to existing limits for cloud backends and a conservative budget for `FoundationModels` ~4k-token sessions) so `MailboxChatController` and summary builders bound input cleanly instead of hitting runtime context-window errors.

### 2. Slice 2 — User-downloaded local model (macOS first, opt-in)

- Add a separate `LocalDownloadedModelAIBackend: AIBackend` (implemented via a single audited local inference engine, e.g. `mlx-swift-lm` on Apple silicon or `llama.cpp` C/Swift binding — exact dependency pinned in `Package.swift` / `THIRD_PARTY_LICENSES.md` when Slice 2 starts).
- **Curated catalog & integrity:** Offer a small curated list (1–2 compact Apache-2.0 / MIT quantized models, ~2–4 GB) with pinned immutable upstream URLs, pinned commit/revision identifiers, and exact SHA-256 digests verified before a downloaded file is moved into place. Reject partial or mismatched downloads.
- **Explicit user-initiated download only:** Settings → AI lists `"On this Mac (download a model)"` with the exact download size, license, source host, and an explicit **Download** button. No download starts automatically on app launch or account setup.
- **Storage & erasure:** Store weights under `Application Support/Brev/Models/` with `NSURLIsExcludedFromBackupKey = true` so weights never bloat iCloud or Time Machine backups. Provide a one-click **Delete model** control in Settings that removes the file from disk immediately.
- **Zero network during inference:** Once downloaded, inference runs strictly in-process with no network sockets and works completely offline.
- **Privacy documentation gate:** Before any Slice 2 networking code lands, add the exact model-download host, trigger ("user clicks Download in Settings → AI"), payload ("HTTP GET for pinned weight file, no account or user headers"), and opt-in row to `ADRs/0006-telemetry-and-privacy.md` and `PRIVACY.md`.

### 3. Shared AI settings & UI contract

- On **macOS**, Settings → AI presents three clear choices alongside turning AI off:
  1. **On this Mac (Apple Intelligence)**
  2. **On this Mac (download a model)** (Slice 2, macOS first)
  3. **Existing ADR-0051 OpenAI-compatible providers** (Ollama / LM Studio / user-configured OpenAI Chat Completions endpoints)
- On **iOS**, Settings → AI presents **On this iPhone / On this iPad (Apple Intelligence)** (Slice 1) alongside existing ADR-0051 OpenAI-compatible providers; the macOS-first weight-download option is omitted on iOS until a dedicated mobile memory/storage slice is proposed. On iOS, the Apple Intelligence option applies the same `SystemLanguageModel.default.availability` gating as macOS (selectable when `.available`, and shown disabled with a plain-language explanation for older OS versions or `.unavailable(.deviceNotEligible)`, `.unavailable(.appleIntelligenceNotEnabled)`, and `.unavailable(.modelNotReady)`).
- AI remains **off by default** on fresh installs, and upgrading to macOS 26 / iOS 26 never silently turns AI on for users who left it off. Existing saved `AIWriterSettings` enablement, provider profiles, and consent choices are preserved unchanged across upgrades.
- Every AI output surface (AI Writer preview, thread summary, Assistant sidebar, mailbox chat) displays the active backend's `transparencyLabel`: on-device backends introduced by this ADR report `"On this Mac"` (macOS) or `"On this iPhone"` / `"On this iPad"` (iOS), while existing ADR-0051 OpenAI-compatible providers continue to display their configured provider destination label.

## Rationale

- **Two slices instead of bundling weights inside `Brev.app`:** Bundling a 2–4 GB model in the app binary would bloat every release DMG, Sparkle update, and TestFlight build even for users who keep AI off. Separating Slice 1 (`FoundationModels`, 0 bytes added) from Slice 2 (explicit user-downloaded weights) delivers zero-network on-device AI immediately on macOS 26 while keeping the app bundle lean.
- **Why not rely solely on Ollama / LM Studio?** Those already work via ADR-0051, but require installing and running a separate daemon. Built-in `FoundationModels` and a managed one-click download remove setup friction without giving up local privacy.
- **Why pinned SHA-256 catalog entries instead of arbitrary model URLs in v1?** Pinning a small vetted catalog makes checksum verification, memory sizing, license attribution, and prompt formatting predictable and auditable. Power users with custom local models already have ADR-0051's local OpenAI-compatible endpoint.
- **Why keep AI off by default even for zero-network Apple Intelligence?** ADR-0008 and ADR-0051 treat AI as an explicit user choice: some users do not want generative UI or local inference running on mail even without network egress.

## Consequences

### Accepted

- `packages/BrevAI` gains an explicit `FoundationModels` backend (Slice 1) and later a local-inference package dependency (Slice 2), both behind `AIBackend` so `BrevMail` views stay provider-agnostic.
- `AIBackend` exposes a context-budget property so smaller on-device context windows degrade gracefully instead of failing mid-request.
- Slice 2 introduces a new explicit user-initiated network download host, requiring updates to ADR-0006, `PRIVACY.md`, and `THIRD_PARTY_LICENSES.md` when Slice 2 is implemented.

### Risks

- **Smaller context window & lower reasoning quality on local models:** Multi-message Assistant queries and long threads may truncate more aggressively than cloud models. Mitigation: enforce deterministic context budgets, prefer concise plain-text snippets, and keep grounded citations pointing strictly to real local messages.
- **Memory pressure & thermal impact (Slice 2):** Loading a 3–4 GB quantized model alongside WebKit and Realm can pressure 8 GB Macs. Mitigation: check available physical RAM before offering a model size, load weights lazily on first explicit AI invocation, and unload after an idle timeout or memory-pressure warning.
- **`FoundationModels` availability & OS behavior changes:** Apple Intelligence availability varies by region, hardware, and system settings. Mitigation: query `SystemLanguageModel.default.availability` dynamically and degrade cleanly with actionable copy.
- **Prompt injection in untrusted email bodies:** Smaller local models are more susceptible to prompt injection. Mitigation: never grant `AIBackend` direct mutation authority; all actions continue through ADR-0026's local planner and typed confirmation challenge.

## References

- [ADR-0006: Telemetry and privacy](0006-telemetry-and-privacy.md)
- [ADR-0008: AI Writer](0008-ai-writer.md)
- [ADR-0026: Supervised mailbox action agent](0026-supervised-mailbox-action-agent.md)
- [ADR-0047: Mailbox chat Q&A](0047-mailbox-chat-q-and-a-ai.md)
- [ADR-0051: User-controlled AI providers](0051-user-controlled-ai-providers.md)
- [ADR-0058: Localization via string catalogs](0058-localization-via-string-catalogs.md)
- Issue #304
- Affected paths (upon acceptance): `packages/BrevAI/`, `packages/BrevSettings/`, `packages/BrevMail/`, `PRIVACY.md`, `ADRs/0006-telemetry-and-privacy.md`
