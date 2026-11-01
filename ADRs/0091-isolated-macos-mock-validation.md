# ADR-0091: Isolated macOS mock validation

- **Status:** Accepted
- **Date:** 2026-11-01
- **Deciders:** Henrik (approved mock-only macOS isolation)

## Context

A dated test app protects the daily-driver bundle, not its shared data.
Foundation can resolve the production App Group even with an alternate HOME.
Native validation must not read or change existing mail, preferences or shared
widget data. ADR-0083's test-group isolation was not implemented by the dated
test identity alone.

## Decision

Add an explicit `--isolated-mock` mode to `script/build_and_run.sh`.
It retains the dated test app name, but generates a fresh UUID bundle identity
and private build directory for every invocation. It cannot install into
Applications, select live mode, or produce a release build.

The signed test bundle has only the App Sandbox entitlement: no App Group,
network, calendar, contacts or iCloud permissions. Remove embedded extensions
from this generated test product before signing. Production signing files and
normal test/live/release builds remain unchanged.

A stamped bundle flag forces a Debug-only, in-memory mock account/session
before production connector construction. Validate the isolated identity and
the actual sandbox home before starting SwiftUI. Missing/invalid isolation
configuration terminates startup rather than falling back to live mode.
Relaunching the same test bundle retains its isolated preferences, but cannot
switch it to a real account. Widget storage and shared attachment handoff do
not resolve any App Group in this mode; iCloud preference activation is skipped.

## Rationale

- A fresh sandbox identity isolates Foundation application support, caches,
  defaults and temporary files without redirecting production store code.
- Removing shared-group access is smaller and safer for this UI task than
  provisioning a new signed App Group. Widgets and extension handoff are not
  acceptance targets here.
- An alternate HOME alone does not isolate App Groups. A separate OS user
  would work, but adds desktop/login lifecycle changes unnecessary for this
  bounded mock validation.
- The mock session has no production restore/login coordinators or credential
  stores. The OS sandbox additionally denies direct network connections.

## Consequences

### Accepted

- This mode validates native Settings/navigation/reader interactions with
  synthetic mail. It does not validate production SQLite recovery, account
  setup, provider consent, PIM sync, widgets, share extensions, or iCloud.
- Ordinary snapshot references remain unchanged. Native interaction evidence
  does not approve hosted snapshot differences.
- Build products and sandbox data are retained for inspection and relaunch;
  cleanup must be explicitly scoped to the generated identity, never production.

### Risks

The app's sandbox home and signed entitlements must be checked on the actual
built artifact before launch. Shell and Swift negative tests guard invalid
mode combinations, production identities, shared paths and mock-only wiring.
No claim is made of machine-wide isolation or of blocking system services
outside the test process.

## References

- ADR-0004 — local builds and project layout.
- ADR-0006 — privacy and local data boundaries.
- ADR-0028 — provider-neutral UI and explicit network intent.
- ADR-0083 — widget snapshot App Group (test isolation amended here).
- Issue #269 — native acceptance remains distinct from storage acceptance.
