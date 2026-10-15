# Drive attachments acceptance evidence — v2 — 2026-10-15

Issue: [#14](https://github.com/henrikogaard/brev/issues/14). Branch:
`fix/drive-acceptance-gaps`, based on `origin/main` at `3a553dd`.
This is a new evidence file; prior QA reports are unchanged. It is not
maintainer acceptance or a claim that the entire issue is complete.

## Scope and implementation evidence

The existing implementation from #77/#78 and configuration repair #161 were
retained. No UI, calendar/contact model, OAuth scope, Picker configuration,
release identity, or CI workflow was changed. The only production file changed
is `packages/BrevBackend/Sources/BrevBackend/GoogleDriveClient.swift`.

| Reproduced defect | Minimal fix | Evidence before fix |
| --- | --- | --- |
| Create and overwrite concatenate JSON directly with the next multipart boundary | Terminate the metadata part with CRLF in both methods | Structural parsing found only two parts instead of three in both request-body tests |
| Native `URLError.cancelled` is shown as a transport failure | Preserve it as `CancellationError` at the common transport boundary | Injected native cancellation failed the expected error-type assertion |
| Cancelling an upload invalidates the session retained by the reusable upload closure | Allocate one ephemeral session and immutable progress delegate per upload; invalidate it when that operation ends | A second upload after cancellation terminated the test process with `Task created in a session that has been invalidated` |

The test-only configuration seam exercises the production upload transport with
`URLProtocol`. It does not replace production networking with a fake client.
Only synthetic data and a reserved `.invalid` hostname are used in that test;
no Google traffic is generated. Sessions are isolated per operation, so cancelling
one operation cannot invalidate the session a subsequent operation will use.
This is transport resource cleanup, not proof of remote-file cleanup or atomicity.

## Automated verification

The red run compiled and reproduced all three defects before implementation.
Post-fix package tests and repository checks were run without launching either
app or contacting Google:

| Command | Result |
| --- | --- |
| `swift test --package-path packages/BrevBackend --filter GoogleDrive` | Pass — 12 tests in 2 suites |
| `swift test --package-path packages/BrevMail --filter GoogleDrive` | Pass — 16 tests in 3 suites |
| `scripts/format.sh` | Pass — 0/1285 files formatted; 174 skipped |
| `scripts/lint.sh` | Pass — SwiftFormat lint, SwiftLint strict, coverage self-test, ADR check |
| `git diff --check` | Pass |

Tests verify request shape, injected HTTP/error behavior, and local URLSession
lifecycle. They do not prove Google accepts an upload, that Picker loads with
production referrer restrictions, or that an authenticated platform flow works.
No unrelated snapshots are re-recorded.

## Evidence levels and remaining acceptance

| Evidence level | What is established | What is not established |
| --- | --- | --- |
| Implementation/source | Existing opt-in Drive feature, attach/save sheets, Picker wrapper, event link attachment seams; narrow `drive.file` scope is unchanged | Source inspection is not authenticated acceptance |
| Automated | Focused regression commands above, with explicit outcomes | Not a full application or platform matrix |
| Mocked/stubbed | JSON/multipart request shape; existing metadata/download/export/conflict/error/progress tests; native cancellation and retry use a custom URLProtocol | No Drive server, OAuth, WebKit referrer, or remote cleanup proof |
| Live provider | None in this session | Authenticated Picker, selected-file access, byte upload/download, Workspace export, grant denial/revocation, offline/retry/failure and remote cleanup |
| Platform runtime | None in this session; command-line package tests only | macOS and iOS Picker/sheet interactions, account switching, background/dismiss/cancel behavior, on-device lifecycle |
| Maintainer acceptance | Pending | No issue closure, Done transition, merge or release authorized |

Issue #14's broad acceptance wording includes saving from mail/calendar views.
The current calendar implementation attaches and opens Drive links; it does not
constitute evidence of a calendar-save workflow. Resolve that acceptance wording
against the intended link-only calendar representation before declaring coverage.
This patch does not expand calendar authoring or general PIM scope owned by #11.

## Proposed runtime plan — approval required

1. Read `testing-brev-ui` before any UI work. Use only a dated **Brev Test** app,
   isolated app/profile/build directories and an isolated iOS simulator/device.
   Never replace or terminate `/Applications/Brev.app`.
2. Parent supplies an approved disposable Google QA identity and private build
   configuration for Picker key/project ID through the existing secure mechanism.
   Existing QA/OAuth secret references are present, but their usability was not
   tested. `BREV_ENV_FILE`, `BREV_GOOGLE_API_KEY`, and `BREV_GOOGLE_APP_ID` were not
   available in this checkout environment; no `.env.local` was found here.
   Do not print credentials, tokens, personal filenames, content or links.
3. Verify starting signed-in account and synthetic fixtures before testing.
   If Google again requires recovery-phone verification, stop and relay the gate;
   do not attempt to bypass it or use another person's files.
4. On both platforms, explicitly invoke Drive, decline then approve consent,
   cancel/open Picker, pick a synthetic file and attach bytes/link; export a
   synthetic Workspace document in a supported format. Verify account/token
   alignment and API-key referrer restrictions in the actual packaged host.
5. Save a synthetic mail attachment into a selected folder; exercise rename,
   replace and keep-both; cancel an active upload and then retry in the same app
   session. Verify resulting bytes and remote file counts without logging content.
6. Exercise offline, provider error, access denial and a narrowly coordinated
   grant-revocation scenario. Do not broadly revoke/remove a shared account or
   grant used by concurrent sessions. Verify no stale success or leaked local
   temporary content, and explicitly inspect remote outcomes after cancellation.
7. Drive-only calendar coverage: attach/open a selected Drive link and verify
   persistence through the existing event provider seam. Do not infer calendar
   upload/save support from that result. Use a separate evidence version for runtime
   findings, recording platform/build and mocked vs live status accurately.

## Handoff gates

| Category | Exact remaining gate |
| --- | --- |
| Decision | Explicit approval for UI/live-provider testing; authorization to open a draft PR that triggers the repository's macOS build/test matrix; resolve calendar-save acceptance wording if required |
| Credential | Parent must securely provide approved Picker API-key/project configuration and confirm the disposable QA account can authenticate; existing secret references alone do not prove usable sign-in |
| macOS-host | Host can run local Swift tests, but no isolated authenticated macOS app or iOS simulator/device acceptance run was performed; runtime builds/configuration and device target remain to be prepared after approval |
| Henrik-only | Resolve any recurrence of the previously reported recovery-phone challenge through the account owner; final maintainer acceptance and any eventual Done/merge/release decision |

GitHub Project access is denied by the available token. Intended status is
**In review** after local checks pass and this branch is pushed, not Done.
Branch push alone does not trigger the inspected PR workflows. A draft PR does
trigger them, so PR creation is held for the parent's CI-cost decision; no gates
were disabled and no manual Actions run was started.

## Documentation sweep

- `CHANGELOG.md`: added an Unreleased bug-fix note; no version changed.
- `WORKLOG.md`: records reproduction, fixes, verification and handoff limits.
- `README.md`: no setup, layout or supported-feature change; no update needed.
- `PRIVACY.md` / ADR-0006: same explicit opt-in, endpoints, data and scope; no new
  network behavior or persistent data lifecycle, so no update needed.
- `ADRs/`: ADR-0072's attachment design and ADR-0001/0028 provider boundaries remain
  unchanged; no protected paths or architectural decision changed.
- `AGENTS.md` / release docs: no workflow, signing, packaging or release change.
- This QA report records new evidence without overwriting earlier findings.
