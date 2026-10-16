# Calendar/Tasks parity evidence v7 — 2026-10-15

**Bottom line:** the bounded synthetic runtime procedure was executed, but
recurrence expansion failed: fresh daily COUNT5 series rendered only their
masters, and the actual third occurrence was unavailable. Later-occurrence
future edit/delete were therefore not attempted. Independent Calendar/Tasks
keep-cache and separate delete-cache checks passed. The AX3 scroll-under
check did not reproduce a persistently untappable action. This is not full
#11/#3 acceptance, live-provider parity or a full automated-check pass.

| Provenance | Value |
| --- | --- |
| Scope | [PR #245](https://github.com/henrikogaard/brev/pull/245), [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3) |
| Approved checkout HEAD | `3a784926563571a59e60b552ce4e7cf6180436d9` |
| Product revision running | `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f`, unchanged from v6 |
| Checkout | `/Users/devin/repos/brev-pim-parity`, `fix/pim-parity-gaps` → `main`; clean before this evidence append |
| Authorization | Parent-approved bounded v7 under Henrik's ongoing “yes, keep working and get the work done”; new distinct disposable fixtures explicitly permitted |
| Device | Owned iPhone 17 simulator, iOS 27.0, `Brev PIM v3 20261015 A`, UDID `0AAE0F16-6167-435E-884F-C0BA50E05A67` |
| Runtime | Existing app PID `24123`, `eu.brevmail.brev.ios`, mock session; no rebuild, reinstall or relaunch |
| Variants | NB/dark; Large for lifecycle/recurrence, then restored AX3 (`accessibility-extra-large`) for the bounded chrome check |
| Time basis | Payloads explicitly UTC; display rendered 17:00Z as 10:00 and 18:00Z as 11:00, UTC−07:00. Host readback was PDT −0700; no independent simulator time-zone-name assertion |
| Runtime interval | Preflight `20:30:43.859603Z`; final identity/hash snapshot `20:55:21.979753Z`, 2026-10-15 |
| Evidence root | `/Users/devin/pim-parity-evidence/v7-20261015-a/` |
| Previous evidence | [v2](pim-parity-v2-2026-10-15.md), [v3](pim-parity-v3-2026-10-15.md), [v4](pim-parity-v4-2026-10-15.md), [v5](pim-parity-v5-2026-10-15.md), [v6](pim-parity-v6-2026-10-15.md), all preserved |
| Session | [Devin session](https://app.devin.ai/sessions/46f25327f307421b85d764d1f7064342) |

All attachment URLs in this report require access to the originating Devin
session. They are **not public or portable GitHub embeds**. No binary artifacts
were added to the checkout.

## Isolation and verified starting states

The existing simulator/app and all prior stub processes were reused. Four
new loopback-only sources used the existing repository DAV stub and existing
external wrapper, without product or harness changes. Tasks provisioning
worked through the existing Tasks (CalDAV) form and VTODO support.
All connections and source removals were performed through app UI.

Before provisioning, the runner copied the active registry and all existing
source/cache files outside the checkout. Original Charlie's frozen state
matched v6. At final readback, all prior source/cache bytes **and modification
times** were unchanged; the active registry equaled its preflight contents.
No prior source was reconnected, recreated, synced, removed or edited.
Alice was only read/opened in the editor and canceled for the AX3 check.

| Frozen identity | Before and final value |
| --- | --- |
| Charlie source | `pim-16183cbc-a8f9-4408-94dc-a15251887d9f` |
| Charlie UID | `brev-pim-20261015-v5-disposable` |
| Provider key | `http://127.0.0.1:18644/card/u/main/v5-disposable.vcf` |
| Cache SHA-256 | `9479d0752b7e5bdc5f46395f86018f85cd107bfd21050f2d2f590b25e5a0f36f` |
| Provider SHA-256 | `3472d57f9af79787d08922fc9a3354845d1e1e949c47fd1e4204561156a2d3e0` |
| State | Removed, disconnected marker preserved, no active-source entry; never reconnected/recreated/deleted |
| Original active Calendar | `pim-046b9749-9093-4787-b976-774c00b95c96`, unchanged |
| Original active Contacts | `pim-538b1860-aaff-418a-84f2-2cb20580b4e7`, unchanged |

### New source identities

| Fixture | Source ID | Endpoint and initial state |
| --- | --- | --- |
| Calendar Keep | `pim-d960dd59-0170-43c0-8757-bd2fb8e3ff76` | `http://127.0.0.1:18646/`; three VEVENTs, read/write enabled before runtime |
| Tasks Keep | `pim-2f6be63c-ee6d-47aa-94b7-b2aa073af946` | `http://127.0.0.1:18647/`; one VTODO, read/write enabled before runtime |
| Calendar Delete | `pim-171af11a-3533-4aca-a9b0-f764c8d7a914` | `http://127.0.0.1:18648/`; separate one-event source, read/sync enabled |
| Tasks Delete | `pim-e5251cd1-ace0-4bb3-803a-094ea5c9a713` | `http://127.0.0.1:18649/`; separate one-task source, read/sync enabled |

For every new record:

- Collection URL is `http://127.0.0.1:<port>/cal/u/main/`.
- Provider key is that collection URL plus the filename below.
- Collection ID is the exact source ID + `|` + collection URL.
- Composite record ID is the exact source ID + `|` + collection URL + `|` +
  provider key. No replacement IDs were used.
- Exact links use `brev://event?id=<percent-encoded composite ID>` or
  `brev://task?id=<percent-encoded composite ID>`.

`keep-baseline.json` and `delete-baseline.json` preserve the full original
source/collection/record IDs, provider versions, raw payloads and cache hashes.
The `*-link.txt` files preserve the exact correctly encoded links.

| Filename / UID suffix | Full UID | Dates and purpose |
| --- | --- | --- |
| `v7-future-edit.ics` | `brev-pim-20261015-v7-future-edit` | DTSTART `20261016T170000Z`, DTEND `20261016T173000Z`, `FREQ=DAILY;COUNT=5` |
| `v7-future-delete.ics` | `brev-pim-20261015-v7-future-delete` | DTSTART `20261016T180000Z`, DTEND `20261016T183000Z`, separate `FREQ=DAILY;COUNT=5` |
| `v7-calendar-keep.ics` | `brev-pim-20261015-v7-calendar-keep` | October 16, 19:00–19:30Z; nonrecurring keep-cache event |
| `v7-tasks-keep.ics` | `brev-pim-20261015-v7-tasks-keep` | Due October 20, 19:00Z, `NEEDS-ACTION`; retained task |
| `v7-calendar-delete.ics` | `brev-pim-20261015-v7-calendar-delete` | October 16, 20:00–20:30Z; separate local-delete fixture |
| `v7-tasks-delete.ics` | `brev-pim-20261015-v7-tasks-delete` | Due October 21, 19:00Z, `NEEDS-ACTION`; separate local-delete fixture |

The keep baseline was verified at `20:37:58.906450Z`: four cached records
matched the provider/seed payloads exactly, both sources were writable, and
the two masters had COUNT5 with no RECURRENCE-ID or split duplicates.
The separate delete sources were not connected until after both keep-cache
proofs. Their two cache records matched their own seeds at
`20:47:37.692777Z` and appeared in their normal lists before removal.

## Recurrence expansion failure and blocked later-scope actions

| Assertion | Expected | Observed |
| --- | --- | --- |
| Edit series expansion | October 16, 17, 18, 19, 20 at 17:00–17:30Z / 10:00–10:30 local | Master appeared October 16; October 18 day grid was empty |
| Delete series expansion | Same five dates at 18:00–18:30Z / 11:00–11:30 local | Master appeared October 16; October 18 day grid was empty |
| Agenda/month/day consistency | Selectable occurrences on the later dates | Agenda showed master rows only; month overview did not show the expected later entries; opening October 16 showed masters, navigating twice to October 18 showed neither |
| Actual third-occurrence selection | Select October 18 without changing master DTSTART | **Failed/unreachable:** no actual third-occurrence row or grid item |
| Future edit | Original UID/provider retains unchanged October 16–17; fresh UID covers edited October 18–20, no overlap/extra occurrence/invalid UNTIL | **Untested:** blocked by selection; no edit was attempted |
| Future delete, separate series | Preserve original October 16–17; remove October 18–20 without mutating unrelated records | **Untested:** blocked by selection; no delete was attempted |
| Provider/cache preservation | Freeze affected recurrence payloads | **Passed:** original COUNT5 payloads/UIDs/provider keys unchanged; no PUT or DELETE |

Search was empty and the collection was visible. October 19/20 were not
individually opened after the decisive October 18 failure. No master DTSTART
was moved to manufacture a later occurrence. No provider-only expansion was
substituted for visible UI proof, and no split/count correctness is claimed.
The subsequent approved keep-cache removal preserved all three Calendar
records, including both unchanged masters, as read-only retained data.

| October 16 — both master rows render | October 18 — expected third occurrences missing |
| --- | --- |
| ![October 16 masters at 10 and 11 local](https://app.devin.ai/attachments/be151c77-79ee-46ec-891d-c4f0377cfb65/03-calendar-oct16-masters-visible.png) | ![October 18 empty day grid](https://app.devin.ai/attachments/90e93fcf-f6c3-47f2-aee8-52596b105429/04-calendar-oct18-occurrences-missing.png) |

### Diagnosis and minimal proposed scope — not implemented

Runtime failure was reported to the parent before any product edit.
Relevant current paths are:

- `CalendarBrowsingModel.swift:130–183`: visible cached records are grouped by
  their own start date; day filtering receives those same records.
- `CalendarGridLayout.swift:82–111`: coverage tests the raw start/end interval.
- `CalendarBrowsingModel.swift:333–336`: selection resolves a cached record ID.
- `CalendarRootView.swift:423–427`: the selected event is passed to the editor.

The narrow proposal is bounded recurrence projection for the visible date
range plus occurrence-aware selection that retains the provider/master
identity and the actual selected occurrence boundary. Then retest a real
third occurrence on **new** disposable series before claiming future-scope
edit/delete correctness. Audit the split's remaining COUNT/end bound as part
of that focused follow-up, not as a defect established by this run.
The existing kept fixtures must remain frozen; no implementation, migration,
harness expansion or speculative mutation was performed here.

## Retained Calendar and Tasks

| Assertion | Fresh v7 result |
| --- | --- |
| Active baseline | **Passed:** Calendar and Tasks normal details showed writable controls before removal; exact cached payloads matched providers |
| UI remove, keep cached copy | **Passed:** each identified keep source removed through Settings; separate keep choices, no source recreation |
| Active-source exclusion | **Passed:** both absent from Settings and registry; no retained-source sync/editing controls |
| Disk state | **Passed:** cache/collection bytes preserved; disconnected markers present; cursor directories absent |
| Normal Calendar browsing | **Passed:** retained event and unchanged masters remain in agenda with cached-data banner |
| Calendar exact-ID link | **Passed:** same retained event opens with Copy Link only; no Edit/Delete |
| Normal Tasks browsing | **Passed:** same retained task remains in list with cached-data banner |
| Tasks exact-ID link | **Passed:** same retained task opens; no Edit/Delete |
| Tasks completion/sync | **Passed, bounded:** visible completion circles remained inert when tapped in list/detail; sync control disabled; no cache/provider change |
| Calendar sync interpretation | Global sync for the unrelated original active Calendar still exists; it was not pressed and is not a retained-source capability |
| Retained network safety | **Passed:** zero request bytes in each measured removal/read window; provider payloads unchanged |
| Coordinator/credentials limit | Evidence is registry/UI exclusion, absent mutation controls and traffic, not direct coordinator instrumentation or signed-Keychain audit |

| Calendar — normal retained list | Calendar — exact-ID retained detail |
| --- | --- |
| ![Retained Calendar agenda](https://app.devin.ai/attachments/75fc7e57-3eff-4669-af78-06e399b14881/06-calendar-retained-list.png) | ![Retained event exact link without editing](https://app.devin.ai/attachments/6626b011-e0f2-42e6-813b-22d8dad6f972/07-calendar-retained-exact-link.png) |

| Tasks — retained list, disabled sync | Tasks — exact-ID retained detail |
| --- | --- |
| ![Retained Tasks list and disabled sync](https://app.devin.ai/attachments/613e0dc9-573c-412c-95d3-3efd138664ed/09-tasks-retained-list-disabled-sync.png) | ![Retained task exact link without Edit or Delete](https://app.devin.ai/attachments/4ce80f11-5d69-4b6d-b5f0-7227310defa7/10-tasks-retained-exact-link.png) |

## Separate delete-cache branches

Only after both keep-cache proofs, new Calendar Delete and Tasks Delete
sources were connected and individually synced. Their UIDs/source IDs were
verified separately from the keep sources before choosing delete cached data.
Write opt-in was not needed for these local-only removal branches.

| Assertion | Fresh v7 result |
| --- | --- |
| Visible/cache starting state | **Passed:** each separate record visible in normal list and exact seed-matching cache |
| Local removal | **Passed:** exact delete-source registry entries and entire source directories gone, including cache/cursor/marker state |
| Exact deleted event link | **Passed:** no event detail; localized unavailable notice |
| Exact deleted task link | **Passed:** no task detail; localized unavailable notice captured on repeated open |
| Keep fixtures untouched | **Passed:** both keep exact links still reopen read-only after separate deletion; cache bytes unchanged |
| Remote preservation | **Passed:** both remote payloads unchanged; zero provider requests during measured removal/link windows and no PUT/DELETE anywhere in new-source logs |

The first deleted Tasks link opened the remaining Tasks list without a
captured notice; a repeated exact link while Tasks was already open showed
the localized missing notice. The first state is preserved in
`15-tasks-deleted-link-unavailable.png`, the explicit notice in `15b-...png`.
Do not claim the notice was verified on every initial presentation.

| Calendar — deleted exact link unavailable | Tasks — deleted exact link unavailable on repeat |
| --- | --- |
| ![Deleted event unavailable notice](https://app.devin.ai/attachments/177d3d13-a075-4ef9-bc50-041b343fe0af/14-calendar-deleted-link-unavailable.png) | ![Deleted task unavailable notice on repeat](https://app.devin.ai/attachments/c8b25ef8-eb14-426f-ad87-f06bafdd812c/15b-tasks-deleted-link-repeat.png) |

## Source-specific request attribution and hashes

Each source had a separate loopback port/log. Existing request-log files
contain method/path/status, not per-line timestamps; UTC timestamps were
captured at byte-boundary observations. Diagnostic GETs were performed
outside the measured app windows and explicitly recorded in the manifests.

| Window, all UTC on October 15 | Byte boundary | App requests |
| --- | --- | --- |
| Calendar Keep removal/reads: `20:41:20.867486` → `20:45:10.582974` | `416` → `416` | **0** |
| Tasks Keep removal/reads: `20:43:57.822886` → `20:45:10.583152` | `283` → `283` | **0** |
| Calendar Delete removal/missing link: `20:48:42.256498` → `20:50:23.498399` | `288` → `288` | **0** |
| Tasks Delete pre-removal/removal/missing link: `20:48:42.256656` → `20:50:23.498571` | `285` → `285` | **0** |

Setup discovery used PROPFIND and REPORT 207. Diagnostic GETs returned 200
and matched the exact seed/raw-cache payloads. `provider-before.json`,
`keep-provider-proof.json`, `delete-provider-proof.json` and
`final-evidence.json` enumerate those diagnostic reads separately.
Every new-source log contains **zero PUT and zero DELETE**.

The original primary and Delta logs had zero additions from preflight to
final readback. Charlie's log had exactly two diagnostic GET additions:
`20:34:21.824032Z` and `20:55:21.988242Z`; neither was an app request.
No unaccounted request to a prior source was observed.

| Provider resource | SHA-256, unchanged before/after |
| --- | --- |
| Future-edit series | `28aad8a95374083e5d96673ccdd25573296fe0a0861d28e9fde85714f4111b09` |
| Future-delete series | `dd4ec975e333fe86c8609f8761830641a576d929d19b4b4b0cfc2e3b1848d0bb` |
| Calendar Keep event | `289debdad40df97038ad035c2e1ff6109679de2f80aaa77c506df0ec69c6fcf4` |
| Tasks Keep VTODO | `3a29772cd9fc1c17dd3f97e9c1ce3593be042fc29ddc62a4b84b87fa6f4618ca` |
| Calendar Delete event | `fc4f85316127bdd8b41eb6d856032156611fd401eab4663c6dd8cc4a2395759b` |
| Tasks Delete VTODO | `f2c790a5c77aa19f4ae8e4879be142c044fa40916cd25e92dd2a3c3f01fefe28` |
| Retained Calendar event-cache file | `a2438cc60330ca9138a6588556d372442605024d3f836fa9cf1e7485086c9351` |
| Retained Tasks task-cache file | `c006e20806d1c04f48b2f91dca8c1125efe9df6c4462188c34c287e1ac8f39d1` |

## AX3 scroll-under and actual tapability

On the original writable Alice detail, NB/dark/AX3, scrolling was allowed to
settle with the Edit label aligned horizontally with the native back button.
The pencil was under that chrome. Tapping the exposed Edit text within the
navigation-bar area did **not** open the editor: the view scrolled to the top.
After scrolling the action fully clear of the chrome and settling, Edit
opened the populated editor; Avbryt returned without saving.

**Judgment, bounded:** this is consistent with ordinary native scroll-under
and navigation-bar hit interception, not a reproduced persistent untappable
overlap. A tap in the covered chrome region is not an action pass. The
action was recoverably reachable without relaunching or changing text size.
All original contact-cache bytes and timestamps remained unchanged.
No speech, full AX traversal or animation-quality assertion is inferred.

| Covered position — chrome intercepts the tap | After scrolling clear — Edit opens, then cancels |
| --- | --- |
| ![AX3 Edit label aligned with native back chrome](https://app.devin.ai/attachments/62963c90-c2f5-4882-92e3-80907544328a/18-ax3-edit-aligned-behind-back-chrome.png) | ![AX3 editor opened after scrolling the action clear](https://app.devin.ai/attachments/a83d65d1-7704-4401-aa47-80154a4f6974/20-ax3-edit-opens-after-clearing-chrome.png) |

## Execution limitations and inherited evidence

| Item | Limit or disposition |
| --- | --- |
| Setup retries | Initial cache-directory selector corrected to `cache/contacts.json`; shifted manual-form coordinates corrected; write opt-in needed settled thumb taps. The initial four-record/write assertion was not accepted until both keep sources actually had write capability |
| Link helper correction | An initial path-style event URL was ignored; corrected to the documented `?id=` syntax, navigated away, then verified the exact link from mailbox. No path-style attempt is counted as link proof |
| Recurrence mutations | Unexecuted because the actual later occurrence was unreachable; no substitute master-date edit |
| Tasks missing notice | Captured on repeat, not on its first presentation; retained and deleted record identities were never conflated |
| Fresh accessibility scope | Visual scrolling/tap/cancel at NB/dark/AX3 only; no complete AX traversal, actual VoiceOver speech or fresh Reduce Motion assertion |
| Prior settled runtime | v4 first-boundary recurrence and cursor recovery, v5/v6 Contacts matrix and Copy Link timing were not rerun |
| Live providers | No new Google/DAV authentication, provider account, external recipient or live acceptance. Synthetic stub results are not live-provider evidence |
| macOS | Not launched; shared App Group isolation blocker remains inherited |
| Signing/device | No signed-Keychain persistence or physical iPhone evidence |
| Automatic CI, parent-reported | At this HEAD, 20 passed / 0 failed / 0 pending / 1 skipped (`snapshot-test`); not dispatched, rerun or independently checked by this runner |
| Inherited local gate | v6 parent reported 89 local BrevMail snapshot mismatches despite same-head CI snapshots reportedly passing. Host drift remains an unverified hypothesis; no broad rerun or full local-pass claim |

## Artifacts and reusable state

The single annotated recording covers the recurrence failure, both keep-cache
flows, separate delete-cache flows and the AX3 chrome check:
[primary v7 recording, session access required](https://app.devin.ai/attachments/a090e174-a8d5-4a5a-8ea9-9bec15260392/pim-v7-ios-primary-edited.mp4).

| Artifact | Absolute path |
| --- | --- |
| Primary recording | `/Users/devin/screencasts/pim-v7-ios-primary/pim-v7-ios-primary-edited.mp4` |
| This report | `/Users/devin/repos/brev-pim-parity/docs/qa/pim-parity-v7-2026-10-15.md` |
| Exact final manifest | `/Users/devin/pim-parity-evidence/v7-20261015-a/final-evidence.json` |
| Plan/baselines/windows/raw seeds | `/Users/devin/pim-parity-evidence/v7-20261015-a/` |
| Primary recurrence screenshots | `03-calendar-oct16-masters-visible.png`, `04-calendar-oct18-occurrences-missing.png` under the evidence root |
| Retained-cache screenshots | `06-calendar-retained-list.png`, `07-calendar-retained-exact-link.png`, `09-tasks-retained-list-disabled-sync.png`, `10-tasks-retained-exact-link.png` under the evidence root |
| Deleted-link screenshots | `14-calendar-deleted-link-unavailable.png`, `15b-tasks-deleted-link-repeat.png` under the evidence root |
| Kept fixtures after separate deletion | `16-calendar-kept-after-separate-delete.png`, `17-tasks-kept-after-separate-delete.png` under the evidence root |
| Chrome screenshots | `18-ax3-edit-aligned-behind-back-chrome.png`, `19-ax3-edit-fully-clear.png`, `20-ax3-edit-opens-after-clearing-chrome.png` under the evidence root |

| Process/state | Left running |
| --- | --- |
| App | PID `24123`; original Alice detail after cancel, NB/dark/AX3 |
| Original primary stub | PID `5246`, port `18643` |
| Frozen Charlie stub | PID `15161`, port `18644` |
| Prior Delta stub | PID `23594`, port `18645` |
| V7 Calendar Keep stub | PID `30916`, port `18646` |
| V7 Tasks Keep stub | PID `30925`, port `18647` |
| V7 Calendar Delete stub | PID `30946`, port `18648` |
| V7 Tasks Delete stub | PID `30955`, port `18649` |

Preserve Charlie and both newly kept caches. The two delete sources are absent
locally but their remote stub payloads remain intact. The recurring masters
remain unchanged in the retained Calendar cache and provider. Process-local
mock credentials are not evidence of persistence across relaunch.

## Publication and next handoff

The bounded runtime procedure documented above is complete at approved checkout
HEAD `3a784926563571a59e60b552ce4e7cf6180436d9`, using unchanged product
revision `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f`; no product change was made.
The runtime runner did not run repository publication lint/format/diff checks
or commit/push. This subsequent documentation-only publication passed
`MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
`MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
`git diff --check`. One documentation-only commit,
`docs(qa): record bounded v7 recurrence and retained-cache evidence`, was
pushed once to `origin fix/pim-parity-gaps`. No tests were rerun as part of
publication; TDD was skipped for this docs-only change. No CI was dispatched or
watched, and no PR/issue actions, merge, release or Done transition occurred.

Documentation sweep: QA/worklog only. No shipped product, architecture,
privacy, setup contract or release change was made, so README, CHANGELOG,
PRIVACY, ADRs and AGENTS need no edits from this evidence-only run.
Blueprint reread: existing tooling/build route was sufficient; owned-device
isolation and disposable loopback fixtures remain outside its full coverage.
No new blueprint/skill edits or proposals under this handoff.

Next: parent review/approval of the recurrence projection/selection scope
before any product change; then new-fixture later-occurrence mutation QA.
No user input is needed to publish this bounded evidence. Broader live,
macOS, signing, physical-device and spoken-accessibility gates remain open,
and Henrik retains final acceptance of #11/#3.
