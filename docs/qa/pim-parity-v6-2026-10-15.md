# Calendar/Contacts parity evidence v6 — 2026-10-15

**Bottom line:** the bounded synthetic iOS runtime procedure is complete.
The original frozen v5 contact is reachable again without reconnecting, the
Contacts action/WORK-label regressions passed, and a separate delete-cache
fixture was removed locally without changing provider data. An initial
clipboard assertion required a settled retry; explicit Cancel, standalone
disconnected-detail messaging and spoken accessibility remain limited.
Parent-reported local snapshot failures remain unresolved. This is not full
#11/#3 acceptance or a full local-check pass.

| Provenance | Value |
| --- | --- |
| Scope | [PR #245](https://github.com/henrikogaard/brev/pull/245), [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3) |
| Approved/tested revision | `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f` |
| Checkout | `/Users/devin/repos/brev-pim-parity`, `fix/pim-parity-gaps` → `main`; clean at preflight |
| Authorization | Henrik's ongoing “yes, keep working and get the work done”; parent-approved bounded v6, original frozen fixture mandatory |
| Device | Owned iPhone 17 simulator, iOS 27.0, `Brev PIM v3 20261015 A`, UDID `0AAE0F16-6167-435E-884F-C0BA50E05A67` |
| Build | Targeted BrevIOS Debug rebuild/install, Xcode 27.0 `27A266a`, SDK `iphonesimulator27.0`, existing owned DerivedData, `CODE_SIGNING_ALLOWED=NO`, `-skipMacroValidation` |
| Tool selection | Explicit `/Applications/Xcode-27.0-RC.app/Contents/Developer`; host default is Xcode 26.6, not the targeted build toolchain |
| Host | macOS 26.5.2, build `25F84` |
| Runtime | `eu.brevmail.brev.ios`, `BREV_USE_MOCK=1`; synthetic loopback DAV/CardDAV only |
| Evidence root | `/Users/devin/pim-parity-evidence/v6-20261015-a/` |
| Prior evidence | [v2](pim-parity-v2-2026-10-15.md), [v3](pim-parity-v3-2026-10-15.md), [v4](pim-parity-v4-2026-10-15.md), [v5](pim-parity-v5-2026-10-15.md) and all prior artifacts preserved |
| Session | [Devin session](https://app.devin.ai/sessions/930e6447745b410bb056d921d709803a) |

All attachment URLs below require access to the originating Devin session.
They are **not public or portable GitHub embeds**. No binary artifacts were
added to the checkout.

## Required frozen starting state

Before rebuilding/installing/launching, the runner compared the original
removed-but-kept Charlie fixture with v5 preservation evidence. No replacement
source, reconnect, migration, cleanup or cache restoration was used.

| Identity/state | Verified value |
| --- | --- |
| Removed source | `pim-16183cbc-a8f9-4408-94dc-a15251887d9f` |
| Contact | `V5 Disposable Charlie`, `v5-charlie@example.test` |
| UID | `brev-pim-20261015-v5-disposable` |
| Provider key | `http://127.0.0.1:18644/card/u/main/v5-disposable.vcf` |
| Composite contact ID | Source ID above + `\|` + provider key above; exact original link preserved in `frozen-original-link.txt` |
| Cache SHA-256, before and after | `9479d0752b7e5bdc5f46395f86018f85cd107bfd21050f2d2f590b25e5a0f36f` |
| Provider SHA-256, before and after | `3472d57f9af79787d08922fc9a3354845d1e1e949c47fd1e4204561156a2d3e0` |
| Local state | `disconnected` marker present, cursor directory absent, source absent from active registry |
| Active sources | Calendar `pim-046b9749-9093-4787-b976-774c00b95c96`; Contacts `pim-538b1860-aaff-418a-84f2-2cb20580b4e7` |
| Preflight timestamp | `2026-10-15T19:17:45.988944Z` |

Installation relocated the simulator data container from
`05A78A40-B45E-4BE9-B88D-97F930185395` to
`0AAFFDA3-9142-4F3E-A76C-970BDA4E6064`. A first read using the old path failed;
the runner resolved the installed container with explicit-device `simctl`.
Byte comparison then proved the original cache and marker unchanged, including
the marker modification timestamp. Nothing was copied back or recreated.
See `frozen-preflight.json`, `post-install-preservation.json` and
`preserved-frozen-before-build/`.

## Primary retained-contact results

| Assertion | Fresh v6 result |
| --- | --- |
| Original Charlie in normal list | **Passed:** Alice, Bob and Charlie appear; cached-data banner visible without reconnecting Charlie |
| Original exact-ID deep link | **Passed:** opens the same populated Charlie, not another contact; copied link ID equals the original composite ID |
| Retained write capabilities | **Passed:** only Copy Link; no Edit/Delete on normal or exact-link detail |
| Active-source-only Settings | **Passed:** original Calendar/Contacts only; Charlie has no source row, Sync control or Editing toggle |
| Standard WORK label | **Passed:** Charlie displays `Arbeid` in NB |
| Frozen network/cache safety | **Passed:** zero new request bytes during the observation window; unchanged cache/provider bytes and marker timestamp |
| Explicit disconnected-detail notice | **Not observed:** list shows the cached-data banner; detail has no separate disconnected/read-only notice. This plan-only UX expectation was not satisfied by a visible notice |
| Credential/coordinator limitation | Runtime evidence is registry/UI exclusion, absent capabilities and observed traffic, not direct method instrumentation or a signed-Keychain audit |

### Original failing link versus v6

| 🔴 Before — v5 original retained link unavailable | 🟢 After — v6 same original link, read-only |
| --- | --- |
| ![v5 kept-cache exact-link failure](https://app.devin.ai/attachments/91f92123-3887-4030-beed-2905c355995d/40-kept-contact-deeplink-unavailable.png) | ![v6 original Charlie exact link with Copy Link only](https://app.devin.ai/attachments/1076bacd-3e70-403b-ae3c-6d2184718a9a/04-original-exact-deeplink.png) |

| Original retained contact in list | Active-only Settings, no retained source controls |
| --- | --- |
| ![Charlie in cached Contacts list](https://app.devin.ai/attachments/1128ffb9-8c0f-46dc-93cc-ab602cd31f7a/01-original-retained-list.png) | ![Only original active sources in Settings](https://app.devin.ai/attachments/e83e96e3-a587-4529-a4fa-43f712583ee3/12-active-only-sources.png) |

### Request attribution

The original secondary stub PID `15161` on port `18644` was reused untouched.
One diagnostic GET occurred before the app observation boundary. The boundary
was **122 log bytes / two lines** at `19:17:45.988944Z`; the log remained exactly
122 bytes at `19:49:58.597944Z`. Thus no app request, including no provider write,
was observed during build/install, retained browsing/deep links, locale
relaunches, active-contact checks and distinct-source removal.

Only after closing that window did the runner make one final diagnostic GET
to compare the frozen provider payload. These diagnostic reads are not app
requests. `frozen-app-observation.log` preserves the pre-final-GET snapshot;
`frozen-provider-before.vcf` and `frozen-provider-after.vcf` are identical.
No credentials, consent, sync or editing access were re-established for Charlie.

## Active Contacts actions and localization

The same original `V3 Synthetic Alice` was opened through the normal Contacts
list, with Edit/Delete/Copy Link present. This was not a read-only deep-link
presentation substituted for a writable detail.

| Variant/action | Fresh v6 result |
| --- | --- |
| NB/dark AX3 | **Passed:** full enlarged Rediger → Slett → Kopier lenke, vertical fallback |
| NB/light AX3 | **Passed:** same complete labels and order |
| EN/light AX3 | **Passed:** full enlarged Edit → Delete → Copy Link |
| EN/dark AX3 | **Passed:** same complete labels and order, no old word fragmentation |
| NB/light Large comparison | **Passed:** horizontal row; AX3 visibly enlarges text rather than shrinking it to fit |
| Edit | **Passed:** populated editor opens; Avbryt returns to unchanged detail |
| Delete | **Passed, limited:** confirmation opens; outside dismissal preserves contact. No visible labeled Cancel button, so explicit Cancel remains unverified |
| Copy Link | **Passed on settled retry:** clipboard query ID matches Alice exactly; initial immediate post-dismissal copy tap did not establish this |
| Active cache preservation | **Passed:** original Alice/Bob cache is byte-identical after cancellation and at final readback |
| Standard/custom labels | **Passed:** separate Delta shows `Arbeid` for WORK and unchanged lowercase custom `qa-lab`, at Large and AX3 |

Alice's composite ID is original Contacts source
`pim-538b1860-aaff-418a-84f2-2cb20580b4e7` + `|` +
`http://127.0.0.1:18643/card/u/main/v3-alice.vcf`.

The initial combined clipboard/cache assertion failed: the cache was
byte-identical, but the clipboard still held Charlie's link. Testing paused
to distinguish mutation from an unverified UI tap. After the delete popover
was fully dismissed, one separate Copy Link tap returned Alice's exact ID.
The initial failure remains in `active-copied-link.txt`; the retry and explicit
result are in `active-copied-link-retry.txt` and
`active-safe-action-result.json`. A transition-timing explanation is plausible,
not proven. No data corruption or reproducible Copy Link defect was observed.

| 🔴 Before — v5 EN/dark AX3 fragmentation | 🟢 After — v6 EN/dark AX3 complete labels |
| --- | --- |
| ![v5 fragmented Contacts actions](https://app.devin.ai/attachments/80414fa9-4085-4869-9202-e27f51d85602/14-contact-en-dark-ax3-fragmentation.png) | ![v6 complete scaled Contacts actions](https://app.devin.ai/attachments/a9b7b381-f895-427a-ae20-24c1f4583f45/11-active-contact-en-dark-ax3.png) |

| NB/light Large — horizontal reference | NB/light AX3 — scaled vertical fallback |
| --- | --- |
| ![NB default-size action row](https://app.devin.ai/attachments/9c48b5b0-541c-4eb0-8ad4-92ed9517cd23/09-active-contact-nb-light-large.png) | ![NB AX3 full action labels](https://app.devin.ai/attachments/191cdf1c-e4b0-4eb9-9cfb-feb124c14bf6/05-active-contact-nb-light-ax3.png) |

| Populated editor before cancellation | Delete confirmation before safe outside dismissal |
| --- | --- |
| ![Populated Alice editor](https://app.devin.ai/attachments/84c5f671-3aaa-4fe4-a020-a00c7f602410/06-active-edit-populated.png) | ![Alice deletion confirmation](https://app.devin.ai/attachments/4eb68cb0-db85-440b-a388-2140f48fd505/07-active-delete-confirmation.png) |

[EN/light AX3 screenshot — session access required](https://app.devin.ai/attachments/c59be836-a8e0-439e-9a55-8b7af8125483/10-active-contact-en-light-ax3.png).

## Distinct local delete-cache branch

Delta was created **only after the original retained-case proof**. Its source,
port, UID and provider key differ from Charlie's. Only Delta's local source
and cache were removed. The frozen Charlie source/cache was never reconnected,
recreated or deleted.

| Item | Exact evidence |
| --- | --- |
| Source display name | `V6 Delta Delete Cache` |
| Source ID | `pim-247b38a5-71ed-4cd5-9999-44d22e7faa53` |
| Contact / UID | `V6 Disposable Delta` / `brev-pim-20261015-v6-deletecache` |
| Provider key | `http://127.0.0.1:18645/card/u/main/v6-deletecache.vcf` |
| Composite ID | Delta source ID + `\|` + provider key; verified copied URL in `delta-copied-link.txt` |
| Setup | New owned loopback stub, one vCard, UI Connect → allow editing → Sync Now; background sync left off |
| Preserved before removal | `delta-before-removal.json`, `delta-preserved-before-removal/`, `delta-provider-before.vcf`, exact copied link |
| UI choice | Dialog explicitly named Delta; selected **Fjern og slett bufrede data** |
| Source/cache removal | **Passed:** source absent from registry/Settings; entire Delta source directory absent, including cache and marker |
| List/deep link | **Passed:** Delta absent from list; exact URL shows NB missing-contact notice |
| Provider isolation | **Passed:** remote payload unchanged; no PUT/DELETE; zero app-request bytes after the initial diagnostic boundary |
| Frozen-case preservation | **Passed:** Charlie still opens via the original link; unchanged cache/marker/provider payload |
| Provider SHA-256, before and after | `95e0670e6d243219f1cf039c14bf934f1d785c7b5ad7bd099b1c200c7ee0678b` |

Delta's setup emitted discovery PROPFINDs and one REPORT. A diagnostic GET
established its before-payload and request-log boundary; the final diagnostic
GET occurred after the app observation window. Neither GET is app traffic.
This is local-cache lifecycle evidence, not remote contact deletion evidence.

| Delta NB labels — standard and custom | Exact named-source delete-cache confirmation |
| --- | --- |
| ![Arbeid and unchanged qa-lab at AX3](https://app.devin.ai/attachments/ab8b0628-8d4f-4654-bc8c-ca1fbd64c190/15-delta-nb-ax3-work-and-custom.png) | ![Delta local delete-cache choice](https://app.devin.ai/attachments/f03878b4-c110-4295-b7b3-d8093e1e461c/17-delta-delete-cache-confirmation.png) |

| Delta exact link correctly unavailable after removal | Original frozen Charlie remains readable |
| --- | --- |
| ![Localized missing Delta contact notice](https://app.devin.ai/attachments/7c388001-e900-4ad3-9e2b-b3af0e316456/20-delta-deeplink-missing-nb.png) | ![Charlie preserved after distinct-source removal](https://app.devin.ai/attachments/1660a4ed-566f-419b-8de7-0b8c3e762960/21-frozen-charlie-still-readable-after-delta-removal.png) |

## Limits and inherited evidence

| Category | Status / limit |
| --- | --- |
| New destructive/isolation/cache mutation defect | None observed in this bounded runtime; no product edits |
| Optional retained Calendar/Tasks smoke | Not run: no pre-existing retained Calendar/Tasks fixtures; only Charlie's disconnected marker remains. No fixtures manufactured |
| Accessibility | Pixel readability and functional taps checked. Native AX inspection returned `capability_unavailable`; no complete traits/traversal or spoken VoiceOver claim |
| Motion / speech preferences | Final owned-device readback: Reduce Motion `0`, VoiceOver `0`. No fresh v6 motion assertion; do not carry forward v5's earlier On readback as current |
| macOS | Not launched: inherited shared App Group isolation blocker; no daily-driver or personal data touched |
| Live Google/DAV | Not attempted; no newly authorized isolated live setup. Stub evidence does not establish live-provider acceptance |
| Signed Keychain / physical iPhone | Untested; mock credentials are process-local. No new signing, auth retries, bypasses or physical-device setup |
| Historical runtime | v4 recurrence/cursor recovery and v5 Calendar actions/source-failure isolation remain inherited, not rerun |
| Parent-reported gate | Parent relayed CI 21/21 pass; full BrevCalendar 266 tests/26 suites pass; full local BrevMail 2194 tests/331 suites **failed with 89 snapshot mismatches** across Login/Compose/Mail Context/Local Folders/PIM at this SHA. CI snapshots reportedly passed the same head |
| Attribution of that gate | Parent-reported, not executed or independently verified by this runtime runner. Host drift is only a hypothesis, **not base-verified**. No full local-pass claim |

The snapshot discrepancy remains a parent-owned investigation. UX limits above
may warrant a separate review of explicit cancellation and disconnected-detail
messaging; no additional product implementation or acceptance decision is
implied by this report.

## Artifacts and reusable state

[Primary annotated recording — retained list/exact-link/capability safety](https://app.devin.ai/attachments/c2264d8a-6007-4f50-8cec-25192dd6dc66/pim-v6-ios-primary-edited.mp4).
The later variant and delete-cache checks use labeled screenshots, not a
second recording.

[Final identity/hash/request evidence — session access required](https://app.devin.ai/attachments/49133650-168b-468a-9997-7235395d897d/final-evidence.json).
The manifest also records final preference/toolchain readback.

| Resource | State/path at handoff |
| --- | --- |
| Primary video | `/Users/devin/screencasts/pim-v6-ios-primary/pim-v6-ios-primary-edited.mp4` |
| Plan | `/Users/devin/pim-parity-evidence/v6-20261015-a/test-plan.md` |
| New app process | PID `24123`, left running; earlier v6 PIDs `21023` and `22872` replaced by owned locale relaunches |
| Final screen | Original frozen Charlie, NB `nb_NO`, dark, AX3 `accessibility-extra-large` |
| Primary stub | PID `5246`, port `18643`, original v3 seed; never restarted in v6 |
| Frozen secondary stub | PID `15161`, port `18644`, original v5 seed; never restarted/modified in v6 |
| New Delta stub | PID `23594`, port `18645`, shell `98e40d`; remote fixture intentionally preserved after local removal |
| Stub wrapper | `/Users/devin/pim-parity-evidence/v3-20261015-a/timestamp-stub.py` |
| Primary log | `/Users/devin/pim-parity-evidence/v3-20261015-a/dav-requests-resumed.log` |
| Frozen log | `/Users/devin/pim-parity-evidence/v5-20261015-a/secondary-requests-recovered.log` |
| Delta seed/log | `/Users/devin/pim-parity-evidence/v6-20261015-a/delta-seed/`; `delta-requests.log` in the same evidence root |
| DerivedData | `/Users/devin/pim-parity-evidence/v3-20261015-a/ios-derived` |
| Active Brev data root | `/Users/devin/Library/Developer/CoreSimulator/Devices/0AAE0F16-6167-435E-884F-C0BA50E05A67/data/Containers/Data/Application/0AAFFDA3-9142-4F3E-A76C-970BDA4E6064/Library/Application Support/Brev` |

Preserved evidence includes `frozen-preserved-final/`, before/after provider
payloads, original/copied links, the failed initial clipboard read, corrected
clipboard read, request-log boundary snapshots and all 21 numbered screenshots.
All server records are synthetic. Do not reconnect or delete Charlie during
follow-up. Reusable processes remain running; process-local mock credentials
must not be mistaken for signed persistence after locale relaunches.

## Publication and remaining decisions

Only this new v6 report and the current `WORKLOG.md` append were authored in
the checkout. The runtime runner did not run repository lint/format/diff gates
or commit/push; parent-reported automated results and limitations are recorded
above and were not rerun or independently verified here. The subsequent
publication phase passed `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
`MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
`git diff --check`. One documentation-only commit,
`docs(qa): record retained cache and contacts runtime verification`, was
pushed once to `origin fix/pim-parity-gaps`. Tested source revision
`3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f` remains distinct from the
evidence-only publication commit. No CI was dispatched or watched; no PR/issue
actions, merges or releases were performed.

Documentation sweep: QA evidence/worklog only. No new setup, architecture,
privacy or release behavior was implemented by this run, so README, CHANGELOG,
PRIVACY, ADRs and AGENTS were not changed. Blueprint reread: existing targeted
build tooling was reused; explicit-owned-device and disposable-stub isolation
are not fully described there. No new blueprint/skill edits or proposals under
this authorization.

Still needed for broader acceptance: parent review of the snapshot discrepancy
and runtime limits; an isolated macOS configuration; approved isolated live
provider accounts/collections and recipient where required; signing and
physical-device access; spoken accessibility verification; Henrik's final
acceptance. None is required merely to preserve or inspect this v6 evidence.
