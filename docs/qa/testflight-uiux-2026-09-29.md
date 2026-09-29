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
Physical-device installation and user acceptance remain unverified.
