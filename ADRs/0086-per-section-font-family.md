# ADR-0086: Per-section font family

- **Status:** Proposed
- **Date:** 2026-10-09
- **Deciders:** Henrik
- **Related:** ADR-0002 (theme), ADR-0012 (settings surface, "Desktop text
  size and density"), ADR-0085 (desktop density default)

## Context

Brev has one font family preference, `mailbox.fontFamily`
(`MailboxViewPreferenceKey.fontFamily`, `MailboxFontFamily`: System, Serif,
Rounded, Monospaced). It is set under Settings > Mailbox View > Reading as
"Message font" and applies to mail content only: message list rows, the
reader (header and body, including HTML via `MessageBodyStyle.cssFamily`),
and the compose body. The sidebar, settings and other chrome always use the
system design through `brevFont`. ADR-0012 records this ("The message font
family continues to affect mail content only").

Henrik wants to choose the font for each part of the window separately, for
example a serif reader with a system-font list and a rounded sidebar. Today
one choice moves list, reader and compose together, and the sidebar cannot
change at all.

Constraints:

- Typography stays token-based. Views use `brevFont` and
  `MailboxFontFamily`, never ad-hoc `.system(size:design:)` literals.
- macOS text size (`mailbox.textSize`) and density stay global, as ADR-0012
  decided. This ADR changes family only.
- Existing users must see no change after upgrading.
- The HTML reader needs a CSS family stack; the native editor needs
  `NSFont`/`UIFont`. Any family we offer must map to all three.

## Decision

1. **Four sections, one family each.** Add a `BrevFontSection` enum in
   BrevDesign with these cases:

   | Section | Covers | Key |
   |---|---|---|
   | `sidebar` | Mail folder sidebar: accounts, favorites, smart views, folders | `font.sidebar` |
   | `messageList` | List rows and the in-pane list header | `font.messageList` |
   | `reader` | Reader header, thread cards, message body (plain and HTML) | `font.reader` |
   | `compose` | Compose fields and body editor | `font.compose` |

   Each key stores a `MailboxFontFamily` raw value. Settings, toolbars,
   menus, dialogs and system chrome keep the system design.

2. **Same four families.** Sections offer the existing `MailboxFontFamily`
   cases only. No installed-font picker in this ADR.

3. **Legacy fallback, no write migration.** Resolve each section as:
   `font.<section>` if set, else `mailbox.fontFamily` for `messageList`,
   `reader` and `compose`, else `.system`. `sidebar` falls back to
   `.system`, because it has never followed the message font. Nothing is
   rewritten on upgrade, so a downgrade still reads the legacy key. One
   resolver, `BrevFontSection.resolvedFamily(in: UserDefaults)`, owns this
   rule and gets unit tests.

4. **Environment, not per-view storage.** Add a `brevFontSection(_:)` view
   modifier that sets the section in the SwiftUI environment at each pane
   root, next to the existing `brevDesktopSizing()` calls in
   `BrevMailRootView` and `ComposeView`. `BrevFontModifier` reads the
   section from the environment and applies that section's family design
   to the token (both the Dynamic Type path and the macOS `desktopFont`
   path). Views outside a section keep `.default`. The list, reader and
   compose call sites that read `mailbox.fontFamily` through `@AppStorage`
   today switch to their section's resolved family.

5. **One Settings group.** Settings > Appearance gets a **Fonts** group with
   four pickers (Sidebar, Message list, Reader, Compose) and a "Use one font
   everywhere" shortcut that writes all four keys at once. The group sits
   beside Text and spacing on macOS and in Appearance on iOS. The "Message
   font" row in Mailbox View is removed, and Settings search routes "font"
   to the new group. Appearance > Reset to Defaults clears all four keys.

6. **ADR-0012 amendment.** The "mail content only" sentence in ADR-0012 is
   superseded by this ADR for the sidebar. Text size and density rules are
   unchanged.

## Rationale

- **Per-section family, not per-section size.** Size is already a single
  desktop control with a tuned ramp (ADR-0012). Splitting it per section
  multiplies the settings surface fourfold and breaks the visual rhythm
  between panes. Henrik's request is about typeface. Per-section size stays
  a possible follow-up.
- **Four system designs, not any installed font.** System designs scale
  with Dynamic Type, have weights for every token, and map cleanly to
  `ui-serif`/`ui-rounded`/`ui-monospace` CSS. An arbitrary font needs
  availability checks, missing-weight fallbacks, iOS font installation and
  a CSS family that may not exist in WebKit. Rejected for now.
- **Environment over `@AppStorage` in every view.** Today five views each
  read `mailbox.fontFamily`. Four sections through `@AppStorage` would
  spread key knowledge across more files. One environment value set at the
  pane root keeps the key in BrevDesign and lets previews and snapshot
  tests set a section without touching `UserDefaults`.
- **Read-time fallback over a one-off migration.** A migration needs
  version tracking and breaks downgrade. The fallback is a few lines and
  testable.
- **Alternative: keep one "Message font" and add only a sidebar font.**
  Smaller, but it does not let the reader and list differ, which is the
  main case Henrik named. Rejected.
- **Alternative: theme-defined fonts (ADR-0002).** Themes own colour today.
  Putting typography in theme JSON would tie font choice to colour choice
  and need a theme schema change. Rejected; a theme can still suggest
  defaults later.

## Consequences

### Accepted

- Four new `UserDefaults` keys, all local. No network, no privacy change,
  no Realm change, no backend change.
- `BrevFontModifier` gains one environment read. Cost is negligible next to
  the existing `@AppStorage` read for text size.
- Settings moves the font control from Mailbox View to Appearance, the
  second move in a month (after ADR-0012). Settings search covers both
  names.
- Snapshot tests: new references for the Fonts settings group and for one
  sidebar row, one list row and one reader header in a non-system family.
  New macOS pixel suites join the macOS<26 skip list per AGENTS.md.
- iOS and macOS both get the feature; on iOS the sidebar section is the
  folder list.

### Risks

- **Missed call sites.** A view with a hard-coded design or its own
  `.font()` will ignore its section. Mitigation: grep for `.font(` and
  `design:` in BrevMail during implementation; the snapshot rows above
  catch the main panes.
- **Monospaced sidebar and list rows are wider.** Truncation may change.
  Mitigation: snapshot the monospaced case for the sidebar and list.
- **Mixed families can look busy.** Accepted; the default stays System
  everywhere and "Use one font everywhere" is one click.

## Open questions for acceptance

- Should compose follow the reader by default instead of having its own
  picker (three pickers, not four)?
- Should the mailbox title in the macOS toolbar follow the list section,
  or stay system like other toolbar text?

## References

- `packages/BrevDesign/Sources/BrevDesign/Tokens/BrevFont.swift`
- `packages/BrevDesign/Sources/BrevDesign/Preferences/MailboxViewPreferences.swift`
- `packages/BrevMail/Sources/BrevMail/MessageBodyStyle.swift`
- `packages/BrevMail/Sources/BrevMail/FolderSidebar.swift`
- `packages/BrevSettings/Sources/BrevSettings/Sections/AppearanceSection.swift`
- `packages/BrevSettings/Sources/BrevSettings/Sections/MailboxViewSection.swift`
- ADR-0012 § "Desktop text size and density (2026-09-29)"
