# Calendar parity evidence v8 — 2026-10-17

**Bottom line:** the ADR-0089 projection fix (PR #249) works against a real
CalDAV server on iOS: a daily COUNT=5 series and a weekly BYDAY series render
every date in agenda and month, the third occurrence shows its own date with
Edit/Delete hidden, the first occurrence stays editable, and an EXDATE added
server-side collapses the series to its raw master with the coverage note. The
real-DAV outage/recovery row also passed. macOS rows, Google rows and the
remaining lifecycle rows were not run in this pass (reasons below). This is
not #11/#3 acceptance.

| Provenance | Value |
| --- | --- |
| Scope | [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3); fix under test: [PR #249](https://github.com/henrikogaard/brev/pull/249) (merged as `c2f1ccef`), plus unmerged [#251](https://github.com/henrikogaard/brev/pull/251) and merged [#252](https://github.com/henrikogaard/brev/pull/252) |
| Build | iOS simulator build from `fix/calendar-occurrence-projection` at `19ab942c` (pre-rebase content of #249), live mode, adhoc-signed; macOS `Brev Test (2026-10-16).app` from a local merge `814be63c` of #249 + #251 + #252 |
| Device | "Brev QA iPhone 17 Pro" simulator, iOS 27.0, UDID `DF87BEA6-DEC5-49C9-A776-14E5996E8CAA`, nb locale, dark |
| Real DAV server | Radicale 3.8.1 at `http://127.0.0.1:5232`, htpasswd/bcrypt, user `brevqa`, collections `/brevqa/main/` (CalDAV) and `/brevqa/contacts/` (CardDAV) |
| Google | Disposable consumer Gmail signed in on both platforms (Calendar, Contacts, Tasks ready); no Google rows exercised in this pass |
| Fixtures | New, prefix `QA-1016-`: `QA-1016-daily` (DAILY COUNT=5 from 2026-10-18 09:00 Europe/Oslo), `QA-1016-weekly` (WEEKLY BYDAY=MO,WE COUNT=6 from 2026-10-19 10:00), `QA-1016-single` (2026-10-20 14:00). Created by `curl PUT` (201 each) |
| Evidence | `docs/qa/pim-parity-v8-2026-10-17/*.png`, half-resolution simulator screenshots; `scripts/check-live-evidence-redaction.sh` OK. No addresses, tokens or private data appear |
| Previous evidence | [v7](pim-parity-v7-2026-10-15.md) and earlier, preserved |

## Results

| Row | Platform | Provider | Result | Evidence |
| --- | --- | --- | --- | --- |
| Recurrence: every date of a daily COUNT=5 series renders (agenda) | iOS | Radicale | Pass | `ios-radicale-agenda-projected.png`: 18, 19, 20, 21 Oct rows plus weekly 19 and 21 Oct |
| Recurrence: weekly BYDAY=MO,WE renders on both weekdays | iOS | Radicale | Pass | same; month view dots on 19, 21, 26, 28 Oct in `ios-radicale-month-dots.png` |
| Recurrence: month grid consistent with agenda | iOS | Radicale | Pass | `ios-radicale-month-dots.png` |
| Recurrence: third occurrence shows its own date, Edit/Delete hidden, note shown | iOS | Radicale | Pass | `ios-radicale-third-occurrence-detail.png`: "tirsdag 20. okt., 09:00 – 09:30", only Kopier lenke, note "Endring av en enkelt senere dato … er ikke tilgjengelig ennå" |
| Recurrence: first occurrence keeps Edit/Delete | iOS | Radicale | Pass | `ios-radicale-first-occurrence-editable.png` |
| Recurrence: server-side EXDATE → incomplete coverage, no generated rows | iOS | Radicale | Pass (as designed) | `ios-radicale-exdate-series-collapsed.png` (only 18 Oct remains), `ios-radicale-exdate-incomplete-note.png` ("Brev kan ikke vise alle datoene …"). PUT returned 204; Brev REPORT followed within 8 s of Sync now |
| 4.x Partial-provider outage and recovery | iOS | Radicale | Pass | Radicale was down when the pass started: both DAV sources showed "Serveren kunne ikke nås"; after restart and Sync now the calendar source went Ready with "3 hendelser bufret" |
| Later-occurrence edit/delete (future scope) | iOS | Radicale | Not run | Disabled by design until ADR-0089 §4 writes land |
| Recurrence rows | macOS | Radicale | Not run | See blockers: accessibility automation unavailable; Fetch schedule is Manual |
| 4.3 macOS timed background pickup | macOS | Radicale | Blocked | Settings → Accounts → Henteplan is "Manuelt", so `PIMSyncScheduler` never ticks; 25 minutes after the fixtures were created the macOS Calendar still showed "Ingen hendelser". Needs the interval set, which this pass could not do without accessibility |
| Google event/contact CRUD, attendees, RSVP, recurrence | both | Google | Not run | Account is signed in and sources are Ready, but the UI-driven legs were not reached |
| Radicale lifecycle: invalid credentials, TLS failure, removal keep/delete | both | Radicale | Not run | Text-entry legs not reached in this pass |
| Contacts rows | both | both | Not run | — |
| Mixed sources, offline restore, cache clear | both | both | Not run | — |
| Physical iPhone, Dynamic Type, VoiceOver readback | iOS | — | Blocked | Needs a team-signed device build (simulator is adhoc-signed, Keychain −34018 risk) |

## Observations

- O13: with any exception (EXDATE here), the whole series is shown only as
  its master date. There is no indicator in the agenda or grid that dates
  are missing; the note appears only in the detail pane. ADR-0089 §2 calls
  exception handling required follow-up work. Recommend implementing read-side
  exception handling before #11 closes, since real calendars routinely carry
  moved or cancelled instances.
- O14: the Calendar stale banner "Viser bufrede data · Sist oppdatert for N
  sekunder siden" stayed visible on iOS even right after a successful sync
  while all calendar sources were Ready. The condition is
  `!staleSources.isEmpty || hasRetainedCache`; a retained cache from an
  earlier removed source keeps the banner on permanently and its wording
  reads like an error. Worth a wording or condition review.
- O15: the pre-#251 iOS Settings → Calendar & Contacts pane showed source
  switches overlapping each other; #251 fixes the layout.
- O16: the macOS Calendar window opened by a stale `brev://event` link kept
  "That event is no longer synced" until #252 added dismissal and
  auto-clear. The macOS build in this pass includes #252 and shows the close
  button.

## Blockers

- The Cua Driver accessibility route returned zero AX windows for every
  macOS app midway through the pass (also for unrelated apps), so no macOS
  clicks or text entry were possible; `cua-driver permissions status` still
  reports Accessibility granted. Screenshots remained possible.
- The macOS test container is TCC-protected, so the Fetch schedule could not
  be changed from the shell to observe timed pickup.

## Not done

No product code changed. No Google data was created or modified. The Radicale
QA fixtures remain on the server for the next pass. Radicale (PID 81721) and
the simulator are left running.
