# Brev UI/UX Audit — 2026-09-22

Scope: full-surface audit of the macOS app ("Brev Test (2026-09-22).app") and the iOS app (BrevIOS on iPhone 17, iOS 27.0), both running `BREV_USE_MOCK=1` demo data. Evaluated: sidebar/folders, smart views, message list, reading pane, compose, sheets, all Settings sections, calendar/contacts/tasks, menus, shortcuts, undo/toast, empty states, cross-platform feel.

Evidence: `/tmp/uiux/*.png` (macOS = `mac-*.png`, iOS = `ios-*.png`), session recording.

Status (same-day update): C1, C2, C3 fixed and verified; C4, N4 verified
as non-issues; every nice-to-have N1–N13 fixed and verified on both
platforms (`fix/uiux-audit-sep22` / PR #85). P1–P9 polish items remain
open for a later pass.

## Critical

| # | Platform | Surface | Issue | Evidence | Suggested fix |
|---|----------|---------|-------|----------|---------------|
| C1 | Both | Smart Views → folders | Selecting a smart view (VIP, Flagged, Today…) silently sets a persistent quick filter that leaks into every regular folder. Afterwards Inbox/All Inboxes/Drafts show 0 messages (footer: "0 shown · 38 total") with **no visible filter indicator** — looks like lost mail. Recoverable only via funnel menu → Clear Filters. On iOS the leaked-filter list is fully blank (not even the "No messages" state). | mac-04-vipfilter-stuck.png; ios-03-inbox-restored.png | Scope the smart-view filter to that view; or when a folder renders 0-of-N, show a persistent "Filtered" banner + Clear affordance in the list body, not just an icon tint. |
| C2 | iOS | Calendar / Contacts / Tasks | All three fullScreenCover surfaces render **completely blank** (black in dark mode, white in light) — only a Done button. Reproduced on both themes. macOS equivalents at least show an empty state. | ios-07-calendar-blank.png | These covers seem to fail silently — check CalendarRootView/ContactsRootView/TasksRootView init path under mock (PIM services nil?). At minimum show the empty-state, not a void. |
| C3 | iOS | Drafts | Tapping a draft opens a **read-only** message view ("No body content"). The "…" menu offers Move/Forward/Reply All/etc. but no Edit/Continue. A saved draft cannot be resumed — dead end. | ss_45406f8b.png (Drafts detail) | Draft tap should reopen the composer with saved content, or add a prominent "Edit Draft" action. |
| C4 | macOS | Window lifecycle | The app process **exited** after the detached reader window closed (observed once — app relaunch required). If intentional quit-on-last-window-close, it's unusual for a mail client (Mail.app stays running). | mac-08-relaunch.png (post-relaunch) | Verify intended behavior; a mail app should typically stay running headless. Investigate whether the reader-window close path exits the process. |

## Nice-to-have

| # | Platform | Surface | Issue | Evidence | Suggested fix |
|---|----------|---------|-------|----------|---------------|
| N1 | macOS | Menu bar → View | The **View menu is completely empty** — 0 items via accessibility, clicking shows nothing. Dead menu in the menu bar. | ss_7f23f6db.png | Remove the View menu or populate it (Toggle Sidebar, layout options, Enter Full Screen). |
| N2 | macOS | Menu bar → Message | Duplicated command groups: "Mark as Read", "Unflag", "Forward", "Previous/Next Message" each appear **twice** with different shortcuts (⌘U dup; ⌥⌘F vs ⌘F; ⌘↑/↓ vs ⌘[/]). | mac-09-message-menu-dupes.png | Merge the two command blocks; one entry per action per menu. |
| N3 | macOS | Menu bar → Window | Calendar/Contacts/Tasks appear **twice** in the Window menu (once in windowList group, once near bottom). | AX dump | Deduplicate the CommandGroup insertions. |
| N4 | macOS | Keyboard Shortcuts help vs menus | Reference says Reply All ⌘⇧R / Forward ⌘⇧F, but Message menu shows ⌥⌘R / ⌥⌘F — help doesn't match real bindings. | ss_1103b9de.png | Single source of truth for shortcut definitions; regenerate help from command specs. |
| N5 | macOS | Aux windows (Calendar/Contacts/Tasks) | ~90px source rail too narrow: empty-state copy wraps mid-word ("No calen-dars con-nected"). Also "Pick an event from the agenda" but no agenda pane is visible. | mac-10/11/12 | Min-width the rail to fit text, or use a full-width empty state. |
| N6 | macOS | Message list | Right-click context menu only opens on the already-selected row; right-clicking an unselected row silently selects it with no menu (non-standard macOS behavior). | mac-05-message-ctxmenu.png | Standard select-then-context-menu on any row. |
| N7 | iOS | Compose autocomplete | Suggestion chip is cramped — name truncated oddly ("Matte <…e Solheim"), rendered as a floating chip overlapping the field rather than a list row. | ss_f53d165c.png | Present suggestions as full-width rows below the field (macOS style). |
| N8 | iOS | List footer | "N messages · N unread" pill floats **over** the last message row, covering its content. | ios-05-inbox-private.png | Reserve bottom inset/padding or pin pill outside scroll content. |
| N9 | iOS | Draft save feedback | Compose auto-saves (draft present in Drafts) but gives no feedback; macOS shows "Draft saved." toast. Closing compose with content shows no confirmation either. | — | Parity: ephemeral toast on auto-save; or explicit save/discard prompt on close-with-content. |
| N10 | macOS | Reading pane | Single-message header layout differs from thread-card headers (name+email inline, lowercase "to", Dark pill) — two header designs for the same concept. | ss_928a9d99.png vs ss_6286e0d7.png | Unify header component between thread cards and single-message view. |
| N11 | Both | Smart view empty states | Generic copy "Messages you receive will appear here" on Snoozed/Done/VIP — doesn't describe the view. Search empty state is better ("No results for 'x'" + Clear). | ss_bbc271cb.png | Per-view empty copy ("Snoozed messages will appear here" etc.). |
| N12 | Both | List footer stats | Footer shows account-wide aggregates ("38 messages · 16 unread") even when the current view is empty/filtered — misleading. | ss_bbc271cb.png | Show view-scoped counts, or drop aggregate on filtered/empty views. |
| N13 | macOS | Snooze discoverability | Snooze isn't in the toolbar "…" menu (Move/Follow Up/Create Task are); only via right-click context menu. iOS same gap — only long-press. | mac-05-message-ctxmenu.png | Add Snooze to the "…" action menus for parity. |

## Polish

| # | Platform | Surface | Issue | Evidence | Fix direction |
|---|----------|---------|-------|----------|----------------|
| P1 | macOS | Undo toast | "Deleted" toast appeared after one delete but not the next consecutive delete — inconsistent; auto-dismisses fast. | ss_68753326.png | Ensure toast re-triggers per mutation or stacks a count. |
| P2 | macOS | Settings → Auto-Reply | Red "Add a message before saving." validation shows on first load before any input. | ss_30dcf21e.png | Validate on submit, not initial render. |
| P3 | macOS | Compose | Selected recipient renders as raw email text + ✕, not a display-name chip. | ss_b0aa4bad.png | Render "Marte Solheim <email>" chip or name pill. |
| P4 | macOS | Reading pane | Tapping the account's own recipient chip does nothing (lookup miss → silent no-op) — no feedback. | — | Show subtle "Add to Contacts" affordance or nothing-for-self state. |
| P5 | macOS | Template picker | Header "0 template(s)" redundant vs the empty state below it. | ss_ee47d88a.png | Hide count when empty. |
| P6 | macOS | Smart Views header | Disclosure needed a precise click — label/chevron taps felt finicky. | — | Widen hit area to the whole header row. |
| P7 | Mock | Message bodies | All expanded messages share identical placeholder body text; invite event dates (11–13 Sep) don't match subject (12–14 Sep). All Attachments view empty despite attachment glyphs (attachments not cached). | ss_6286e0d7.png | Mock-data nits — vary bodies; align invite dates; cache one attachment for demo. |
| P8 | macOS | Help menu | Contains only "Keyboard Shortcuts…" — no app help/docs/feedback. | — | Add Help/Feedback entries. |
| P9 | iOS | Settings rows | Row taps felt finicky — needed taps near row text; taps on leading-icon zone didn't navigate (may be simulator imprecision; verify on device). | — | Verify hit targets on hardware. |

## What feels genuinely good

- **Theme system is excellent**: instant app-wide recolor on both platforms, 10–12 curated themes per mode with a swatch grid, live mail preview in settings. Dark mode flips every surface cleanly.
- **Search**: Local/Auto/Server scope chips, keyword chips, "Search finished · Some results may be missing" honesty, and a proper "No results for 'x'" + Clear empty state.
- **Calendar invite banner + RSVP**: clean card with Accept/Maybe/Decline, Tentative state, and an honest "not synced to a Brev calendar" caveat — thoughtful.
- **Move To sheet**: scoped to the source mailbox, search filter, correct folder hierarchy indent.
- **Message context menu**: 25+ actions (Pin, Snooze, Mark Done, Block Sender, Create Rule/Task/Meeting, Keep Offline, Copy Message Link…) — deep feature surface.
- **Settings depth**: ~21 sections, per-mailbox contexts, capability gating with explanations ("does not provide original message source"), honest network/AI copy.
- **Pin to Top** creates a proper PINNED section; **draft autosave** works on both platforms; **thread expansion** is smooth; **swipe actions + long-press** on iOS feel native.
- Badge counts, date sections, unread dots, attachment/thread glyphs are consistent between platforms.

## Coverage notes

- Mock mode has no PIM sources seeded, so Calendar/Contacts/Tasks content couldn't be evaluated beyond the empty/blink states (which surfaced C2/N5).
- Remote-content banner, List-Unsubscribe banner, and error banners weren't reachable in the mock data.
- Outbox/schedule-send couldn't be exercised (mock has no scheduled queue UI entry point found; Schedule send in compose was disabled).
- iPad/landscape layouts not tested (iPhone 17 portrait only).
