# Release Runbook

This runbook turns a verified local build into a shareable macOS beta
or an internal iOS TestFlight build.
It intentionally keeps signing, notarization, and Sparkle private keys
on Henrik's release machine. CI may build unsigned artifacts, but it
must not receive Developer ID certificates, App Store Connect API keys,
or Sparkle EdDSA private keys unless a later ADR explicitly changes the
release model.

## Release Inputs

- Apple Developer Program membership for Henrik's team.
- Developer ID Application certificate:
  `Developer ID Application: Henrik O. Gaard (<TEAM_ID>)`.
- App Store Connect API key with notarization permission.
- Sparkle 2 tooling available on the release machine, including
  `generate_appcast`.
- Sparkle 2 EdDSA public key exported to
  `BREV_SPARKLE_PUBLIC_ED_KEY` for the release archive build.
- Sparkle 2 EdDSA private key stored on the release machine only.
- A clean checkout of the release commit.
- Final `CHANGELOG.md` entry under the release version.
- Updated `PRIVACY.md` and ADR-0006 network-call table.
- Passing desktop smoke checklist in `docs/qa/desktop-smoke.md`.

## Local Secrets

Keep these out of Git and out of CI logs:

- Apple signing certificates and private keys.
- `BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER` for the macOS Developer ID
  provisioning profile used by the release app. The profile itself is
  installed on the release machine, not committed.
- App Store Connect API key ID, issuer ID, and `.p8` private key
  (`BREV_ASC_KEY_ID`, `BREV_ASC_ISSUER_ID`, `BREV_ASC_KEY_PATH`).
- Sparkle EdDSA private key.
- Any release server credentials for `updates.brevmail.eu`.

The Sparkle public EdDSA key is intentionally not secret. It may be
passed as `BREV_SPARKLE_PUBLIC_ED_KEY` during release builds and is
embedded in the app bundle. The private EdDSA key never leaves the
release machine.

Use local environment files or Keychain-backed tooling. Do not store
release secrets in `.env.example`, workflow YAML, shell history, or
checked-in scripts.

## Version Preparation

1. Choose the release version using ADR-0009 semantic versioning.
2. Move relevant `CHANGELOG.md` entries from `Unreleased` to the new
   version section.
3. Set `BREV_BUILD_NUMBER` in the release machine's `.env.local` to a positive
   integer greater than every previously built or shipped app. The archive
   script requires this explicit value and passes it as `CFBundleVersion` so it
   cannot silently fall back to the repository's development default.
4. Confirm the app marketing version and explicit release build number match
   the chosen release.
5. Confirm `PRIVACY.md` lists every external network call.
6. Confirm `docs/qa/desktop-smoke.md` passes in mock mode and live
   mode.
7. Commit the release-prep changes with a conventional commit, for
   example `chore(release): prepare 1.0.0-beta.1`.

## Verification Gate

Run from repo root:

```bash
scripts/beta-readiness.sh
scripts/desktop-smoke-mock.sh
scripts/privacy-audit.sh
scripts/release-preflight.sh
./script/build_and_run.sh --preflight --live
```

Expected:

- All commands exit `0`.
- `scripts/beta-readiness.sh` is the discoverable local beta gate. Use
  `scripts/beta-readiness.sh --full` for workspace preparation plus
  mock smoke, and `scripts/beta-readiness.sh --release-machine` after
  release artifacts exist on the signing/notarization machine.
- `scripts/release-preflight.sh` may report signing, notarization, or
  Sparkle warnings on non-release machines. On Henrik's release
  machine, run it with `--strict` before archiving.
- Live preflight reports `preflight: live OAuth configuration ready`.

For the final macOS beta packaging evidence pass on Henrik's release
machine, use the bundled closeout collector:

```bash
scripts/release-machine-closeout.sh --app-path /Applications/Brev.app
```

It writes command transcripts and a GitHub-ready summary under
`docs/qa/results/release-machine-$(date +%F)/`, including issue update
snippets for #96, #97, #98, #99, and the umbrella #6. Review logs for
secrets before posting them, and leave project cards in `In review`
until maintainer QA accepts the release artifact.

## iOS Internal TestFlight

The App Store Connect record is **Brev Mail** (`6789346666`) with bundle
identifier `eu.brevmail.brev.ios`. Internal builds use Apple team
`45AD7E7G5G`; confirm that team is signed in under Xcode Accounts before
archiving.

Run the focused configuration gates and generate the workspace:

```bash
scripts/test-apple-team-config.sh
scripts/test-ios-privacy-manifest.sh
scripts/test-testflight-export-options.sh
mise exec -- tuist generate
```

Create the signed archive with automatic provisioning:

```bash
mkdir -p build/testflight
xcodebuild archive \
  -workspace Brev.xcworkspace \
  -scheme BrevIOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/testflight/BrevIOS.xcarchive \
  -allowProvisioningUpdates
```

Before upload, confirm the archive version/build, bundle identifier, and
bundled app privacy manifest:

```bash
plutil -p build/testflight/BrevIOS.xcarchive/Info.plist
test -f \
  build/testflight/BrevIOS.xcarchive/Products/Applications/BrevIOS.app/PrivacyInfo.xcprivacy
codesign --verify --deep --strict \
  build/testflight/BrevIOS.xcarchive/Products/Applications/BrevIOS.app
```

Upload the archive to App Store Connect:

```bash
xcodebuild -exportArchive \
  -archivePath build/testflight/BrevIOS.xcarchive \
  -exportPath build/testflight/upload \
  -exportOptionsPlist scripts/export-options-testflight-internal.plist \
  -allowProvisioningUpdates

```

The checked-in export options preserve the repository version/build and
set `testFlightInternalTestingOnly=true`. Builds uploaded with that flag
cannot later be used for external TestFlight or App Store distribution;
use a separately reviewed export policy for release candidates.

After upload, wait for App Store Connect processing, resolve encryption
compliance when prompted, and add the build only to an internal testing
group. Missing third-party dSYMs do not necessarily block an internal
upload, but treat them as a release-quality issue before public submission.

## Local Test vs Daily-Driver Builds

The default desktop workflow is always a dated, isolated test app:

```bash
script/build_and_run.sh --install-run --mock
# /Applications/Brev Test (YYYY-MM-DD).app
```

`--live`, `--verify`, logging, telemetry, and debugger modes retain the same
test identity unless the explicit release gate below is present. Test builds
use a date-isolated bundle identifier such as
`eu.brevmail.brev.test.d20260826`, may use mock mail or smoke
accounts, and never replace or stop `/Applications/Brev.app`. Mock mode is
passed only to the launched test process; it is never published globally with
`launchctl`, so a later Finder launch of Brev cannot inherit placeholder mail.

Replacing the daily-driver app requires Henrik's explicit approval and this
exact release-main gate:

```bash
script/build_and_run.sh --install-run --release-main --live
```

The script fetches `origin/main` and refuses the operation unless the checkout
is clean and exactly at current `origin/main` (a `main` branch or detached
checkout is accepted). Release-main mode rejects `--mock`, uses the production
bundle identity `eu.brevmail.brev`, and is the only local path allowed to
produce or replace `/Applications/Brev.app`.

## Archive Build

Use the dedicated script, which validates environment variables before
running Tuist:

```bash
# Set required env vars in .env.local first (see Local Secrets above),
# including BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER.
scripts/release-archive.sh
```

This produces `build/release/BrevMail.xcarchive`. Use `--dry-run` to
verify env vars without starting a build. The script enables hardened runtime
for the Developer ID archive, which is required by Apple's notarization
service.

Default Debug builds use `Resources/BrevMacOS.entitlements`. Release builds
use `Resources/BrevMacOSRelease.entitlements` for distribution-backed
capabilities such as opt-in iCloud preference sync. Neither file requests mail
remote-push capability under ADR-0037.

After a real archive, verify that the signed app does not embed a retired APNS
entitlement:

```bash
codesign -d --entitlements :- \
  build/release/BrevMail.xcarchive/Products/Applications/Brev.app
```

Expected: no `aps-environment` or `com.apple.developer.aps-environment` key.

## DMG Creation and Notarization

```bash
scripts/release-dmg.sh
```

This exports the archive with the explicit Developer ID provisioning profile,
creates and signs the DMG, submits it for notarization, staples the ticket,
verifies Gatekeeper, and writes a SHA-256 checksum. Use `--skip-notarize` on
non-release machines to package without Developer ID signing.

Output:
- `build/release/BrevMail.dmg`
- `build/release/BrevMail.dmg.sha256`

Verify the release artifact bundle before publication:

```bash
scripts/release-artifact-verify.sh
```

## Installed-Build Smoke

After DMG creation, test on a clean macOS user account:

```bash
scripts/release-smoke.sh --installed
```

This runs the automated installed-app verification gate
(`scripts/release-installed-verify.sh`) and then prints the remaining
manual checklist. Follow each step, then record results in
`docs/smoke-checklist-results-$(date +%Y-%m-%d)-installed.md`.

## Sparkle Appcast

Sparkle is the direct-download update path described in ADR-0009.
The macOS app links Sparkle only in the direct-download target and
uses Settings -> Updates for cadence, beta channel opt-in, and manual
checks. Development builds keep `BREV_SPARKLE_PUBLIC_ED_KEY` set to a
placeholder, which disables runtime update checks until the release
machine injects the real public key.

1. Confirm the release build has the real public key:
   ```bash
   BREV_SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
     scripts/release-preflight.sh --strict
   ```
2. Generate release notes HTML from `CHANGELOG.md`.
3. Sign the DMG and generate the appcast with Sparkle's EdDSA key:
   ```bash
   generate_appcast \
     --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
     "$PWD/build/release"
   ```
4. Upload the DMG, release notes, and generated appcast to
   `updates.brevmail.eu`.
5. Validate the appcast URL from a clean installed copy with
   Settings -> Updates -> Check for Updates.

Never commit the Sparkle private key. Only the public key belongs in
the app bundle. Publish stable releases to
`https://updates.brevmail.eu/appcast.xml`; publish beta releases to
`https://updates.brevmail.eu/appcast-beta.xml` only after opting the
build/release notes into the beta channel.

### Local Test Appcast QA

Use a throwaway Sparkle EdDSA key when validating the updater before a
real release. The app only accepts `BREV_LOCAL_APPCAST_URL` values that
point at loopback hosts (`localhost`, `127.0.0.0/8`, or `::1`), so this
cannot redirect production users to an arbitrary external feed.

1. Generate a temporary EdDSA keypair:
   ```bash
   cat >/tmp/brev-sparkle-keys.swift <<'SWIFT'
   import CryptoKit
   import Foundation

   let privateKey = Curve25519.Signing.PrivateKey()
   print(Data(privateKey.rawRepresentation).base64EncodedString())
   print(Data(privateKey.publicKey.rawRepresentation).base64EncodedString())
   SWIFT

   swift /tmp/brev-sparkle-keys.swift >/tmp/brev-sparkle-keys.txt
   export SPARKLE_PRIVATE_KEY="$(sed -n '1p' /tmp/brev-sparkle-keys.txt)"
   export SPARKLE_PUBLIC_KEY="$(sed -n '2p' /tmp/brev-sparkle-keys.txt)"
   printf '%s' "$SPARKLE_PRIVATE_KEY" >/tmp/brev-sparkle-private.key
   ```
2. Build or copy a debug app, inject the temporary public key into the
   app under test, and create a separate higher-version update archive:
   ```bash
   rm -rf /tmp/brev-sparkle-qa
   mkdir -p /tmp/brev-sparkle-qa/feed

   ditto .codex/build/macos/DerivedData/Build/Products/Debug/Brev.app \
     /tmp/brev-sparkle-qa/current/Brev.app
   /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" \
     /tmp/brev-sparkle-qa/current/Brev.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c "Add :BRLocalAppcastURL string http://127.0.0.1:8765/appcast.xml" \
     /tmp/brev-sparkle-qa/current/Brev.app/Contents/Info.plist
   codesign --force --deep --sign - /tmp/brev-sparkle-qa/current/Brev.app

   ditto /tmp/brev-sparkle-qa/current/Brev.app \
     /tmp/brev-sparkle-qa/update/Brev.app
   /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 99945" \
     /tmp/brev-sparkle-qa/update/Brev.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.45-local" \
     /tmp/brev-sparkle-qa/update/Brev.app/Contents/Info.plist
   codesign --force --deep --sign - /tmp/brev-sparkle-qa/update/Brev.app

   ditto -c -k --keepParent /tmp/brev-sparkle-qa/update/Brev.app \
     /tmp/brev-sparkle-qa/feed/Brev-0.45-local.zip
   ```
3. Generate the signed appcast and serve it locally:
   ```bash
   Tuist/.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
     --ed-key-file /tmp/brev-sparkle-private.key \
     --download-url-prefix "http://127.0.0.1:8765/" \
     /tmp/brev-sparkle-qa/feed

   python3 -m http.server 8765 --directory /tmp/brev-sparkle-qa/feed
   ```
4. In another terminal, launch the lower-version app built with the
   same temporary public key and local appcast URL:
   ```bash
   open -F -n /tmp/brev-sparkle-qa/current/Brev.app
   ```
5. Open Brev -> Check for Updates... or Settings -> Updates -> Check
   for Updates. The manual check should contact the local appcast and
   offer the synthetic update. If you need to launch the app executable
   directly instead of using `open`, `BREV_LOCAL_APPCAST_URL` may be
   supplied as an environment variable instead of injecting
   `BRLocalAppcastURL` into `Info.plist`. Record the result in the
   issue or release QA notes.

## Clean-Machine Install Test

Run on a clean macOS user account or clean VM:

- [ ] Download the notarized DMG.
- [ ] Mount the DMG.
- [ ] Drag Brev into Applications.
- [ ] Launch without Gatekeeper warnings.
- [ ] Run through the mock smoke checklist if a mock build was shipped.
- [ ] Run through the live OAuth and mailbox smoke checklist.
- [ ] Quit and relaunch to verify session restore.
- [ ] Sign out and verify the app returns to login.

## GitHub Release

1. Tag the release commit:
   ```bash
   git tag -a "v<version>" -m "Brev <version>"
   git push origin "v<version>"
   ```
2. Create a GitHub Release with:
   - notarized DMG
   - SHA-256 checksum
   - release notes rendered from `CHANGELOG.md`
   - known issues from the smoke checklist
   Use `docs/releases/macos-beta-github-release-draft.md` as the
   starting release body, and replace every `<...>` placeholder with
   release-machine evidence before publishing. After the DMG exists,
   generate the filled release body with:
   ```bash
   scripts/release-draft-fill.sh --version "<version>" \
     --dmg-path build/release/BrevMail.dmg
   ```
   The fill step reads the artifact's `.sha256` file and verifies that the
   generated body contains both the exact digest and the versioned
   `Brev-<version>.dmg` asset name. Re-run the verifier with the artifact
   cross-check before publishing:
   ```bash
   scripts/release-draft-verify.sh \
     --draft build/release/github-release-<version>.md \
     --dmg-path build/release/BrevMail.dmg \
     --version "<version>"
   ```
3. Mark prereleases as prerelease until the daily-driver gate is met.

## Release-machine Evidence Runner

To collect all release-machine closure evidence in one pass (archive,
DMG, artifact verification, installed-app verification, release-draft
gate), run:

```bash
scripts/release-machine-closeout.sh --app-path /Applications/Brev.app
```

This writes per-step logs and a summary under
`docs/qa/results/release-machine-<date>/`.

## Rollback

Direct-download rollback is manual because Brev has no telemetry-based
rollout controls.

1. Remove the bad DMG link from the appcast.
2. Re-publish the previous known-good appcast entry.
3. Update the GitHub Release notes to mark the broken build as pulled.
4. If the public key is compromised, rotate the Sparkle EdDSA keypair,
   ship a manually downloaded recovery DMG signed with Developer ID,
   and document the required reinstall path in release notes.
5. Open a public issue describing the failure and the fixed version.
6. Ship a patch release as soon as the root cause is fixed and verified.

For App Store builds, use App Store Connect phased-release controls if
available. If a submitted build is already live and harmful, submit a
fixed patch build and document the workaround in the release notes.

## Future Automation

`scripts/release.sh` should eventually wrap:

- version/build-number validation
- archive and export
- DMG creation
- notarization and stapling
- Sparkle signing and appcast generation
- SHA-256 checksum generation
- final smoke-test prompts

Keep the script interactive for secret-dependent steps so sensitive
values stay on the release machine.
