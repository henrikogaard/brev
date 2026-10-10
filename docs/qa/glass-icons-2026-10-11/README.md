# Glass icon verification, 2026-10-11

Scope: Frost, Smoke (default) and Obsidian, including the Dock size mismatch
reported while testing the first build. Baseline: `1cdb17f7`.
Host: macOS 27.0.1, Xcode 27.0 (27A266a), Apple Silicon.

| Check | Result |
| --- | --- |
| `swift test --package-path packages/BrevSettings --filter AppIconPreferencesTests` | 7 tests passed, including three parameterized saved-choice/backup cases. The changed default and iOS mapping assertions first failed against the old behavior. |
| `scripts/lint.sh` | Passed, including strict SwiftLint, format lint, coverage self-test and ADR gate. |
| `scripts/format.sh` | Passed, 0 files changed. |
| `scripts/prepare-xcode-workspace.sh` | Passed; generated project changes are limited to icon resources and alternate names. |
| `BREV_ENV_FILE=/dev/null script/build_and_run.sh --verify --mock` | Passed build, launch and startup stability for `Brev Test (2026-10-11).app`. Rebuilt after the sizing fix. |
| `xcodebuild -workspace Brev.xcworkspace -scheme BrevIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .codex/build/ios-icons -skipMacroValidation CODE_SIGNING_ALLOWED=NO -quiet build` | Passed. iOS alternate selection on a physical device was not exercised. |
| Catalog audit | All 20 macOS and 54 iOS manifest entries have their declared pixel sizes. All iOS PNGs are RGB without alpha. iPhone/iPad alternate declarations match Frost and Obsidian. |
| Regeneration | Repeated generation produced identical PNG/PDF/ICNS/catalog outputs with librsvg 2.62.3. |
| Native selector | Clicked Frost, Obsidian and Smoke in the dated mock app; selected states updated and vector previews rendered. Left Smoke selected. |
| Dock size regression | All variants now use `NSImage(contentsOf:)` on ICNS, including Smoke. Each image reports 512x512 logical size. At 16/32/64/128 px all three have identical alpha bounds. The system Dock could not be captured through the UI automation API, so no before/after Dock pixel screenshot is claimed. |

## Login snapshot evidence

The complete `LoginViewSnapshotTests` suite initially had 11 mismatches. A
controlled comparison temporarily restored the exact `1cdb17f7` LoginView source
and original brand asset, ran the same suite, then restored the new files. That
baseline passed four tests and reproduced the other seven mismatches outside
the icon. Those seven existing baselines were left unchanged.

The four icon-only snapshots were visually inspected, recorded, and passed with
recording disabled:

```sh
swift test --package-path packages/BrevMail \
  --filter 'LoginViewSnapshotTests/(brandIconArtwork|compactGoogleIMAPFallback|compactOnboarding|wideLightOnboarding)\(\)'
```

The seven baseline failures are `compactGoogleUnconfigured`,
`compactOnboardingRecovery`, `errorBannerSuppressesGoogleCaption`,
`manualAccountSetupPinsConnectFailure`, `manualAccountSetupStartsEmailFirst`,
`wideOnboarding` and `wideOnboardingSigningIn`. This work does not claim a green
complete snapshot suite. Existing Swift concurrency/deprecation warnings also
remain outside the icon changes.

## Limits

No release, version change, production deployment or daily-driver replacement.
The website counterpart is `henrikogaard/brev-site#1`, checked on the home,
privacy and terms pages at desktop/mobile widths. Privacy/network behavior,
release procedures and agent rules are unchanged, so their documentation does
not need updates. ADR-0004, README, asset notes, CHANGELOG and WORKLOG describe
the changed asset pipeline and defaults.
