# Calendar/Contacts parity evidence v3 — 2026-10-15

**Bottom line:** isolated iOS simulator execution stopped at a reproducible
first-occurrence “This and Future Events” defect. Search, same-process offline
cached reads, and All Events save worked on synthetic DAV data. This is not
full platform/provider acceptance; #11 and #3 remain open.

## Provenance and authorization

| Item | Value |
| --- | --- |
| Source revision | `08f1f461d59ede0e793b74eb205563479c94961e` |
| Worktree / branch | `/Users/devin/repos/brev-pim-parity`, `fix/pim-parity-gaps` → `main` |
| PR | [#245](https://github.com/henrikogaard/brev/pull/245) |
| Session | [QA session](https://app.devin.ai/sessions/930e6447745b410bb056d921d709803a) |
| Approval | Henrik: “yes, keep working and get the work done”, answering the isolated macOS/iOS/disposable-provider QA request, as relayed by parent |
| Stop rule | Stop at first reproducible product defect, preserve evidence, propose minimal fix; parent decides before any product change |
| Runtime | Fresh owned iOS simulator `Brev PIM v3 20261015 A`, iOS 27.0, UDID `0AAE0F16-6167-435E-884F-C0BA50E05A67` |
| Toolchain | `/Applications/Xcode-27.0-RC.app/Contents/Developer`; pinned Tuist 4.119.4 |
| App | Debug `BrevIOS.app`, `eu.brevmail.brev.ios`, `BREV_USE_MOCK=1`, `-AppleLanguages '(en)'`, `CODE_SIGNING_ALLOWED=NO` |
| Data | Owned loopback DAV fixtures only; three events and two contacts initially; no live-provider login or data access |
| Scope limits | Simulator, same-process in-memory DAV credentials; no signed persistent-Keychain, physical iPhone, macOS runtime, suspended execution, or live-provider claim |

The unchanged v2 report was the execution plan. Historical reports, artifacts
and the inherited automated baseline were preserved, not rerun. No product
source, entitlement, signing configuration, CI, issue or release change
was made during runtime execution. The evidence and WORKLOG were subsequently
committed and pushed to PR #245 after lint/format checks. #14 Drive scope was
not tested.

## Failure F1 — future scope at the first occurrence

**Actual:** selecting This and Future Events on the first occurrence leaves
two same-time rows. The old record is also renamed to the edited title and
its recurrence ends one day before its DTSTART. Duplicate rows remain after
explicit calendar sync.

**Expected:** changing this and all future events at the first occurrence
leaves one effective series, with the edited title and five valid daily
occurrences, not an additional visible record whose UNTIL predates DTSTART.

Reproduction, using only the owned synthetic fixture:

1. Connect Calendar through Settings → Calendar & Contacts → Add DAV Source →
   Manual server URL `http://127.0.0.1:18643/`. Enable Background sync and editing.
2. Open Calendar and select `brev-pim-20261015-a Series`.
   Seed UID is `brev-pim-20261015-a-series`, DTSTART `20261015T190000Z`,
   DTEND `20261015T193000Z`, RRULE `FREQ=DAILY;COUNT=5`.
3. Edit the title to `brev-pim-20261015-a Series All`; Save → All Events.
   Detail shows the new title and “Every Day 5 times”.
4. Edit the same event to `brev-pim-20261015-a Series Future`; do not change
   dates. Save → This and Future Events.
5. Detail shows start Thursday, 15 October and “Every Day until 14 Oct 2026”.
   Return to Calendar: two same-title/same-time series rows.
6. Click Sync calendars now. Both rows remain. This persistence check was
   the final runtime action; testing stopped.

| Before future-scope action | After action — observed failure, not a fix |
| --- | --- |
| ![Initial populated calendar](https://app.devin.ai/attachments/a3f6762b-f959-4c45-842a-f57db6d16556/01-calendar-en-light.png) | ![Duplicate rows persist after sync](https://app.devin.ai/attachments/302c3ce1-7607-4388-9350-a7e217c9c3db/03-future-scope-duplicate-after-sync.png) |
| ![Valid five-occurrence series before](https://app.devin.ai/attachments/cee84528-ee72-4538-b028-7f132fdb23a2/04-before-future-scope-detail.png) | ![Old series ends before start](https://app.devin.ai/attachments/14a185bc-af66-43fa-8b9d-3e413dc73577/05-invalid-until-detail.png) |

Corroboration from the owned cache after the sync at `17:15:51Z`:

| Record | Start / recurrence / title |
| --- | --- |
| Original `v3-series.ics`, UID `brev-pim-20261015-a-series` | `2026-10-15T19:00:00Z`; `FREQ=DAILY;UNTIL=20261014T190000Z`; `brev-pim-20261015-a Series Future` |
| New `BE6DB56F-D0E0-41D7-B739-7EDCFCDD62BE-brev.ics` | Same start; `FREQ=DAILY;COUNT=5`; same edited title |

Redacted stub process output:

```text
2026-10-15T17:14:35.666985+00:00 PUT /cal/u/main/v3-series.ics cond="seed-v3-series" -> 204
2026-10-15T17:15:24.117972+00:00 PUT /cal/u/main/v3-series.ics cond="stub-2-1792084475666" -> 204
2026-10-15T17:15:24.120917+00:00 PUT /cal/u/main/BE6DB56F-D0E0-41D7-B739-7EDCFCDD62BE-brev.ics cond=* -> 201
2026-10-15T17:15:51.369694+00:00 REPORT /cal/u/main/ -> 207
```

**Narrow proposal, not implemented:** guard the first-occurrence boundary in
`CalendarEditingModel.saveFutureScope` (around lines 433–493). When there is
no earlier occurrence to retain, update the original series in place instead
of truncating it to an earlier UNTIL and creating another series. Add focused
first-occurrence coverage and rerun this exact UI sequence. A genuine later
split should preserve original master fields for past events; this pass did
not execute a later-occurrence split and does not claim that behavior.
The detail UI remained attached to the original record after splitting; the
parent should include that readback in the bounded follow-up.

## Per-row runtime results

| Matrix / assertion | Result | Fresh evidence and limit |
| --- | --- | --- |
| iOS source baseline | Passed | UI connection yielded 3 cached events and 2 contacts, synthetic Calendar and Contacts sources |
| 2.2 event search | Partial pass | Alpha query returned one matching event; unmatched query showed no-match state. Only one calendar source; cross-calendar search not executed |
| 2.3 offline events | Partial pass | Owned stub stopped at `17:11:44Z`; opening Calendar and Alpha detail retained time/location/notes/source. Same app process, not relaunch restoration |
| 2.6 All Events | Passed, stub only | Conditional PUT 204; title and five-occurrence recurrence read back |
| 2.6 This and Future Events | **Failed** | F1 above; first-occurrence duplicate and invalid old-series end persist after sync |
| 3.2 contact search | Partial pass | Alice query filtered two contacts to one. Multiple address books/no-match variant not executed |
| 3.3 offline contacts | Partial pass | Stub stopped; Alice search and cached detail retained email, phone and notes. Same-process only |
| 4.4 independent-source failure | Untested | Stopped for F1; whole-stub offline check is not independent-source isolation |
| 4.5 expired cursor recovery | Untested | Stopped for F1; no expiry injected |
| 4.6 cache removal/rebuild | Untested | Stopped for F1; no source/cache removal exercised |
| Populated English/light UI | Partial evidence | Calendar, Contacts, event/contact detail and event editor captured; not a complete accessibility/layout sign-off |
| Norwegian/dark/AX text size/reduced motion | Untested | Stopped for F1 before those variants |
| VoiceOver spoken readback | Untested | No actual VoiceOver traversal or speech captured. Simulator AX label inspection is not spoken readback |
| AX labels | Inconclusive | Event editor exposed labeled fields; populated list/detail children were not reliably exposed through Simulator's macOS bridge. Not filed as a product accessibility defect without actual VoiceOver verification |
| macOS keyboard/populated UI | Untested | macOS launch blocked by shared app-group resolution |
| macOS 4.3 idle pickup | Untested | Isolation preflight prevented launch; no cadence/idle timing claim |
| macOS 1.8 timeout, 2.5 conflict, 2.8 RSVP | Untested | Same isolation blocker |
| iOS 2.7/2.8/4.3 | Not repeated | Historical evidence preserved; no fresh attendee/RSVP/idle claim |
| Live Google | Untested | References available, but safe persistent credential/account isolation not established; no auth attempt and no current challenge claim |
| Live CalDAV/CardDAV | Untested | No approved dedicated endpoint/credentials discovered; mail credentials not substituted |
| Physical iPhone / signed Keychain | Untested | No device execution; `security find-identity -v -p codesigning` returned `0 valid identities found` |
| Maintainer acceptance | Pending | F1 and remaining provider/platform evidence block completion |

## Authoritative macOS no-launch preflight

`CFFIXED_USER_HOME=/Users/devin/pim-parity-evidence/v3-20261015-a/home`
redirected normal Application Support, but Foundation application-group lookup
still returned:

```text
Optional(file:///Users/devin/Library/Group%20Containers/group.eu.brevmail.brev/)
```

The shared group is used by `WidgetSnapshotStore` and share handoff and is in
the normal macOS entitlements. No macOS Brev process was launched for this pass.
No personal state was copied or read. Parent explicitly agreed not to change
product code, entitlements or signing to bypass this blocker. An isolated OS
user, or separately approved signed app-group arrangement, remains required.

## Setup and reusable owned state

Missing pinned Tuist was installed using the existing authenticated mise
blueprint command. `scripts/prepare-xcode-workspace.sh` then succeeded.
The targeted simulator build succeeded with owned DerivedData:

```text
DEVELOPER_DIR=/Applications/Xcode-27.0-RC.app/Contents/Developer
xcodebuild -workspace Brev.xcworkspace -scheme BrevIOS -configuration Debug
  -destination 'platform=iOS Simulator,id=0AAE0F16-6167-435E-884F-C0BA50E05A67'
  -derivedDataPath /Users/devin/pim-parity-evidence/v3-20261015-a/ios-derived
  -skipMacroValidation CODE_SIGNING_ALLOWED=NO -quiet build
```

| Owned resource | State at handoff |
| --- | --- |
| App process | PID `4639`, still running on the owned simulator; do not relaunch expecting in-memory credentials to persist |
| Stub process | PID `5246`, `127.0.0.1:18643`, shell `1c1bd8`; still running with failing recurrence state |
| Stub runner | `/Users/devin/pim-parity-evidence/v3-20261015-a/timestamp-stub.py`, imports unchanged repository stub |
| Original stub | PID `3781` deliberately stopped for offline checks; restarted from seed before edits, not left running |
| App data root | `/Users/devin/Library/Developer/CoreSimulator/Devices/0AAE0F16-6167-435E-884F-C0BA50E05A67/data/Containers/Data/Application/ED647919-457B-4A08-8902-CDD90E7C6DE1` |
| Build | `/Users/devin/pim-parity-evidence/v3-20261015-a/ios-derived/Build/Products/Debug-iphonesimulator/BrevIOS.app` |

Other simulators, apps and servers were not stopped or repurposed. The
simulator AX shortcut targets the first booted device, so interaction used
the specifically named owned Simulator window. Only synthetic local data
was changed. No live cleanup was needed because no live objects were created.
Local failing records were deliberately retained for reproduction.

## Evidence paths

All paths below are local artifacts; the embedded image URLs above require
access to the Devin session and are not public repository assets.
Base directory: `/Users/devin/pim-parity-evidence/v3-20261015-a/`.

- Primary annotated recording:
  `/Users/devin/screencasts/pim-v3-ios-primary/pim-v3-ios-primary-edited.mp4`.
- `01-calendar-en-light.png`, `02-contacts-en-light.png`,
  `03-future-scope-duplicate-after-sync.png`,
  `04-before-future-scope-detail.png`, `05-invalid-until-detail.png`.
- `06-calendar-search-alpha.png`, `07-calendar-no-match.png`,
  `08-contact-offline-detail.png`, `09-event-offline-detail.png`,
  `10-populated-editor-en-light.png`.
- `owned-events-after-sync.json`, `owned-contacts.json`,
  `owned-pim-sources.json`: copied only from the new owned simulator.
- `dav-requests.log`, `dav-requests-resumed.log`: auth redacted.
  The runner timestamps stdout; the stub's `--log` file remains untimestamped.
  No bounded-idle timing conclusion relies on these files.
- `seed/`: original owned ICS/VCF fixtures; `isolation-probe.log`,
  `ios-build.log`, `workspace.log`, `tuist-install.log`.

No real password, token or recovery code was entered into the recording.
The bundled demo mail sidebar is synthetic (`.example` identities), not
personal mailbox data.

## Parent / Henrik actions and setup suggestions

1. Parent decides whether to authorize the narrow F1 implementation and its
   regression run. No further product/runtime scope was assumed.
2. Approve an isolated macOS OS-user or separate signed app-group setup before
   macOS QA. Do not treat `CFFIXED_USER_HOME` as app-group isolation.
3. Provision usable signing/Keychain capability for persistence testing and
   an actual physical iPhone if that acceptance layer is required.
4. Identify dedicated DAV endpoint(s), credential references, synthetic-only
   collections and second approved invite recipient. Existing Google QA
   references do not prove consent or account cleanliness; after safe isolation,
   complete any real challenge normally, without bypass.
5. Resume unexecuted rows above; final acceptance remains Henrik's decision.

Blueprint already covers pinned-tool install, workspace generation and the
iOS build. Suggested safety update: replace generic `simctl ... booted`
examples with explicit owned UDIDs and owned DerivedData; document fresh-device
creation, isolated loopback stub setup and the application-group preflight.
No blueprint was changed. Suggested testing-skill note is outside the repo:
`/Users/devin/pim-parity-evidence/v3-20261015-a/SKILL.md`.

Documentation sweep: new QA report and appended worklog only. No shipping,
privacy/network, architecture, release or policy change requiring README,
CHANGELOG, PRIVACY, ADR or AGENTS edits. No tests, lint, formatting, snapshots
or unrelated suites were rerun during runtime execution. Evidence publication
then ran `scripts/lint.sh`, `scripts/format.sh` and `git diff --check`; all
passed, with no files reformatted.
