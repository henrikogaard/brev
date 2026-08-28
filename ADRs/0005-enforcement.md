# ADR-0005: Enforcement and automation

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev is a solo open-source project where most code will be written by
AI agents under Henrik's direction. The architectural decisions in
ADRs 0001-0006 are only valuable if they're enforced mechanically.
Without enforcement, agents drift toward the path of least resistance:
literal colors leak into views, telemetry calls sneak back in, ADRs go
unwritten.

This ADR specifies the mechanical enforcement that protects every
prior decision.

## Decision

### SwiftLint custom rules

Custom rules added to `.swiftlint.yml`. Each rule's intent is
documented inline so agents understand the *why*, not just the
pattern.

```yaml
custom_rules:
  no_literal_colors_in_views:
    name: "No literal colors in view code"
    regex: 'Color\.(?!clear)\w+|Color\(red:|Color\(#'
    match_kinds:
      - identifier
    message: "Use theme.<token>.color — see ADR-0002. Only Color.clear is allowed."
    severity: error
    included:
      - "apps/macOS/Sources/.*\\.swift"
      - "apps/iOS/Sources/.*\\.swift"
      - "packages/BrevDesign/Sources/.*\\.swift"

  no_telemetry_imports:
    name: "No telemetry library imports"
    regex: 'import\s+(Matomo|Sentry|FirebaseAnalytics|Mixpanel|Amplitude)'
    message: "Brev ships zero telemetry — see ADR-0006. Never add telemetry libraries."
    severity: error

  no_matomo_calls:
    name: "No Matomo tracking calls"
    regex: 'matomo\w*\.(track|setUserId|setView)|MatomoUtils'
    message: "Matomo is stripped from Brev — see ADR-0006."
    severity: error

  no_sentry_calls:
    name: "No Sentry calls"
    regex: 'SentrySDK|Sentry\.capture|sentryDelegate'
    message: "Sentry is stripped from Brev — see ADR-0006. Errors are logged locally only."
    severity: error

  no_hardcoded_localizations:
    name: "No hardcoded user-facing strings"
    regex: 'Text\("[A-Z][^"]{2,}"\)'
    message: "Use MailResourcesStrings or BrevStrings — localizable. Mark debug-only strings with `// debug`."
    severity: warning
    included:
      - "apps/.*\\.swift"

```

These rules run pre-commit (via `scripts/lint.sh`) and in CI. Failing
rules block commits and PRs.

### Pre-commit hooks

Installed via `.git/hooks/pre-commit` (committed as
`scripts/install-hooks.sh` since git itself doesn't version hooks):

1. `swiftformat --lint` — fail on unformatted code.
2. `swiftlint --strict` — fail on warnings.
3. `scripts/check-adr-required.sh` — see "Protected paths" below.

### Protected paths require ADRs

Changes to these paths require an ADR (new or updated) in the same
commit / PR. CI check `adr-required.yml` enforces.

Protected paths:

- Public APIs of `packages/BrevDesign/`, `packages/BrevThemes/`,
  `packages/BrevAvatars/`, `packages/BrevCalendar/`, `packages/BrevAI/`
  — anything declared `public`.
- `apps/macOS/Project.swift`, `apps/iOS/Project.swift`, top-level
  `Workspace.swift` — target structure changes.
- `.swiftlint.yml`, `.swiftformat`, `.mise.toml` — enforcement
  configuration.
- `LICENSE`, `NOTICE`, `THIRD_PARTY_LICENSES.md` — legal surface.

The CI check parses git diff for these paths and verifies the same PR
adds or updates a file in `ADRs/`. Override label `adr-not-required`
exists for genuine emergencies (build break fixes, security patches);
its use is logged in PR description.

### No-network-by-default verification

The beta gate verifies the zero-network-by-default posture through
`scripts/privacy-audit.sh`, settings-default tests, and manual smoke
checks until a runtime socket-deny harness is added. These checks
must prove optional external calls stay off by default and that
`PRIVACY.md` plus ADR-0006 match the implemented network surfaces.

If a future commit introduces a default-on network call, the PR must
either add explicit user opt-in and update `PRIVACY.md` plus ADR-0006,
or add/update the enforcement harness that blocks the regression.

## Rationale

**Why mechanical enforcement, not "we'll be careful."** Solo project
with AI agents means "careful" doesn't scale. Mechanical rules scale.

**Why custom SwiftLint rules over more elaborate static analysis.**
SwiftLint is already a dependency, agents understand it, CI runs it.
Custom rules are sufficient for the rules we care about. SwiftSyntax-
based tooling is overkill for v1.

**Why ADR-required for protected paths, not all paths.** Most file
changes are routine. ADR-gating everything would make the project
unworkable. Protected paths are the ones where wrong decisions
propagate: sync engine, public APIs, target structure, legal
surface.

**Why the provider review agent runs weekly, not on-demand.** Cadence
matches the rate of provider change. Daily is noise; monthly is too
slow to catch security-relevant fixes. Weekly fits the
"acknowledge and decide" rhythm.

## Consequences

### Accepted

- Some friction adding ADRs for protected-path changes. Mitigation:
  prompt template `prompts/new-adr.md` to make drafting fast for
  agents.
- CI surface grows: lint, format, test, snapshot, build, ADR check.
  ~5-10 min total CI time per PR. Acceptable.
- Snapshot tests must be regenerated on every intentional visual
  change. Documented in `scripts/`.

### Risks

- **False positives in custom SwiftLint rules.** Regex matching is
  imprecise. Mitigation: rules are added incrementally; false
  positives get refined or `// swiftlint:disable next_line
  rule_name` annotations with justification.
- **Rules drifting from the architecture.** Enforcement can become stale
  after large refactors. Mitigation: protected-path changes include ADR
  updates, and review tasks audit rule wording against the current graph.

## References

- ADR-0002: Theme system (no literal colors rule)
- ADR-0006: Telemetry and GDPR compliance (rules enforce zero telemetry)
- prompts/new-adr.md
