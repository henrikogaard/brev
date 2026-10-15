# Drive attachments acceptance evidence — v4 — 2026-10-15

Completed the bounded runtime procedure: the isolated iOS synthetic ineligible-source no-Save state passed; authentic Google acceptance and macOS runtime remain blocked.

PR: [#244](https://github.com/henrikogaard/brev/pull/244), issue [#14](https://github.com/henrikogaard/brev/issues/14).
Revision: `0f10db03ea930859e7b3fae691fc1c37087e944d`.
Checkout: `/Users/devin/repos/brev-drive`, branch `fix/drive-acceptance-gaps`.
[Devin session](https://app.devin.ai/sessions/75be006f1e754c3b92ff30f482a70e30).

This evidence version does not replace v2/v3 or constitute maintainer acceptance. No repository files, Git state, PR, issue, board, CI workflow, release, or daily-driver app were changed during the runtime pass. Checkout was clean at the pinned revision before and after the run; the subsequent evidence commit contains only this report and `WORKLOG.md`.

## Prerequisites and blockers

| Item | Observed state | Consequence |
| --- | --- | --- |
| Dedicated Google identity | Lead confirmed `secret:repo:henrikogaard/brev:BREV_QA_GOOGLE_EMAIL` and `BREV_QA_GOOGLE_PASSWORD` are dedicated disposable Workspace QA refs | Credential usability and actual grant are **not verified**; values were not accessed or used |
| Picker configuration | No `BREV_GOOGLE_API_KEY`, `BREV_GOOGLE_APP_ID`, or `BREV_ENV_FILE` environment values; no checkout `.env.local`; lead confirmed no Picker key/app-ID secret refs listed | Authentic Picker start cannot be established; no unnecessary sign-in/challenge attempt |
| Built iOS configuration | Presence-only plist inspection found Picker key/app ID and OAuth iOS client ID unset in this synthetic build | This build is not a configured live-Drive acceptance build; available OAuth refs were deliberately not injected without Picker prerequisites |
| Eligible event fixture | No established dedicated Google-linked read-only calendar source with real binary/Workspace attachment files | Positive calendar-save start is blocked, not replaced by synthetic provider success |
| macOS isolation | No authorized isolated OS user or App Group arrangement established | macOS was not built/launched; `CFFIXED_USER_HOME` is not accepted as App Group isolation |
| Native accessibility semantics | `ios` AX targets the first booted, non-owned simulator; owned iOS process did not answer macOS AX requests | Full accessible names/roles and VoiceOver remain untested; other simulators were not stopped |

No personal mailbox or daily-driver App Group was read. No Google challenge bypass, broad revocation, browser-cookie API call, or fake Google auth was used.

## Evidence levels

| Level | This report establishes | Limits |
| --- | --- | --- |
| Implemented | Tested pinned app includes the new calendar save eligibility path; source references are in the runtime plan | Source existence does not establish positive runtime behavior |
| Automated prior | v2/v3 and PR description retain the lead's prior automated evidence | No package/unit/snapshot suites were rerun here; prior automation is not live acceptance |
| Synthetic-native | Running iOS app renders two actual parsed link attachments from a standalone local DAV event; no Save action for its genuinely unlinked source | Bundled demo mail plus loopback DAV fixture; no Google server/files/grant |
| Live-provider | None | All positive Google rows below blocked |
| Platform | Owned iOS 27 simulator, pinned Debug unsigned build, EN/NB, accessibility-extra-large layout | No macOS runtime, physical device, native VoiceOver, authenticated WebKit Picker, or positive save sheet coverage |

## Runtime setup and starting state

- Read full `AGENTS.md` and `testing-brev-ui` skill. Blueprint reviewed.
- Created owned iPhone 17 simulator **Brev Drive QA v4**, UUID `3A71F572-F1FA-4F1E-B763-17D4F074CFE7`; did not reuse/terminate other devices.
- Built with Xcode-27.0-RC `xcodebuild`, `BrevIOS`, Debug, `-skipMacroValidation CODE_SIGNING_ALLOWED=NO`, explicit destination UUID and new QA-only DerivedData. Build completed successfully. No global tools were installed.
- The attempted Xcode-27 `Simulator.app` path did not exist. Recovered using the already-running Simulator, which displayed the newly owned iOS 27 device. This setup exception did not substitute another app revision.
- Installed only to the owned simulator and launched with `BREV_USE_MOCK=1`. Maximized its Simulator window before the recording.
- Started repository `scripts/stub-dav-server.py` at `127.0.0.1:8654` with one fixture outside the repository. Through native Settings → Calendar & Contacts → Add DAV Source, connected the loopback source and selected Sync Now.
- Persisted **actual source** is `calDAV`, `enabledCapabilities=["read"]`, `syncEnabled=false`, status `ready`, and **`linkedAccountID` is absent**. It resides only in the owned simulator app container. Source name: `Drive QA local - no Google`.
- Event `Drive QA - ineligible source` contains `QA binary.pdf` and `QA workspace` URI attachments. Their Google-shaped IDs are fabricated fixture IDs; they do not denote real Google files. Links were not opened.
- Feature route: Mailboxes → Calendar → event row → attachment section. The new action is gated through `CalendarRootView.swift:329-342,365-392`, `CalendarDriveSaveEligibility.swift:78-87`, and `CalendarEventDetailView.swift:477-528`. Native DAV connect omits linked account at `PIMSourceSettingsModel.swift:322-335`; default nil/read-only source creation is `PIMSourceCoordinator.swift:97-125`.

## Assertions and required-scope coverage

| Assertion | Result | Actual evidence / limitation |
| --- | --- | --- |
| No Save on an actual ineligible source | **Passed — synthetic-native** | Both attachment link rows visible with read-only notice and source label; neither row has Save. Persisted source proves linked account absent; not inferred from an unrelated screen |
| Reselect same event | **Passed — synthetic-native** | Back → same event retains both links and no-Save state |
| EN/NB negative-state UI | **Passed — visual subset** | English `Attachments`; Norwegian `Vedlegg`, `Notater`, `Kopier lenke`, translated read-only notice. Fixture names intentionally remain English |
| Large-text attachment reachability | **Passed — visual subset** | At accessibility-extra-large, both rows reachable by scrolling, no overlap between attachment controls; labels middle-truncate. Restored default `large` size afterward |
| Accessible names/roles, VoiceOver, eligible Save/retry localized UI | **Untested** | AX targeting limitation and no eligible Google start; do not infer semantics or positive-flow translations from screenshots |
| Preserve local event while viewing | **Passed — synthetic-only** | Before/after EN/after NB SHA-256 identical; zero DAV PUT/DELETE. This does not prove Google source bytes/link preservation after save |
| Actual dedicated Google auth/grant restricted to `drive.file`; authentic Picker/config/referrer | **Blocked** | Missing Picker key/app ID; no sign-in performed |
| Read-only eligible Google-linked source with real binary and Workspace attachments | **Blocked** | Required dedicated-account source/fixtures not established |
| Explicit Drive opt-in and exact-file Picker matching | **Blocked** | Positive start unavailable |
| Binary download/save and explicitly selected Workspace export | **Blocked** | No authentic Picker or real fixtures |
| Destination validation, Keep Both, original source-file overwrite protection | **Blocked** | No authentic destination/upload/conflict flow |
| Retry/cancel and event-link/source-byte preservation after save | **Blocked** | No save/upload operation attempted |
| Denial, revocation, offline and late completion | **Blocked** | No safely disposable authenticated operation/grant established; no broad revoke |
| macOS native acceptance | **Blocked** | Genuine OS-user/App Group isolation unavailable; no launch |

No independent product UI defect was established in the reachable negative state. The limited run does not justify merge readiness.

Local viewing-preservation digest: `dcda8c93978d24f4788c74fccf34b436eab142439410b0c5b724a3449ff6c22f`.

## Visual evidence

[Primary annotated recording — synthetic iOS no-Save state](https://app.devin.ai/attachments/ac54f331-0972-4adf-b4ef-8c58229600d2/drive-v4-native-ineligible-edited.mp4).

| English — actual unlinked source | Norwegian — same cached event |
| --- | --- |
| ![EN synthetic-native ineligible source: attachment links, no Save](https://app.devin.ai/attachments/760077b3-ccf3-48be-ba73-eb077c195e38/ios-en-ineligible.png) | ![NB synthetic-native ineligible source: Vedlegg, no Save](https://app.devin.ai/attachments/101d094a-9813-4bcc-9c32-bc4b1dc1c09c/ios-nb-ineligible.png) |

| Norwegian default text | Norwegian accessibility-extra-large, scrolled |
| --- | --- |
| ![NB default text](https://app.devin.ai/attachments/101d094a-9813-4bcc-9c32-bc4b1dc1c09c/ios-nb-ineligible.png) | ![NB larger text: both link rows reachable, no Save](https://app.devin.ai/attachments/84edb28d-efc7-432d-86d5-12ef7fa42e9c/ios-nb-large-text.png) |

## Follow-up environment and artifacts

Owned app PID at handoff: `18636`; local fixture server PID: `17710`, port `8654`. Both left running. Simulator remains booted in NB at normal text size. Locale relaunch drops the mock credential store; cached event remains available, but **reconnect the local source before future sync/write tests**. No source removal or daily-driver action is needed.

All supplemental artifacts are under `/Users/devin/.devin-files/drive-qa-v4-20261015/`:

- `test-plan.md`, `ios-build.log`, `synthetic-source.json`, `dav-requests.log`
- `seed/drive-ineligible.ics`, `event-before.ics`, `event-after-en.ics`, `event-after-nb.ics`
- `ios-en-ineligible.png`, `ios-nb-ineligible.png`, `ios-nb-large-text.png`
- Primary video: `/Users/devin/screencasts/drive-v4-native-ineligible/drive-v4-native-ineligible-edited.mp4`

## Smallest next actions

1. Lead/owner securely supplies **Picker developer key and numeric Google project app ID** corresponding to the existing OAuth clients, with required APIs enabled and packaged-host restrictions configured. Suggested secure names are `BREV_GOOGLE_API_KEY` and `BREV_GOOGLE_APP_ID`; no values in chat/report. See [Google API credentials](https://console.cloud.google.com/apis/credentials) and [API library](https://console.cloud.google.com/apis/library).
2. Confirm existing dedicated Workspace identity can authenticate; if the known recovery challenge recurs, account owner resolves it directly. Do not use Aurora/personal credentials. No auth attempt is needed until Picker configuration exists.
3. In that dedicated account, establish a read-only eligible calendar source linked to the same Google account and actual disposable binary/Workspace attachments plus destination/conflict fixtures. Fixture links/content must remain synthetic. Then rerun the blocked positive rows against real Google, verifying actual grant/Picker rather than stubs.
4. For macOS only, provide an authorized isolated OS user or a genuinely isolated App Group arrangement. `CFFIXED_USER_HOME` alone is insufficient.
5. Use a dedicated simulator/tool-targeting arrangement for native AX/VoiceOver verification without stopping another session's simulator.

## Blueprint and skill follow-up

The existing blueprint covers Xcode-27 iOS builds and mock launch, but not safe multi-session runtime isolation. Suggested update: require fresh/owned simulator UUID and explicit per-run DerivedData for install/launch; do not use ambiguous `booted` on shared hosts. Document optional loopback DAV fixture setup, locale process-scoped credential caveat, and require genuine macOS App Group isolation before its mock-launch command. No dependency-install change is needed.

Suggested update to `testing-brev-ui` is supplied separately outside the repository: `SKILL-testing-brev-ui-isolation.md`. It records the lead-provided macOS isolation prerequisite and removes unsafe assumptions about host source-copying/other-session simulators.

Net: native synthetic negative-state evidence advanced; live-provider, eligible-source, accessibility semantics, and macOS acceptance remain open. No merge/closure/Done/release authorized or performed.
