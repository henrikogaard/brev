# Calendar/Contacts parity evidence v4 — 2026-10-15

**Bottom line:** the exact first-occurrence recurrence retest passed at
`9cb1cd9`; independent populated accessibility testing then stopped at a
reproducible AX3 action-label layout defect. This is not full #11/#3 acceptance.

| Provenance | Value |
| --- | --- |
| Scope | [PR #245](https://github.com/henrikogaard/brev/pull/245), [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3) |
| Approved/tested revision | `9cb1cd9737ea69dc7068b70e39f42bab749dbe89` |
| Checkout | `/Users/devin/repos/brev-pim-parity`, `fix/pim-parity-gaps` → `main`; clean at start |
| Authorization | Parent resumed the exact retest under Henrik's “yes, keep working and get the work done”; independent iOS/stub continuation conditional on passing it |
| Device | Owned iPhone 17 simulator, iOS 27.0, `Brev PIM v3 20261015 A`, UDID `0AAE0F16-6167-435E-884F-C0BA50E05A67` |
| Build | Targeted BrevIOS Debug rebuild using Xcode 27 RC, existing owned DerivedData, `CODE_SIGNING_ALLOWED=NO`, `-skipMacroValidation` |
| Runtime | `eu.brevmail.brev.ios`, `BREV_USE_MOCK=1`, English; same-process synthetic DAV credentials |
| Provider | Existing owned loopback DAV stub, `127.0.0.1:18643`; not live-provider evidence |
| Preserved history | [v2](pim-parity-v2-2026-10-15.md), [v3](pim-parity-v3-2026-10-15.md), their artifacts and failing v3 records preserved |
| Session | [Devin session](https://app.devin.ai/sessions/930e6447745b410bb056d921d709803a) |

## New finding and stop condition

| Item | Runtime evidence |
| --- | --- |
| Finding | Populated event-detail actions are squeezed into narrow columns at accessibility-extra-large (AX3). “Delete” renders as `Del / ete`; “Copy Link” as `Co / py / Lin / k`. |
| Reproduction | Open the corrected owned event, English/dark, default Large → AX3. Restore Large: normal row. Reapply AX3: same broken word wrapping. |
| Impact | Readability/layout defect at an accessibility text size. No assertion that actions are inoperable, data is lost, or VoiceOver fails. |
| Narrow proposal | Make `CalendarEventDetailView.actionRow` adapt to a vertical layout at accessibility sizes/insufficient width, preserving full labels and font scaling. Its current fixed horizontal layout is the likely constraint. |
| Decision | Parent review required before a fix or further runtime continuation. The runner made no product changes. |

The primary recording below covers the corrected recurrence flow. The subsequent
AX3 finding is demonstrated by the screenshot comparison, not by another video.
All Devin attachment links and images require access to the originating session;
they are **not public or portable GitHub embeds**.

| Default Large — reference | AX3 — reproduced failure |
| --- | --- |
| ![Event actions at default Large, English and dark](https://app.devin.ai/attachments/f3a3d8e8-7238-482f-b124-6d076ed66a5c/04-en-dark-default-actions.png) | ![Event action labels wrap into fragments at AX3](https://app.devin.ai/attachments/86aebb4a-83e3-4528-8a24-50ff92e72d1c/05-en-dark-ax3-actions.png) |

## Required baseline and exact recurrence retest

Before reset, all four active v3 calendar payloads and the owned PIM cache/source
metadata were archived outside the checkout in `preserved-v3`. Only run-owned
calendar fixtures were reset: the old split duplicate and Alpha/Beta siblings
were removed, and the original series was reseeded from its original fixture.
Owned contact fixtures were retained.

The new binary required an owned-app relaunch. A first sync reported
“The source has no stored credential. Reconnect it first.” This is expected
process-only mock credential behavior, not a persistent-Keychain product failure.
The Calendar source was reconnected through UI with synthetic credentials.

The stub's delta response does not emit tombstones for its DELETE operation;
therefore the first sync retained four cache entries. Expiring the owned stub
cursor and syncing caused REPORT 403 → full REPORT 207, rebuilding the cache to
one original record. Server enumeration, cache payload and visible list then
agreed **before** recording and editing. No baseline was substituted.

| Identity/invariant | Baseline | After both saves and explicit sync |
| --- | --- | --- |
| Server/cache count | 1 / 1 | 1 / 1 |
| Visible list | One original series row | One updated series row |
| UID | `brev-pim-20261015-a-series` | Same |
| Provider key | `http://127.0.0.1:18643/cal/u/main/v3-series.ics` | Same |
| Internal ID | Source/collection/provider-key composite | Same |
| DTSTART | `20261015T190000Z` | Same |
| DTEND | `20261015T193000Z` | Same |
| RRULE | `FREQ=DAILY;COUNT=5` | Same |
| UNTIL | Absent | Absent |
| Summary | `brev-pim-20261015-a Series` | `brev-pim-v4 Future Updated` |

The simulator displays these UTC times as 12:00–12:30 PM local time.

| Exact action/assertion | Result |
| --- | --- |
| Edit only title to `brev-pim-v4 All Events`; Save → All Events | Passed: conditional PUT 204 to original href; detail shows updated title and five repeats |
| Return to list, reopen same event; edit only title to `brev-pim-v4 Future Updated`; Save → This and Future Events | Passed: conditional PUT 204 to the same href; dates unchanged |
| Return to list; press Sync calendars now | Passed: REPORT 403 → full REPORT 207 recovery; single updated row remains |
| Reopen updated detail after sync | Passed: updated title, original time range, “Every Day 5 times” |
| Inspect server enumeration, raw ICS and cache after sync | Passed: one record, same UID/provider key/internal ID/dates/count, no UNTIL and no new split resource |

This proves the specified first-occurrence title-edit case, not later-occurrence
splitting, moving to another calendar, recurrence expansion or future-scope
deletion. One stored master row is not proof of five expanded occurrence rows.

[Primary annotated recording — session access required](https://app.devin.ai/attachments/f8f44806-178c-4a42-8b64-8e1883355b39/pim-v4-ios-primary-edited.mp4).

| 🔴 Before — original fixture | 🟢 After — both scopes and explicit sync |
| --- | --- |
| ![Single original series baseline](https://app.devin.ai/attachments/c671bf7a-ffc4-4f83-a043-9c672537d46b/01-baseline-calendar.png) | ![Single updated series after explicit sync](https://app.devin.ai/attachments/57a4aa29-4551-404d-b5e7-e2dfb933f53d/02-post-sync-single-row.png) |

[Updated event detail after sync — session access required](https://app.devin.ai/attachments/c5ee5a5c-dbd1-4b91-90c8-44b1af61cbef/03-post-sync-detail.png).

## Coverage and remaining acceptance

| Layer/row | Current v4 outcome |
| --- | --- |
| Exact iOS/stub recurrence regression | Passed as detailed above |
| Cursor expiry/full cache rebuild | Limited positive evidence during baseline setup and explicit sync: 403 → 207, one correct accepted generation. Full independent-source/cursor matrix not executed. |
| Populated English/light Calendar list/detail/editor | Exercised in exact regression |
| Populated English/dark event detail, default Large | Rendered normally |
| Populated English/dark event detail, AX3 | Failed action-label layout; reproduced by toggling size twice |
| AX-label inspection | Limited: editor title and fields, scope buttons and Sync control exposed through simulator accessibility. Detail inspection returned an “Event details” container, not a complete child traversal. This is not actual VoiceOver/readback evidence. |
| Populated Contacts, NB, additional light/dark/size/editor permutations | Not executed in v4 after stop condition; v3 evidence remains historical |
| Reduced motion, actual VoiceOver/readback | Not executed; no simulator AX-label result substituted for spoken output |
| Independent-source failure and keep/delete-cache source removal | Not executed after stop condition |
| Search/offline cached reads | v3 evidence preserved; not needlessly repeated |
| Automated checks | Parent's focused regression/editing/draft checks and settled v2 baseline inherited, not rerun by this runtime runner |
| macOS | Not launched: inherited app-group resolution points to shared host storage despite home redirection |
| Live Google/DAV | Not attempted; safe isolated account/signing and dedicated DAV configuration gates remain. No new login challenge claimed. |
| Signed Keychain / physical iPhone | Not tested; unsigned simulator and same-process mock credentials do not establish either |
| #11/#3 acceptance | Still pending provider/platform matrix and Henrik's explicit sign-off |

## Artifacts and reusable state

All local paths below are on the originating host and are not portable repository
evidence. Images/video above are Devin-hosted, session-access-restricted links.
No binary artifact is tracked.

| Artifact | Absolute path |
| --- | --- |
| Primary recording | `/Users/devin/screencasts/pim-v4-ios-primary/pim-v4-ios-primary-edited.mp4` |
| Evidence root | `/Users/devin/pim-parity-evidence/v4-20261015-a/` |
| Screenshots | Evidence root: `01-baseline-calendar.png`, `02-post-sync-single-row.png`, `03-post-sync-detail.png`, `04-en-dark-default-actions.png`, `05-en-dark-ax3-actions.png` |
| Identity proof | Evidence root: `baseline-cache-events.json`, `baseline-server-series.ics`, `baseline-server-list.xml`, `post-sync-cache-events.json`, `post-sync-server-series.ics`, `post-sync-server-list.xml` |
| Preserved v3 state | Evidence root: `preserved-v3/` including original and split ICS payloads plus PIM cache/source metadata |
| Setup/runtime evidence | Evidence root: `ios-build.log`, `runtime-identity.txt`, `dav-requests-snapshot.log`, `test-plan.md` |
| Active stub log | `/Users/devin/pim-parity-evidence/v3-20261015-a/dav-requests-resumed.log` |

| Reusable resource | State at handoff |
| --- | --- |
| App | PID `7682`, running on owned UDID above; English/dark/AX3 event detail left visible |
| Stub | PID `5246`, port `18643`; original owned service reused, not restarted |
| Stub wrapper | `/Users/devin/pim-parity-evidence/v3-20261015-a/timestamp-stub.py` |
| Seed directory | `/Users/devin/pim-parity-evidence/v3-20261015-a/seed` (original fixtures; active in-memory server contains corrected series and retained contacts) |
| DerivedData | `/Users/devin/pim-parity-evidence/v3-20261015-a/ios-derived` |
| App data root | `/Users/devin/Library/Developer/CoreSimulator/Devices/0AAE0F16-6167-435E-884F-C0BA50E05A67/data/Containers/Data/Application/B36BFA97-ECA8-4226-9454-B9443671B33D` |
| Credential caveat | Calendar was reconnected in the current process; a relaunch loses mock credentials. Contacts were not reconnected in v4. No credential persistence claim. |

Do not restart the stub expecting the edited in-memory state to persist, or
target generic `booted` on this shared host. Other simulators and daily-driver
storage were not touched. Only this owned device's appearance/text size changed;
no host-global accessibility preferences changed.

## Handoff and publication

- Parent decision: review the narrow AX3 action-layout proposal before product
  work or remaining runtime rows. This finding is newly reproduced here, not
  evidence that the recurrence fix introduced it.
- Maintainer gates remain: isolated macOS user/approved app-group configuration;
  usable signing and physical-device access; approved dedicated DAV endpoints,
  credential references, synthetic collections and invitation recipient; safe
  Google identity/consent setup and final provider/platform acceptance.
- The runtime runner did not run repository lint/format/diff checks or
  commit/push; its runtime checks are reported above. The subsequent
  publication phase passed `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
  `git diff --check`. One documentation-only commit,
  `docs(qa): record recurrence retest and accessibility findings`, was pushed
  once to `origin fix/pim-parity-gaps`. Tested source revision
  `9cb1cd9737ea69dc7068b70e39f42bab749dbe89` is distinct from this publication
  commit. No CI was dispatched or watched.
- No new skill or blueprint edits. Existing blueprint was reread; tools and
  targeted Xcode build route were reused. Prior shared-host safety suggestions
  remain in v3; this pass adds no setup dependency.
- Documentation sweep: only QA evidence and WORKLOG change. Product behavior,
  privacy/network policy, architecture, release/version, README and AGENTS
  require no update for this runtime-only pass. Drive remains out of scope.
