# Continuation QA review — 2026-09-28 (main @ `3d882f9`)

Scope: continuation verification pass on `main` after PRs #144 (WidgetKit
mail-summary widget, iOS+macOS, ADR-0083), #145 (iOS store file protection
`UntilFirstUserAuthentication`, ADR-0082), #151 (auth-required sync banner →
"Sign in again" → pre-filled reconnect sheet), #152 (Microsoft OAuth client-ID
wiring — env only). Environment: iPhone 17 simulator, iOS 27.0
(UDID `8E780854-5816-4435-AD8F-8098DF847EB5`); Xcode 27.0 RC toolchain per repo
blueprint; live accounts Gmail (`h3nrik.0gard@gmail.com`, Gmail API backend) and
Mailo (`henrik.ogard@mailo.com`, IMAP/SMTP).

## ⚠️ Build blocker found on this machine's toolchain

Both the iOS workspace build and `script/build_and_run.sh --mock` (macOS)
**failed** on `main` before any test could run:

```
xcstringstool generate-symbols … Localizable.xcstrings →
"error: This string key would generate the same symbol as …" / "Unable to derive
a symbol name …" / "This key is too close to a reserved keyword in Swift. …"
```

- `packages/BrevSettings/…/Localizable.xcstrings`: ~28 collision groups
  (e.g. `days`/`Days`, `Reconnect`/`Reconnect…`, `Saved in Keychain`/`Saved in
  Keychain.`) plus un-nameable keys (`%@ → %@`, `%lld%%`) and reserved key `Type`.
- `packages/BrevMail/…/Localizable.xcstrings`: ~43 collision groups (e.g.
  `All Mailboxes`/`All mailboxes`, `Block Sender`/`Block Sender?`/`Block
  Sender…`, `Create Task…`/`Create task`).
- Root cause: PR #148's l10n import added all ~1,100 keys to previously
  near-empty catalogs — including duplicate-looking pairs whose normalized Swift
  symbol names collide. Catalogs are valid JSON with no literal duplicate keys;
  the collision is only at symbol-generation time.
- **CI is green on the same commit** (`build (BrevIOS)`, `build (BrevMacOS)`
  both `success` on `3d882f9`) — CI's `macos-15` Xcode accepts these keys;
  Xcode-27.0-RC's `xcstringstool` is stricter. `SWIFT_EMIT_LOC_STRINGS=NO` did
  **not** bypass it (SPM catalog symbol generation ignores that setting).
- Workaround used for this QA pass: temporarily dropped the colliding keys from
  the two catalogs for the local build (English fallback still renders the
  strings; only `nb` translations for dropped keys absent). Originals preserved
  in git / `/tmp/*_Localizable.orig.xcstrings`; working tree restored after
  builds.
- **Action needed on main**: either rename/de-duplicate the offending keys so
  `generate-symbols` passes on Xcode 27, or disable symbol generation for the
  affected catalogs. Until then every local build on this machine's documented
  toolchain fails.

## Results

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | iOS build installs fresh @3d882f9, `BrevMailWidgets.appex` in PlugIns | PASS | bundle `5FBC3240…`, widget appex + share ext + notification ext present; Google client ID baked; `BREVMicrosoftOAuthClientID` empty |
| 2 | `WidgetSnapshot.json` written to `group.eu.brevmail.brev` (ADR-0083) | PASS | file appears on launch; schema `version:1, generatedAt, totalUnread:5, previews[3]` each `{senderName, subject, receivedAt, accountName}` |
| 3 | #151 auth banner → "Sign in again" → pre-filled reconnect sheet | PASS | banner "Sign-in required / Sign in again to continue." + "Sign in again" button; tap opens sheet with `h3nrik.0gard@gmail.com` pre-filled and locked, "Found settings for Gmail.", "Sign in with Google" offered |
| 4 | Google OAuth token persists cold relaunch (no re-auth) | PASS | terminate → relaunch → Gmail INBOX clean, no banner; log: `oauth2.googleapis.com/token` → 200, `gmail.googleapis.com/…/history` → 200s |
| 5 | macOS `Brev Test (2026-09-28).app` mock build runs | PASS | script build green post-patch; app launches into mock mailbox (list + threaded reader render); `/Applications/Brev.app` untouched |
| 6 | Mailo IMAP send→receive roundtrip | PASS | composed self-send in app, received in Mailo INBOX ~40 s later as unread |
| 7 | Microsoft sign-in stays hidden with unset client ID (#152) | PASS | outlook.com address → disabled "Microsoft sign-in not configured" row + explanatory text; no enabled OAuth button (matching the designed gating) |
| 8 | VoiceOver spot-check on message list | PASS (spot) | every row/control has full label ("Unread, M, Mailo, 4m, QA continuation send test…"); VO focus box selects rows correctly |

## Notes / nits (non-blocking)

- **Reconnect-sheet title mismatch**: for the Gmail OAuth account the #151
  reconnect sheet is titled "Update mail password" — a password-centric title on
  an OAuth path. It still offers "Sign in with Google", so the flow works, but
  the title is misleading.
- **Banner cosmetics**: the "Sign-in required" banner sits directly under the
  nav-bar title and reads a bit cramped on iPhone 17, but no overlap with the
  title in this build (screenshot in session artifacts).
- **iOS app-group consent dialog names the app "Brev Test (2026-09-28)"** on
  first launch after install — consistent with the dated test-identity
  convention, noted for awareness.
- Widget snapshot previews present because `NotificationSettings.showPreviews`
  was on in this install — the privacy gating branch itself was not toggled in
  this pass.

## Not covered / blockers

- **Microsoft sign-in end-to-end**: not exercisable — `BREV_MICROSOFT_OAUTH_CLIENT_ID`
  unset by design and no Microsoft test account exists. The hidden/disabled
  state is the only checkable surface and it behaves as designed.
- #145 file-protection enforcement is not directly observable in the UI;
  the build ran normally (protection is applied silently to the store dirs).
- VoiceOver was a spot-check only (labels + focus), not a full swipe-order pass.

Recording: `brev-continuation-3d882f9` (session artifact). Screenshots in
`/Users/devin/screenshots/`; supporting logs in `/tmp/`.
