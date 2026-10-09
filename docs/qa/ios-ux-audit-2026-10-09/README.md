# iOS UI/UX and accessibility audit — 2026-10-09

Audit of the Brev iOS app (iPhone and one iPad pass) against the iOS HIG and
Apple Mail conventions. This is an audit only: no product code changed.

| Item | Value |
| --- | --- |
| Source | `origin/main` at `5eb968dc` (includes #209 reader header) plus a local, unpushed merge of `origin/fix/ios-account-setup-sheet` (#208) |
| Branch | `audit/ios-ux-2026-10-09` (local only) |
| Toolchain | Xcode 27.0 (27A266a), iOS 27.0 simulator runtime |
| Devices | Own simulators `brev-audit-iphone` (iPhone 17 Pro, 402×874 pt) and `brev-audit-ipad` (iPad Pro 11-inch M5); both deleted after the run |
| Data | `BREV_USE_MOCK=1` mock backend only; onboarding via `BREV_USE_MOCK=0`; no real accounts |
| Driver | A temporary XCUITest target (`BrevIOSAuditUITests`, never committed) that walks each surface, saves a screenshot and the accessibility tree, and runs `XCUIApplication().performAccessibilityAudit(for: .all)` per screen |
| Variants | English light; English dark; Norwegian (`-AppleLanguages (nb)`) dark; AX5 (`UICTContentSizeCategoryAccessibilityXXXL`); nb + AX3; built-in themes Gruvbox Light, Solarized Dark, Catppuccin Latte, Blurple Night; iPad portrait and landscape |
| Code review | Every iOS-reachable view in `BrevMail`, `BrevSettings`, `BrevDesign`, `BrevWidgets`, and `apps/iOS` extensions, read for the same checklist |

## 1. Bottom line

The iPhone app is close to native at the top level (list rows, context menus,
Settings root, the #208 add-account sheet, the #209 reader header), but almost
every second-level surface is still a macOS layout running on a phone. The
reader is a ZStack overlay with no push or swipe-back, archiving from it
silently swaps to another message, and it carries two or three competing •••
menus. Compose closes without asking and opens without a keyboard. Selection
mode has no Cancel. Settings panes, sheets and PIM editors are custom
card/`VStack` layouts with bordered buttons and grey info bands instead of
`Form`/`List` with nav-bar actions. Accessibility is the other large gap:
Dynamic Type is capped on most mail chrome, dozens of controls are below 44 pt,
opacity-dimmed text fails contrast in all 37 built-in themes, six themes ship
an accent colour below 4.5:1, and the widget and share extension are
English-only (the widget also lacks the iOS 17 `containerBackground`). Eight
mostly independent PRs (section 3) cover it; the first three (reader
navigation, list selection and swipe, compose) remove most of the
"not like iOS Mail" feeling.

## 2. Findings

Severity: **P0** blocks use · **P1** clearly wrong or inaccessible · **P2** polish.
Effort: **S** < half a day · **M** 1–2 days · **L** > 2 days.
Screenshot names refer to `screens/`. Raw `performAccessibilityAudit`
output per screen is in `a11y-audit/` and summarised in section 2.11.
File paths are relative to `packages/BrevMail/Sources/BrevMail/` unless they
start with `packages/` or `apps/`.

### 2.1 Mailbox list and selection

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Mail reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L1 | List · multi-select | P1 | Native feel / Usability | There is no Edit/Select button. Selection mode is only reachable from a row's long-press menu ("Select"). Once in it there is no Cancel/Done; the mode only ends when every row is unticked or via ••• → Deselect All (`isInSelectionMode = !bulkSelection.isEmpty`); the bulk bar is an inline strip of six 28×28 pt icons plus a 28 pt overflow; search and compose stay on screen. Audit: 3× "Hit area is too small" (`en-light-22-select-mode.jpg`, `en-light-22b-select-two.jpg`, `en-light-22c-bulk-more.jpg`). The overflow item "Done" (mark as done) reads like "exit selection". At AX5 the count wraps as "1 select-ed" while the bulk icons stay tiny (`en-ax5-22-select-mode.jpg`). | iOS Mail: "Select" in the nav bar → circles appear, nav bar shows "Select All" / "Cancel", bottom bar shows Mark · Move · Trash/Archive. Use `List(selection:)` with `.environment(\.editMode, …)` on iOS, a `ToolbarItem(placement: .topBarTrailing)` Select/Cancel, and `ToolbarItemGroup(placement: .bottomBar)` for bulk actions (44 pt by default). Rename the overflow item "Mark as Done". | `MessageListView.swift:376, 641-684, 3660-3668`; `UnifiedInboxListView.swift:994-1016`; `BulkActionIconButton.swift:42-49`; `MessageCommandPresentation.swift:608` | M |
| L2 | List · row | P1 | Visual / Accessibility | Unread is a 3 pt bar in `textPrimary`, and the sender is bold on every row, so read and unread rows look almost the same (`en-light-01-list-inbox.jpg`). Read rows still expose a child element labelled "Unread" (tree: Harbour Logistics row). | iOS Mail: filled accent dot left of the sender, semibold only when unread. `Circle().fill(theme.accent.color).frame(width: 10, height: 10)` and `.fontWeight(header.isRead ? .regular : .semibold)`; `.accessibilityHidden(header.isRead)` on the marker. | `MessageListView.swift:3417, 3850-3862` | S |
| L3 | List · section headers | P1 | Accessibility / Native feel | Date groups ("Today · 3") are collapse buttons only 18 pt tall; audit flags them; a test tap meant to dismiss a swipe landed on one and collapsed "Yesterday" (`en-light-06b-swipe-right.jpg`). No `.isHeader` trait. Label "Yesterday, 1 messages" (wrong plural; nb "I går, 1 meldinger"). | iOS Mail has no date grouping. On compact width drop collapsible groups, or render a non-interactive `Section` header with `.accessibilityAddTraits(.isHeader)`; plural via catalog variants (see N3). | `MessageListView.swift:4086-4135` | S |
| L4 | List · unified inbox | P1 | Usability | All Inboxes uses the desktop row variant: one-line truncated subject, extra account line, no compact VoiceOver value (`en-light-10c-unified-inbox.jpg` vs `en-light-01-list-inbox.jpg`). | Pass `isCompactWidth: horizontalSizeClass == .compact` as `MessageListView` does. | `UnifiedInboxListView.swift:1081` (cf. `MessageListView.swift:833`) | S |
| L5 | List · nav bar | P2 | Native feel | A Refresh button sits in the nav bar (iOS Mail has none) and pull-to-refresh goes through a different path (`reloadVisibleMessages` → `reload()`) from the button (`refreshVisibleMail`); check on a live account that pulling actually fetches new mail. Title is a custom `.principal` view with an "N unread" capsule, centred in a mailbox but leading-aligned in All Inboxes (`en-light-01-list-inbox.jpg`, `en-light-10c-unified-inbox.jpg`). | iOS Mail: large title "Inbox", status ("Updated just now · 5 unread") in the bottom bar. Route `.refreshable` to `refreshVisibleMail()`, drop the compact-width button (keep ⌘R), use `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)` and `.navigationSubtitle` for the account. Stop forcing an opaque `toolbarBackground` so iOS 26 scroll-edge effects work. | `BrevMailRootView.swift:2136, 2205-2231, 2267-2281, 6428`; `MessageListView.swift:757, 1976, 3079`; `MailPaneSurface.swift:33, 44, 228-229` | M |
| L6 | List · swipe | P2 | Native feel | Leading swipe is Flag (full swipe) + Read; iOS Mail's full swipe right toggles read. Trailing has Delete + Archive only, both the same dark filled circles (`en-light-06-swipe-left.jpg`). | `leadingSwipeActions = [.toggleRead]`; trailing `[.more, .flag, .archive/.trash]` with "More" opening the action sheet; tint destructive with `theme.danger`, archive with `theme.info`. | `MessageCommandPresentation.swift:830-834`; `MessageListView.swift:1437-1500` | S |
| L7 | List · context menu | P2 | Usability | The row long-press menu has about 20 items and scrolls past the screen; "Move…" is below the fold (`en-light-06c-context-menu.jpg`, `en-light-25-move-sheet.jpg`). | Order like iOS Mail (Reply / Reply All / Forward, then Mark / Flag / Snooze, then Move / Archive / Trash) and fold Create Task / Rule / Meeting / Note / Properties / Copy Link into one `Menu("More")` submenu. | `MessageCommandPresentation.swift` (detail/list context actions) | S |
| L8 | List · undo toast | P1 | Usability / Accessibility | After a swipe-archive the "Archived · Undo ×" toast covers the search field and compose button (`en-light-26-undo-toast.jpg`). Undo and Dismiss are borderless footnote buttons under 44 pt (audit 3× hit area), nothing posts an announcement, and the window is 5 s. | Inset it above the bottom toolbar with `.safeAreaInset(edge: .bottom)`, 44 pt buttons, post `AccessibilityNotification.Announcement`, and extend the timeout while VoiceOver or Switch Control is running. | `BrevMailRootView.swift:1089, 1116-1133`; `packages/BrevDesign/Sources/BrevDesign/Components/BrevToast.swift`; `UndoableMutation.swift:47` | S |
| L9 | List · Dynamic Type | P1 | Accessibility | `MailDenseChromeDynamicType.compactRange` caps the search field, category bar, row status icons and date headers at `.large`. The audit reports "Dynamic Type font sizes are partially unsupported" for the title, account subtitle, unread capsule and row subject/preview on every list screen (`a11y-audit/en-light/01-list-inbox.audit.txt`); at AX5 the rows grow but the nav title, unread capsule, date headers and search pill stay at default size and the sender truncates to "Marte Solh…" (`en-ax5-01-list-inbox.jpg`). | Remove the cap on text-bearing chrome; size row heights and icons with `@ScaledMetric`; switch to an accessibility row layout above `.accessibility1` (the row already has `usesAccessibilityLayout`). | `MailDenseChromeDynamicType.swift`; `MessageListSearchField.swift:82`; `MessageListView.swift:3237, 4065, 4132` | M |
| L10 | List · VoiceOver | P2 | Accessibility | Row label starts with the avatar initials and uses the abbreviated date: "HL, Harbour Logistics, 1d, Weekly delivery digest…". | Hide the initials (`.accessibilityHidden(true)` on `BrevAvatarView` inside rows) and give the date an accessibility form ("Yesterday", "25 minutes ago") via `Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)`. | `MessageListView.swift:3669-3680, 3776-3800` | S |
| L11 | List · empty/error | P2 | Visual / Accessibility | Empty and error states use a fixed 40 pt icon, `textTertiary.opacity(0.6)` (2.3–3.8:1 in every built-in theme, see G1) and a borderless action. | `ContentUnavailableView(label:description:actions:)` with theme colours and a `.borderedProminent`-free text button. | `MessageListView.swift:4168-4195` | S |

### 2.2 Search

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Mail reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 | Search field | P1 | Native feel | Search is a hand-built `UITextField` capsule in the bottom bar. Focused, it has no Cancel, no recent searches or suggestions, and no scope control (`en-light-08-search-focused.jpg`). `chromeHeight`'s compact branch is dead (`max(44, …32…)`). | iOS 26 Mail: bottom search field that expands with Cancel, suggestions, "All Mailboxes / Current Mailbox" scope. Use `.searchable` + `DefaultToolbarItem(kind: .search, placement: .bottomBar)`, `.searchScopes`, `.searchSuggestions` (recent searches and contacts), `.searchToolbarBehavior(.minimize)`. | `MessageListSearchField.swift:12-83`; `BrevMailRootView.swift:2246-2256` | M |
| Q2 | Search results | P1 | Visual / Usability | Results stack three bands above the list: "This folder · Filters" strip, a predicate chip row (chip remove target 18 pt, audit hit area), and a grey "Search finished · Some results may be missing … Retry" band, shown here for a plain local mock search (`en-light-08b-search-results.jpg`). | Scope lives in the search bar (Q1), predicates become `.searchable(text:tokens:)` tokens, status becomes a list footer, and the "may be missing" warning only shows when a server search actually failed. | `MessageListView.swift:392-413, 3150-3175`; `MailSearchStatusView.swift`; `CollapsibleOptionsStrip.swift:35-41`; `MailSearchOptionsBar.swift` | M |

### 2.3 Reader, thread and quick reply

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Mail reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R1 | Reader navigation | P1 | Native feel | The compact reader is a `ZStack` overlay on the list: no push transition, no interactive edge-swipe back, icon-only back button (`en-light-04-reader.jpg`). The audit still walks list rows behind the reader (`a11y-audit/en-light/18-reader-single.audit.txt` lists inbox subjects) despite `.accessibilityHidden` on the background. | iOS Mail pushes the message (edge swipe pops, back shows the mailbox name). Present the reader with `navigationDestination(item:)` on the list's `NavigationStack` and delete `MailCompactReaderStack` on iPhone. | `MailCompactReaderStack.swift:31-39`; `BrevMailRootView.swift:640-651, 1724, 2862-2872` | M |
| R2 | Reader · archive/delete | P1 | Usability | Archive from the reader swaps the page to the next message with no animation, no toast and no announcement; the user cannot tell the action happened (`en-light-20-reader-before-archive.jpg` → `en-light-20b-reader-after-archive.jpg`). With an empty list the removed message stays on screen as the fallback. | iOS Mail animates to the next message and offers Undo (shake/toast). After a successful archive/trash on compact width either pop (when the list is empty or a "return to list" setting is on) or advance with a slide transition, show the undo toast above the reader, and post an announcement. | `BrevMailRootView.swift:1578, 2865, 6220`; `MailNavigationState.swift:476-484` | M |
| R3 | Reader · actions | P1 | Native feel / Usability | Up to three ••• menus: top-right "More message actions", bottom-bar "More message actions" (different contents, with "AI Sidebar" and "Refresh"), and the thread's "Conversation controls" (`en-light-04-reader.jpg`, `en-light-05-reader-more-menu.jpg`; iPad shows two adjacent ••• buttons, `ipad-en-42-ipad-portrait-reader.jpg`). Bottom bar is Reply · Archive · Trash · •••: Move costs 3 taps, Reply All and Forward 2, there is no Compose and no previous/next. | iOS Mail bottom bar: Trash/Archive · Move · Reply (menu: Reply, Reply All, Forward, Print…) · Compose; ↑/↓ in the nav bar. Keep one ••• in the nav bar (merge both inventories; drop Refresh; rename AI Sidebar "Ask AI"). Wire `selectNextHeader`/previous to `chevron.up`/`chevron.down`. | `BrevMailRootView.swift:2875-2992`; `MessageDetailView.swift:694-720`; `ThreadConversationView.swift:759-826` | M |
| R4 | Thread view | P1 | Native feel | Thread header shows the raw mailbox address and count on its own row with a separate ⊙ ("henrik@ogard.example · 2 messages"); the expanded card shows the sender's raw address wrapped over two lines plus a ⌃ and a ••• (`en-light-04-reader.jpg`). The single-message header from #209 is not reused. | Reuse #209's phone header (avatar, one-line name, short date, "to … ⌄") on every card; drop the mailbox-address row; move "Conversation controls" into the single nav-bar •••. | `ThreadConversationView.swift:174-181, 728-748`; `ThreadMessageCard.swift:135-169, 267-269` | M |
| R5 | Reader header | P1 | Accessibility | "From GitHub, Oct 9, 2026 at 10:13 AM" is a 19 pt-tall element and the "to … ⌄" toggle 15.7 pt (audit hit area on every reader screen). The chevron is a fixed `9 * scale` pt glyph; label column and indent are fixed 44 pt. Tapping the sender does nothing. | `.frame(minHeight: 44)` + `.contentShape(Rectangle())` on both rows; `@ScaledMetric` for widths; make avatar + name a `Button` that opens `SenderContactDetailSheet` (iOS Mail opens the contact card). | `MessageDetailView.swift:1173, 1184-1205, 1253, 1277, 1307-1345` | S |
| R6 | Quick reply | P1 | Usability / Accessibility | The quick-reply bar is a second chrome layer above the bottom toolbar (`en-light-18-reader-single.jpg`). Buttons are 32×32 pt, the send glyph is a fixed 24 pt, Return is "return" not Send (`en-light-28-quick-reply.jpg`), and the countdown/"Sent"/failure states are not announced. Placeholder contrast fails (audit). | Fold it into the bottom bar (Reply button expands it), or keep it but give it 44 pt targets, `.submitLabel(.send)`, `@ScaledMetric` glyph, announcements, and `theme.textSecondary` placeholder. | `ReaderQuickReplyBar.swift:49, 82-118` | S |
| R7 | Attachments | P1 | Usability | On iOS "Save" downloads, skips the AppKit-only save panel, then shows "Saved …" although nothing was saved; "Open" duplicates Preview. Attachment rows: unscaled borderless preview icon, 1-line filename, hand-built plural `"\(n) attachment\(n==1 ? "" : "s")"`. Not reachable in mock (mock messages render no attachments, `en-light-19-reader-attachments.jpg`), so this is code evidence. | Use `ShareLink`/`.fileExporter` on iOS and only toast on success; whole row is a `Button` to QuickLook with Save/Share in `.contextMenu`; catalog plural. | `MessageDetailView.swift:1814-1870, 1932-1942, ~2000` | S |
| R8 | Reader banners | P1 | Native feel | Up to ten stacked grey cards above the body (security row, warnings, read status, receipt prompt, unsubscribe, invite, DMARC, fallback notice, remote content). Remote-content card has four `BrevButton`s and "Keep blocked" sets a value that is already false. Not reached in mock (no remote content or receipts), code evidence. | One slim inline row at a time, iOS Mail style ("Load Remote Content", "Unsubscribe"); "Always allow sender/domain" via `confirmationDialog`; delete "Keep blocked". | `MessageDetailView.swift:608-690, 1422-1460, 1551-1580, 2158-2178, 2434-2497` | M |
| R9 | HTML body | P1 | Usability | Body web view disables scrolling and sets `initial-scale=1` without shrink-to-fit, so a 600 px newsletter on a 402 pt phone loses its right edge. Code evidence; mock bodies are plain text. | Scale-to-fit after measuring `scrollWidth`, or `max-width:100%` for tables and fixed-width wrappers; avoid the nested scroll above the 20 000 pt cap. | `HTMLBodyWebView.swift:127-131, 494, 548, 609` | M |
| R10 | HTML body · dark | P2 | Visual | Dark themes force-recolour every HTML mail (`background: transparent !important; color: inherit !important`), which breaks CTA buttons and transparent logos; "Original" is buried in the ••• menu. Code evidence. | Default to original rendering unless the message has no `prefers-color-scheme` rules; a one-tap toggle in the header row. | `HTMLBodyRenderingMode.swift:22-24`; `MessageBodyStyle.swift:100-120` | S |
| R11 | Thread · VoiceOver | P2 | Accessibility | Collapsed card's header button is labelled with the sender only (snippet and date hidden); thread subject lacks `.isHeader`; `withAnimation` calls ignore Reduce Motion. | `.accessibilityElement(children: .combine)` with "sender, date, snippet"; `.accessibilityAddTraits(.isHeader)`; wrap animations in a `reduceMotion` check. | `ThreadMessageCard.swift:135-141`; `ThreadConversationView.swift:174-181, 227-308, 781-794` | S |
| R12 | AI panel ("AI Sidebar") | P1 | Native feel / Localization | Sheet with no nav bar or Done (swipe is the only exit), caption-size title "Mailbox chat", Mac copy "Answers use only the messages cached on this Mac.", scope chip shows a raw local part "notifications" (audit: label not human-readable), VoiceOver hint "Press Command-Return to send." (`en-light-21-ai-sidebar.jpg`). | `NavigationStack` titled "Ask AI" with toolbar Done, `.presentationDetents([.medium, .large])`, "on this iPhone"/"on this device" copy, display names in chips, iOS hint. | `BrevMailRootView.swift:1172-1204`; `MailboxChatPanel.swift:67, 323-356, 391-413, 472`; `MailContextChrome.swift:63` | S |

### 2.4 Compose

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Mail reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Compose · cancel | P1 | Usability | ✕ closes immediately and silently saves a draft: typing a subject and tapping ✕ returns to the inbox with no prompt (`en-light-24-compose-after-close.jpg`). Swipe-down is not blocked; `.onDisappear` also cancels a pending undo-send countdown. "Discard Draft" in ••• has no confirmation. | iOS Mail: "Cancel" → action sheet "Delete Draft / Save Draft". `ToolbarItem(placement: .cancellationAction) { Button("Cancel") }`, `.confirmationDialog`, `.interactiveDismissDisabled(isDirty \|\| pendingUndoSend)`. | `ComposeView.swift:605-609, 887-897, 1066-1072, 1162-1168, 2931, 2962-2977` | S |
| C2 | Compose · focus | P1 | Usability | New Message opens with no keyboard and no focused field (`en-light-07-compose-new.jpg`); Reply opens with nothing focused (`en-light-18b-reply-compose.jpg`). Subject has no `.submitLabel(.next)`. | iOS Mail focuses To for new mail and the body for replies. `@FocusState` field enum with `.defaultFocus`, `.submitLabel(.next)` + `.onSubmit` chaining To → Subject → body. | `ComposeView.swift:1763-1772`; `RecipientChipField.swift:38, 101-110` | S |
| C3 | Compose · attach and format | P1 | Usability | The paperclip goes straight to the Files picker (`en-light-23b-compose-attach.jpg`); no Photo Library, Camera or Scan Document. Formatting is behind an "Aa" menu in a bottom utility bar; there is no keyboard formatting bar. | iOS Mail: keyboard bar with Aa, photo, camera, document, scan. `ToolbarItemGroup(placement: .keyboard)` with Format, Photos (`PhotosPicker`), Camera, Files, Scan (`VNDocumentCameraViewController`). | `ComposeView.swift:918-937, 2090-2120, 3723-3735` | M |
| C4 | Compose · header | P2 | Native feel | From is always a visible row with the raw address and a ⌃⌄ glyph; Cc and Bcc are two inline buttons in the To row (`en-light-07-compose-new.jpg`, `en-light-23-compose-cc.jpg`). Send is plain grey text. In Norwegian the two inline buttons "Kopi til" and "Blindkopi" squeeze the To field until its placeholder truncates (`nb-dark-07-compose-new.jpg`). | iOS Mail: one "Cc/Bcc, From:" row that expands, From shows the account name; Send is an accent `arrow.up.circle.fill`. Use nav-bar `.confirmationAction` for Send. | `ComposeView.swift:887-916, 1229-1330, 1434-1459, 1631`; `ComposePresentation.swift:226-229` | S |
| C5 | Compose · Dynamic Type | P1 | Accessibility | Body editor uses `UIFont.systemFont(ofSize: bodyPointSize)` and ignores Dynamic Type; compose chrome icons are fixed 14 pt in 26 pt frames and capped at `xxxLarge`. Audit on every compose screen: "Dynamic Type partially unsupported" and "Text clipped" for Attach. At AX5 the header fields scale but the quoted reply body and the bottom icons stay at default size (`en-ax5-18b-reply-compose.jpg`). | `UIFontMetrics(forTextStyle: .body).scaledFont(for:)` + `adjustsFontForContentSizeCategory = true`; `@ScaledMetric` icons. | `ComposeEditorTypography.swift:55`; `ComposeBodyEditor.swift:891-904`; `ComposeView.swift:913, 937, 1203` | S |
| C6 | Compose · recipients | P2 | Accessibility / Native feel | Reply chip shows the raw address ("notifications@github…", audit: label not human-readable); chips are ~50 pt tall because the remove button keeps a 44 pt box inside; chip and remove are separate VoiceOver stops; no (+) contact picker. | Show display name in the chip, combine chip with `.accessibilityAction(named: "Remove")`, keep 44 pt hit area via `contentShape`, add a (+) `CNContactPickerViewController` button. | `RecipientChipField.swift:143, 157-170`; `packages/BrevDesign/Sources/BrevDesign/Components/BrevIconButton.swift:58-59` | S |
| C7 | Google Drive sheets | P0 | Native feel | `.frame(minWidth: 560, minHeight: 420)` is not guarded by `#if os(macOS)`, so on a 402 pt iPhone the attach/save sheets lay out wider than the screen. Sheets also lack `NavigationStack` and use `.font(.system(size: 32))`. Code evidence; Drive needs a configured Google client and was not opened. | Guard the frame to macOS, wrap in `NavigationStack` with Cancel, scale fonts. | `GoogleDriveAttachSheet.swift:44-57, 152, 175`; `GoogleDriveSaveSheet.swift:58`; `GoogleDriveEventAttachSheet.swift:49`; `GoogleDriveSheetSupport.swift:66` | S |
| C8 | Compose sheets | P1 | Native feel | Insert Link, Schedule Send and Templates are custom `VStack`s with an in-content title, ✕ and bottom `.bordered`/`.borderedProminent` button rows; Schedule Send does not scroll (graphical picker + six rows + notice overflow on small phones); the URL field has no `.keyboardType(.URL)`. | `NavigationStack { Form { … } }` with Cancel/Insert/Schedule in the nav bar, `.presentationDetents`, `.searchable` for templates. | `ComposeLinkSheet.swift:62-129`; `ScheduleSendSheet.swift:55-192`; `TemplatePickerView.swift:50-62, 134-170` | M |
| C9 | Reply attribution | P2 | Localization | Quote header is hard-coded English and UTC: "On 9 Oct 2026 at 08:13 UTC, GitHub <…> wrote:" while the reader shows 10:13 local (`en-light-18b-reply-compose.jpg`). Norwegian users send English attribution lines (`nb-dark-18b-reply-compose.jpg`). | Localized, local-time attribution ("Den 9. okt. 2026 kl. 10:13 skrev …:"); keep a stable internal marker for the quote-edit guard instead of matching the visible text. | `ComposeReplyFormatter.swift:54, 93-99`; `ComposeQuoteEditGuard.swift` | M |
| C10 | Compose · runtime | P2 | Usability | Opening compose and typing a subject logs "Modifying state during view update, this will cause undefined behavior" (test log, `test24_ComposeCancel`). | Find the state write in the subject/autosave path and move it to `.onChange`/`.task`. | `ComposeView.swift` (subject binding / autosave) | S |

### 2.5 Mailboxes sidebar

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Mail reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Mailboxes · nav | P2 | Native feel / Accessibility | The Mailboxes screen has a leading "Inbox ›" button with a forward chevron (`en-light-02-mailboxes.jpg`). Its accessibility label is "Show messages", so Voice Control "Tap Inbox" fails (label not in name, WCAG 2.5.3). | iOS Mail: Mailboxes is the root; opening a mailbox pushes it, and the list's back button reads "Mailboxes". If the current model stays, label the button with its visible title. | `BrevMailRootView.swift:1997-2019` | M |
| S2 | Mailboxes · layout | P2 | Native feel / Usability | Hand-built `ScrollView` + `LazyVStack` of cards: Smart Views expand as un-carded rows in a different style, account rows use lighter text with no icon, and Calendar/Contacts/Tasks drop below every folder once an account is expanded (`en-light-11-smart-views.jpg`, `en-light-15-calendar.jpg` — the PIM tests had to scroll to find them). | `List` `.insetGrouped` with `Section`s and `DisclosureGroup` for accounts, Edit for favourites; keep the Apps section reachable (pin it above accounts, or move it to a toolbar menu). | `FolderSidebar.swift:229-231, 402-474, 441, 537, 729, 1376` | M |
| S3 | Mailboxes · VoiceOver | P2 | Accessibility | Counts speak as bare numbers ("All Inboxes, 16"), the selected mailbox has no `.isSelected`, section titles lack `.isHeader`, and a collapsed account's badge is overridden by its label. | `accessibilityValue("16 unread")`, `.isSelected`, `.isHeader`. | `FolderSidebar.swift:406, 516, 663, 835-900, 1560-1640, 2004` | S |

### 2.6 Settings

| ID | Surface | Sev | Category | What's wrong | Proposed fix (iOS Settings reference) | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | Settings panes | P1 | Native feel | Every pane is a `ScrollView` of macOS-style cards: headline + subtitle above each group, an always-visible footnote subtitle under every toggle, 0.42-opacity quiet surfaces, nested card-in-card (`en-light-12-01-settings-appearance.jpg`, `en-light-12-04-settings-notifications.jpg`, `en-light-13b-accounts.jpg`). The root list is already native (`en-light-09-settings.jpg`). | On iOS render panes as `Form` (`.insetGrouped`) with `Section(header:footer:)`; explanatory text goes in footers; `.scrollContentBackground(.hidden)` + `listRowBackground(theme.bgSecondary.color)`. Keep `SettingsGroup` for macOS. | `packages/BrevSettings/Sources/BrevSettings/Sections/SectionScaffold.swift:47-80`; `SettingsSectionComponents.swift:75-136, 288, 386`; `packages/BrevDesign/Sources/BrevDesign/Components/BrevQuietSurface.swift:26-33` | L |
| T2 | Settings depth | P1 | Native feel / Usability | Categories with two to four rows add a whole level (Accounts & Connections → Accounts; Mailboxes & Reading; Writing; Rules; Privacy & Security; Sync & Storage). The large title truncates to "Accounts & Connectio…" (`en-light-12-00-settings-accounts-connections.jpg`, `en-light-12-02-settings-mailboxes-reading.jpg`). | One root list with `Section` headers (iOS Settings style), rows pushing straight to panes; shorter category names. | `packages/BrevSettings/Sources/BrevSettings/SettingsView.swift:333-365, 438-455`; `SettingsCategory.swift:29` | M |
| T3 | Settings · Accounts | P1 | Usability / Accessibility | Each mailbox has an unlabeled switch ("Enable mailbox …") placed directly before "✓ Default mailbox" / "Make default", so the switch reads as the default selector; both switches are on. "Make default" is a 78×16 pt text button (audit hit area); raw addresses flagged "Label not human-readable"; names clipped (`en-light-13b-accounts.jpg`). At AX5 the address breaks mid-word ("henrik@og / ard.e…mple") and the Demo/Default chips truncate to "De…"/"Def…" (`en-ax5-13b-accounts.jpg`). | Account row → detail page with `Toggle("Show in Mail")` and a checkmark list for the default mailbox; display names first. | `packages/BrevSettings/Sources/BrevSettings/Sections/AccountsSection.swift:165, 1036-1060` | M |
| T4 | Settings · Notifications | P1 | Usability / Accessibility | "Show dock badge" on iPhone; a filled "Request Access" pill; a grey band of IDLE/polling/push-relay jargon; per-account nested cards with three toggles each; disabled rows dimmed so the audit fails contrast on "Play a sound…", "Display sender…" and "Test notification"; the denied state has no Open Settings button (`en-light-12-04-settings-notifications.jpg`, `en-light-12-04b-settings-notifications-scrolled.jpg`). | "App icon badge"; plain "Allow Notifications" row; footer copy in plain words; per-account NavigationLink; `.disabled` instead of opacity; `Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }`; `DatePicker(.hourAndMinute)` for quiet hours. | `packages/BrevSettings/Sources/BrevSettings/Sections/NotificationSection.swift:163, 196-201, 231-320, 376, 399, 410, 580` | M |
| T5 | Settings · buttons | P2 | Native feel | `BrevButton` (bordered/filled) appears 57 times in Settings; e.g. Appearance "Reset to Defaults" pill and a "Choose…" text link inside a card (`en-light-12-01b-settings-appearance-scrolled.jpg`). Destructive actions without confirmation: Outbox "Discard All Pending Changes", restored-account "Remove", privacy allowlist trash, task delete. | Plain accent rows, `Button(role: .destructive)` rows with `confirmationDialog`, Save/Cancel in the nav bar. Needs an ADR-0002 note: `BrevButton` stays the sanctioned standalone button, form rows use system row buttons. | `Sections/AppearanceSection.swift:127`; `AIProviderSettingsPanel.swift:130-146, 346-404`; `SecuritySection.swift:193-198`; `PrivacySection.swift:181, 263-266`; `OutboxView.swift:175-182`; `AccountsSection.swift:416` | M |
| T6 | Settings · iOS copy | P2 | Usability / Localization | Mac-only text and dead UI on iPhone: "System accent is available on Mac", disabled Import buttons "available on Mac", a sandbox cache path, unlocalized "Calculating...", a "Capabilities and roadmap" disclosure of internal jargon in Calendar & Contacts. Mixed UK/US spelling ("Organisation", "Favourites" vs US elsewhere). | `#if os(iOS)` copy or hide; remove the roadmap group on iOS; pick one spelling. | `Sections/AppearanceSection.swift:288`; `ImportExportSection.swift:305-323, 730-736`; `MailStorageSection.swift:712, 748, 801, 846`; `CalendarContactsSection.swift:247`; `SettingsCategory.swift:29` | S |
| T7 | Settings · preview | P2 | Accessibility | The Appearance mail preview uses fixed font sizes; the audit reports "Dynamic Type font sizes are unsupported" for every preview string. | Use the same `brevFont` text styles as the list. | `Sections/SettingsMailPreview.swift` | S |
| T8 | Settings · presentation | P1 | Usability | `showSettings` replaces the whole mail root instead of presenting over it, so opening Settings tears down list selection and scroll position. | Present `SettingsView` with `.sheet`/`.fullScreenCover` over `BrevMailRootView`, or keep the root alive underneath. | `apps/iOS/Sources/BrevApp.swift:103-145` | M |
| T9 | Settings · other sheets | P1 | Native feel | Saved Search editor and Smart Views sheet are macOS dialogs (in-content title, bottom Cancel/Save or Done row, fixed 155/145 pt pickers); Smart Views reorder uses per-row ↑/↓ buttons; Per-Folder Sync is a three-column table with fixed 132/52 pt columns. | `NavigationStack` + `Form`; `List` + `.onMove` + `EditButton` (as `MailboxFavoritesEditor` already does); folder → detail page. | `packages/BrevSettings/Sources/BrevSettings/SavedSearchEditorView.swift:39-174`; `FolderSidebar.swift:356-377`; `Sections/SmartViewsSection.swift:62-120`; `Sections/PerFolderSyncSection.swift:317-400` | M |

### 2.7 Sheets and theming

| ID | Surface | Sev | Category | What's wrong | Proposed fix | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| H1 | Sheet theming | P1 | Visual | About 28 presented views theme themselves with `.brevTheme(theme)`, which calls `.preferredColorScheme(theme.mode.colorScheme)` and pins the scheme from inside the sheet, while the root uses `.brevRootAppearance(session:)` (nil in follow-system mode plus colour-scheme-aware resolution). This is the pattern that already produced light sheets in a dark app twice. Sites: Snooze (`MessageListView.swift:367`, `UnifiedInboxListView.swift:495`, `BrevMailRootView.swift:987` — being redesigned separately), Schedule Send (`ComposeView.swift:598`, `OutboxView.swift:95`), Insert Link (`ComposeView.swift:610`), Initial Mailbox Selection (`InitialMailboxSelectionSheet.swift:96`), AI panel (`BrevMailRootView.swift:1202`), and the root `MailAuxiliaryPresentation` cases in `BrevMailRootView.swift:4082-4422`: Theme Picker, Compose (4142), Profiles, Move To, Copy To, Copy/Move to Local, Outbox, Keyboard Shortcuts, Mailbox Assistant, System Share / Task Unavailable, Create Rule, Create Meeting, Message Note, Follow-Up picker (4389), Properties, View Source, Show Headers. Sheets with no theming at all: `ThemePickerSheet` (`Sections/AppearanceSection.swift:455`), `PIMSourceConnectSheet` (`Sections/PIMSourcesSettingsView.swift:636`), Drive sheets, participant contact and share sheets in `MessageDetailView.swift:228, 289, 293-300`, `TemplatePickerView`. `.presentationBackground` is used nowhere. Not reproduced in this pass: in follow-system dark (`en-dark-13c-add-account-sheet.jpg`, `en-dark-07-compose-new.jpg`) and in always-dark Solarized on a light system (`theme-solarized-dark-07-compose-new.jpg`, `theme-solarized-dark-13c-add-account-sheet.jpg`) the sheets matched; the risk is structural (a sheet pins the window scheme from a possibly stale `theme`, e.g. when the system flips while the sheet is open). | One `brevSheetAppearance()` modifier in BrevMail that reads the same settings as `brevRootAppearance` (no pinned scheme in follow-system mode), sets `.presentationBackground(theme.bgPrimary.color)`, `.scrollContentBackground(.hidden)`, and `.tint(theme.accent.color)`. Replace every `.brevTheme(theme)` on a presented view with it; add a snapshot test that renders one sheet in dark follow-system mode. | `RootAppearance.swift`; `BrevMailRootView.swift:987, 1202, 4082-4422`; the files listed | M |
| H2 | Utility sheets | P1 | Native feel | Move To, Note, Properties, Raw Source, Task, Event, Follow-Up sheets are hand-built: in-content title, `xmark.circle.fill`, divider lines, bottom button rows; Move To is a `ScrollView` capped at `maxHeight: 400` with a custom search field; Follow-Up and Snooze are bare `VStack`s that overflow at large type (`en-light-25b-snooze-sheet.jpg`: audit 6× "Text clipped"). Raw Source close button has no label. | `NavigationStack { List/Form }` with toolbar Cancel/Done/Save, `.searchable` for folders, `.presentationDetents`. Snooze is excluded: a separate PR is redesigning it. | `MoveToSheet.swift:96-153`; `MessageNoteSheet.swift:44-136`; `MessagePropertiesSheet.swift:29-63`; `MessageRawSourceSheet.swift:79-126`; `MessageTaskSheet.swift:70-175`; `MessageEventSheet.swift:55-150`; `FollowUpDatePickerView.swift:44-182`; `InitialMailboxSelectionSheet.swift:97-216` | M |
| H3 | Sheet buttons | P2 | Accessibility | The #208 add-account sheet's glass Cancel/Add, the theme picker's Done and the PIM covers' Done fail the audit's contrast check and "Dynamic Type partially unsupported" (`a11y-audit/en-light/13c-add-account-sheet.audit.txt`, `14b-theme-picker.audit.txt`, `50-calendar.audit.txt`). A disabled "Add" on glass is expected to be dim, but Cancel and Done are enabled. | Check against iOS 26 glass defaults: drop custom `foregroundStyle` on toolbar buttons and let `.tint(theme.accent)` apply; re-run the audit. | `IMAPAccountSetupSheet.swift:80-97`; `Sections/AppearanceSection.swift:455`; `CalendarRootView.swift:411-416` | S |

### 2.8 Onboarding and account setup

| ID | Surface | Sev | Category | What's wrong | Proposed fix | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | Add account fields | P1 | Native feel / Usability | Email and password lack `.textContentType` (no Keychain autofill, which matters most for re-auth); Return in Email moves focus to a hidden Display name instead of running Find settings; host/port fields have no `.keyboardType(.URL)`/`.numberPad` and keep autocapitalisation and autocorrect. Layout itself is good after #208 (`en-light-13c-add-account-sheet.jpg`, `login-en-30c-login-add-account.jpg`). | `.textContentType(.username)`/`.password`; `.submitLabel(.go).onSubmit { discover() }`; URL/number keyboards with `.textInputAutocapitalization(.never).autocorrectionDisabled()`. VoiceOver reads placeholders as labels; use `TextField("Email address", …)` with `prompt:`. | `IMAPAccountSetupSheet.swift:239-267, 530-545, 757-790` | S |
| O2 | Login | P2 | Usability | In a build without a Google client the login page shows developer copy: "Google sign-in isn't configured in this build. Provide the OAuth client ID at build time…" (`login-en-30-login.jpg`). Several captions are footnote size in a page with lots of empty space. | Hide the Google row entirely when unconfigured; use `.body`/`.subheadline` for the explanations. | `LoginView.swift:185-230, 333-373` | S |
| O3 | Restore/re-auth errors | P1 | Localization / Accessibility | iPhone shows "Mac Keychain is locked. Unlock your Mac…"; the sign-in-required banner merges its "Sign in again" button into a combined element, uses a small borderless caption button, and is English-only ("Sign-in required", "Reconnect this account to keep syncing mail."). Code evidence. | `#if os(iOS)` copy; `.accessibilityElement(children: .contain)`; 44 pt button; catalog strings; announce `signInError`. | `AppSessionPresentation.swift:27-31`; `ImportProgressBanner.swift:29-36, 95-115`; `ImportProgressPresentation.swift:63-71`; `LoginView.swift:333-356` | S |
| O4 | Initial mailbox selection | P1 | Native feel / Accessibility | No nav bar, bottom-right "Continue", not dismissible and no Skip; every row's default radio is labelled "Make default mailbox", so VoiceOver cannot tell rows apart. Not reached in mock. | `NavigationStack` + `List` with checkmark, Done in the nav bar; label "Make <name> the default". | `InitialMailboxSelectionSheet.swift:97, 136-150, 178-180, 204-216` | S |

### 2.9 Calendar, Contacts, Tasks

The mock backend has no PIM source, so the covers only showed empty states
(`en-light-50-calendar.jpg`, `en-light-51-contacts.jpg`, `en-light-52-tasks.jpg`).
Grid and editor findings are code evidence.

| ID | Surface | Sev | Category | What's wrong | Proposed fix | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | PIM empty states | P1 | Usability | "Connect a calendar in Settings → Calendar & Contacts" names a path that does not exist (it is Accounts & Connections → Calendar & Contacts) and offers no button; a search field is shown with nothing to search. Audit: contrast failed on the title, "Done" contrast and DT partial. | `ContentUnavailableView` with an `actions:` button that opens the right Settings page; hide `.searchable` until there is data. | `CalendarRootView.swift:164`; `ContactsRootView.swift:157`; `TasksRootView.swift:158` | S |
| P2 | Calendar chrome | P1 | Native feel | Layout menu, chevrons, Today, a `lineLimit(1)` range title, + and sync sit in one in-content `HStack`; chevrons are bare sub-44 pt glyphs; Done is leading. Week view gives ~49 pt columns on iPhone; month cells use 96 pt minimum height and ~50 pt chips. | iOS Calendar: Today and + in the nav bar, view picker in `.principal`, Done trailing; on compact width offer Day / 3-day / dot-month with a day agenda. | `CalendarRootView.swift:411-512`; `CalendarWeekView.swift:60-82`; `CalendarMonthView.swift:128-180` | L |
| P3 | Calendar accessibility | P1 | Accessibility | Month cell label is the date only (events and "+N more" hidden), `onTapGesture` without button trait, 22×22 day circle, out-of-month cells at 0.55 opacity, today colour-only; Day/Week event blocks labelled with title only; fixed `hourHeight`/ruler; weekday picker shows raw ICS codes ("MO") in 30×30 circles. | Combine label "Thursday 9 October, 3 events: …", `.isButton`, `.isSelected` for today, `@ScaledMetric`, localized weekday symbols. | `CalendarMonthView.swift:128-180`; `CalendarDayView.swift:63, 196, 283`; `CalendarEventEditorView.swift:295-320, 466-667` | M |
| P4 | Task editor and rows | P1 | Native feel / Accessibility | `TaskEditorView` is a macOS dialog (✕ header, bottom Cancel/Create); task rows combine the completion button into the row so VoiceOver activation toggles completion; ~20 pt checkbox; overdue is colour-only; task delete has no confirmation. | Toolbar Cancel/Save like the Calendar and Contacts editors; `.accessibilityElement(children: .contain)`, 44 pt checkbox, "Overdue" text. | `TaskEditorView.swift:64-204`; `TasksListView.swift:149`; `TaskDetailView.swift:50-157`; `TasksRootView.swift:264-270` | M |

### 2.10 iPad, extensions and widgets

| ID | Surface | Sev | Category | What's wrong | Proposed fix | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| I1 | iPad compose | P1 | Native feel | Reply/New Message on iPad opens a separate full-window scene (`ipad-en-49-ipad-reply.jpg`), and the scene is restored on next launch: a fresh test launch came up with "1 skjult vindu" (1 hidden window) and the compose window in front. | iPadOS Mail presents compose as a form sheet over the split view; keep "Open in New Window" as an explicit action only. | `apps/iOS/Sources/BrevApp.swift:381-403`; `MailRootComposePresentationPolicy.swift`; `DetachedComposeWindowView.swift:57-72` | M |
| I2 | iPad windows theme | P1 | Visual | Detached reader and compose `WindowGroup`s do not apply `.brevRootAppearance(session:)`, unlike the main, Calendar, Contacts and Tasks scenes. | Add the modifier to both scene roots. | `apps/iOS/Sources/BrevApp.swift:381-403` | S |
| I3 | iPad layout | P2 | Visual | Landscape three-column layout works; sidebar account names truncate ("Henrik Øgård (pri…)"); reader shows two adjacent ••• buttons (R3). | Account rows wrap to two lines or show display name only. | `FolderSidebar.swift` | S |
| X1 | Widget | P0 | Native feel | No `.containerBackground(for: .widget)` anywhere; on iOS 17+ WidgetKit renders a "Please adopt containerBackground API" placeholder instead of the widget. No `widgetURL`/`Link`, no `.privacySensitive()`. Code evidence (widget not added to a home screen). | `.containerBackground(.fill.tertiary, for: .widget)`; deep-link rows; `.privacySensitive()` on subjects. | `packages/BrevWidgets/Sources/BrevWidgets/MailSummaryWidget.swift:75-81`; `MailSummaryWidgetView.swift:29-125` | S |
| X2 | Share extension | P1 | Native feel / Accessibility | Fixed 300 pt UIKit card, `.systemFont(ofSize:)` everywhere (no Dynamic Type), translucent `systemBackground`, plus an extra "Open Brev" hop with no compose preview. Not driven in the simulator. | SwiftUI card in `UIHostingController` with text styles and theme tint, or hand straight to compose. | `apps/iOS/BrevShareExtension/ShareViewController.swift:43-112, 290-345` | M |
| X3 | Notification content | P2 | Visual / Accessibility | Literal `.systemGreen` avatar and fixed 12–18 pt fonts; repeats sender/subject/body because default content is not hidden. | `UIFontMetrics`, a neutral avatar colour, `UNNotificationExtensionDefaultContentHidden = true`. | `apps/iOS/BrevNotificationContent/NotificationViewController.swift:26-67`; `Info.plist` | S |

### 2.11 Cross-cutting accessibility and localization

| ID | Surface | Sev | Category | What's wrong | Proposed fix | Files | Effort |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G1 | Contrast across themes | P1 | Accessibility / Visual | WCAG ratios computed from `BuiltIns.swift` for all 37 built-in themes: base `textSecondary`/`textTertiary` pass everywhere (ADR-0002 contract), but derived styles fail. `textTertiary` at 0.6 opacity: 2.3–3.8:1 in **37/37**. Accent as text: below 4.5:1 in **6** (gruvbox-light 3.73, solarized-light 3.41, solarized-dark 4.08, catppuccin-latte 4.34, blurple-night 3.58, pearl-light 4.32). Accent on its own 18 % chip: below 4.5:1 in **15**. Danger as text: below 4.5:1 in **9** (nord 3.05, solarized-dark 3.25, nordic 3.56, tender 3.87, gruvbox-dark 4.29, solarized-light 4.29, blurple-night 4.37, one-dark-pro 4.38, tomorrow-night 4.46). `border` vs `bgPrimary` below 3:1 in **37/37**, which matters for text-field outlines. There are 38 `.opacity(0.0–0.6x)` sites in BrevMail/BrevDesign/BrevSettings (not all on text). Full table in `contrast-themes.txt`. Visible in `theme-gruvbox-light-18b-reply-compose.jpg` (teal Cc/Bcc/Send on cream). | Extend the ADR-0002 contrast contract and its palette test to `accent`, `danger`, `warning` (≥ 4.5:1 on bgPrimary/bgSecondary) and `border` for inputs (≥ 3:1); recalibrate the 6/9 failing palettes; replace opacity dimming with `textTertiary` or `.disabled`. | `packages/BrevThemes/Sources/BrevThemes/BuiltIns.swift`; `packages/BrevThemes/Tests`; `MessageListView.swift:4177`; `packages/BrevDesign/Sources/BrevDesign/Components/BrevChip.swift`, `BrevStatusBanner.swift`, `BrevButton.swift` | M |
| G2 | Fixed sizes | P1 | Accessibility | 46 `.font(.system(size:))` and 25 `.dynamicTypeSize(...)` caps in BrevMail/BrevDesign/BrevSettings; `BrevIconButton` hardcodes its glyph size so icon buttons never grow. At AX5: sidebar and Settings-root icons stay at default size next to giant labels, Settings rows hyphenate ("Connec-tions", "Notifica-tions"), the thread's mailbox line and the quick-reply/compose bottom icons do not scale (`en-ax5-02-mailboxes.jpg`, `en-ax5-09-settings.jpg`, `en-ax5-04-reader.jpg`, `en-ax5-07-compose-new.jpg`). | `@ScaledMetric(relativeTo:)` in `BrevIconButton` and `BulkActionIconButton`; remove caps where text is involved. | `packages/BrevDesign/Sources/BrevDesign/Components/BrevIconButton.swift:58`; top offenders `MessageDetailView.swift` (8), `FolderSidebar.swift` (6), `MessageListView.swift` (5) | M |
| G3 | Motion | P2 | Accessibility | `withAnimation` without a Reduce Motion check across list, thread and follow-up; status-rail animations at `BrevMailRootView.swift:673-676`. Only `MessageListRefreshArrivalEffect` reads `accessibilityReduceMotion`. | A `brevAnimation(_:)` helper that returns nil when Reduce Motion is on. | `ThreadConversationView.swift:227-308, 781-794`; `MessageListView.swift:866`; `UnifiedInboxListView.swift:1128`; `FollowUpDatePickerView.swift:120` | S |
| G4 | UI-test coverage | P1 | Accessibility | No XCUITest target and no `accessibilityIdentifier` in product code, so nothing catches these regressions. This audit's walker ran in 20–40 s per screen. | Add a permanent `BrevIOSUITests` target with mock launch, one test per surface and `performAccessibilityAudit` (allow-list known issues), plus identifiers on primary controls. ADR-0004 update (new target). | `apps/iOS/Project.swift`; ADR-0004 | M |
| N1 | Widget strings | P1 | Localization | `BrevWidgets` catalog has 7 keys and **0** nb translations ("Mail", "%lld unread", "You're all caught up.", "Open Brev to see your mail."…). | Translate; add the catalog to the nb completeness check. | `packages/BrevWidgets/Sources/BrevWidgets/Resources/Localizable.xcstrings` | S |
| N2 | Share extension strings | P1 | Localization | The share extension calls `String(localized:)` 10 times but its catalog has **0** keys, so nb users get English. | Extract the keys into `apps/iOS/BrevShareExtension/Resources/Localizable.xcstrings` and translate. | same + `ShareViewController.swift:50-310` | S |
| N3 | Plurals | P2 | Localization | 42 count strings in `BrevMail` have no plural variants. Seen: "Yesterday, 1 messages" (en) and "I går, 1 meldinger" (nb) on date headers; `%lld hidden read message%@` → nb "1 skjulte leste meldinger"; `%lld attachment%@` builds an English suffix in code. | Catalog plural variations (`one`/`other`) for en and nb; delete manual suffix logic. | `packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings`; `MessageDetailView.swift:1816`; `ThreadConversationView.swift:927-934` | S |
| N4 | Unlocalized literals | P2 | Localization | Plain `String` literals that reach the UI: "Select All"/"Deselect All", "Not Done", "Open", "Collapse/Expand thread" (`MessageListView.swift:641, 658, 3506, 3784, 4129`); "Unified Inbox", "Marked Done/Not Done" (`UnifiedInboxListView.swift:803, 2477, 2492`); attachment "Saved …", "Preview/Save/Open" (`MessageDetailView.swift:1940`, `MessageAttachmentActionPresentation.swift:36-52`); list-unsubscribe, remote-content and read-receipt copy (`ListUnsubscribePresentation.swift:34-85`, `MessageHTMLRenderPolicy.swift:67-107`, `MessageDetailPresentation.swift:122-147`); autocomplete source labels (`ComposeRecipientAutocomplete.swift:36-38, 104`); compose attachment status (`ComposeAttachmentRowPresentation.swift:28, 37`, `ComposeAttachmentUploadState.swift:119, 123`, `ComposeAttachmentImport.swift:119-124`); "Summary"/"Next actions" (`ThreadConversationView.swift:968-970`); sender-auth banner missing `bundle: .module` (`MessageDetailView.swift:2158-2178`). nb run evidence in 2.12. | `String(localized:bundle: .module)` and catalog entries. | listed | M |

### 2.12 Accessibility audit output (per screen)

`performAccessibilityAudit(for: .all)` was run on every captured screen; each
issue is listed with its type, description and element in
`a11y-audit/<variant>/<screen>.audit.txt`. Counts below are for English
light mode unless noted. Contrast and hit-area issues on SwiftUI nodes often
come back with `element: nil`; where that happens the finding above names the
element from the screenshot and code.

#### English, light (per screen)

| Screen | Contrast | Hit area | Dyn. Type | Clipped | Label | Other | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `01-list-inbox` | 3 | 3 | 5 | 2 | 0 | 0 | 13 |
| `02-mailboxes` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `03-sort-filter-menu` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `04-reader` | 3 | 0 | 9 | 4 | 1 | 0 | 17 |
| `04b-reader-scrolled` | 3 | 0 | 9 | 4 | 1 | 0 | 17 |
| `05-reader-more-menu` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `06c-context-menu` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `07-compose-new` | 1 | 0 | 1 | 2 | 0 | 0 | 4 |
| `08-search-focused` | 18 | 2 | 5 | 2 | 0 | 0 | 27 |
| `08b-search-results` | 4 | 3 | 3 | 2 | 0 | 0 | 12 |
| `09-settings` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `10-account-work-tapped` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `10b-account-expanded` | 3 | 3 | 5 | 2 | 0 | 0 | 13 |
| `10c-unified-inbox` | 2 | 1 | 2 | 6 | 0 | 0 | 11 |
| `11-smart-views` | 0 | 0 | 2 | 1 | 0 | 0 | 3 |
| `12-00-settings-accounts-connections` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-01-settings-appearance` | 0 | 0 | 6 | 2 | 0 | 0 | 8 |
| `12-02-settings-mailboxes-reading` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-03-settings-writing` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-04-settings-notifications` | 5 | 0 | 0 | 1 | 0 | 0 | 6 |
| `12-05-settings-rules-organisation` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-06-settings-privacy-security` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-07-settings-sync-storage` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `12-08-settings-about-updates` | 0 | 1 | 0 | 0 | 0 | 0 | 1 |
| `13-accounts-connections` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `13b-accounts` | 0 | 1 | 0 | 5 | 3 | 0 | 9 |
| `13c-add-account-sheet` | 2 | 0 | 2 | 1 | 0 | 0 | 5 |
| `14-appearance` | 0 | 0 | 6 | 2 | 0 | 0 | 8 |
| `14b-theme-picker` | 1 | 0 | 17 | 0 | 0 | 0 | 18 |
| `15-calendar` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `16-contacts` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `17-tasks` | 0 | 0 | 2 | 0 | 0 | 0 | 2 |
| `18-reader-single` | 14 | 2 | 5 | 4 | 0 | 0 | 25 |
| `18b-reply-compose` | 0 | 0 | 1 | 3 | 1 | 0 | 5 |
| `19-reader-attachments` | 8 | 2 | 5 | 2 | 0 | 0 | 17 |
| `19b-reader-attachments-scrolled` | 6 | 2 | 5 | 2 | 0 | 0 | 15 |
| `20b-reader-after-archive` | 2 | 2 | 5 | 3 | 0 | 0 | 12 |
| `21-ai-sidebar` | 1 | 0 | 2 | 1 | 1 | 0 | 5 |
| `22-select-mode` | 1 | 3 | 5 | 4 | 0 | 0 | 13 |
| `23-compose-cc` | 1 | 0 | 1 | 2 | 0 | 0 | 4 |
| `25-move-sheet` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `25b-snooze-sheet` | 0 | 0 | 0 | 10 | 0 | 0 | 10 |
| `26-undo-toast` | 5 | 3 | 5 | 4 | 0 | 0 | 17 |
| `28-quick-reply` | 18 | 2 | 5 | 4 | 0 | 0 | 29 |
| `50-calendar` | 2 | 0 | 3 | 1 | 0 | 0 | 6 |
| `51-contacts` | 2 | 0 | 3 | 2 | 0 | 0 | 7 |
| `52-tasks` | 2 | 0 | 3 | 0 | 0 | 0 | 5 |

#### Other variants (summed over the screens each variant captured)

| Variant | Screens | Contrast | Hit area | Dyn. Type | Clipped | Label | Other | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| en-ax5 | 12 | 12 | 2 | 36 | 11 | 4 | 0 | 65 |
| en-dark | 13 | 30 | 6 | 41 | 27 | 7 | 0 | 111 |
| ipad-en | 8 | 33 | 20 | 51 | 40 | 5 | 0 | 149 |
| login-en | 3 | 4 | 0 | 4 | 2 | 0 | 0 | 10 |
| login-nb-dark | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| nb-ax3 | 5 | 7 | 1 | 24 | 9 | 2 | 0 | 43 |
| nb-dark | 11 | 27 | 5 | 41 | 19 | 3 | 0 | 95 |
| theme-blurple-night | 7 | 24 | 6 | 14 | 17 | 4 | 0 | 65 |
| theme-catppuccin-latte | 7 | 21 | 6 | 14 | 17 | 4 | 0 | 62 |
| theme-gruvbox-light | 7 | 22 | 6 | 14 | 17 | 4 | 0 | 63 |
| theme-solarized-dark | 7 | 31 | 6 | 14 | 17 | 4 | 0 | 72 |

Recurring items across variants (the same element appears on most screens
because the list stays in the tree behind the reader, see R1):

- **Dynamic Type partially unsupported:** list title, account subtitle, "N unread" capsule, row subject and preview (L9); compose Attach button (C5); Appearance preview text fully unsupported (T7); sheet toolbar buttons (H3).
- **Hit area too small:** reader "From …" (19 pt) and "to … ⌄" (15.7 pt) rows (R5); date section headers 18 pt (L3); bulk bar icons 28 pt (L1); search predicate chip (Q2); toast buttons (L8); Accounts "Make default" 78×16 pt (T3); About repository link 18 pt; All Inboxes footer status 18.5 pt.
- **Contrast failed:** quick-reply placeholder and disabled/dimmed rows (R6, T4); empty-state titles on the PIM covers (P1); glass toolbar Cancel/Add/Done (H3). Many contrast results come back with `element: nil` for SwiftUI nodes. Dark mode roughly doubles contrast failures per screen (en-dark 30 over 13 screens).
- **Label not human-readable:** raw email addresses as the only label (recipient chip C6, AI scope chip R12, Accounts rows T3).
- **Text clipped:** row previews (expected one-line truncation) plus real clipping in Accounts (T3), Snooze (H2), Notifications "Not requested" badge, PIM empty-state copy.

## 3. Proposed PR slices

Ordered by user impact. File ownership is chosen so slices can be built in
parallel; where two slices touch `BrevMailRootView.swift` they edit different
regions (noted). Every slice keeps macOS unchanged via `#if os(iOS)` or
size-class branches, uses theme tokens only, and adds en + nb catalog entries.

### Slice 1 — `fix(ios): push the reader and give it an iOS Mail action bar`

- **Findings:** R1, R2, R3, R4, R5, R6, R11, L8 (toast placement over the reader).
- **Files:** `MailCompactReaderStack.swift` (remove on iPhone), `BrevMailRootView.swift` (compact reader region ~640-651, 1578, 1724, 2862-2992, toast overlay 1089-1133), `MessageDetailView.swift` (top ••• 694-720, phone header 1173-1345), `ThreadConversationView.swift`, `ThreadMessageCard.swift`, `ReaderQuickReplyBar.swift`, `MailNavigationState.swift` (previous/next), `packages/BrevDesign/Sources/BrevDesign/Components/BrevToast.swift`.
- **Verification:** unit tests for the new "after archive/delete" navigation policy and the merged menu inventory (Swift Testing, `BrevMail`); snapshot tests of the phone reader header and thread card (light/dark, AX3); simulator: open → edge-swipe back, archive from reader shows toast + next message, VoiceOver focus lands on the new message; `performAccessibilityAudit` on the reader has no hit-area issues for the header rows.
- **Depends on:** nothing. Coordinate with Slice 2 on `BrevMailRootView.swift` (Slice 1 owns the compact reader and toast regions, Slice 2 the list toolbar region 2136-2281).

### Slice 2 — `fix(ios): native selection mode, unread dot and swipe parity in the message list`

- **Findings:** L1, L2, L3, L4, L5, L6, L7, L9, L10, L11.
- **Files:** `MessageListView.swift`, `UnifiedInboxListView.swift`, `BulkActionIconButton.swift`, `MessageCommandPresentation.swift`, `MailDenseChromeDynamicType.swift`, `MailPaneSurface.swift`, `BrevMailRootView.swift` (list toolbar/title region 2136-2281 and `refreshVisibleMail` wiring only).
- **Verification:** Swift Testing for swipe/context action ordering and selection-mode state; snapshot tests for list rows (read/unread, compact unified row, AX5) on iOS; simulator: Select → Select All → Archive → Cancel with VoiceOver; pull to refresh hits `refreshVisibleMail`; audit on list and select mode has no hit-area or DT-partial issues.
- **Depends on:** nothing (parallel with Slice 1; see file split above).

### Slice 3 — `fix(ios): compose cancel, focus, attachments and native compose sheets`

- **Findings:** C1, C2, C3, C4, C5, C6, C7, C8, C10 (and C9 if the quote-guard marker change stays small; otherwise split it out).
- **Files:** `ComposeView.swift`, `ComposeEditorTypography.swift`, `ComposeBodyEditor.swift`, `RecipientChipField.swift`, `ComposePresentation.swift`, `ComposeLinkSheet.swift`, `ScheduleSendSheet.swift`, `TemplatePickerView.swift`, `GoogleDrive*Sheet.swift`, `GoogleDriveSheetSupport.swift`, `ComposeReplyFormatter.swift`, `ComposeQuoteEditGuard.swift`.
- **Verification:** tests for the dirty-draft dismissal policy and the localized attribution + guard marker; compose snapshots (new, reply, Cc/Bcc expanded, AX3); simulator: New Message focuses To with keyboard up, Cancel on a dirty draft shows Delete/Save, swipe-down on dirty draft is blocked, paperclip shows Photos/Camera/Files/Scan; macOS compose snapshots unchanged.
- **Depends on:** nothing.

### Slice 4 — `fix(a11y): theme contrast contract, scalable icon buttons, plurals and extension strings`

- **Findings:** G1, G2, G3, N1, N2, N3, N4 (strings in files not owned by Slices 1–3 and 5–8), X1, X3.
- **Files:** `packages/BrevThemes/Sources/BrevThemes/BuiltIns.swift` + palette tests, `ADRs/0002-theme-system.md` (contract extension), `packages/BrevDesign/Sources/BrevDesign/Components/{BrevIconButton,BrevChip,BrevStatusBanner,BrevButton}.swift`, a `brevAnimation` helper, `packages/BrevMail/Sources/BrevMail/Resources/Localizable.xcstrings` (plural variants), `packages/BrevWidgets/**`, `apps/iOS/BrevShareExtension/Resources/Localizable.xcstrings`, `apps/iOS/BrevNotificationContent/**`, presentation/policy files from N4 (`ListUnsubscribePresentation.swift`, `MessageHTMLRenderPolicy.swift`, `MessageDetailPresentation.swift`, `MessageAttachmentActionPresentation.swift`, `ComposeRecipientAutocomplete.swift`, `ComposeAttachment*.swift`).
- **Verification:** extended palette contrast test over all built-ins (accent/danger/warning ≥ 4.5:1, border ≥ 3:1); catalog completeness test for nb including widgets and share extension; widget preview/snapshot with `containerBackground`; simulator in nb: date headers read "I går, 1 melding".
- **Depends on:** nothing. Protected path: ADR-0002 change.

### Slice 5 — `fix(ios): native search with scopes, tokens and suggestions`

- **Findings:** Q1, Q2.
- **Files:** `MessageListSearchField.swift` (replace on iOS), `MailSearchOptionsBar.swift`, `MailSearchStatusView.swift`, `CollapsibleOptionsStrip.swift`, `MessageListView.swift` (search band region 392-413 and predicate chips 3150-3175 only), `BrevMailRootView.swift` (search toolbar item 2246-2256 only).
- **Verification:** tests for scope → query mapping and when the "may be missing" status shows; simulator: search focus shows Cancel, suggestions, scope switch; results without bands on a complete local search; VoiceOver reads tokens.
- **Depends on:** Slice 2 (same files, different regions) — land after it or rebase onto it.

### Slice 6 — `fix(ios): one sheet appearance modifier and native utility sheets`

- **Findings:** H1, H2, H3, R12, O4. Snooze is excluded (separate PR in progress); only swap its `.brevTheme(theme)` call sites once that PR lands.
- **Files:** `RootAppearance.swift` (new `brevSheetAppearance()`), `BrevMailRootView.swift` (auxiliary presentation switch 4082-4422 and AI sheet 1172-1204 only), `MoveToSheet.swift`, `MessageNoteSheet.swift`, `MessagePropertiesSheet.swift`, `MessageRawSourceSheet.swift`, `MessageTaskSheet.swift`, `MessageEventSheet.swift`, `FollowUpDatePickerView.swift`, `InitialMailboxSelectionSheet.swift`, `OutboxView.swift`, `MailboxChatPanel.swift`, `MailContextChrome.swift`.
- **Verification:** snapshot of one representative sheet in follow-system dark, always-dark-on-light-system and a light theme; a test asserting no presented view in BrevMail uses `.brevTheme(` (grep test like the existing lint tests); simulator: each sheet has nav-bar Cancel/Done and follows the theme.
- **Depends on:** coordinate the compose sheets (C8) with Slice 3: Slice 3 rebuilds them, Slice 6 only swaps their theming modifier.

### Slice 7 — `fix(ios): Settings panes as Forms, flatter navigation and iOS-only copy`

- **Findings:** T1, T2, T3, T4, T5, T6, T7, T8, T9.
- **Files:** `packages/BrevSettings/Sources/BrevSettings/**` (SectionScaffold, SettingsSectionComponents, SettingsView, SettingsCategory, Sections/*, SavedSearchEditorView), `packages/BrevDesign/Sources/BrevDesign/Components/BrevQuietSurface.swift` (iOS branch), `apps/iOS/Sources/BrevApp.swift` (Settings presentation 103-145 only), `FolderSidebar.swift` (Smart Views sheet 356-377 only).
- **Verification:** settings snapshot tests on iOS (root, Accounts, Notifications, Appearance) in light/dark/AX3; macOS settings snapshots unchanged; settings search still finds every row; simulator: Settings → Accounts → toggle mailbox → default mailbox checkmark; denied notifications show Open Settings.
- **Depends on:** Slice 6 for the shared sheet modifier (or add it here if Slice 6 is later). Likely needs an ADR-0002 note on `BrevButton` vs form row buttons.

### Slice 8 — `fix(ios): Mailboxes list, PIM covers, iPad compose sheet and onboarding keyboard traits`

- **Findings:** S1, S2, S3, P1, P2, P3, P4, I1, I2, I3, O1, O2, O3, X2.
- **Files:** `FolderSidebar.swift`, `FolderSidebarPresentation.swift`, `BrevMailRootView.swift` (sidebar toolbar 1997-2019 only), `Calendar*View.swift`, `Contacts*View.swift`, `Task*View.swift`, `apps/iOS/Sources/BrevApp.swift` (detached window scenes 381-403), `MailRootComposePresentationPolicy.swift`, `IMAPAccountSetupSheet.swift`, `LoginView.swift`, `AppSessionPresentation.swift`, `ImportProgressBanner.swift`, `ImportProgressPresentation.swift`, `apps/iOS/BrevShareExtension/ShareViewController.swift`.
- **Verification:** sidebar snapshot (expanded account, AX5); calendar month/day snapshots at compact width with seeded events (stub DAV); simulator with `scripts/stub-dav-server.py`: PIM empty-state button opens the right Settings page; iPad: Reply opens a form sheet, relaunch restores no compose window; add-account email field offers Keychain autofill and Return runs Find settings.
- **Depends on:** Slice 6 (sheet modifier) for the PIM editors. Large; split into 8a (sidebar + iPad), 8b (PIM), 8c (onboarding + share extension) if parallel agents are available.

## 4. Not reached or not verified

| Area | Status | Why / what would verify it |
| --- | --- | --- |
| Attachments, remote-content and read-receipt banners, List-Unsubscribe, calendar invites, wide HTML newsletters (R7–R10) | Code only | Mock messages have plain bodies and no attachments. Needs a fixture backend with HTML, attachments and receipt headers, or a smoke account. |
| Calendar/Contacts/Tasks with data (P2–P4) | Code only; empty states captured | Mock has no PIM source. `scripts/stub-dav-server.py` + seeded `.ics`/`.vcf` (see the testing skill) would let the grid, detail and editor screens be audited. |
| Google sign-in, Google Drive sheets (C7), Gmail-specific UI | Not reached | The local build has no Google OAuth client or Drive keys. C7 is a layout bug visible in code. |
| Widget (X1), share extension (X2), notification content (X3) | Code only | Not added to a home screen, not invoked from a share sheet, no notification delivered in the simulator. |
| VoiceOver speech order, Switch Control, Voice Control | Inferred | Evidence is the accessibility tree and `performAccessibilityAudit`; no VoiceOver session was recorded. R1 (list behind reader still in the audited tree) and the banner `.combine` issue (O3) need a VoiceOver check. |
| Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text at runtime | Code only | Not toggled in the simulator for this pass; G3 is from code. Increase Contrast is handled by `brevRootAppearance` (`colorSchemeContrast`), not checked visually. |
| iPad hardware keyboard and focus | Inconclusive | The simulator had no hardware keyboard attached: ⌘/ focused the search field and brought up the software keyboard (`ipad-en-43-ipad-cmd-slash.jpg`) rather than proving or disproving the shortcut overlay. |
| iPad landscape screenshots | Partial | XCUITest captures in landscape came back rotated and cropped; the `-rot` images show the usable part. Portrait captures are complete. |
| Swipe right (leading actions) | Not captured | The synthetic swipe did not reveal the leading actions; L6 is from code. |
| Snooze sheet | Not in slices | Captured (`en-light-25b-snooze-sheet.jpg`, 6× "Text clipped") but being redesigned in a separate PR; only its theming call sites appear in H1. |
| Settings sub-pages in Norwegian | Not captured | The settings walker matched English labels, so in `nb` it only reached the root (`nb-dark-09-settings.jpg`). Catalog coverage for BrevSettings is complete (1156 keys, 0 missing nb); the gaps are the plain-`String` literals in N4 and T6. |
| Error, offline and re-auth states, Outbox, undo-send countdown, InitialMailboxSelectionSheet | Code only | The mock backend does not fail, has no `OutboxManaging`, and undo send defaults to 0 s. |
| Physical device, live IMAP/SMTP, push | Not in scope | Mock data only by instruction. |
