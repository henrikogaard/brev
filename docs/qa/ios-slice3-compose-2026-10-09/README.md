# iOS compose slice — runtime evidence, 2026-10-09

Slice 3 of the iOS UI/UX pass: compose cancel, focus, attachments and native
compose sheets (audit findings C1–C8, C10, plus C9).

| Item | Value |
| --- | --- |
| Build | iOS Debug, `BREV_USE_MOCK=1` mock backend, no real accounts |
| Device | Own simulator (iPhone 17 Pro, iOS 27.0), created for this run and deleted afterwards |
| Driver | A temporary XCUITest bundle outside the repository; it is not committed |
| Variants | English light, English dark, Norwegian (`-AppleLanguages (nb)`) dark, English and Norwegian at AX3 (`UICTContentSizeCategoryAccessibilityXL`) |

## What each shot proves

| Shot | Proves |
| --- | --- |
| `*-01-new-message-*` | New Message opens with the keyboard up and the To field focused (`hasKeyboardFocus` was true in every run) |
| `*-02-cancel-delete-save` | Cancel on an edited draft shows Delete Draft / Save Draft |
| `*-03-swipe-down-blocked-routes-to-choice` | Swiping an edited draft down does not dismiss it; the same Delete/Save choice appears |
| `en-light-08-clean-cancel-closes` | Cancel on an untouched compose closes without a prompt |
| `en-light-09-clean-swipe-down-closes` | Swipe-down on an untouched compose still dismisses |
| `*-04-attach-menu` | The paperclip is a menu. The simulator has no camera or document scanner, so only Photo Library and Attach File appear; Take Photo and Scan Documents are hidden by design |
| `*-05-reply-body-focused` | A reply opens with the body focused and the localized, local-time attribution line |
| `*-06-link-sheet`, `*-07-template-sheet` | Insert Link and Templates are native sheets (URL keyboard, Cancel/Done in the navigation bar, system search) |
| `*-ax3-*` | The compose chrome and fields at AX3; icons scale and the centred title yields to Cancel and Send |

## Not covered at runtime

- Take Photo and Scan Documents: the simulator offers neither. The menu policy
  is unit-tested; the VisionKit and camera wrappers compile and are unexercised.
- Schedule Send and the Google Drive sheets: the mock backend has no scheduled
  send and the build has no Google client. Both are covered by phone-width
  snapshot tests (`ComposeNativeSheetsSnapshotTests`).
- `performAccessibilityAudit` on the new-message screen reports two issues
  (a contrast failure and "Text clipped"); the audit does not name the element.
  The earlier "Dynamic Type partially unsupported" issue is gone.
