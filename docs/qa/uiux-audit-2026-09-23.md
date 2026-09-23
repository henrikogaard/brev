# UI/UX + accessibility audit — 2026-09-23 (round 2)

Audited on `main` @ `4617777` in mock mode: macOS `Brev Test` + BrevIOS on
iPhone 17 simulator (iOS 27.0), recorded full-surface pass.

**Headline:** no release blockers found. Since the previous audit the mock
ships stub DAV sources — Calendar (Agenda/Day/Week/Month + event detail +
editor), Contacts (real entries + complete edit sheets), and Tasks are
populated surfaces for the first time. All #85 fixes still hold; #89's
sent-copy fix verified (clean `>` quotes, no entities). C4 (quit-on-close)
did not reproduce — confirmed non-issue.

## Critical

None.

## Nice-to-have (ordered by impact)

| # | Platform | Surface | Issue | Suggested improvement |
|---|---|---|---|---|
| N1 | macOS | Keyboard nav | Tab only reaches the sidebar outline; **no visible focus ring anywhere**; arrow keys inert in sidebar + message list. Keyboard-only users can't operate the app beyond menus — biggest a11y gap. | Add `.focusable()` + focus ring treatment on interactive lists; wire arrow-key selection in sidebar and message list; make focus move sidebar→list→reader. **Recommend treating as release-gating for a11y.** |
| N2 | macOS | Contacts/Tasks windows | "No selection" detail panes render **white in dark mode**; populated details are dark — theme inconsistency. | Empty state should use the view's theme background, not `.windowBackground`/white. |
| N3 | macOS | Calendar | Week/Month/Day layouts render inside the ~140pt rail only — events become single-letter chips. iOS uses full width correctly. | Give the calendar surface a proper detail column (or wide layout) on macOS instead of confining it to the PIM rail. |
| N4 | macOS | DAV writes (mock) | Saving a stub-DAV event/contact prompts for a **real Keychain item** — writes unverifiable without the login-keychain password. Denial handled gracefully (sticky inline error). | Mock mode should bypass the real Keychain for stub credentials (in-memory credential store) so write round-trips are testable. |
| N5 | macOS | Compose | Reply quote region freely editable — cursor lands mid-quote, typed text merges into the quote. | Make the quote block non-editable or break out of it on typing (caret policy + visual separation). |
| N6 | iOS | Reader "…" | **No Snooze** (macOS reader "…" has it per N13 round-1) and no plain Reply (Reply All/Forward only). Long-press offers Snooze. | Parity: add Snooze… + Reply to the reader "…" menu. |
| N7 | backend | Recipients | Recent-recipient store accepts malformed addresses — a polluted `ingrid.halvorsen@acme.examplepost-merge` persists and suggests as "Contact". | Validate/normalize addresses on insert into the recent-recipient store. |
| N8 | macOS | Settings | Auto-Reply shows premature validation "Add a message before saving." with the feature **off** (carried from audit 1). | Only validate the message field when the feature is enabled or on save. |
| N9 | iOS | Reader | Body pop-in delay — blank body ~1–1.5s before rendering (worse at larger Dynamic Type). | Render a skeleton/progress state or last-known snippet while the body loads. |

## Polish

- P1 AI sidebar: chat input placeholder reads "Unavailable"; scroll-to-bottom FAB shows with no content.
- P2 Quick-filter icon lacks active tint when filtered (only footer counts hint).
- P3 iOS calendar view switcher truncates ("Ag…/We…/Mo…").
- P4 Compose "…" menu lacks Discard — closing silently saves another draft copy.
- P5 Sent copies render reply quotes as literal `>` text vs styled quote bar.
- P6 Stub PIM data differs per platform ("harbour-date"/Completed vs "harbour-data"/Needs action).
- P7 Aux windows don't persist size — Calendar reopens small.
- P8 "Hide AI Sidebar" inside message-actions "…" menu (view control misplaced — carried over).
- P9 Escape in chip field commits text as a chip instead of canceling.
- P10 macOS contact editor lacks iOS's Addresses + Groups sections (iOS editor richer).
- P11 Add-account "Find settings" silently no-ops on malformed email — no validation feedback.

## Accessibility notes

- **Inbox toolbar (issue #1):** fully verified — every control announces
  name + role, back chevron is destination-aware, message rows expose rich
  labels + custom rotor actions.
- **Dynamic Type:** list + reader adapt cleanly at +3 steps.
- **macOS keyboard navigation is the dominant gap** (N1) — no focus
  ring, no arrow-key traversal, Tab reaches only the sidebar outline.
- Footer pill `Inbox, 9 messages, 5 unread` is labeled but has no Button
  trait — acceptable if informational only.

## Consistency notes

- iOS surfaces look consistently stronger than macOS this round (calendar
  layout N3, contact editor P10, reader actions N6 are all iOS-wins).
- The improvement theme for v1: **macOS keyboard operability + theme
  consistency in empty states + compose quote hygiene**, then the parity
  deltas (Snooze/Reply on iOS reader, editor sections on macOS contacts).

## Verified good

- #85 regression suite still all-pass on `4617777`.
- #89 sent-copy quotes verified clean.
- Privacy surfaces: S/MIME depth, sender-icons-off note, honest
  notification-sync caveats — excellent copy.
- iOS swipe + long-press menu depth.

## Known mock limits

- Stub-DAV writes need the real login Keychain (N4) — round-trip write
  verification pending a password or the in-memory-credential change.
- No live Google/DAV accounts — provider sync paths remain #11/#2 scope.

## Improvement roadmap (suggested order)

1. **N1** macOS keyboard navigation + focus rings (a11y).
2. **N2** dark-mode empty-pane theme fix.
3. **N3** macOS calendar layout (full-width detail).
4. **N6** iOS reader "…" parity (Snooze + Reply).
5. **N5** compose quote-block editing guard.
6. **N4** mock Keychain bypass for stub credentials.
7. **N7** recent-recipient validation.
8. **N8** Auto-Reply premature validation.
9. **N9** iOS reader body-load state.
10. Polish items P1–P11 as a batch.
