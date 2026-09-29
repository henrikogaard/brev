# Desktop Favourites, Mono Grey and transparency — 2026-09-29

This continues PR #162 on `feature/uiux-audit-fixes`, target `main`, from
`7382bc24`. The requested outcome is a compact desktop counterpart to iPhone
Favourites, a softer default dark theme, and understandable transparency
coverage across Mail, Settings, compose and separately opened messages.
No matching issue or project card exists; the PR tracks this work.

## Implemented behavior

| Surface | Result |
| --- | --- |
| Mail sidebar | Favourites first, with All Inboxes and each account inbox; optional Drafts/Sent shortcuts use the shared visibility/order model. Compact single-line rows respect desktop size/density and icon visibility. Smart Views and collapsible accounts follow below |
| Selection | One selected row even when an inbox also appears under its account. Clicking a favourite leaves accounts collapsed; account expansion is saved. Up/Down stays in the sidebar; Return/Right hands focus to messages |
| Editor | Checkboxes, move-up/down controls, native reorder support, and accessible move actions. Inbox counts are unread; Drafts counts are total drafts |
| Theme | Brev Mono Grey joins the built-ins as default dark theme. Saved themes and custom accents remain unchanged. Mono Dark remains available |
| Transparency | Off / Sidebars only / Full windows. Sidebars only includes Mail and Settings sidebars while keeping reading and auxiliary windows solid. Full windows includes Mail, Settings, compose and separate readers |
| Opacity | Sidebar and window backgrounds have independent sliders ending at 100%, with More transparent / Fully opaque labels and coverage previews. Text and icons remain opaque. Advanced holds material style and title-bar integration |
| Accessibility | Reduce Transparency forces solid backgrounds. Sidebar controls expose names, button roles and selection. No VoiceOver audio session was performed |

The macOS reader uses a flat canvas, so the old message-card opacity control
had no effect there and is no longer offered in the desktop UI. Its stored
preference and the separate iPad rendering behavior remain intact. Original
HTML mail can retain its own background; transparency does not rewrite mail.

## Automated and build evidence

Xcode 27.0 on macOS 27, with native AppKit snapshot rendering. All commands
below exited successfully after intentional snapshot recording:

| Check | Result |
| --- | --- |
| BrevMail focused suites | 57 tests in 6 suites, including 20 sidebar/editor image comparisons; Small/Compact and Large/Spacious in light and Mono Grey |
| BrevSettings focused suites | 51 tests in 4 suites, including coverage-choice mapping, theme preservation/defaults, search/category routing and five appearance image comparisons |
| BrevDesign WindowAppearancePreferences | 31 tests, including sidebar-only root backing, Settings/utility coverage, title-bar independence, full opacity and Reduce Transparency |
| BrevThemes BuiltInThemeTests | 9 tests; 37 complete palettes, including Mono Grey text contrast of at least 4.5:1 across its base/secondary/tertiary/selection surfaces |
| macOS build | `script/build_and_run.sh --mock`; dated test identity built and launched |
| Repository gates | Lint, format (0/1,203 files changed), actionlint and diff checks passed |
| iOS build | BrevIOS Debug simulator build, UDID `20E1894E-648E-4BBD-A273-555EDE378FB7`, `/tmp/brev-uiux-ios-build`; BUILD SUCCEEDED |

Reproduction commands:

```sh
swift test --package-path packages/BrevMail --filter 'FolderSidebarSnapshotTests|MailboxFavoritesTests|FolderSidebarPresentationTests|FolderSelectionPolicyTests|SavedSearchSidebarPresentationTests|ThemePreferencesTests'
swift test --package-path packages/BrevSettings --filter 'WindowTransparencySelectionTests|AppearanceThemeSettingsTests|AIWriterSectionMacSnapshotTests/(windowTransparency|desktopSizing)|SettingsNavigationStateTests'
swift test --package-path packages/BrevDesign --filter WindowAppearancePreferencesTests
swift test --package-path packages/BrevThemes --filter BuiltInThemeTests
```

Default-theme and sidebar-only backing assertions first failed against the
previous implementation, then passed. Native arrow navigation reproduced an
early focus handoff; a focused regression assertion and native recheck passed
after the fix. Window toolbar hosting is verified in the running app because
offscreen view snapshots do not reproduce it.

Existing sidebar references were intentionally updated for Favourites/header
placement; the icon-hidden reference also verifies the saved icon preference.
Editor snapshots attach their host to an NSWindow so AppKit List rows render.
The existing compatible-macOS snapshot job includes the new transparency case;
no comparison tolerance was relaxed. Broader unrelated message-row pixel
failures documented in the earlier QA record are not a full-suite pass here.

## Native checks

All screenshots use the dated mock app; `/Applications/Brev.app` was untouched.

| Scenario | Observation |
| --- | --- |
| Account switching | Work favourite opens its source-scoped Inbox without expanding account folders. Collapsed account state survives rebuild/relaunch |
| Favourite editing | Added Private Drafts, moved it above Work, then restored order/visibility. Mouse move controls and checkbox changes work; the latest accessible move actions are code/snapshot covered, not VoiceOver-audio tested |
| Keyboard | Five Down presses from initial sidebar focus reach Drafts through All Inboxes, both inbox favourites and the expanded private Inbox. Up returns to Work; Return then Down opens its conversation |
| Theme | Selected Mono Grey; light theme and the saved custom accent were retained. Native Norwegian appearance labels and percentages render correctly |
| Settings coverage | [Full windows](settings-full-windows.png) and [Sidebars only](settings-sidebars-only.png) show the coverage descriptions, schematic preview and correctly conditional sliders |
| Compose coverage | The same open compose window changes from [solid in Sidebars only](compose-sidebars-only.png) to [translucent in Full windows](compose-full-windows.png), without reopening. No recipient added and no message sent |
| Separate message | The same detached message changes from [Full windows](message-full-windows.png) to [solid in Sidebars only](message-sidebars-only.png) |
| Title bar | Reproduced a white strip with Unified title bar disabled in dark mode. Supplying the theme background to the native toolbar fixed its colour; re-enabling unified title bar also worked |

Full-windows screenshots for compose/message use 50% opacity to make the
coverage difference visible. Settings examples use 82% window/59% sidebar.
The existing custom accent is intentionally retained, so screenshots are not
the untouched Mono Grey palette.

## Limits and handoff

Native control later returned `App quit` followed by `cgWindowNotFound` while
the dated process was running. Reconnecting/relaunching did not recover a
window. The extra full-screen/resize pass and final preference restoration
were therefore not completed. Last verified preferences were Mono Grey,
Small/Compact, Sidebars only, Frosted, 59% sidebar, saved 50% window opacity,
and unified title bar enabled. No cause is inferred from the tool error.

The current iOS source compiles; this follow-up did not repeat the earlier
phone interaction suite because the phone layout is unchanged. No physical
device, VoiceOver audio, live-provider send, or user acceptance is claimed.

[Internal TestFlight 0.2.3 (6)](../testflight-uiux-2026-09-29.md) is now VALID and
IN_BETA_TESTING in Henrik Internal QA. It predates this desktop/theme/transparency
pass. PR #162 remains unmerged; this pass has not been released.
