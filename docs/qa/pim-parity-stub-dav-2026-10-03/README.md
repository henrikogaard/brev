# PIM parity stub-DAV pass — 2026-10-03 (issue #11)

iOS simulator evidence for the three stub-matrix rows still open after the
2026-09-26 pass: **2.7** (attendee add/remove), **2.8** (RSVP round-trip)
and **4.3** (background pickup without relaunch). See
`docs/qa/pim-parity-matrix.md` for the matrix.

## Setup

| Item | Value |
|------|-------|
| Build | `main` @ `ed631a71`, iOS Debug, mock mail mode, fetch interval 5 min |
| Device | iPhone 17 Pro simulator, iOS 27.0 (Xcode 27.0, 27A266a) |
| Stub | `scripts/stub-dav-server.py --port 8643 --auth stub:<pw> --seed <dir>` |
| Seed | canonical `scripts/stub-dav-seed/` + `seed-evt-hytte-invite.ics` (this dir) |
| Source | CalDAV "Stiv CalDAV" → `http://127.0.0.1:8643/`, editing ON |
| Locale | Norwegian Bokmål UI |

The invite seed shares its UID with the mock mailbox's Sigrid Moen invite
(`MockBackend` m1, "Hytte weekend in Hemsedal"), so the mail invite card
resolves to a writable event on the stub calendar. All names and
addresses are synthetic (`*.example`, `example.org`).

## Results

### 2.8 — RSVP accept / maybe / decline (✓)

Mail → All inboxes → "Re: Hytte weekend…" → Sigrid Moen's message → invite
card (`ios-10-rsvp-invite-card.png`). Each response is single-shot per
message (answered state hides the buttons), so the app was relaunched
between responses. Mock mail state resets on relaunch, but the PIM cache
persists.

| Response | Wire (stub log) | Remote ATTENDEE after | UI |
|----------|-----------------|-----------------------|----|
| Godta (accept) | `PUT …/evt-hytte-invite.ics cond="seed-evt-hytte-invite" → 204` | `PARTSTAT=ACCEPTED` | "Invite accepted. Calendar updated on Stiv CalDAV." — `ios-11-rsvp-accepted.png` |
| Kanskje (maybe) | `PUT … cond="stub-2-…" → 204` | `PARTSTAT=TENTATIVE` | "Tentative response sent. Calendar updated on Stiv CalDAV." — `ios-12-rsvp-tentative.png` |
| Avslå (decline) | `PUT … cond="stub-3-…" → 204` | `PARTSTAT=DECLINED` | "Invite declined. Calendar updated on Stiv CalDAV." — `ios-13-rsvp-declined.png` |

Each conditional write carried the ETag returned by the previous write, so
the cache tracked every response. Calendar → event detail shows the user as
"Avslått" ("Declined") with Sigrid as organizer
(`ios-14-rsvp-calendar-declined.png`). The final remote copy is
`remote-evt-hytte-invite-after-decline.ics`; `RSVP=TRUE` is dropped once the
user has answered.

### 2.7 — Attendee add / remove (✓, with caveat)

Calendar → "Harbour Data — daily standup" (seed has no attendees) →
Rediger → Deltakere ("Attendees").

| Step | Wire | Remote | Evidence |
|------|------|--------|----------|
| Add `qa-attendee@example.org` → Lagre ("Save") | `PUT /cal/u/main/evt-standup.ics cond="seed-evt-standup" → 204` | `ATTENDEE;PARTSTAT=NEEDS-ACTION:mailto:qa-attendee@example.org` | `ios-20-attendee-added-editor.png` (footer: "Leverandøren kan varsle deltakerne når du lagrer." — "The provider may notify attendees when you save."), `ios-21-attendee-added-detail.png` ("Ikke svart", i.e. "Not responded"), `remote-evt-standup-after-add.ics` |
| Remove (⊖) → Lagre | `PUT … cond="stub-5-…" → 204` | no ATTENDEE line | `ios-22-attendee-removed-editor.png`, `ios-23-attendee-removed-detail.png`, `remote-evt-standup-after-remove.ics` |

Caveat: the stub implements no CalDAV scheduling (RFC 6638), so "sends
invites" is proven only as far as the attendee change reaching the server.
The written payload is `METHOD:PUBLISH` with no `ORGANIZER` when the
source event had none. A scheduling server needs an organizer to fan out
iTIP requests, so live invite delivery stays open for the live `C`/`G`
fixtures (observation O9).

### 4.3 — Background pickup without relaunch (✓ iOS)

| Time (UTC) | Event |
|------------|-------|
| 19:52 | Settings → Kalender og Kontakter → "Bakgrunnssynkronisering" ("Background sync") ON (`ios-30-background-sync-enabled.png`); the toggle's immediate pass issued `REPORT /cal/u/main/ → 207` |
| 19:52:54 | `POST /__control/add` injected `inject-evt-idle-pickup.ics` ("Idle pickup — server-side add", 26 Sep) |
| ≈19:54:00 | Unprompted `REPORT /cal/u/main/ → 207` (L20) with no user interaction (app idle in foreground on the Settings screen) |
| 19:56 | Calendar agenda opened. **No new request** (log line count unchanged at 20), and the injected event renders on lørdag 26. sep. (`ios-31-idle-pickup-agenda.png`) |
| ≈19:59:20 | Next unprompted `REPORT → 207` (L22), confirming the ~5-minute cadence |

This verifies the O3 fix on iOS. `PIMSyncScheduler` was added in #135
(2026-09-28) after the 2026-09-26 macOS miss. It only ticks sources whose
`syncEnabled` opt-in ("Background sync") is ON (ADR-0006), and the toggle
defaults OFF on connect. macOS shares the scheduler code but stays ⚠ until
it is re-run with the toggle ON.

## Request log

`requests.log` is the stub wire log for the session (auth redacted as
`auth=Basic ***`). Operator `curl` reads are L1–2, the `GET` directly after
each `PUT`, and L21. L19 is the operator injection.

| Lines | Meaning |
|-------|---------|
| L3–4 | Reconnect + Sync Now (`PROPFIND /`, `REPORT` 207) |
| L5, L8, L11 | RSVP accept / maybe / decline conditional PUTs → 204 (L7, L10 = reconnect after relaunch) |
| L13, L16 | Attendee add / remove conditional PUTs → 204 |
| L18 | Immediate pass when background sync was switched ON |
| L20, L22 | Unprompted scheduled passes (≈19:54:00 and ≈19:59:20 UTC, ±5 s poll) |

## Observations (not fixed in this pass)

| # | Area | Observation | Evidence |
|---|------|-------------|----------|
| O7 | Settings | Source error row shows the raw enum `missingCredential` after a mock-mode relaunch (mock DAV credentials are in-memory by design) | — |
| O8 | Localization | RSVP badges ("Accepted"/"Tentative"/"Declined"/"Responded") and confirmation sentences render in English in a Norwegian UI | `ios-11…13-*.png` |
| O9 | Calendar write | Attendee edits PUT `METHOD:PUBLISH` without `ORGANIZER` when the event had none; a scheduling server cannot send invites without one | `remote-evt-standup-after-add.ics` |
| O10 | Calendar editor | Attendee field accepts a non-address (`qaattendee2exampleorg`) without validation | — |
| O11 | iOS dark theme | Agenda event titles are near-invisible (dark text on black); event detail/editor sheets render light with light-theme pills, timezone, calendar picker and attendee placeholder nearly invisible. **Fixed in this PR:** the Calendar/Contacts/Tasks full-screen covers (iOS) and windows (macOS) sat outside `.brevRootAppearance`, so they fell back to the default `brevMonoLight` theme under a dark system appearance. The stale banner's "Last updated" line also showed English because its catalog key held the raw `\(…)` source instead of `Last updated %@` | Before: `ios-obs-agenda-title-contrast.png`, `ios-20-attendee-added-editor.png`. After: `ios-40-fix-agenda-themed.png`, `ios-41-fix-editor-themed.png` |
| O12 | Settings | "N hendelser bufret" ("N events cached") count stayed at 3 after the background pass cached a 4th event (Settings did not refresh) | `ios-obs-settings-count-stale.png` |
