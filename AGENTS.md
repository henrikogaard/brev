# AGENTS.md

`AGENTS.md` is the canonical instruction file for AI agents in this
repository. `CLAUDE.md` points here for compatibility; update this file
first when workflow rules change.

This document is the contract for AI agents (Claude Code, Codex CLI, or
any other) working in the Brev codebase. Read this in full before making
changes. Read the relevant ADRs in `ADRs/` before designing anything
substantial.

## Communication and summary format

Use `summary-router` and `summary-tables` for summaries, suggestions,
status updates, comparisons, progress readouts, acceptance-criteria
checks, PR/issue readiness reports, verification summaries, closeouts,
and any answer that would be clearer as a compact evidence-backed table.

- Lead with the bottom line in one sentence, then use a Markdown table
  when the information is easier to scan by row.
- Prefer short, concrete table columns such as `Item`, `Status`,
  `Evidence`, `Suggestion`, `Tradeoff`, `Recommendation`, or
  `Verification`.
- Close with a short `Verified:` or `Net:` line when it helps clarify
  what is proven, pending, or recommended next.
- Skip tables only for genuinely tiny answers where a table would add
  noise.

## Project summary

Brev is a modern, open-source mail client for macOS and iOS. The
codebase is Brev-owned UI, sync, and provider integration layers. Current
mail backends are standards-first IMAP/SMTP and the native Gmail API adapter;
Microsoft Graph/Exchange remains future provider scope.

- **Language:** Swift 5.10+
- **UI:** SwiftUI on both macOS and iOS, with platform-conditional
  modifiers for native feel
- **Build system:** Tuist + SPM
- **Storage:** RealmSwift for local persistence inside the backend
  layer
- **Networking:** URLSession + async/await in new code; provider-specific
  API adapters live in their own packages
- **Tests:** Swift Testing, ViewInspector, swift-snapshot-testing,
  XCUITest
- **Lint/format:** SwiftLint (with custom rules), SwiftFormat
- **CI:** GitHub Actions
- **Commit style:** Conventional Commits
- **Tool versions:** Pinned via `.mise.toml`

## Required reading before designing

Before substantial work, read:

1. **`AGENTS.md`** in full.
2. **`ADRs/README.md`** — the ADR index and the rules for when a new
   ADR is required.
3. **ADR-0028** — the standards-first IMAP/SMTP roadmap and current
   provider/backend direction.
4. **ADR-0028** — the architectural invariants. ADR-0028 supersedes
   the old roadmap parts, but the invariants still bind every change:
   view-layer boundaries, capability-driven UI, and rendering-pipeline
   seams.
5. **Backend internals when relevant:** ADR-0029 (IMAP/SMTP backend
   foundation) and ADR-0030 (full IMAP sync/cache engine).
6. **The ADRs relevant to your area:**
   - View / UI work: ADR-0002 (theme), ADR-0004 (layout)
   - Backend / sync / provider integration: ADR-0001 (backend),
     ADR-0028 (standards-first IMAP/SMTP roadmap)
   - Avatars: ADR-0003
   - Calendar: ADR-0007
   - AI: ADR-0008
   - Privacy: ADR-0006
   - Build, lint, CI: ADR-0004, ADR-0005
   - Release: ADR-0009

If your change requires a new ADR (per the protected-paths list in
ADR-0005), draft it *first* using `prompts/new-adr.md` and link it
in the PR.

Check the current branch, README, worklog, and GitHub issues before
relying on any remembered product-state summary. Brev is a working
IMAP/SMTP mail client, not a scaffold, but the exact build graph and
remaining priorities move with active issues.

## Repository structure

See ADR-0004 for the full tree. Headlines:

- `apps/macOS/` and `apps/iOS/` — the two app targets, both built
  fresh. Share components via `packages/BrevDesign/`.
- `packages/BrevBackend/`, `packages/BrevMail/`, `packages/BrevDesign/`,
  `packages/BrevThemes/`, `packages/BrevAvatars/`, `packages/BrevCalendar/`,
  `packages/BrevAI/` — Brev's own SPM packages, licensed under MIT.
- `packages/BrevSyncEngine/` — IMAP sync, cache, CONDSTORE/polling, and
  related sync orchestration.
- `packages/BrevSettings/` and `packages/BrevCrypto/` — settings and
  local cryptographic support.
- `themes/` — JSON theme files (built-ins).
- `prompts/` — agent prompt templates. Versioned; improve them when
  they fail.

## Hard rules

These are mechanically enforced. Don't try to work around them.

### Rule 1: No literal colors in views

```swift
// WRONG
Text("Subject").foregroundStyle(Color.blue)
Text("Date").foregroundStyle(Color(hex: "#888"))

// CORRECT
@Environment(\.brevTheme) var theme
Text("Subject").foregroundStyle(theme.accent.color)
Text("Date").foregroundStyle(theme.textSecondary.color)
```

`Color.clear` is the only exception (structural, not visual). SwiftLint
rule `no_literal_colors_in_views` blocks violations.

### Rule 2: No telemetry libraries

Banned imports anywhere in Brev:
`Matomo`, `Sentry`, `FirebaseAnalytics`, `Mixpanel`, and `Amplitude`.

If telemetry imports reappear, run `scripts/test-telemetry-artifacts.sh`
and `scripts/privacy-audit.sh`.

### Rule 3: Capability-driven UI, not backend type-checks

```swift
// WRONG
if backend is GmailAPIBackend {
    showCalendarReply()
}

// CORRECT
if backend.capabilities.contains(.serverSideCalendarReply) {
    showCalendarReply()
}
```

See ADR-0001 for the capability flags. See ADR-0028 invariant 2.

### Rule 4: Views don't see Realm types

`BrevBackend` exposes plain Swift domain models (`Message`,
`Folder`, `Draft`). View code never imports `RealmSwift` and never sees
`Object`, `Results<>`, `@ObservedResults`.

### Rule 5: ADR-required protected paths

If your change touches anything in the protected-paths list (ADR-0005),
the PR must include a new or updated ADR. The `adr-required.yml` CI
job blocks otherwise.

### Rule 6: No new network calls without explicit opt-in

Per ADR-0006, Brev has a zero-network-by-default property verified
by `BrevTesting`. Any new code that adds an external network call
must:

1. Be gated by an explicit user opt-in.
2. Be documented in `PRIVACY.md`.
3. Be added to the network calls table in ADR-0006.

### Rule 7: Test builds never replace the daily-driver app

All local development, UI, mock, smoke-account, and verification builds use
`script/build_and_run.sh`'s default test identity. The produced and installed
bundle is named `Brev Test (YYYY-MM-DD).app`; test builds must never produce,
rename to, install over, kill, or otherwise replace `/Applications/Brev.app`.

Only Henrik's explicit request to rebuild the release app from current `main`
authorizes `script/build_and_run.sh --release-main --live`. That command must
fail closed unless the checkout is clean and exactly matches `origin/main`.
`Brev.app` must always launch with live IMAP/SMTP mode and must never contain or
inherit a placeholder/mock mailbox. Test builds may use `--mock`, `--live`, or
smoke accounts.

## Workflow conventions

### Implementation discipline

Brev agents should follow a caution-over-cleverness coding loop,
adapted from the Karpathy-style agent guidelines:

- Before coding, name consequential assumptions and tradeoffs. If the
  request has multiple plausible meanings and the wrong one would
  create churn, ask or draft the narrower plan first.
- Define success criteria before editing: which tests, lint, builds,
  ADR updates, issue updates, and worklog entries will prove the task
  is complete.
- Prefer the smallest implementation that satisfies the request and
  existing ADRs. Do not add speculative flexibility, new abstractions,
  provider-general machinery, or broad error handling for impossible
  states unless the current requirement needs it or the codebase already
  has that pattern.
- For multi-step tasks, state a brief plan with the verification target
  for each step. If the goal cannot be phrased as a verifiable outcome,
  clarify the goal before making broad edits.
- If the implementation grows noticeably larger than the problem
  warrants, stop and simplify before continuing. Prefer deleting a
  premature abstraction over expanding it.
- Keep changes surgical. Touch only files that trace directly to the
  task, match local style, and avoid drive-by formatting or refactors.
  If unrelated dead code or design debt is noticed, mention it in the
  handoff instead of editing it.
- Remove unused imports, helpers, fixtures, or code paths introduced
  by your own changes. Do not remove pre-existing unused code unless
  the user asked for cleanup.
- Loop until the agreed verification passes. If verification cannot be
  run, record the skipped check and reason in `WORKLOG.md` and the PR
  handoff.

For implementation work, use `superpowers:test-driven-development` when
it is available and practical: write or update a failing test first,
verify the expected red failure, implement the smallest passing change,
verify green, and refactor only while keeping tests green. Documentation-only,
generated-code, configuration-only, and throwaway prototype work
may skip TDD, but call out that exception in the handoff.

### When to push back

If a requested change violates an invariant or hard rule, stop and
surface the conflict instead of working around it. Henrik's input is
required. Examples:

- ADR-0028 says views do not import backend-specific models, but the
  requested feature appears to require that boundary crossing.
- ADR-0006 says new external network calls require explicit opt-in,
  `PRIVACY.md` documentation, and an ADR-0006 network-calls entry.

### File creation defaults

- Match the formatting and structure of existing files when adding new
  ones.
- Every Swift file in `packages/` and `apps/` starts with the MIT
  header from `file-header-template.txt`.
- Every public type and method has a doc comment explaining intent in
  one line, plus parameter descriptions when they are not obvious.
- New user-visible strings use the String Catalog convention (ADR-0058):
  `String(localized:)` / `Text(_:bundle:)` in app targets (no `bundle:`
  needed), `String(localized:bundle:.module)` / `Text(_:bundle:.module)`
  in SPM packages. Never a bare string literal in `NSAlert`, `Text`,
  `LocalizedError.errorDescription`, or similar user-facing call sites.

### Branch naming

`feature/<short-name>`, `fix/<short-name>`, `chore/<short-name>`,
`review/<YYYY-MM-DD>` for maintenance batches.

### GitHub project board

Brev work is tracked on the GitHub project board with these status
columns: `Backlog`, `Ready`, `In progress`, `In review`, and `Done`.

- When an agent starts working on an issue, move that issue/card to
  `In progress` before making code changes.
- When an agent has finished the coding work and local verification
  passes, move the issue/card to `In review`.
- Do **not** move an issue/card to `Done`. The user/maintainer moves
  it to `Done` only after QA testing and explicit acceptance.
- If the agent cannot access the GitHub project board from the current
  environment, say so in the handoff/final response and include the
  intended board status change.
- Do not close issues, move issues/cards to `Done`, publish releases,
  deploy, or change versions without explicit confirmation.
- Add or update a concise issue comment when work needs handoff, has
  blockers, or changes scope.

### Issue And PR Completion Discipline

- When work is tied to an issue, identify the issue number, target branch, and
  expected integration branch before implementation. Default integration branch
  is `development` when it exists; otherwise use repo-level instructions or
  ask.
- Before starting implementation, record the current branch/worktree and
  whether the branch already has an open PR.
- Implementation is not complete until all of these are true:
  - relevant tests/checks have run, or skipped checks are explicitly justified
  - changes are committed on a named branch
  - the branch is pushed
  - a PR exists targeting the correct integration branch, usually `development`
  - the PR description links the issue and includes verification evidence
  - project/issue status is moved to `In review` when repo rules use that state
- If the agent cannot push or create a PR because of auth, detached HEAD,
  sandbox, CI, or branch protection, it must stop with a clear handoff
  containing branch name, commit SHA, target branch, exact PR title/body,
  commands already run, and remaining manual action.
- Do not report an issue as `done`, `complete`, or `ready` when code exists
  only in an unpushed branch, local worktree, stash, or detached commit.
- When asked for progress/status, check for stale local branches, unpushed
  commits, open PRs, and issue/project status before summarizing.
- For issue work, prefer the lifecycle: branch -> implement -> verify ->
  commit -> push -> PR to integration branch -> move issue to `In review`.
- Never leave completed implementation work only in a local branch without
  either creating a PR or explicitly handing off why PR creation was blocked.
- Before final response on implementation tasks, run `git status --short`,
  `git branch --show-current`, and check whether the branch is pushed / has a
  PR when the repo uses GitHub.

### Documentation sweep

Before closing non-trivial work, explicitly check whether these need
updates:

- `README.md`: setup, architecture, repo structure, current product
  state, developer workflow, or file layout changed.
- `CHANGELOG.md`: user-facing behavior, setup, migration, packaging, or
  release-facing changes shipped. Keep internal coordination in
  `WORKLOG.md`.
- `PRIVACY.md` and ADR-0006: privacy posture, local data lifecycle, or
  external network behavior changed.
- `ADRs/`: protected paths, architectural decisions, backend/provider
  direction, distribution, privacy, or enforcement changed.
- `docs/qa/**` or `docs/releases/**`: QA evidence, runbooks, release
  procedure, packaging, or verification changed.
- `AGENTS.md`: workflow, conventions, or agent operating rules changed.
- `WORKLOG.md`: non-trivial code, docs, issue-management, or repo-state
  work was performed.

If no documentation update is needed for non-trivial work, say why in
the handoff.

### Agent worklog

Agents must append a short entry to `WORKLOG.md` for any code or
issue-management session that changes repository state.

- Use `YYYY-MM-DD — Agent — Issue/PR` headings.
- Include the goal, summary of changes, verification run, skipped
  verification with reason, and next handoff notes.
- Keep release/user-facing changes in `CHANGELOG.md`; keep agent
  coordination, partial context, and blockers in `WORKLOG.md`.
- Do not log secrets, tokens, private user data, or raw command output
  that contains credentials.

### Commit messages

Conventional Commits. Examples:

- `feat(macos): add toolbar with full keyboard shortcuts`
- `fix(avatars): handle malformed BIMI SVG payloads`
- `chore(deps): bump Tuist to 4.30.0`
- `refactor(BrevBackend): extract MailBackend protocol`
- `review: fix draft save race (#1234)`
- `docs(adr): add ADR-0010 on logging strategy`

PR descriptions and commit messages should be direct, factual, and free
of marketing language. Reference the ADR that justifies a change when an
ADR is relevant. For decisions made during implementation that did not
need an ADR but may surprise future readers, leave a short code comment
with the rationale.

### PR checklist

Before opening a PR:

1. `scripts/lint.sh` passes.
2. `scripts/format.sh` produces no changes.
3. New or changed views have snapshot tests.
4. If protected paths touched: ADR drafted/updated.
5. If new external network call: opt-in gate + ADR-0006 entry +
   PRIVACY.md update.
6. CHANGELOG.md updated under `## Unreleased`.

### Running things locally

- Generate project: `tuist generate`
- Build macOS: `tuist build BrevMacOS`
- Build iOS: `tuist build BrevIOS`
- Lint: `scripts/lint.sh`
- Format: `scripts/format.sh`
- Snapshot test record mode: `RECORD_SNAPSHOTS=YES tuist test`
- Backend package tests: `swift test --package-path packages/BrevBackend`
- Mail package tests: `swift test --package-path packages/BrevMail`
- Privacy audit: `scripts/privacy-audit.sh`
- Local test install/run diagnostics: `script/build_and_run.sh` (produces
  `Brev Test (YYYY-MM-DD).app`)
- Explicit daily-driver rebuild from clean current main only:
  `script/build_and_run.sh --install-run --release-main --live`
- Local install environment guard: `scripts/test-build-run-env.sh`

Prefer focused package tests and targeted scripts for narrow changes.
Run broader Tuist builds, lint, format, privacy audit, or release checks
when the touched surface warrants it.

## Git and worktree safety

Feature work may happen in dedicated worktrees, and multiple agent
sessions may touch the repo at once. Worktrees share the git stash stack
and object store, so broad git operations can affect another session.

- Do not run `git stash`, `git stash pop`, or `git stash apply` unless
  Henrik explicitly asks.
- Do not run `git add .`, `git add -A`, broad `git checkout`, `git pull`,
  `git merge`, `git rebase`, `git reset`, or history-rewriting commands
  unless Henrik explicitly asks for that exact operation.
- Stage only explicit paths you intentionally changed.
- Before committing, pushing, or opening a PR, run `git status`. If a
  file you did not intentionally edit appears modified or untracked,
  stop and surface it instead of resolving or committing it.
- When dispatching subagents, tell them the intended worktree path and
  require them to confirm `git rev-parse --show-toplevel` before editing.

### Branch and worktree cleanup

Agent-created branches and worktrees are temporary, but cleanup must be
evidence-based.

1. Confirm the PR is merged or the branch is contained in the updated
   target branch.
2. Confirm the target branch is current with its remote.
3. Confirm the worktree is clean with `git -C <worktree> status --short`.
4. Remove only the worktree you created with `git worktree remove
   <worktree>`.
5. Delete only the local branch you created with `git branch -d
   <branch>`.
6. Run `git worktree prune`.

Do not use `--force` or `git branch -D` unless Henrik explicitly
approves discarding local state. Never delete branches or worktrees you
did not create unless Henrik explicitly asks for that cleanup.

## How to ask for help

If a decision isn't obvious from the ADRs and invariants:

- **Tactical question** (which API to use, how to structure a view):
  proceed with the choice that best matches existing patterns in
  the codebase. Document the choice in your PR description.
- **Strategic question** (architectural decision, would-need-an-ADR):
  draft a Proposed-status ADR and open a PR with just the ADR.
  Don't write the implementation until the ADR is Accepted.
- **Ambiguous between tactical and strategic:** lean toward drafting
  the ADR. Cheaper to write a small ADR than to re-do a
  significant implementation.

## What good looks like

A model PR:

- Touches a focused area.
- Includes tests for new logic (Swift Testing for behavior,
  snapshot tests for views).
- Updates `CHANGELOG.md`.
- If protected paths: includes the ADR alongside the change.
- Passes all CI gates.
- Doesn't bundle unrelated changes ("while I was in here…" is the
  enemy of reviewable PRs).

## Reference

- All ADRs: `ADRs/`
- This file: `AGENTS.md`
- Privacy promise (user-facing): `PRIVACY.md`
- License: MIT (see `LICENSE`)
