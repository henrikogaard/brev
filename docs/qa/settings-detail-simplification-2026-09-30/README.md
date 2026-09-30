# Settings detail simplification — 2026-09-30

The Privacy & Security and Calendar & Contacts detail panes now lead with the
controls people actually change; reference material sits behind one disclosure
each and stays reachable from settings search. The Calendar & Contacts copy now
matches shipped scope instead of the earlier roadmap wording.

Branch `feature/settings-detail-simplification`, based on `main` at `d96fd4d9`.

## What changed

| Surface | Change |
| --- | --- |
| Privacy & Security → Security (macOS) | Record summary rows stay visible. The full key-material record list, the draft editor, and the destructive actions sit behind **Administrer nøkkelmateriale**; the two import/export toggles sit behind **Avansert**. |
| Calendar & Contacts | Capability lists moved into a **Funksjoner og veikart** disclosure. Browsing and authoring capabilities moved to "Tilgjengelig nå"; only scoped PIM search remains "Ikke tilgjengelig ennå". The old info callout is replaced by a direct subtitle. The Google capability row reuses the Sources-list label ("Google Calendar & Contacts"); its Norwegian rendering is unchanged, so the captured screenshots still apply. |
| Settings search | New Calendar & Contacts keywords (`Kilder`, `Legg til DAV-kilde …`, capability titles). A search result that targets a row inside a disclosure expands that disclosure on arrival. |
| Security (iOS) | Unchanged by design: iOS renders only the platform-availability group, so the disclosure work does not apply there. Checked for no regression. |
| `README.md` | Calendar/Contacts/Tasks status corrected to shipped-with-limitations. |

## Verification states

| State | Status | Evidence |
| --- | --- | --- |
| Implemented locally | Done | `swift test --package-path packages/BrevSettings` — 434 tests / 66 suites; the 29 remaining issues are pre-existing snapshot-renderer mismatches that reproduce identically on `main` (see the snapshot note). |
| CI-verified | Done | All 21 required checks pass on PR #168 (run [36765681298](https://github.com/henrikogaard/brev/actions/runs/36765681298), head `a477a9cd`); the docs-only commit carrying this note re-runs the same set. |
| Native-tested (macOS) | Done | Rendered QA on `Brev Test (2026-09-30)`, AX-verified, plus a real app restart for persistence. |
| Native-tested (iOS simulator) | Done | Brev QA iPhone 17 Pro (iOS 27.0): default state, search-expansion, and Security no-regression checks below. |
| Physical-device-tested | Not done | No physical iPhone is available in this environment. |
| Live-provider-tested | Not applicable | No provider or network behavior changed. |

Snapshot note: the macOS snapshot baselines were recorded on macOS 26 or
newer; this host runs macOS 27.0. An unmodified `origin/main` checkout fails
the same 29 issues (37 parameterized cases) with a byte-identical failure
list, so they are environmental, not branch regressions. CI skips these
suites below macOS 26 and runs a dedicated snapshot job on a compatible
host (`.github/workflows/build.yml`).

## macOS evidence

Build: `Brev Test (2026-09-30)`, mock mail, Norwegian UI.

| Check | Result | Screenshot |
| --- | --- | --- |
| Security summary rows visible; both disclosures collapsed by default | Pass | [Collapsed](macos-security-collapsed.png) |
| Both disclosures expand and render the full record list and import/export toggles | Pass | [Expanded](macos-security-disclosures-expanded.png) |
| Calendar & Contacts new subtitle renders; disclosure collapsed by default | Pass | [Collapsed](macos-calendar-contacts-collapsed.png) |
| Disclosure expands to 11 "Tilgjengelig nå" rows and 1 "Ikke tilgjengelig ennå" row | Pass | [Expanded](macos-calendar-contacts-expanded.png), [scrolled](macos-calendar-contacts-expanded-scrolled.png) |
| Settings search ("privat materiale", "Tilgjengelig nå") navigates and expands the owning disclosure | Pass | AX-verified in the same session |
| QA metadata record created, rendered, and deleted cleanly | Pass | Metadata-only record; removed after the check |
| Persisted values survive a real app restart | Pass | Same session; settings unchanged after relaunch |

## iOS simulator evidence

Simulator: Brev QA iPhone 17 Pro (iOS 27.0), same branch build, Norwegian UI.

| Check | Result | Screenshot |
| --- | --- | --- |
| Fresh navigation: Calendar & Contacts shows the new subtitle and Sources, disclosure collapsed by default | Pass | [Default](ios-calendar-contacts-default.png) |
| Settings search for "Tilgjengelig" lists the capability results | Pass | [Results](ios-settings-search-results.png) |
| Tapping "Tilgjengelig nå" opens Calendar & Contacts with **Funksjoner og veikart** expanded and all capability rows rendered (AX-verified) | Pass | [Expanded](ios-search-target-expanded.png) |
| Security pane unchanged: platform-availability group only, no key-material controls | Pass | [Security](ios-security-platform-availability.png) |

Interaction note: simulator taps for this pass were driven through the
`serve-sim` mirror; AXe typing accepts US keyboard characters only, so the
search query used "Tilgjengelig" (the result title is "Tilgjengelig nå").

## Skipped checks

| Check | Reason |
| --- | --- |
| macOS snapshot suites on this host | Pre-existing renderer mismatch: baselines are macOS 26+; this host is macOS 27.0. Failure set is byte-identical on `main`. |
| Physical iPhone cold launch | No physical device in this environment. |
| Live provider round-trip | No provider behavior changed; the QA record was metadata-only. |

## Related documents

- [Main verification 2026-09-29](../main-verification-2026-09-29.md)
- [TestFlight UI/UX 2026-09-29](../testflight-uiux-2026-09-29.md)
- [Settings assessment 2026-09-29](../settings-assessment-2026-09-29/README.md)
- [Navigation polish 2026-09-29](../navigation-polish-2026-09-29/README.md)
- [UI/UX fixes 2026-09-29](../uiux-fixes-2026-09-29/README.md)
