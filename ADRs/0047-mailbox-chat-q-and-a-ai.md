# ADR-0047: Mailbox chat Q&A AI for sender-scoped cached mail

- **Status:** Proposed
- **Date:** 2026-07-25
- **Deciders:** Henrik

## Context

The Mail Context inspector adds a mailbox chat surface beside the reader on
macOS. Task 6 introduces the first read-side Q&A path: the user asks a
question about the current sender, Brev searches only the local cache for that
sender, then optionally sends a bounded set of cached headers/snippets to the
selected AI backend to answer the question.

ADR-0008 allowed AI Writer for user-authored compose content but intentionally
avoided received-message AI in v1. ADR-0027 later carved out one narrow
exception: manual thread summaries for a loaded conversation. Mailbox chat Q&A
is another read-side AI path, but it differs from thread summaries because it
answers sender-scoped questions from cached mailbox search results instead of a
single loaded thread.

ADR-0006 still requires optional privacy-sensitive network calls to be off by
default, disclosed in plain language, and visible at the action site. ADR-0028
invariant 6 still applies: AI is invoked, never automatic. The design spec for
the Mail Context column also requires the sender panel to stay zero-network and
the chat transcript to remain session-local.

The decision needed here is whether Brev may send bounded sender-scoped cached
mail context to an already-configured AI backend for foreground Q&A, and under
which privacy and prompting constraints.

## Decision

Brev may add user-selected sender, current-folder, or all-folders mailbox chat
Q&A under these constraints.

1. **Manual invocation only.** Brev sends mailbox context to AI only when the
   user explicitly sends a chat message. Opening the Mail Context column,
   loading sender facts, changing selection, or idling in the reader must not
   invoke AI.

2. **Local search remains the retrieval boundary.** Q&A uses cache-only search
   within the explicitly selected sender, current-folder, or all-folders scope.
   “All folders” remains bounded to the current account/mailbox source and does
   not cross into another configured account. The implementation may use
   `SearchQuery` plus existing cached header/snippet data. It must not broaden
   to server-side search, background fetches, HTML-body loads, or attachment
   extraction.

3. **Context is bounded and explainable.** The AI request may include only a
   bounded set of cached message headers/snippets, capped by message count and
   byte budget. The initial implementation uses `maxMessages = 12` and
   `maxBytes = 48 KiB`.

4. **Received mail is treated as untrusted prompt input.** Prompt construction
   must instruct the model not to follow instructions embedded in email
   subjects/snippets and to answer only from the provided cached context.

5. **Existing AI consent and provider routing apply.** Mailbox chat Q&A reuses
   the same AI Writer enablement and consent model as compose/thread summary.
   It does not introduce a separate hidden backend, service, or Brev-operated
   relay.

6. **Destination transparency is mandatory per answer.** Each assistant answer
   must show the same destination label pattern as other AI surfaces (for
   example `Sent to: provider-hosted AI` or a configured BYOK/local host).

7. **Answers stay grounded and cited.** The assistant may answer only from the
   supplied cached context and must surface citations back to the originating
   messages by subject/date. If the cached context is insufficient, the answer
   must say so plainly instead of inferring missing facts.

8. **Results remain local/session-scoped.** Brev does not upload transcripts to
   a Brev service, persist them as mailbox metadata, or use them for training.
   The transcript stays in the local UI session unless a later ADR says
   otherwise.

9. **Mailbox mutations remain separate.** This ADR authorizes Q&A only. Action
   planning, review, and confirmation remain governed by ADR-0026 and must not
   piggyback on the Q&A path.

## Rationale

**Why allow this path at all?** Users often want quick answers such as "did
this sender mention the invoice?" while they are already browsing mail. Local
sender search plus bounded AI synthesis is meaningfully more useful than raw
search results alone.

**Why sender-scoped cache-only search first?** Sender scope is easy to explain,
cheap to compute locally, and aligns with the Mail Context column's product
shape. Keeping retrieval cache-only preserves the zero-network default until
the explicit AI send action.

**Why reuse the AI Writer backend and consent instead of inventing a new one?**
The user already has one explicit AI opt-in/control surface. Reusing it keeps
destination handling consistent and avoids a second silent privacy model.

**Why not allow full body fetches or server search now?** Those would expand
both data exposure and surprise: a "chat question" could suddenly trigger
network fetches before the AI call itself. The first version is more reviewable
if it works only from already-cached headers/snippets.

**Why a new ADR instead of stretching ADR-0027?** Thread summary is a
thread-bounded read-side tool; mailbox chat Q&A is a sender-scoped retrieval +
answering workflow. Keeping them separate makes the context boundary,
retrieval/posture, and future risks clearer.

## Consequences

### Accepted

- Mailbox chat Q&A may ship using the existing `AIBackend.generateReply` seam,
  avoiding a new public AI protocol method.
- `PRIVACY.md` and ADR-0006 must document mailbox chat Q&A as a separate opt-in
  AI data flow before the feature ships.
- Tests should cover sender-scoped cache-only search, bounded context,
  untrusted-content prompt instructions, citations, and cancellation/error
  behavior.
- The sender panel remains local-only even when mailbox chat is available.

### Risks

- **Users may overestimate what the answer saw.** Mitigation: sender-scope chip,
  bounded cached context, and citations.
- **Sensitive received mail can still leave the device on explicit use.**
  Mitigation: defaults-off AI, shared consent, clear destination labels, and a
  documented provider choice.
- **Models may still hallucinate despite the prompt.** Mitigation: cache-only
  grounding, explicit "insufficient context" instruction, and citations.
- **Users may mistake All folders for all accounts.** Mitigation: the scope is
  source-bound, the accessible label names the account, and cross-account or
  body-heavy retrieval needs another ADR review.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0008: AI Writer architecture
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0026: Supervised mailbox action agent
- ADR-0027: Manual thread summary AI
- `docs/specs/2026-07-25-mail-context-column-design.md`
- `packages/BrevMail/Sources/BrevMail/MailboxChatController.swift`
