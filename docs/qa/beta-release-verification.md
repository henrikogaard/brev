# Beta Release Verification Checklist

Umbrella checklist for maintainer-only open issues that require signed builds,
clean install environments, or live provider accounts. Code paths are already on
`main`; these items close only after supervised QA.

## Issues covered

| Issue | Runbook | Owner |
| --- | --- | --- |
| #6 macOS beta packaging | `docs/release.md` | Release machine |
| #98 Clean install verification | `docs/qa/desktop-smoke.md` | Maintainer QA |
| #256 Server search | `docs/qa/live-issue-256-server-search.md` | Maintainer QA |
| #257 Settings storage | `docs/qa/live-issue-257-settings-storage.md` | Maintainer QA |
| #282 Provider onboarding | `docs/qa/live-issue-282-provider-onboarding.md` | Maintainer QA |

## Recommended order

1. **#6** — produce signed/notarized DMG from a clean checkout (`docs/release.md`).
2. **#98** — install DMG in a clean macOS user account; run `docs/qa/desktop-smoke.md`.
3. **Parallel QA afternoon** — execute #282, #256, and #257 runbooks against
   redacted disposable accounts.
4. Record results under `docs/qa/results/` and move issues to `In review` only after
   evidence is attached.

## Automated preflight before live QA

```sh
scripts/beta-readiness.sh --full
scripts/performance-budget-gate.sh --self-test
swift test --package-path packages/BrevMail --filter 'MailboxStorageInfo|MessageListSearch'
```

## Cannot be closed by code-only PRs

These issues need human verification with signing credentials and real mail
accounts. Implementation PRs should link here instead of claiming
closure without maintainer acceptance.
