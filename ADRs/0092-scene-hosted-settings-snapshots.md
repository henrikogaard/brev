# ADR-0092: Scene-hosted iOS Settings snapshots

- **Status:** Accepted
- **Date:** 2026-11-01
- **Deciders:** Henrik (approved capture diagnostic and confirmed harness repair)

## Context

The Settings form fixtures use an unhosted layer capture. A synthetic native
comparison on iOS 26.5 (23F73), Xcode 26.6 (17F113), SDK 26.5 (23F81a)
reproduced missing UIKit and SwiftUI switch thumbs in both appearance modes.
Genuine scene-hosted hierarchy drawing retained the visible thumbs and returned
success. Three captures per mode and method were stable. This establishes a
capture-path defect, not a defect in the production controls or a complete
explanation of hosted reference differences. The hosted runtime was 23F77.

## Decision

1. Give the existing iOS Settings form tests a dedicated synthetic app host,
   separate from the shipping app and its startup, entitlements, account stores,
   extensions and provider integrations. Keep the fixture source and committed
   references in place; remove this suite from the unhosted package target.
   Reuse the shipping iOS static asset catalog so Settings' main-bundle icon
   previews are available; this shares artwork, not app initialization or
   entitlements. Require every icon preview to resolve in the host bundle.
2. Attach each fixture to a real foreground scene/key window. Fix dimensions,
   scale, size class, content size, language and appearance. Wait for layout and
   display completion, then require successful hierarchy drawing. Do not fall
   back to layer rendering. Preserve strict image comparison and restore the
   previous window after capture, including on errors.
3. Require three pixel-identical consecutive display frames within a bounded
   60-frame budget, failing on display timeout or continued pixel changes.
   Exercise ordinary and tall accessibility canvases, checking switch-thumb
   contrast at their top and bottom rather than dimensions alone.
   A working small synthetic probe alone is not acceptance of actual
   Settings panes or off-screen portions of tall fixtures.
4. Pin and log Xcode, SDK, runtime build, device and renderer for the dedicated
   iOS job. Fail closed when those prerequisites differ. Local diagnostics may
   explicitly select another runtime build, but must identify that deviation
   and cannot stand in for the pinned CI run.
   The initial CI profile is Xcode 26.6/17F113, SDK 26.5/23F81a,
   runtime 26.5/23F77, and iPhone 16e. The device is deliberately aligned with
   the synthetic diagnostic, not silently inferred from old reference names.
5. Keep candidate recording separate from verification. Candidates go only to
   diagnostic attachments, never over committed references. All reference
   changes still require separate visual acceptance. No production control,
   macOS capture strategy or existing precision is changed by this decision.
6. Compile the same seeded pane fixtures into the synthetic host and tests.
   An explicit review-only launch selects Appearance, Notifications, consent
   or PIM and a light/dark/accessibility variant; invalid selections fail closed.
   Use isolated resettable defaults and in-memory account, PIM and credential
   stores, with no provider authorization or network-capable fixture clients.
   This host still pins appearance and does not validate production System mode.
7. Preserve the existing top-of-pane geometry, names and references. Add
   bottom-of-form diagnostic captures for icon cards, lower Notifications
   content and lower PIM sources/collections. Locate one outer scroll view,
   enforce its current bottom offset
   through layout settling, and retain the existing draw/stability guards.
   These supplemental attachments are review coverage, not approved references
   or a substitute for native inspection of the requested content.
   Native review reached the final CalDAV source, calendar and footer outside
   the canonical PIM viewport; include these in supplemental coverage without
   changing the single-line collection layout or accepting its AX3 truncation.

## Rationale

Changing controls to suit incomplete captures would alter working native UI.
Enabling a key-window flag in an unhosted package does not supply a real scene.
A small app host avoids launching production initialization just to draw
synthetic settings. Explicit provenance prevents comparisons across silently
selected runtimes from being mistaken for source regressions.

## Consequences

The suite must run through its dedicated app-hosted scheme, not `swift test`.
Its CI remains a blocking visual gate even while old references disagree.
Rendering correctness and reference acceptance are separate: neither a green
synthetic canary nor candidate output accepts the visual baselines. Native
screenshots and render images can have different pixel scales; compare equal
point-space regions rather than asserting cross-method byte equality.

## References

- ADR-0004: Build system and project layout
- ADR-0005: Enforcement and automation
- ADR-0006: Telemetry and privacy
- ADR-0091: Isolated macOS mock validation (separate platform and scope)
- `packages/BrevSettings/Tests/BrevSettingsTests/SettingsFormSnapshotTests.swift`
- `.github/workflows/settings-native-review.yml`
