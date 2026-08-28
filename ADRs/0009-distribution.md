# ADR-0009: Distribution and code signing

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev needs to ship to users on both macOS and iOS. The decisions are:

- App Store, direct distribution, or both?
- Code-signed under what identity?
- Auto-update mechanism?
- Release cadence and versioning?

MIT historically had friction with the Mac App Store (VLC's well-
documented case in 2011). Apple's current terms accept MIT with
appropriate license disclosures, but there's residual ambiguity.

## Decision

### macOS: dual distribution

- **Direct download (primary).** Released via GitHub Releases. Hosted
  installer DMG signed with Henrik's Developer ID (Apple's
  Gatekeeper requirement), notarized via Apple's notary service.
  Auto-update via Sparkle 2.x with EdDSA-signed appcasts hosted at
  `updates.brevmail.eu/appcast.xml`.
- **Homebrew Cask (secondary).** A `brev` cask in homebrew-cask
  installs the latest DMG. Tracks GitHub Releases.
- **Mac App Store (v1.1).** Submitted after v1 ships to direct
  channels. MIT compliance handled per Apple's current acceptance
  of the license. Updates ship to both channels in parallel.

### iOS: App Store only

- **App Store** is the only realistic distribution channel on iOS.
- Released via Apple Developer Program under Henrik's personal
  identity.
- TestFlight beta available before v1 release.
- App Store and TestFlight builds include an app-level Apple privacy
  manifest. Brev declares no tracking or developer data collection.
  Access to file timestamps and size metadata inside the app container
  is declared with reason `C617.1`; the local message-source cache uses
  that metadata only for size-bounded pruning.

### Code signing

- **Developer ID:** Henrik Ø. Gaard (personal Apple Developer
  account).
- **Team identifier:** `45AD7E7G5G`, the App Store Connect team used for
  Brev distribution.
- **Mac signing identity:** "Developer ID Application: Henrik Ø.
  Gaard (<TEAM_ID>)".
- **Mac App Store signing identity:** "3rd Party Mac Developer
  Application: Henrik Ø. Gaard (<TEAM_ID>)" (different from above;
  used only for MAS submissions).
- **iOS signing identity:** "Apple Distribution: Henrik Ø. Gaard
  (45AD7E7G5G)".

Personal-name identity is simpler than registering a business and
matches the project's open-source-personal-project nature. If Brev
later grows into something requiring a business identity (employees,
tax structure changes, corporate users requiring it), we re-sign and
migrate. App Store transfers between Apple accounts are supported.

### Sparkle setup

- **Sparkle 2.x** for macOS auto-update.
- **EdDSA signing keys** (not the older DSA). Private key stored in
  Keychain on Henrik's release machine; never committed to repo;
  never accessible to CI.
- **Appcast at** `https://updates.brevmail.eu/appcast.xml`.
- **DMGs at** `https://updates.brevmail.eu/releases/Brev-<version>.dmg`
  (also linked from GitHub Releases for redundancy).
- **Release notes** rendered inline in Sparkle from
  `appcast.xml`-referenced HTML files. Source of truth lives in
  `CHANGELOG.md` and is rendered to HTML at release time by
  `scripts/release.sh`.
- **Update check cadence:** once per launch by default. User can
  switch to weekly/manual in Settings → Updates.

### Versioning

Semantic versioning:

- **MAJOR.** Breaking changes to user data format, account migration
  required, or v1→v2 type transitions (IMAP support, etc.).
- **MINOR.** New features (theme additions, new settings, etc.).
- **PATCH.** Bug fixes.

Build numbers monotonically increase across all versions (Apple
requirement for App Store; convenient for Sparkle).

### Release cadence

- **No fixed cadence.** Releases happen when work is ready. Solo
  project — there's no obligation to ship on a schedule.
- **Beta channel:** TestFlight on iOS, separate Sparkle appcast
  (`appcast-beta.xml`) on macOS. Opt-in via Settings.
- **First release:** v1.0.0 only after the daily-driver gate of
  ADR-0028 is met for both platforms.

### Mac App Store deferred to v1.1

Reasons:

1. Mac App Store review adds latency to releases and friction to
   features that interact with the file system (entitlement quirks).
2. MIT + Mac App Store, while workable, requires extra steps that
   I'd rather do once the app is stable.
3. Sparkle + GitHub Releases is the standard open-source-Mac
   distribution path and serves the early audience well.

iOS App Store is not deferred because there is no alternative
channel for iOS distribution.

### What's not in v1

- **Subscription, paywall, or in-app purchase.** Brev is free.
  Donations possible via GitHub Sponsors or Ko-fi link (ADR-0028
  positioning).
- **Receipt validation, license keys.** Free app; no receipts.
- **Telemetry-based gradual rollout.** No telemetry; releases are
  global.
- **Crash-driven rollback.** No automatic crash reporting (ADR-0006).
  Rollback if needed is manual (re-release prior version's appcast
  entry, or pull the App Store version).

## Rationale

**Why dual distribution on Mac.** Open-source Mac users overwhelmingly
prefer direct download via Sparkle. Mac App Store gives reach to
less-technical users and visibility. Both have low marginal cost
once code signing is set up. Doing both is standard for projects
like this.

**Why iOS-only via App Store.** Apple's policy forbids non-store
distribution on iOS (TestFlight aside). No decision to make.

**Why personal Developer ID.** Simpler legally, no business setup,
matches the project's character. App Store account transfers are
possible if this changes.

**Why Sparkle 2.x with EdDSA.** Sparkle 2.x is the modern standard.
EdDSA signing replaced the older DSA in Sparkle 2; we should not
inherit weak crypto by accident.

**Why no fixed cadence.** Solo project. Schedule pressure produces
bad releases. We ship when we're ready.

## Consequences

### Accepted

- Maintaining two distribution channels (Sparkle + Mac App Store
  eventually) doubles the per-release work. Mitigation: `scripts/
  release.sh` automates both.
- TestFlight has a 90-day expiry; betas need re-issuing if the
  release timeline extends. Acceptable.
- Mac App Store version may lag direct-download by days (review
  time). Documented on landing page.

### Risks

- **MIT + Mac App Store edge cases.** If Apple changes terms or
  rejects a release for MIT reasons, we fall back to direct-only
  on Mac. No real loss — direct is the primary channel anyway.
- **Sparkle EdDSA key compromise.** If the private signing key is
  stolen, attackers can publish malicious updates. Mitigation: key
  lives only on Henrik's release machine (never CI), regular
  password manager backup, key rotation procedure documented in
  `docs/release.md`.
- **iOS App Store rejection.** First submission may bounce for
  metadata or compliance reasons. Plan a week of buffer for v1
  iOS release.
- **Account name change.** If the developer identity name needs to
  change (e.g. legal name change, marriage), re-signing is required
  and existing installs see an "Identity changed" warning. Low
  probability.

## References

- ADR-0028: initial project rationale (MIT inheritance)
- ADR-0028: Project identity and scope
- Sparkle: https://sparkle-project.org/
- Apple Developer Program: https://developer.apple.com/
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple privacy manifest required-reason APIs:
  https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
