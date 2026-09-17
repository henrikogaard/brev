# ADR-0080: Stable and Nightly release rings with CI-signed updates

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Henrik
- **Amends:** ADR-0009 (distribution and code signing), ADR-0006
  (network calls table)

## Context

ADR-0009 chose Sparkle 2 with EdDSA-signed appcasts for macOS
direct-download updates and specified a Stable feed plus an opt-in Beta
feed, both served from `updates.brevmail.eu`. The in-app side of that
decision exists: `MacUpdateController` drives `SPUStandardUpdaterController`,
`UpdateBuildConfiguration` gates Sparkle on a direct-download build with a
configured public key, and Settings → Updates exposes cadence and a
Stable/Beta channel picker.

What does not exist:

- No release has ever been published through the feed. The tag `v0.2.0`
  exists, `updates.brevmail.eu` does not respond, and the repository holds
  no GitHub Actions secrets.
- ADR-0009 and `docs/release.md` require the Developer ID certificate, the
  App Store Connect API key, and the Sparkle private key to stay on
  Henrik's release machine and never reach CI. That rules out automated,
  signed nightly builds.
- The Beta channel is a *same-app* channel switch. Switching back to Stable
  leaves the user stranded until a Stable version overtakes the beta
  version, and a bad beta replaces the daily-driver app that Rule 7 in
  `AGENTS.md` protects.

Henrik has asked for two release rings, Stable and Nightly, with signed
builds produced automatically: Stable on a release tag, Nightly from `main`
every night between 00:00 and 01:00.

## Decision

### 1. Two rings, two apps

| Ring | Product | Bundle identifier | Trigger | Version scheme |
| --- | --- | --- | --- | --- |
| Stable | `Brev.app` | `eu.brevmail.brev` | Push of tag `vX.Y.Z` | `X.Y.Z`; `CFBundleVersion` = `YYYYMMDDHH` of the build |
| Nightly | `Brev Nightly.app` | `eu.brevmail.brev.nightly` | Schedule, plus manual dispatch | `X.Y.Z-nightly.YYYYMMDD` where `X.Y.Z` is `BrevConstants.marketingVersion`; `CFBundleVersion` = `YYYYMMDDHH` |

Nightly installs side by side with Stable. It has its own bundle
identifier, its own `UserDefaults` domain and Keychain access group, its
own Sparkle feed, and a badged app icon so the two are distinguishable in
the Dock. Nothing about Nightly can replace or update `Brev.app`.

The ring is a **build-time property** carried in `Info.plist` as
`BRReleaseRing` (`stable` | `nightly`) alongside `SUFeedURL`. Both are
injected through build settings (`BREV_RELEASE_RING`,
`BREV_SPARKLE_FEED_URL`) using the same `BREV_APP_PRODUCT_NAME` /
`BREV_APP_BUNDLE_ID` override mechanism that `script/build_and_run.sh`
already uses for `Brev Test (…).app`. Local and CI test builds default to
`stable` ring metadata but remain unable to initialize Sparkle because they
carry the public-key placeholder (existing `canInitializeSparkle` rule).

The ADR-0009 Beta channel is retired. `UpdateChannel` and the
`updates.channel` preference are removed; a stored `beta` value is
ignored. Settings → Updates shows the installed ring read-only and, for
the Stable ring, a link to the Nightly download page (and vice versa).
There is no in-app ring switch.

`CFBundleVersion` uses the build timestamp so it increases monotonically
across both rings and across re-tags, satisfying Sparkle's comparison
and the ADR-0009 requirement that build numbers only grow. Sparkle
compares `CFBundleVersion` first; the marketing version is display only.

### 2. Signed builds in GitHub Actions

ADR-0009's "never accessible to CI" rule for signing material is
**replaced**. Release material is stored as GitHub Actions repository
secrets and used only by the two release workflows:

| Secret | Contents | Used for |
| --- | --- | --- |
| `BREV_DEVELOPER_ID_P12_BASE64`, `BREV_DEVELOPER_ID_P12_PASSWORD` | Developer ID Application certificate | `codesign` of app and DMG |
| `BREV_MACOS_PROFILE_STABLE_BASE64`, `BREV_MACOS_PROFILE_NIGHTLY_BASE64` | Developer ID provisioning profiles for the two bundle ids | Export (required because the release entitlements include iCloud KVS) |
| `BREV_ASC_KEY_ID`, `BREV_ASC_ISSUER_ID`, `BREV_ASC_KEY_P8_BASE64` | App Store Connect API key | `notarytool` |
| `BREV_SPARKLE_PRIVATE_ED_KEY` | Sparkle EdDSA private key (base64, `generate_keys -x` format) | `sign_update` / `generate_appcast` |
| `BREV_SPARKLE_PUBLIC_ED_KEY` | Matching public key | Injected into `SUPublicEDKey` at build time (repository *variable*, not secret) |

Rules:

- The secrets are only referenced by `release.yml` and `nightly.yml`.
  `build.yml` and `lint.yml` remain unsigned and secret-free
  (`permissions: contents: read`).
- Both workflows run in a dedicated `release` GitHub environment so
  secrets are scoped and environment protection rules can be added later.
- Keys are imported into a temporary keychain created for the job and
  deleted in an `always()` step. Nothing is written to the checked-out
  tree.
- The Sparkle private key is written to a file with mode `0600` in the
  runner's temp directory and removed in the same `always()` step.
- Third-party actions are pinned to a commit SHA, as `build.yml` already
  does.
- The same signing key pair signs both rings. A separate Nightly key
  would not reduce blast radius (a compromised runner exposes both) and
  would complicate `SUPublicEDKey` injection.

The existing `scripts/release-archive.sh` and `scripts/release-dmg.sh`
are the single implementation and gain `--ring stable|nightly`,
`--version`, and `--build-number` inputs so that local and CI runs share
one path. Notarization, stapling, DMG creation, and Sparkle signing are
unchanged in mechanism.

The Developer ID signing style and ring-specific provisioning profile are
configured on the `BrevMacOS` app target's Release configuration. The archive
script passes the selected profile through the custom
`BREV_PROVISIONING_PROFILE_SPECIFIER` build setting rather than setting
`PROVISIONING_PROFILE_SPECIFIER` globally. SPM package targets do not support
provisioning profiles and must remain outside that app-only signing scope.

### 3. Hosting: GitHub Releases and GitHub Pages

`updates.brevmail.eu` is retired as the update host. Both feeds and all
artifacts live on GitHub:

| Artifact | Location |
| --- | --- |
| Stable DMG `Brev-X.Y.Z.dmg` | Asset on the GitHub Release for tag `vX.Y.Z` |
| Nightly DMG `Brev-Nightly-YYYYMMDD.dmg` | Asset on a rolling pre-release tagged `nightly`; the previous night's asset is replaced. The pre-release body records the source commit. |
| `appcast.xml` (Stable), `appcast-nightly.xml` (Nightly) | Published to the `gh-pages` branch, served at `https://henrikogaard.github.io/brev/` |
| Release notes HTML | Same `gh-pages` branch, generated from `CHANGELOG.md` (Stable) or from `git log` since the previous nightly (Nightly) |

Appcast regeneration is idempotent: the workflow checks out `gh-pages`,
rewrites only the feed for its own ring, and force-pushes nothing.
Sparkle's `generate_appcast` is not used because it requires every prior
archive on disk; `scripts/release-appcast.sh` signs the DMG with
`sign_update` and merges one `<item>` into the existing feed. No delta
updates are published. Stable keeps the full history of entries; Nightly
keeps the last 14. Because the rolling pre-release holds only the current
DMG, older Nightly items point at removed assets; Sparkle only offers the
newest item, so this is accepted.

### 4. Nightly schedule and skip rule

- Cron `30 23 * * *` UTC (00:30 CET / 01:30 CEST) plus
  `workflow_dispatch`. GitHub cron may start late; the window is best
  effort.
- Before building, the job compares `main`'s head to the commit recorded
  on the current `nightly` pre-release. If they match, the job exits
  successfully without building or publishing.
- Nightly builds `main` only. The workflow refuses any other ref.
- Nightly requires the Build workflow to have passed on that commit.

### 5. Privacy and network behavior

The update check destination changes from `updates.brevmail.eu` to
`henrikogaard.github.io` (appcast, release notes) and
`github.com` / `objects.githubusercontent.com` (DMG download). Per ADR-0006
and Rule 6 the check remains:

- Off for App Store, TestFlight, and unsigned test builds.
- Governed by Settings → Updates cadence (once per launch, weekly,
  manual) for signed direct-download builds of either ring.
- Free of message content, account identity, or identifiers beyond the
  request metadata Sparkle sends (app version, OS version, IP address,
  user agent). Sparkle's optional system-profile reporting stays disabled.

`PRIVACY.md` and the ADR-0006 network table are updated in the same PR.
Nightly is described in `PRIVACY.md` as a pre-release build with the same
privacy posture as Stable.

## Rationale

**Why a separate Nightly app.** Firefox Nightly and VS Code Insiders set
the expectation: a pre-release ring is a second app you can keep next to
the one you rely on. It removes the downgrade problem inherent in a
same-app channel switch, keeps the Rule 7 guarantee that `Brev.app` is
never replaced by unvetted code, and gives Nightly its own preferences so
a broken migration cannot corrupt Stable's state.

**Why keys in CI.** A nightly ring that requires a human to sign at
00:00 is not a nightly ring. A self-hosted runner keeps the keys local
but ties the schedule to one Mac being awake and reachable. Repository
secrets in a dedicated environment are the standard trade-off for a solo
open-source project; the compensating controls are environment scoping,
temp-keychain hygiene, SHA-pinned actions, and the ability to revoke and
re-issue the Developer ID certificate and Sparkle key pair if the account
is compromised.

**Why GitHub hosting.** The ADR-0009 host was never provisioned. GitHub
Releases already hold the DMG links "for redundancy" under ADR-0009;
making them primary removes an unowned server, a deploy credential, and a
second privacy destination to document.

**Why build-time ring instead of a runtime switch.** With two bundle
identifiers there is nothing for a runtime switch to do. Removing the
picker also deletes the untested `beta` code path.

**Why timestamp build numbers.** They need no shared counter, are
monotonic without coordination between the tag workflow and the nightly
workflow, and encode the build date for support.

## Consequences

### Accepted

- ADR-0009's signing-material custody rule no longer holds. Henrik must
  create the secrets listed in §2 and a second App ID plus Developer ID
  provisioning profile for `eu.brevmail.brev.nightly` in the developer
  portal before the first signed run.
- Users on the Beta channel (none exist; no release shipped) lose
  nothing. The `updates.channel` preference is orphaned and ignored.
- The Nightly pre-release is a moving target; anyone linking to a
  specific nightly must link to the dated DMG asset name.
- `docs/release.md` becomes the runbook for the tag-driven Stable release
  plus the manual fallback, not the primary release path.
- `scripts/release-archive.sh` and `scripts/release-dmg.sh` grow ring
  awareness; `scripts/test-developer-id-release-config.sh` gains
  assertions for the nightly export options.

### Risks

- **Secret exfiltration from a compromised workflow dependency.**
  Mitigated by SHA pinning, no third-party action touching the keychain
  step, and the environment scope. Residual risk accepted.
- **Notarization latency or outage** fails the nightly. The job fails
  visibly; there is no unsigned fallback publish.
- **iCloud KVS entitlement** ties the Nightly bundle id to a provisioning
  profile that expires yearly. Profile expiry surfaces as an export
  failure in CI; the runbook records renewal.
- **Rolling `nightly` tag** is force-moved each night. Tooling that
  assumes immutable tags must ignore it.

## References

- ADR-0006: telemetry, privacy, and network calls table
- ADR-0009: distribution and code signing (amended)
- `AGENTS.md` Rule 6 and Rule 7
- `docs/release.md`
- Sparkle publishing: https://sparkle-project.org/documentation/publishing/
- Sparkle feed signing keys: https://sparkle-project.org/documentation/#segue-for-security-concerns
