# New ADR prompt

Used when an agent (or Henrik) needs to draft an ADR. Triggered by:

- Touching a protected path (per ADR-0005 and `ADRs/README.md`).
- Making an architectural decision that future readers should
  understand.
- Superseding an existing ADR.

## Read first

- `ADRs/README.md` — conventions, when ADRs are required.
- `ADRs/0028-mail-provider-architecture.md` — the invariants. Your ADR
  must not violate these unless you're explicitly proposing to
  change one.

## Template

Copy this template to `ADRs/NNNN-kebab-case-title.md` where NNNN is
the next available number (check `ls ADRs/` first):

```markdown
# ADR-NNNN: <descriptive title in sentence case>

- **Status:** Proposed
- **Date:** YYYY-MM-DD
- **Deciders:** <list of names>

## Context

What forces the decision? What constraints apply? Include enough
that someone reading this in two years understands why we cared.

Reference relevant prior ADRs.

## Decision

State the decision crisply. If there are sub-decisions, enumerate
them.

## Rationale

Why this decision over the alternatives? Name the alternatives
explicitly and say why each was rejected. This is the most useful
section for future readers — it captures *thinking*, not just
*outcome*.

## Consequences

### Accepted

What changes as a result. What we explicitly accept as trade-offs.

### Risks

What could still go wrong. What we're betting on. Mitigations.

## References

- Other ADRs this depends on or supersedes.
- External standards (RFCs, specs).
- Code paths affected.
```

## Quality bar

A good ADR:

- Is between 50 and 300 lines. Shorter is fine for narrow decisions.
  Longer means the decision probably contains multiple decisions
  that should be split.
- Names alternatives explicitly. "We chose X" without "instead of
  Y" is incomplete.
- States consequences honestly. If a decision has real costs, say
  so. Future readers can handle bad news; they can't handle
  surprises.
- Is dated. ADRs are historical documents.
- References related ADRs by number and link.

A bad ADR:

- Reads like a marketing pitch. ADRs are internal; honesty
  beats persuasion.
- Justifies a foregone conclusion without addressing alternatives.
- Mixes multiple decisions. Split them.
- Doesn't mention trade-offs. There are always trade-offs.

## Process

1. Draft with `Status: Proposed`.
2. Open a PR with just the ADR (no implementation).
3. Discuss in PR. Revise.
4. When agreed, change status to `Accepted` and merge.
5. Implementation PRs reference the Accepted ADR.

If the ADR is small and the implementation is small, they can ship
together — but the ADR commit lands first in the same PR, before
implementation commits.

## Updating the ADR index

When adding a new ADR, also update `ADRs/README.md` to add the new
entry to the index table. This is mechanical; CI does not enforce
it but reviewers will catch the omission.

## When to supersede vs amend

- **Supersede** when the original decision was wrong or the
  situation changed materially. Write a new ADR with `Supersedes:
  ADR-NNNN` in the references. Update the original's status to
  `Superseded by ADR-MMMM`.
- **Amend in place** for typo fixes, broken link repairs,
  formatting improvements. Don't change the decision in place;
  that requires a supersession.
