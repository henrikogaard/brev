# Mail status and empty-state localization — 2026-09-30

Mail status, error, and empty-state copy was hardcoded English inside
`packages/BrevMail` presentation types, so a Norwegian interface showed
Norwegian navigation and folder names next to English banners such as
"Couldn't load messages." and empty states such as "No messages". The copy now
resolves through the BrevMail String Catalog, which carries the `nb` values
(for example "Ingen meldinger", "Kunne ikke laste meldinger.", "Prøv igjen").

## Change

- Status, error, and empty-state strings in `MailRefreshPresentation`,
  `FolderMetadataRefreshPresentation`, `MailboxLoadPresentation`,
  `MailboxSwitchPresentation`, `MessageListPresentation`,
  `MessageDetailPresentation`, `MessageCommandPresentation`
  (`mutationErrorStatus`/`mutationTimeoutStatus`), `MessageDetailView`
  (preview-only banner), and `UnifiedInboxListView` resolve through
  `String(localized:bundle:.module)`; interpolated strings use runtime keys
  (`%@`/`%lld` format specifiers).
- `BrevStatusBanner` gains an optional `bundle:` parameter so Swift-package
  call sites resolve against the owning package's catalog instead of the main
  bundle; app-target call sites keep the default lookup path (ADR-0013
  amended).
- `MailStatusCopyLocalizationTests` guards the runtime keys and the plural
  entry so a missing catalog value cannot silently fall back to English.
- Catalog: 40 `stringUnit` entries and one plural entry added to
  `packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings`
  (1116 → 1156 keys).

## Rendered verification

Environment: iPhone 17 Pro simulator (iOS 27), Debug build of `BrevIOS`,
mock backend (`SIMCTL_CHILD_BREV_USE_MOCK=1`), launched with
`-AppleLanguages '(nb)' -AppleLocale nb_NO`, driven through `xcodebuildmcp`
with frames captured through `xcrun simctl io … screenshot`. The `serve-sim`
mirror served the same simulator; the Mac screen was locked during the run,
so the mirror page itself was not visually re-confirmed and the screenshots
below are the simulator framebuffer.

| Screen | Rendered Norwegian copy | Screenshot |
| --- | --- | --- |
| Mock inbox launch | Norwegian mailbox chrome, no English status copy | [00-launch.png](00-launch.png) |
| Search empty state | "Ingen meldinger" / "Ingen treff på «Zzqq»." / "Nullstill søk" | [01-search-empty-state.png](01-search-empty-state.png) |
| Filter empty state (Unread + Attachments) | "Ingen samsvarende meldinger" / "Ingen meldinger samsvarer med gjeldende filtre." / "Nullstill filtre" | [02-filter-empty-state.png](02-filter-empty-state.png) |
| Spam folder empty state | "Ingen meldinger" / "Meldinger du mottar, vises her." | [03-spam-empty-state.png](03-spam-empty-state.png) |

All rendered strings match the catalog `nb` values (spot-verified against the
catalog JSON). The search-finished banner ("Søket er fullført · Noen
resultater kan mangle") is a pre-existing translated key and not part of this
change.

## Limits

- Physical-iPhone acceptance (handoff item 1) is still pending; simulator
  evidence does not close it. The status/empty-state strings covered here are
  not what the physical device is blocked on: the device reports the Gmail
  HTTP 404 session failure from PR #164's scope.
- The reader preview-only banner ("Showing a preview only") is catalog-verified
  and covered by the localization test, but the mock backend does not fail a
  body load, so it has no rendered frame in this record.
- The full `swift test --package-path packages/BrevMail` run shows 54 issues on
  this host (macOS 27): host-renderer snapshot mismatches that reproduce
  byte-identically on a pristine `origin/main` checkout
  (`/private/tmp/brev-main-clean`), matching the CI skip list plus two
  MonoMail suites. They are pre-existing environment-versus-baseline drift,
  not this branch; baselines were not re-recorded.
