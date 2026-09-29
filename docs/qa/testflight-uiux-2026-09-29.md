# UI/UX internal TestFlight deployment — 2026-09-29

The user explicitly requested an iOS TestFlight build of the new UI/UX work.
This deploys the feature branch for internal QA; it does not merge PR #162 or
publish an App Store release.

| Item | Evidence |
| --- | --- |
| App | Brev Mail, App Store Connect `6789346666`, bundle `eu.brevmail.brev.ios` |
| Source | `8b3ffbd9fce5befacc32c05cbbbcdc4b01db7db3`, `feature/uiux-audit-fixes`, PR #162 |
| Version | `0.2.3 (6)`; explicit archive overrides preserve the checked-in version fallback |
| Prior build | Apple reported `0.2.3 (5)` as VALID and IN_BETA_TESTING in Henrik Internal QA |
| Toolchain | Xcode 27.0, build `27A266a`, iPhoneOS 27.0 SDK, arm64 Release archive |
| Configuration | Existing Google iOS client verified against the shipping bundle ID and team in Google Cloud; its callback/redirect, Microsoft client and Google Drive configuration were explicitly injected through a private temporary xcconfig. No provider-console setting changed |
| Source CI | All 21 checks passed on `8b3ffbd9`, including both app builds, package tests and snapshot jobs; [Build run](https://github.com/henrikogaard/brev/actions/runs/36604062471) |
| Release gates | Apple team, iOS privacy manifest and TestFlight export-policy scripts passed; `AppSessionFactoryTests.releaseBuildIgnoresInjectedDemoRequest` passed compiled in Release |
| Archive | Completed successfully; app and share/widget/notification extensions all report `0.2.3 (6)`; correct team, bundled privacy manifest, non-exempt encryption flag false and strict deep code-signature verification passed |
| Distribution | Repository internal-only export policy, preserving build number; upload completed; build VALID and IN_BETA_TESTING in Henrik Internal QA |

Native UI evidence is in [navigation polish](navigation-polish-2026-09-29/README.md).
The iPhone interaction and snapshot checks used the simulator. The new archive
also compiles the shared regular-width Settings search hit-area correction.
Physical-device installation, live account sign-in/sending, and user acceptance
are separate checks and are not claimed here.

Local transient artifacts (not committed):

- `/tmp/BrevIOS-0.2.3-6.xcarchive`
- `/tmp/brev-testflight-6-archive.log`
- `/tmp/brev-testflight-6-upload.log`
- `/tmp/brev-testflight-release-guard.log`

## Upload and processing

The export/upload command exited 0 and reported `EXPORT SUCCEEDED` at
19:25:02 CEST (17:25:02 UTC). Apple accepted the package and started processing.
A later App Store Connect API verification on 2026-09-29 confirmed upload
`4f7b85df-535a-442e-b764-598d2244a262` is `COMPLETE`, with empty errors/warnings.
The build resource reports version `6`, prerelease `0.2.3`, `VALID`,
`INTERNAL_ONLY`, and `IN_BETA_TESTING`. The existing Henrik Internal QA group
(`5668fbb5-06ce-49b6-9493-1aee32eee12e`) already includes the build; no additional
group mutation was needed. Internal TestFlight availability is verified.

This build predates the subsequent desktop Favourites, Mono Grey, and window
transparency pass. Those later changes are in PR #162 and are not in build 6.
Physical-device launch was subsequently reported to fail immediately. See the
crash investigation below; processing success did not prove launch success.


## Immediate launch crash investigation

App Store Connect supplied crash reports for internal builds 6 and 5 on
an iPhone 17 Pro Max running iOS 27.0. Both terminate before the first
mailbox frame, approximately 0.2 seconds after launch. Build 6 reports
EXC_BAD_ACCESS in a stack guard while constructing `BrevMailRootView`;
build 5 explicitly reports that the thread stack size was exceeded in
the same computed-view construction chain. Downgrading to build 5 is
therefore not a verified workaround.

A Release simulator regression, `BrevMailRootLaunchTests`, renders the
actual mailbox root with a temporary guard page at the physical iPhone's
1 MiB main-thread stack limit. The unmodified root crashed with signal 11.
Ordinary simulator tests have a larger stack, and Debug builds can erase
opaque SwiftUI types, hiding this failure mode. Raw Apple reports and
simulator diagnostics stay in temporary local storage, outside Git.

The correction introduces fixed-size, deferred rendering boundaries between
the root's existing construction stages. State, tasks, environment values
and navigation remain owned by the mailbox root. CI now runs the dedicated
Release launch regression independently of the iOS 27 pixel baseline gate.
Validation and replacement-build availability are recorded below.
Physical-device acceptance is still required.


## Replacement 0.2.3 (7)

Verified on 2026-09-29 after the immediate-launch report:

| Check | Result |
| --- | --- |
| Source | `08c129299b48e8c41ebb6d9aae5cfe400519006e`, same feature branch and PR #162 |
| CI | All 21 checks passed on the archive source; [Build run](https://github.com/henrikogaard/brev/actions/runs/36623579498) |
| Crash regression | Unmodified Release mailbox root crashed with signal 11 under the phone stack budget; the corrected root passed one executed test, no skips, on local iOS 27.0 and hosted iOS 26.2 |
| Rendering and navigation | 15 Release iOS rendering tests and 40 macOS navigation/reader-retention tests passed; no pixel baselines changed. Hosted iOS pixel comparisons remain deferred on its 26.2 runtime |
| Simulator interactions | Real serve-sim frame verified; message open/return, Favourites/account switching, and Compose open/dismiss passed. No message sent. Original work inbox restored; temporary mirror cleaned up |
| Release guard | Optimised `AppSessionFactoryTests.releaseBuildIgnoresInjectedDemoRequest` passed |
| Archive | Release arm64 archive succeeded; app and all three extensions report 0.2.3 (7). Bundle/team, encryption declaration, privacy manifest, provider configuration parity with build 6 and strict deep signature verification passed |
| Upload | Export/upload exited 0 at 22:23:43 CEST; Apple upload `30deaf61-a8be-46be-a720-d959919eb5a2` is COMPLETE with empty errors/warnings |
| Distribution | Build is VALID, INTERNAL_ONLY, IN_BETA_TESTING. Explicitly added to Henrik Internal QA; read-back confirms the group contains build 7. English TestFlight notes describe the fix and cold-launch check |
| Remaining | Physical iPhone was unavailable to CoreDevice. User cold-launch confirmation, live-provider acceptance and maintainer PR review remain pending; no merge or public release |

Local transient evidence remains outside Git:

- `/tmp/BrevIOS-0.2.3-7.xcarchive`
- `/tmp/brev-testflight-7-archive.log`
- `/tmp/brev-testflight-7-upload.log`
- `/tmp/brev-release-stack-red.log` and `/tmp/brev-release-stack-green.log`
- `/tmp/brev-release-rendering-checks.log`
- `/tmp/brev-ci-release-launch.log`

The initial red run's diagnostic collection timed out after the runner crash;
Xcode still reported TEST FAILED. The corrected stack regression and rendering
run both exited successfully. Signature validation required host trust-service
access; the restricted sandbox's trust error did not recur on the host.
No physical-phone success is inferred from simulator or distribution evidence.
