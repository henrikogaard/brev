# Calendar/Contacts parity evidence v5 — 2026-10-15

**Bottom line:** the Calendar action-layout regression passed on the approved
revision. The bounded independent batch found Contacts AX3 word fragmentation,
an untranslated standard contact label, and retained-cache content that is no
longer reachable after source removal. The affected removal flow was frozen.
This is not full #11/#3 acceptance.

| Provenance | Value |
| --- | --- |
| Scope | [PR #245](https://github.com/henrikogaard/brev/pull/245), [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3) |
| Approved/tested revision | `bbe06d81b50ad19dc49169cab951f42d5a91ba6f` |
| Checkout | `/Users/devin/repos/brev-pim-parity`, `fix/pim-parity-gaps` → `main`; clean before the run |
| Authorization | Parent resumed v5 under Henrik's ongoing “yes, keep working and get the work done”; continue harmless independent findings, freeze a failing provider/cache mutation flow |
| Device | Owned iPhone 17 simulator, iOS 27.0, `Brev PIM v3 20261015 A`, UDID `0AAE0F16-6167-435E-884F-C0BA50E05A67` |
| Build | Targeted BrevIOS Debug rebuild/install at the approved revision, Xcode 27 RC, existing owned DerivedData, unsigned simulator configuration |
| Runtime | `eu.brevmail.brev.ios`, `BREV_USE_MOCK=1`; owned synthetic DAV/CardDAV sources; credentials reconnected through UI after app relaunches |
| Primary provider | Existing owned stub at `127.0.0.1:18643`, reused without restart |
| Independent fixture | Separate owned CardDAV stub at `127.0.0.1:18644`, one disposable v5 contact |
| Evidence root | `/Users/devin/pim-parity-evidence/v5-20261015-a/` |
| History | [v2](pim-parity-v2-2026-10-15.md), [v3](pim-parity-v3-2026-10-15.md), [v4](pim-parity-v4-2026-10-15.md) and their evidence remain unchanged |
| Session | [Devin session](https://app.devin.ai/sessions/930e6447745b410bb056d921d709803a) |

All Devin attachment links/images below require access to the originating
session. They are **not public or portable GitHub embeds**. No binary artifacts
were added to the checkout.

## Independent findings collected in this batch

| ID | Result and reproduction | Proposed minimal scope — not implemented |
| --- | --- | --- |
| F1 | **Failed:** open writable `V3 Synthetic Alice` in Contacts at Large, then AX3. English/dark fragments Delete into `Del / ete` and Copy Link into `Co / py / Lin / k`. NB/light and NB/dark AX3 also fragment Rediger and Kopier lenke. Large restores the normal horizontal row. | Apply adaptive layout to `ContactDetailView.actionRow`, preserving full labels, order, handlers and Dynamic Type scaling. Do not shrink text to hide the problem. |
| F2 | **Failed:** remove `V5 Disposable Contacts` with **“Fjern, behold bufret kopi”**. The dialog promises that retained cache stays readable. Charlie disappears from the unfiltered list; an exact cached-ID deep link shows the missing-contact notice. The contact cache remains byte-identical on disk and has a disconnected marker. | Make retained disconnected-cache metadata discoverable by browsing/deep-link lookup without restoring credentials, sync or write access. Relevant paths are `PIMSourceCoordinator.removeSource`, `PIMSourceLocalDataStore` and `ContactsBrowsingModel.load/loadContacts`. Retest both removal choices separately after review. |
| F3 | **Failed, narrow localization case:** NB detail for the disposable contact shows **“Work”** beneath E-post. The owned vCard contains standard `EMAIL;TYPE=WORK`; its cached label is `work`, not custom user-authored “Work” text. | Localize recognized standard type labels in `ContactPresentation.fieldLabel` while preserving arbitrary custom labels. Only WORK was exercised in this run. |

F1 and F3 were non-destructive, so the batch continued. On F2, the runner
preserved state and stopped **that source's mutation flow**: no reconnect,
second removal, cache deletion or attempted repair. Only read-only cache and
deep-link diagnostics followed. Healthy Calendar navigation remained usable.

### F1 — populated Contacts comparison

| Default Large — English/light reference | AX3 — English/dark failure |
| --- | --- |
| ![Readable Contacts actions at Large](https://app.devin.ai/attachments/1663e39d-b5e9-41be-bd66-584225a15542/11-contact-en-light-large.png) | ![Fragmented Contacts actions at AX3](https://app.devin.ai/attachments/80414fa9-4085-4869-9202-e27f51d85602/14-contact-en-dark-ax3-fragmentation.png) |

[NB/dark AX3 reproduces the Contacts fragmentation — session access required](https://app.devin.ai/attachments/e024befe-0002-4099-9615-373921da656a/21-contact-nb-dark-ax3-fragmentation.png).

### F2/F3 — owned contact before and after keep-cache removal

The right-hand image is a **failure after the action**, not a corrected result.
The left-hand image also shows the standard type label “Work” in the NB UI.

| 🔴 Before — owned contact is readable and writable | 🟢 After keep-cache removal — unexpected missing-contact notice |
| --- | --- |
| ![Owned contact before removal with Work label in NB](https://app.devin.ai/attachments/311618eb-704c-4f4c-9554-c1f4fc175ba9/37-disposable-contact-writable-nb-work-label.png) | ![Kept contact cannot be opened by exact cached ID](https://app.devin.ai/attachments/91f92123-3887-4030-beed-2905c355995d/40-kept-contact-deeplink-unavailable.png) |

F2 identity and preservation evidence:

| Item | Observed value |
| --- | --- |
| Removed source ID | `pim-16183cbc-a8f9-4408-94dc-a15251887d9f` |
| Contact UID | `brev-pim-20261015-v5-disposable` |
| Provider key | `http://127.0.0.1:18644/card/u/main/v5-disposable.vcf` |
| Internal ID | `pim-16183cbc-a8f9-4408-94dc-a15251887d9f` + `\|` + the provider key above |
| Cache after removal | `contacts.json` still contains Charlie; byte-identical to the pre-removal copy |
| SHA-256 | `9479d0752b7e5bdc5f46395f86018f85cd107bfd21050f2d2f590b25e5a0f36f` |
| Local lifecycle | Disconnected marker exists; cursor directory removed; source no longer in `pim-sources.json` |
| Provider mutation | Secondary request logs contain no PUT, DELETE or POST; seed/server were preserved. Direct post-removal provider enumeration was not repeated after freezing the flow. |
| Unexecuted dependent branch | Remove with delete cached data; no claim that this branch passes or fails |

## Primary regression — adaptive Calendar actions

Before comparison, the runner rebuilt the approved binary, reconnected the two
existing owned sources and opened the **same writable synthetic event** with
Edit, Delete and Copy Link all present. No substitute event, recurrence edit or
new series was used. Its before-v5 cache was preserved.

| Required assertion | Fresh v5 result |
| --- | --- |
| English/light default Large | Passed: full labels, horizontal order Edit → Delete → Copy Link |
| English/dark default Large | Passed: same full horizontal labels/order |
| English/light and English/dark AX3 | Passed: text enlarges, labels remain whole, leading vertical layout preserves order |
| NB/light and NB/dark AX3 | Passed: Rediger → Slett → Kopier lenke, enlarged and unfragmented |
| NB/dark Large reference | Passed: horizontal full labels at default size |
| Edit and Cancel | Passed: populated editor opens; cancel returns without saving |
| Delete and safe cancellation | Passed: recurring-event confirmation opens; tapping outside safely dismisses it and the event remains. An explicit Cancel button was not visible in that AX3 popover; this does not establish a labeled Cancel-control assertion. No delete option was chosen. |
| Copy Link identity | Passed: decoded copied ID equals the preserved cache ID; opening it reveals the same title/date/repetition. The deep-link route renders read-only detail, distinct from the writable Calendar-root route. |
| Data preservation | Passed: final original event count remains one; internal ID, provider key and raw ICS equal the before-v5 copy. Original two contact payloads also remain unchanged. |

[Primary annotated recording — fixed English labels and safe actions, session access required](https://app.devin.ai/attachments/ddcae5c2-ebb3-4eb8-a3fc-f12b88ea5540/pim-v5-ios-primary-edited.mp4).

The recording is the one primary clip. NB and independent continuation are
documented with screenshots, not a second recording.

| 🔴 Before — v4 English/dark AX3 failure | 🟢 After — v5 English/dark AX3 |
| --- | --- |
| ![Historical v4 action-label fragmentation](https://app.devin.ai/attachments/86aebb4a-83e3-4528-8a24-50ff92e72d1c/05-en-dark-ax3-actions.png) | ![Fixed full-size stacked Calendar actions](https://app.devin.ai/attachments/0649faea-16bd-4c36-9acc-9ca82f01569c/03-event-en-dark-ax3.png) |

| English/light Large reference | NB/dark AX3 |
| --- | --- |
| ![Horizontal Calendar actions at Large](https://app.devin.ai/attachments/bd00a33f-35c0-4a82-aaef-96f7b3fac46c/01-event-en-light-large.png) | ![Full Norwegian Calendar actions at AX3](https://app.devin.ai/attachments/d818f9e7-13ea-4a00-8723-4211f38ef8ec/30-event-nb-dark-ax3.png) |

### Unchanged original event identity

| Field | Before and after v5 |
| --- | --- |
| Title | `brev-pim-v4 Future Updated` |
| UID | `brev-pim-20261015-a-series` |
| Source | `pim-046b9749-9093-4787-b976-774c00b95c96` |
| Collection | `http://127.0.0.1:18643/cal/u/main/` |
| Provider key | `http://127.0.0.1:18643/cal/u/main/v3-series.ics` |
| DTSTART / DTEND | `20261015T190000Z` / `20261015T193000Z` |
| RRULE | `FREQ=DAILY;COUNT=5`; no UNTIL |
| Local display | October 15, 12:00–12:30 |
| Internal ID | Source + `\|` + collection + `\|` + provider key |

`copied-event-link.txt` and `final-evidence.json` record the copied URL and
decoded-ID comparison. Reading the unchanged recurrence payload is a
preservation check, **not** another recurrence-flow test.

## Bounded populated matrix and accessibility

This was a coherent variant matrix, not every Cartesian combination.
Screenshot numbers refer to files in the evidence root; the manifest below
groups them. Editor values were not changed or saved.

| Surface | Fresh variants and result |
| --- | --- |
| Calendar list | Populated initial English navigation; NB/light AX3 (32), NB/dark Large (25). One original row remains. |
| Calendar detail | EN light/dark Large and AX3 (01–04); NB/dark Large (26), NB light/dark AX3 (30–31). Primary action assertions passed. |
| Calendar editor | EN/light Large (09), EN/light AX3 (05), EN/dark AX3 lower fields (08); NB/dark Large (27), NB/light AX3 (28), NB/dark AX3 lower fields (29). Opens, scrolls and cancels; no save. |
| Contacts list | EN/light Large (10), EN/dark AX3 (15), NB/light AX3 (17), NB/dark Large (24). Owned Alice/Bob visible; disposable Charlie appears after its separate initial sync. |
| Contacts detail | EN/light Large (11), EN/dark AX3 (14), NB/light AX3 (18), NB/dark AX3 (21), NB/dark Large (22). F1 at AX3; ordinary fields remain populated. |
| Contacts editor | EN/light Large (12), EN/dark AX3 (13), NB/dark AX3 (19), NB/light AX3 lower fields (20), NB/dark Large (23). Scroll/cancel works. Long single-line values ellipsize at AX3; full-value editing/readback was not asserted. |
| NB localization | Navigation, action/editor labels and the induced server-unreachable error are Norwegian. F3 identifies the tested standard contact-label exception. Synthetic titles/notes/source names intentionally stay as fixture data. |
| Reduced Motion | **Partial:** the owned device preference was set/read back as `ReduceMotionEnabled=1`, then the NB app process was launched. Calendar/Contacts list/detail/editor navigation and cancellation worked. Settings pointer interaction had stalled after VoiceOver; the runner used the owned simulator preference domain, not shared host preferences. No measured animation or UIKit motion-state assertion is made. |
| Available AX inspection | **Partial:** limited English control/editor metadata was inspected; not a complete detail traversal. After VoiceOver interaction the Simulator host AX bridge returned no matching native controls, so NB navigation used pixels. No complete NB AX names/traits audit claimed. |
| Actual VoiceOver | **Untested spoken readback:** a VoiceOver focus rectangle was visually observed (16), but host AVFoundation exposed no audio-input device for recording speech. Focus/AX metadata are not proof of spoken output or correct reading order. VoiceOver is Off at handoff. |

Additional observations, not promoted to confirmed product defects:

- The recurring confirmation was safely dismissed without a visible Cancel
  button. The exact labeled-control requirement remains unverified.
- The deep-link event presentation was read-only. The same event reopened
  through Calendar root retained all writable controls.
- Contact Edit/Delete temporarily disappeared during the VoiceOver/background
  sequence despite source metadata remaining ready/read-write. The observation
  was not isolated; the NB process with reconnected credentials restored the
  writable detail. It is not classified as a confirmed cache or write failure.

## Independent-source failure and recovery

The new disposable source started with background sync Off, was explicitly
connected/synced and showed one owned contact. Editing was enabled and all
three detail actions were verified before removal. The original 18643 server
was never stopped.

| Action/assertion | Result |
| --- | --- |
| Stop only the secondary server PID 12731; Sync Now for its source | Passed expected failure: source becomes Mislyktes with localized “Serveren kunne ikke nås. Kontroller tilkoblingen og prøv igjen.” |
| Sync the healthy original Calendar while secondary source is failed | Passed: original server logs REPORT 207; original source remains Ready and same event opens with writable actions (35). Original Contacts source also remains Ready. |
| Restart only the secondary server; Sync Now | Passed: REPORT 207; secondary source returns Ready with one cached contact (36). No reauthentication/relaunch needed. |
| Preserve state, then remove secondary source keeping cache | Failed readability contract, F2. Before/after cache preserved; stop affected mutations. |
| Delete-cache removal/cache rebuilding branch | Untested after F2. Not replaced with a raw-file deletion or another fixture. |
| Cursor expiry/full-sync recovery | Inherited limited v4 REPORT 403 → 207 evidence; deliberately not repeated in v5. |

| Induced secondary failure — healthy sources remain Ready | Secondary source recovered by Sync Now |
| --- | --- |
| ![Isolated source error with healthy original sources](https://app.devin.ai/attachments/983c4e87-7674-45f7-a306-9cb16395639b/34-secondary-failure-healthy-sources-ready.png) | ![Secondary source Ready again with one contact](https://app.devin.ai/attachments/9c3586a8-65af-47dd-ab8f-a2bf604f3471/36-secondary-recovered-ready.png) |

## Evidence layers and remaining gates

| Layer | Status |
| --- | --- |
| Fresh iOS simulator + synthetic stub | Results above; not live provider or physical-device evidence |
| Historical runtime | v4 exact first-occurrence recurrence and limited cursor recovery remain inherited; v3 search/same-process offline evidence remains historical |
| Automated/snapshot checks | Parent-owned checks and snapshots inherited, not rerun or substituted for this runtime batch |
| macOS | Not launched. Inherited application-group preflight failed isolation despite synthetic home redirection; needs an isolated OS user or reviewed separately signed/group-isolated setup |
| Live Google/DAV | Not retried. No newly authorized isolated provider configuration or credential-persistence setup; mail credentials are not DAV authorization. No new login challenge claimed. |
| Signed Keychain | Untested. Earlier `0 valid identities found` gate remains; process-local mock credentials naturally disappear on relaunch |
| Physical iPhone | Untested; requires an approved signed build/device |
| Actual VoiceOver / motion acceptance | Spoken readback and complete AX audit unresolved; Reduced Motion is only configuration readback plus functional smoke |
| Remaining cache lifecycle | Keep-cache failure needs review; delete-cache/rebuild branch remains untested |
| Final acceptance | Henrik-only after outstanding defects and platform/provider gates; #11/#3 are not closed |

## Artifact manifest and reusable handoff

All filesystem paths are on this session's host.

| Artifact | Absolute path or location |
| --- | --- |
| Primary annotated recording | `/Users/devin/screencasts/pim-v5-ios-primary/pim-v5-ios-primary-edited.mp4` |
| Plan | `/Users/devin/pim-parity-evidence/v5-20261015-a/test-plan.md` |
| Calendar English primary/safe-action screenshots | Evidence root, `01`–`09` |
| Contacts English / VoiceOver-focus screenshots | Evidence root, `10`–`16` |
| NB matrix screenshots | Evidence root, `17`–`32` |
| Failure/recovery/removal/final-state screenshots | Evidence root, `33`–`41` |
| Original pre-v5 preservation | Evidence root, `preserved-before-v5/` and `v3-series.ics` |
| Source-mutation preservation | Evidence root, `preserved-before-source-removal/`, `preserved-after-keep-cache-removal/`, `sources-during-secondary-failure.json` |
| Final identity/settings comparison | `/Users/devin/pim-parity-evidence/v5-20261015-a/final-evidence.json` |
| Redacted request evidence | Evidence root, `primary-dav-requests-final.log`, `secondary-requests.log`, `secondary-requests-recovered.log`; primary log includes inherited earlier runs |
| Timestamped secondary output | Evidence root, `secondary-server.log`, `secondary-server-recovered.log` |
| Build log | `/Users/devin/pim-parity-evidence/v5-20261015-a/ios-build.log` |

| Reusable process/state | Handoff |
| --- | --- |
| Owned app | PID **12451**, left running on original writable Calendar detail |
| Original stub | PID **5246**, port **18643**, unchanged v3 seed/service |
| Secondary stub | PID **15161**, port **18644**, left running; its source was removed keeping cache and must not be casually reconnected/cleaned before review |
| Stub wrapper | `/Users/devin/pim-parity-evidence/v3-20261015-a/timestamp-stub.py` |
| Original seed | `/Users/devin/pim-parity-evidence/v3-20261015-a/seed/` |
| Secondary seed | `/Users/devin/pim-parity-evidence/v5-20261015-a/secondary-seed/` |
| Owned DerivedData | `/Users/devin/pim-parity-evidence/v3-20261015-a/ios-derived/` |
| App data container | `/Users/devin/Library/Developer/CoreSimulator/Devices/0AAE0F16-6167-435E-884F-C0BA50E05A67/data/Containers/Data/Application/05A78A40-B45E-4BE9-B88D-97F930185395` |
| Final UI preferences | `AppleLanguages=(nb)`, `AppleLocale=nb_NO`, dark, `accessibility-extra-large` (AX3); ReduceMotionEnabled **1**, VoiceOverTouchEnabled **0** |
| Source registry | Original Calendar and Contacts only, both Ready/read-write; one original event and two original contacts unchanged |
| Credential limitation | Same-process synthetic credentials; do not assume persistence across another relaunch |

## Publication and documentation scope

The runtime runner did **not** run repository lint/format/diff checks or
commit/push; its runtime results and bounded findings are reported above. The
subsequent parent-owned publication phase passed
`MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
`MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
`git diff --check`. One documentation-only commit,
`docs(qa): record PIM accessibility and cache acceptance findings`, was pushed
once to `origin fix/pim-parity-gaps`. Tested source revision
`bbe06d81b50ad19dc49169cab951f42d5a91ba6f` remains distinct from the
evidence-only publication commit. No PR edits/comments, CI dispatch/watch,
issue closure, merge, product edits or Drive testing were performed in this
publication.

Only this new v5 report and an appended `WORKLOG.md` entry change the checkout.
README, CHANGELOG, PRIVACY, ADRs and AGENTS require no update for this
evidence-only run; no product or architecture change was made. Prior v2/v3/v4
reports and artifacts were not overwritten.

SKILL.md suggestions: none. Blueprint was reread; existing build/tool routes
were reused. Disposable stub provisioning and explicit-device isolation are not
fully described there, but no new blueprint/skill edit or proposal is made
under this handoff's restriction.
