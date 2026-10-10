# iOS slice 8c: onboarding keyboard traits, sign-in errors and native share extension (2026-10-10)

Findings O1, O2, O3 and X2 from `docs/qa/ios-ux-audit-2026-10-09/README.md`.
Branch `fix/ios-onboarding-share-extension`, iOS 27.0 simulator (own device
`brev-s8c-qa`, deleted afterwards), `BREV_USE_MOCK=0` so the app opens on the
login page. Driven by a temporary XCUITest kept outside the repo.

| Screenshot | Shows |
| --- | --- |
| `en-light-01-login.jpg`, `nb-light-01-login.jpg`, `en-dark-01-login.jpg`, `en-ax3-01-login.jpg` | Login in a build without a Google client (O2): neutral notice, no developer copy, body-size explanations |
| `en-light-02-add-account-keyboard.jpg`, `nb-light-02-add-account-keyboard.jpg` | Email field focused: email keyboard with the system Passwords (Keychain) suggestion bar and a Go key (O1) |
| `en-dark-02-add-account.jpg` | Add account, dark |
| `en-light-03-after-return-runs-find-settings.jpg`, `en-ax3-03-add-account-after-return.jpg` | Return in Email ran Find settings and revealed the details (O1) |
| `en-light-04-share-extension.jpg`, `en-dark-04-share-extension.jpg`, `nb-dark-04-share-extension.jpg`, `en-ax3-04-share-extension.jpg` | Share extension invoked from Safari's share sheet (X2) |
| `banner-sign-in-required.png`, `banner-sign-in-required-ax3.png` | Sign-in-required banner snapshots (O3): footnote text, 44 pt "Sign in again", full message at AX3 |

## Checks

| Check | Result |
| --- | --- |
| Email field traits | Verified at runtime: keyboard shows `@`, a Go key and the Passwords suggestion bar. Also pinned by `IMAPAccountSetupKeyboardTraitsTests` (reads the `UITextField`: `.username` content type, Go return key, no autocapitalisation or autocorrect). |
| Return in Email | `person@gmail.com` + Go ran Find settings ("Found settings for Gmail"). Gmail is an OAuth path here, so no password field appeared to take focus; for password providers focus moves to Password after discovery (not exercised at runtime, no password-provider fixture). |
| Share extension | Invoked for real: Safari, Page Menu, Share, Brev. Opened in en, nb, light, dark and AX3. "Open Brev" hand-off to the app was not tapped (it would open the compose draft, covered by existing `ShareHandoffURLTests`). |
| `performAccessibilityAudit` login | Clean in en light/dark, nb and AX3. |
| `performAccessibilityAudit` add account | Reports contrast and Dynamic Type on the navigation-bar Cancel/Add buttons (#208, not in this slice) and "Text clipped" on the email field. Not introduced here; the field label now reads "Email address" instead of the placeholder. |
| `performAccessibilityAudit` share extension | One finding: the raw URL text is "not human-readable". It is the URL itself. |
| Banner VoiceOver grouping | `ImportProgressBannerPresentation.accessibilityGrouping` is unit-tested. VoiceOver speech itself was not listened to. |
