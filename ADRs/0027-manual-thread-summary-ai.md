# ADR-0027: Manual thread summary AI

- **Status:** Proposed
- **Date:** 2026-06-05
- **Deciders:** Henrik

## Context

ADR-0008 accepted AI Writer for user-authored compose text and explicitly
rejected AI in the message reading flow for v1. That was the right default:
read-side AI can easily become background triage that sends received mail to an
AI backend without the user understanding the data flow.

The related feature request asks Brev to adopt a narrower Canary Mail-inspired feature:
user-invoked summaries for a loaded conversation, with concise bullets and a
separate next-actions section. This is not automatic mailbox triage. It is a
foreground action on content the user has already opened.

ADR-0028 invariant 6 still controls the design: AI is invoked, never
automatic. ADR-0006 requires optional privacy-sensitive AI calls to be off by
default, explicitly disclosed, and labeled at the action site. ADR-0026 keeps
mailbox action interpretation separate from read-side AI and does not authorize
summaries; this ADR covers only manual summary/action extraction.

## Decision

Brev may add manual thread summaries and next-action extraction under these
constraints.

1. **Manual invocation only.** The user must explicitly choose a summarize
   action from the loaded message/thread UI. Brev must not summarize messages
   in the background, from notification surfaces, during sync, or as automatic
   triage.

2. **Existing AI consent and destination transparency apply.** The action is
   unavailable unless an AI backend is enabled for the current account/source
   and the relevant AI consent has been given. The summary surface must show
   the same destination label pattern as AI Writer before content is sent.

3. **Bounded, explainable context.** The request may include only the loaded
   thread/conversation window needed for the summary. The UI or policy should
   describe when a thread is truncated, for example by message count or
   character budget.

4. **Content leaves only on action.** Received message content may be sent to
   the selected AI backend only after the user invokes the action. Brev does
   not log the prompt, response, message bodies, or raw summary text.

5. **Results are local and ephemeral by default.** Summary results render in
   the reader session. Brev does not upload them to any Brev service, use them
   for training, or persist them as mailbox metadata. If future persistence is
   desired, it needs its own decision and storage/privacy review.

6. **No autonomous actions.** Extracted next actions are text suggestions
   only. They do not create tasks, send replies, schedule events, mutate mail,
   or create rules without a separate explicit user action handled by the
   relevant feature.

7. **Provider abstraction remains intact.** Views use `AIBackend` and shared
   settings/availability policy. They do not import provider-hosted AI, provider API
   types, BYOK implementations, Realm types, or provider DTOs.

8. **Graceful fallback.** If no backend is available, consent is missing, the
   thread body is not loaded, or the provider fails, the UI explains the state
   without retry loops or hidden background sends.

## Rationale

**Why amend ADR-0008's read-side ban?** ADR-0008 rejected broad read-side AI
because it implied automatic processing of received mail. A manual, foreground
summary of a loaded thread has a narrower and more understandable data flow:
the user chooses one conversation and sees the destination before sending.

**Why allow provider-backed summaries instead of local-only only?** ADR-0028
records local-LLM-only read-side AI as a v3 aspiration, but Brev already has a
transparent opt-in AI backend path. Letting the same per-action transparency
govern a manual thread summary is useful without weakening the ban on
background triage. Users who want the strongest privacy posture can leave AI
off or use a local/BYOK endpoint when available.

**Why not add automatic next-action triage?** Automatic triage would require
processing many received messages and would create new trust and retention
questions. This ADR permits only text extraction for the one thread the user
has selected.

**Why not persist summaries?** Persisted summaries become mailbox metadata:
they need lifecycle, export, deletion, encryption, and sync choices. The first
slice is more reviewable if results remain session-local.

## Consequences

### Accepted

- ADR-0008's "no AI in the message reading flow" rule is narrowed for
  manually invoked, per-thread summaries only.
- `PRIVACY.md` and ADR-0006 should describe manual thread summaries as an
  opt-in AI data flow before the feature ships.
- The first implementation can use the existing `AIBackend.generateReply`
  request shape with summary-specific prompt construction, avoiding a new
  public AI protocol method until broader read-side AI requirements are known.
- Tests should cover availability gating, prompt/context bounding, destination
  label presentation, and absence of message identifiers/headers not needed by
  the summary request.

### Risks

- **Users may overgeneralize from one summary action to background AI.**
  Mitigation: keep the action manual and label the destination at the action
  site.
- **Sensitive received mail content can be sent to the AI provider.**
  Mitigation: AI is disabled by default, consent is required, and the user sees
  the provider destination before invocation.
- **Long threads may be summarized incompletely.** Mitigation: deterministic
  context-window policy and visible truncation copy.
- **Future pressure to automate triage.** Mitigation: this ADR explicitly
  excludes background summarization, scoring, folder suggestions, and mailbox
  rules.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance.
- ADR-0008: AI Writer architecture.
- ADR-0028: Roadmap to v2 and architectural invariants.
- ADR-0026: Supervised mailbox action agent.
- The related feature request: Summarize threads and extract next actions with explicit opt-in.
