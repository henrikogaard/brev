# Brev UI/UX review — 2026-09-27

Revision: `main` @ `1422851` — all ten PRs from this week are merged
(composer polish #111; DAV error surfacing #113/#114/#115/#117; Google
missing-config guidance #116; stale-precondition re-resolution #119/#120;
save-error callout above the fold #121).

Reviewer stance: Apple-platform designer doing a pre-v1 pass; reference apps are
Apple Mail, Calendar, Contacts and Reminders. This is a critique, not a pass/fail
regression run. No app code was changed.

Environments exercised:

| Platform | Build | Modes covered |
| --- | --- | --- |
| macOS 26 | `Brev Test (2026-09-27).app` (mock, `./script/build_and_run.sh --mock`) | Light + Dark (in-app Appearance), 1440 / 900 / ~960 pt-min widths |
| iPhone 17, iOS 27 (`8E780854…`) | `BrevIOS` team-signed from this revision, `BREV_USE_MOCK=1` | Light + Dark, portrait + landscape |
| Stub DAV server | `scripts/stub-dav-server.py --port 8643` | CalDAV calendar, CardDAV, CalDAV tasks connected through Settings on both platforms |

Screenshots live in `docs/qa/uiux-review-2026-09-27/` (referenced below).
Recording: `/Users/devin/screencasts/rec-uiux-0927/rec-uiux-0927-edited.mp4`.

Not reached in this pass (called out honestly rather than inferred): iPad
entirely; Dynamic Type accessibility-extra-large; a real Google OAuth flow
(the build intentionally bakes an empty client ID, so the #116 guidance
callout is what a user sees); macOS toast/banner states (none triggered by
mock data); Settings sections beyond Accounts, Appearance, Mailbox View and
Calendar & Contacts; iOS event/task **editors** (DAV sources were wiped
mid-pass — see M3 — so only the contact editor was re-opened); physical-device
confirmation of the landscape back-button hit-target overlap (M1); mailto:
handling.

A testing note, not a product finding: iOS `developer.demoModeEnabled` is a
user-default that survives `simctl uninstall` — after removing the demo
account the app still booted to the inbox until the defaults domain was
deleted. Harmless for users; it makes "fresh onboarding" hard to reach on a
sim without `defaults delete eu.brevmail.brev.ios`.

---

## Top-10 "fix first"

| # | Severity | Surface (platform) | Finding | Screenshot |
| --- | --- | --- | --- | --- |
| 1 | high | Calendar / Contacts / Tasks covers (iPhone, portrait) | Cover content is laid out wider than the screen and pushed offscreen-left — row text clipped mid-word, and the nav-bar back button is rendered offscreen entirely (`offscreen=true` in AX; unreachable by taps, edge swipes, or AX scroll). All three covers affected; landscape renders them correctly | `ios-04…`, `ios-06…`, `ios-11…`, `ios-18…` |
| 2 | high | Calendar / Contacts / Tasks windows (macOS) | No live-refresh: a DAV source connected while the window is open never appears — all three windows stay on "No sources connected" until closed and reopened (3/3 reproduced) | `macos-13…` → `macos-17…`, `macos-21…` → `macos-22…` |
| 3 | medium | Reader (iPhone, landscape) | "Back to messages" hit target is overlapped by the floating Reply/Archive/Delete action bar — AX reports its centre "covered by button Reply"; chevron taps repeatedly did nothing | `ios-23-dark-reader.png` |
| 4 | medium | Account removal (iOS) | Removing the last account leaves dangling records — the next launch shows an "Account error — one or more accounts couldn't be restored" alert and a persistent "Saved account settings are incomplete" banner over onboarding | `ios-20…`, `ios-21…` |
| 5 | medium | Add mail account sheet (iOS) | A ~80 s IMAP connect failure re-enables "Add account" with **no in-sheet error**; the "IMAP transport failed" callout only appears on the LoginView behind after Cancel — inconsistent with the DAV sheet's in-sheet callout (#113) | `ios-17-light-onboarding-error.png` |
| 6 | medium | PIM detail panes (macOS) | Read-only: event detail offers only "Copy Link", contact detail only "Copy Link", task detail nothing — while iOS contact detail exposes Edit / Delete / Copy Link. macOS users cannot modify DAV items at all | `macos-20…`, `macos-23…`, `macos-24…` |
| 7 | medium | Search scope chips (macOS, carried) | All/From/Subject/… scope pills are still heavy black chips rather than NSSearchField tokens/menus | `macos-08…` |
| 8 | medium | Composer label gutter (macOS, carried) | To / From / Subject labels still sit at slightly different x positions (~5 pt drift); Send remains a filled black capsule | `macos-06…` |
| 9 | polish | Event detail (iPhone) | Only "Copy Link" is offered — no Edit/Delete — while contact detail shows all three. Possibly "Allow editing"-gated, but the detail gives no hint why editing is absent | `ios-06…` |
| 10 | polish | Add DAV Source username field (macOS) | The placeholder is a person glyph that reads like already-entered text; typed input silently did not register and Connect stayed disabled with no hint of what was missing | — |

---

## Findings by severity

### High

#### N-H1 — iPhone PIM covers render offscreen-left in portrait
- **Surface:** Mailboxes → More → Calendar / Contacts / Tasks (iPhone).
- **What's off:** In portrait, every cover lays out a wider-than-screen
  column offset to the left. The agenda list clips mid-word ("…bour Data —
  daily standup", "…m 3 Stub Calendar"); the contacts list clips similarly;
  the event detail loses the leading third of every line ("…migration —
  design review", "…oom 3"); the tasks empty-state subtext is cut on both
  edges. Worst of all, the covers' back/dismiss control is laid out beyond
  the screen edge — accessibility reports it `offscreen=true` and refuses to
  scroll it into view; taps, edge swipes and swipe-down all fail. The only
  recovery found was rotating to landscape (or relaunching the app).
- **Why it matters:** all three covers are effectively unusable in portrait —
  users can open them but can't read them or leave them. Any mechanism that
  resizes the presented content (rotation, dynamic type, split) risks the
  same offset.
- **Fix:** the cover presentation appears to measure against a wider or
  landscape-oriented bounds — verify the cover's content is laid out against
  the *current* trait collection / window bounds, not a stale size, and that
  the nav-bar chrome participates in the same bounds. A smoke test that
  presses the back affordance after rotation changes would have caught this.
- **Screenshots:** `ios-04-light-calendar-agenda.png`,
  `ios-06-light-event-detail-portrait-clip.png`,
  `ios-11-light-contacts-clip.png`, `ios-18-light-tasks-clip.png`;
  landscape controls: `ios-05-light-calendar-landscape.png`,
  `ios-12-light-contacts-landscape.png`, `ios-19-dark-tasks-landscape.png`.

#### N-H2 — macOS PIM windows never pick up a source added while open
- **Surface:** Window → Calendar / Contacts / Tasks (macOS).
- **What's off:** with a PIM window open, connect a DAV source in Settings →
  Calendar & Contacts — the window keeps showing "No sources connected"
  forever. No sync spinner, no error, no row. Only ⌘W + reopen shows the
  data. Reproduced identically on all three windows.
- **Why it matters:** the natural first-run flow is "open Calendar → nothing
  there → go add a source → come back" — and it still shows nothing. It
  reads as "the connection failed" and will generate support noise.
- **Fix:** the windows should observe the source list / sync state (they
  clearly can — a reopened window renders correctly), or Settings should
  post a refresh. At minimum a "Sources changed — Reload" affordance.
- **Screenshots:** `macos-13-light-calendar-empty.png` (after adding the
  source, still empty) vs `macos-17-light-calendar-agenda.png` (same window
  reopened); `macos-21-light-contacts-empty.png` vs
  `macos-22-light-contacts-list.png`.

### Medium

| ID | Surface (platform) | Finding | Fix | Screenshot |
| --- | --- | --- | --- | --- |
| M1 | Reader (iPhone, landscape) | AX reports "Back to messages" centre covered by the floating Reply/Archive/Delete action bar; chevron taps didn't navigate — had to rotate to portrait to go back | Give the back control z-priority over the floating bar, or move the bar off the nav area in landscape | `ios-23-dark-reader.png` |
| M2 | Account removal → relaunch (iOS) | After removing the only signed-in account, next launch raises "Account error — one or more accounts couldn't be restored" plus a sticky "Saved account settings are incomplete" banner on the LoginView | Cascade-delete (or re-key) the account's dependent records on removal; don't surface a restore error for a deliberately removed account | `ios-20-dark-onboarding-accterror.png`, `ios-21-dark-onboarding.png` |
| M3 | Add mail account sheet (iOS) | Submit to an unreachable IMAP server spins ~80 s, then silently re-enables "Add account" — no in-sheet callout; the red "IMAP transport failed" banner appears only on the LoginView after Cancel | Render the failure inline in the sheet like the DAV connect sheet does (#113) | `ios-17-light-onboarding-error.png` |
| M4 | PIM detail panes (macOS) | Detail panes are read-only — event: "Copy Link" only; contact: "Copy Link" only; task: no affordances at all — while iOS exposes Edit / Delete / Copy Link | Add Edit/Delete affordances gated on the source's "Allow editing" (already in Settings) | `macos-20-light-event-detail.png`, `macos-23-light-contact-detail.png`, `macos-24-light-task-detail.png` |
| M5 | Search (macOS, carried) | Scope chips (All / From / Subject / …) remain heavy black pills | System token/menu styling | `macos-08-light-search-scope-chips.png` |
| M6 | Composer (macOS, carried) | To / From / Subject labels still ~5 pt misaligned; Send a filled black capsule | Fixed-width label gutter; toolbar-style send | `macos-06-light-composer-format-menu.png` |
| M7 | Inbox footer pill (iPhone, carried) | "9 messages · 5 unread" pill still overlaps the last visible row | Bottom-inset the list | `ios-22-dark-inbox.png` |
| M8 | Contact & task editors (iOS, carried from #120) | `lastError` still renders as red caption text at the **bottom** of the form below the fold; #121 lifted it into a `BrevInlineStatus` at the top only in the event editor | Apply the same top-of-form banner in `ContactEditorView` / `TaskEditorView` | (verified on PR #120 run; pattern unchanged on main) |
| M9 | Calendar stub times (carried) | Seeded events still render odd hours ("Friday, 25 Sep at 4:00AM – 5:00AM") — likely a TZ conversion | Format in the event's local zone | `macos-29-dark-calendar.png` |

### Polish

| ID | Surface (platform) | Finding | Fix | Screenshot |
| --- | --- | --- | --- | --- |
| P1 | Event detail (iPhone) | Only "Copy Link" visible — no Edit/Delete even after "Allow editing" was on for the source; contact detail offers all three. Either a gating inconsistency or affordances hidden by the clipping (N-H1) | Audit edit affordances per object kind; surface a hint when editing is disabled | `ios-06-light-event-detail-portrait-clip.png` |
| P2 | Add DAV Source username field (macOS) | Placeholder is a person glyph that can read as entered text at a glance; plain typing into the field didn't register and Connect stayed silently disabled — only AX `set_text` filled it | Use a text placeholder ("Username"); validate on field blur; keep the person glyph as a leading icon distinct from the text | — |
| P3 | Reader (iPhone) | Message body area renders blank for a beat before content paints (noticed in dark mode) | Skeleton or cached render | `ios-23-dark-reader.png` |
| P4 | Onboarding after account removal (iOS) | The stale "Saved account settings are incomplete" banner persists on the LoginView alongside the Google-config callout — two stacked banners fight for attention | Collapse to one status banner with priority | `ios-21-dark-onboarding.png` |
| P5 | Add mail account sheet (iOS) | "Advanced setup" disclosure row ignored a direct coordinate tap; expanded only via AX press — its hit area may be narrower than the row | Make the whole row the button | `ios-15-light-add-account-advanced.png` |

---

## Previously reported — re-verified on main @ 1422851

| 09-26 ID | Surface | Status on main | Evidence |
| --- | --- | --- | --- |
| H1 | Add DAV Source sheet | **Fixed** — no premature validation box; kind picker is a compact pill radiogroup; manual URL + u/p connects cleanly | `macos-15`, `macos-16` |
| H2 | Reader clips at 700 pt | **Fixed** — window min width ~960 + pane minimums make the clip unreachable | `macos-11`, `macos-12` |
| H3 | iPhone thread all-collapsed | **Fixed** — latest message expanded, older collapse with preview lines | `ios-09`, `ios-23` |
| H4/H5 | Sidebar glyph/chevron columns | **Fixed** — one glyph column, chevrons in reserved gutter, icons on/off both clean | `macos-02`…`macos-04` |
| H6 | Add-account dead end | **Fixed** both platforms — "Advanced setup" → Google / Outlook / Manual IMAP/SMTP pills + full server fields | `macos-25`, `ios-14`, `ios-15` |
| H7 | DAV source toggle labels | **Fixed** both platforms — "Background sync" / "Allow editing" labeled and live | `macos-15`/`16`, `ios-08` |
| H8 | Window reopen | **Fixed** — Window → Message Viewer ⌥⌘0 reopens the viewer | Window menu |
| M9 (part) | Orphan caption / mailbox-view pills | Partially still present — scope-chip heaviness carried as M5 | `macos-08` |
| M12/P4 | iOS footer pill / Dynamic Type | Footer pill overlap persists (carried → M7); Dynamic Type not re-run | `ios-22` |
| P3 | Reader "Dark" pill | Not re-verified (message display control now a combobox in the reader header) | `ios-23` |

This week's merged surfaces, in situ: **#111** iPhone composer polish renders
correctly in light and dark (centred "New Message", text Send, To → From →
Subject, From picker, bottom Attach/Aa/⋯ bar); **#115** verified live — after a
failed manual IMAP add + Cancel, the section title stays "Choose how to
connect"; **#116** verified — "Google sign-in isn't configured in this build…"
callout renders on the LoginView in both themes. #113/#114/#117/#119/#120/#121
were device-verified on their fix branches earlier this week; on main the DAV
sheet is clean and nothing regressed the surfaces they touched.

---

## What already feels good (do not regress)

| Surface | Why it works |
| --- | --- |
| iPhone composer (#111) | The centred title + text Send + ordered fields + bottom utility bar now read like a real Mail sheet — `ios-10`, `ios-24` |
| Thread collapse (both platforms) | Latest expanded, older messages collapse to one-line previews — exactly Mail's contract — `ios-09`, `macos-05` |
| Onboarding / add-account (#115, #116, H6) | Real guidance for a missing OAuth config, stable section title after failure, Advanced setup that actually expands — `ios-16`, `ios-17`, `macos-25` |
| Dark palette (macOS + iOS) | Neutral greys, no tinted chrome, good contrast on inbox/reader/composer/calendar — `macos-26`…`macos-29`, `ios-19`…`ios-24` |
| macOS window management | Message Viewer ⌥⌘0 reopens; min-width + pane minimums prevent the old reader clip — `macos-11`, `macos-12` |
| Contact editor (iPhone) | Native grouped form, photo picker, labelled fields — `ios-13` |
| Account-removal flow (iOS) | Context menu on the account card → "Server mail is not deleted" confirmation is honest copy — but see M2 for the aftermath |
| DAV source rows | Per-source labelled toggles + status; manual connect via stub worked first try on both platforms — `macos-16`, `ios-08` |
| Empty states | Trash / PIM empty states are calm and centred — `macos-10` |
| AX labels | Row summaries carry unread state ("Unread, MS, Marte Solheim, …"), disclosure controls report Collapsed/Expanded, toggles are labelled |

---

## Screenshot index

All files in `docs/qa/uiux-review-2026-09-27/`: `macos-01` … `macos-29`
(light 01–25, dark 26–29), `ios-01` … `ios-24` (light 01–18, dark 19–24).
Names encode platform, mode, surface and the finding they support.
`macos-12-light-window-700w` is a duplicate capture — the window clamps at
its ~960 pt minimum rather than reaching 700 pt.
