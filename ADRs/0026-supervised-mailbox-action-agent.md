# ADR-0026: Supervised mailbox action agent

- **Status:** Proposed
- **Date:** 2026-06-05
- **Deciders:** Henrik

## Context

Brev now has a local supervised mailbox action surface for the related feature request:
`MailboxActionAgentSheet` accepts a user request, the local planner
recognizes sender-scoped delete/move requests, cache-only search counts
matching messages, and the UI requires an exact confirmation phrase before
the mutation is applied.

The user goal is broader than deterministic parsing: they want to ask an
AI agent to perform mailbox actions such as:

- "delete all mails from sender xxxx@xxxx.com"
- "move all mails from sender sss@ssss.co to this folder here"

ADR-0008 currently rejects AI in the message reading flow and AI triage for
v1 because those flows can imply sending received message content to an AI
backend. ADR-0028 invariant 6 also says AI is invoked, never automatic.
ADR-0006 requires optional privacy-sensitive network calls to be off by
default, explicitly disclosed, and visible at the action site.

The decision needed here is not whether Brev may mutate mail: the app
already supports user-initiated delete/move/archive actions through
`MailBackend`. The decision is whether an AI system may interpret a mailbox
action request, what context it may receive, and where the boundary sits
between interpretation, deterministic planning, user confirmation, and
mutation execution.

## Decision

Brev may add a supervised mailbox action agent, but only under these
constraints.

1. **AI may interpret intent, never execute mutations.** The AI layer may
   translate the user's explicit request into a structured mailbox action
   intent. It must not call `MailBackend`, enqueue `PendingMutation`, or
   bypass the deterministic planner/executor.

2. **The deterministic planner remains the authority.** The existing
   planner/resolver validates supported operations, resolves folders,
   performs cache-only sender search, computes counts, and builds the
   confirmation challenge. Invalid, ambiguous, or unsupported AI output is
   treated exactly like an unsupported local parse.

3. **Every mutation requires explicit review and confirmation.** The UI must
   show the matched sender, target folder if any, exact message count, and
   destructive/non-destructive action. The user must type the required phrase
   such as `DELETE 12` or `MOVE 3` before execution.

4. **No background or automatic mailbox scanning.** The agent is invoked only
   from a user action in the mailbox UI. It does not watch incoming mail,
   classify mail in the background, suggest folders proactively, or run from
   notification/system-tray surfaces.

5. **AI context is minimized.** For the sender-scoped v1 action set, the AI
   request may include:
   - the user's typed instruction,
   - visible/candidate folder names and roles needed to resolve a target,
   - selected/focused folder metadata needed for phrases like "this folder".

   It must not include message bodies, attachments, full mailbox indexes,
   full sender lists, or the final list of matching message IDs. Counts and
   matching IDs are computed locally after AI interpretation.

6. **Provider-backed AI is opt-in and transparent.** Any nonlocal AI
   interpreter is disabled by default, uses the same provider transparency
   standard as ADR-0006/ADR-0008, and shows the destination at the action
   site. Before enabling hosted/BYOK interpretation, implementation must
   update `PRIVACY.md` and ADR-0006's network-call table with the mailbox
   action data flow.

7. **Local interpretation is allowed without new network disclosure.**
   Deterministic local parsing and local-only models whose endpoint is
   constrained to localhost may be used for intent interpretation. Local
   endpoints still require user configuration and an action-site destination
   label, but they do not send data to Brev or a hosted AI provider.

8. **Read-side AI remains out of scope.** This ADR does not authorize
   summarization, action-item extraction, importance scoring, "clean my
   inbox" recommendations, body-aware triage, or agentic rule creation.
   Those require a separate ADR because they need different message-content
   and background-processing boundaries.

9. **Capability and backend invariants still apply.** UI gates continue to
   use backend capabilities and shared settings, not concrete backend type
   checks. Views must not import provider-specific AI or mail implementation
   types.

## Rationale

**Why allow a mailbox action agent at all?** Bulk sender cleanup is a real
mail-client workflow. Natural language can make it faster, especially for
destructive operations where the important safety property is not the syntax
but the counted review and confirmation gate.

**Why AI interpretation only?** Letting an AI call backend mutation APIs would
collapse interpretation, authorization, and execution into one opaque step.
Brev already has deterministic mail mutation APIs and a supervised
confirmation flow. Keeping AI before that boundary preserves testability and
lets the same safety logic protect deterministic and AI-assisted requests.

**Why no message bodies for v1?** The requested examples are sender/folder
operations. They can be satisfied with the user's instruction, folder
metadata, and local cache search. Sending message bodies to interpret these
requests would be unnecessary and would violate the privacy distinction that
ADR-0008 drew between compose assistance and received-message processing.

**Why not use provider-hosted AI automatically for the provider accounts?** provider-hosted AI is a
credible AI Writer provider, but mailbox action interpretation is a different
data flow from compose assistance. Even when the mailbox provider and AI
provider are both the provider, the user must opt into this specific use and
see the destination label at the action site.

**Why not make this local-only forever?** Local-only interpretation is the
strongest privacy posture, but some users will not run a local model. The
decision permits BYOK/hosted providers only with explicit opt-in, disclosure,
and minimal prompt context. That keeps the feature useful without weakening
the zero-network-by-default promise.

**Why not allow broader actions now?** Sender-scoped delete/move has a clear
local verification story: exact sender search, counted matches, and explicit
mutation target. Broader requests such as "delete unimportant mail" or
"archive newsletters I never read" depend on classification policy,
potentially message bodies, and user-specific preferences. Those need their
own design.

## Consequences

### Accepted

- The local `MailboxActionAgentPlanner` / `MailboxActionAgentSheet` remains
  the execution boundary for v1 mailbox actions.
- A future AI interpreter should return structured intent, not executable
  closures or backend calls.
- The first AI-backed slice should support only sender-scoped delete/move
  requests that the deterministic planner can independently validate.
- Settings need a mailbox-action-specific AI consent surface or an AI settings
  extension that distinguishes compose assistance from mailbox action
  interpretation.
- Any hosted/BYOK interpreter implementation must update `PRIVACY.md` and
  ADR-0006 before it ships.

### Risks

- **Prompt leakage through user instructions.** The user may type sensitive
  email addresses or folder names into the request. Mitigation: action-site
  destination label, explicit opt-in, and local-only/default-off behavior.
- **Overtrust in "AI" wording.** Users may assume the agent understood more
  than it did. Mitigation: counted review copy, exact phrase confirmation,
  and clarification instead of guessing on ambiguous folders or unsupported
  operations.
- **Provider output drift.** Hosted or local models may produce invalid JSON
  or unsupported actions. Mitigation: strict structured decoding, deterministic
  planner validation, and treating invalid output as clarification failure.
- **Future feature pressure.** It will be tempting to add body-aware cleanup,
  triage, and automatic rules. Mitigation: this ADR explicitly excludes those
  paths and requires separate ADRs for message-content or background AI.

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0008: AI Writer architecture
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0022: Offline mutation queue and local cache evolution
- The related feature request: Supervised mailbox action agent
- `packages/BrevMail/Sources/BrevMail/MailboxActionAgentPlanner.swift`
- `packages/BrevMail/Sources/BrevMail/MailboxActionAgentSheet.swift`
