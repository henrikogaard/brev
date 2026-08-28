# ADR-0062: Localization and extension lint coverage

- **Status:** Proposed
- **Date:** 2026-08-25
- **Deciders:** Henrik

## Context

ADR-0058 defines the String Catalog conventions for Brev's app targets and
SPM packages. The initial enforcement covered the main app source roots and
the packages converted in that change, but it did not include the build-time
example plugin or the two iOS extensions. A rule that is not applied to those
paths can silently regress: plugin UI can reintroduce literal colors and
package-bundle mistakes, while extension UI can gain unlocalized UIKit copy.

The SwiftLint configuration also listed several style rules in both
`disabled_rules` and `opt_in_rules`. SwiftLint treats a disabled rule as
disabled, so the duplicate entries obscure the actual policy and make future
configuration changes error-prone.

## Decision

1. Include `Plugins/**`, `apps/iOS/BrevShareExtension/**`, and
   `apps/iOS/BrevNotificationContent/**` in the authoritative SwiftLint input
   roots.
2. Apply the existing literal-color and hardcoded-view-string checks to those
   roots, and apply the package-local String Catalog bundle check to plugin
   package sources. Keep extension strings on the app-target
   `String(localized:)` convention from ADR-0058.
3. Keep style-only rules that are intentionally disabled out of
   `opt_in_rules`; a rule has one explicit state rather than contradictory
   duplicate entries. No existing error-level architecture, privacy, or
   telemetry gate is weakened.
4. Add a deterministic self-test that asserts the configured roots and rules,
   checks that disabled/opt-in lists are disjoint, and proves that synthetic
   violations in each newly covered root are reported by the configured
   custom rules.
5. The example plugin continues to depend only on BrevPlugins and SwiftUI.
   It uses semantic system ShapeStyles where it needs a secondary border and
   resolves package UI copy through its own String Catalog (`bundle: .module`)
   rather than importing Brev's theme package.

## Rationale

Extending the existing rules keeps enforcement centralized and avoids a
second, subtly different lint policy for extensions and plugins. Importing
`BrevThemes` into the standalone example plugin would violate ADR-0031's
low-dependency boundary; SwiftUI semantic styles remain theme-safe because
the host controls the environment and system appearance.

Removing only contradictory duplicate rule entries preserves the existing
intentional style debt allowance while making the effective configuration
auditable. A self-test catches accidental path removal before a new source
root can bypass the policy.

## Consequences

### Accepted

- New plugin and extension source files are covered by the same localization,
  literal-color, privacy, and architecture gates as the corresponding app or
  package code.
- The example plugin gains a package-local catalog and resource declaration.
- Lint self-tests add a small deterministic shell check to the normal lint
  workflow.

### Risks

- Existing style-only violations in newly included roots may surface as
  warnings when their rules are enabled in the future. The self-test does not
  suppress real source findings.
- Synthetic lint fixtures require SwiftLint to be available through the
  pinned toolchain; the script reports that prerequisite clearly.

## References

- ADR-0005: Enforcement and automation
- ADR-0031: UI Extension Plugin API
- ADR-0058: Localization via String Catalogs
- `.swiftlint.yml`
- `scripts/test-swiftlint-coverage.sh`
