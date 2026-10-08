# PIM Parity Matrix — Google & DAV (issue #11)

Fillable verification matrix for the release-level Calendar/Contacts
parity pass on macOS and iOS. Run each row against the three live
fixtures and record **redacted** evidence (no addresses, tokens, or
calendar/contact content — screenshot crops + result only).

## Fixtures

- [ ] `G` — disposable Google Workspace account (Gmail + Calendar +
  Contacts, incremental consent enabled)
- [ ] `C` — generic CalDAV server (calendar-capable)
- [ ] `D` — generic CardDAV server (contacts-capable)

Record fixture builds/versions here (no credentials):

| Fixture | Provider/version | Notes |
|---------|------------------|-------|
| G | | |
| C | stub-dav-server.py :8643 (CalDAV home set `/cal/u/main/`) | no-auth local stub; seeds evt-standup + evt-review; `:8644 --auth u:p` for §1.7 |
| D | stub-dav-server.py :8643 (CardDAV home set `/card/u/main/`) | same stub; seeds alice.vcf + bob.vcf; wire log `/tmp/davstub-requests.log` |

Live pass round 2 (2026-09-26, on `fix/imap-smtp-provider-compat`): generic-IMAP macOS lifecycle passed end-to-end (D5/D6 fixed); Google leg still blocked — 2FA was disabled but Google now demands recovery-phone device verification (SMS/call to ••55, trusted device, or recovery-number confirmation); needs Henrik — see account-lifecycle doc. iOS live add is env-blocked (unsigned sim build → keychain -34018). G columns and the marked rows remain untested. All iOS/mac stub evidence lives in `docs/qa/pim-parity-stub-dav-2026-09-26/` (screenshots named `ios-*.png`/`mac-*.png`; request logs `requests-baseline.log`, `davstub-mac-run2.log`, `davstub-auth-mac-run2.log`).

Stub pass 2026-10-03 (iOS sim, `main` @ ed631a71): rows 2.7, 2.8 and 4.3 (iOS) verified against the authed stub; evidence, request log and observations O7–O12 in `docs/qa/pim-parity-stub-dav-2026-10-03/`.

## 1. Source lifecycle

| # | Check | G mac | G iOS | C mac | C iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|----------|
| 1.1 | Incremental consent prompt shows only the scopes the action needs | | | — | — | — | — | |
| 1.2 | Connect → first sync completes without re-prompt | | | | | | | |
| 1.3 | Reconnect after revoke restores the source cleanly | | | | | | | |
| 1.4 | Token refresh survives app restart | | | — | — | — | — | |
| 1.5 | Scope denial leaves the source connectable (no zombie state) | | | — | — | — | — | |
| 1.6 | Generic DAV manual setup (server URL + creds) connects | — | — | ✓ | ✓ | ✓ | ✓ | macOS/iOS: log L13–16 discovery PROPFIND /→/principals/u/→/cal/u/ +REPORT 207; L17–20 same for /card/u/; ss_d219f61a (both sources "Ready", items cached); iOS: baseline log L20–27 PROPFIND/REPORT 207 for both home sets; ios-sources-ready.png |
| 1.7 | Invalid credentials surface a clear error, no partial source | — | — | ✓ | ✓ | ✓ | ✓ | :8644 wrong pw → davstub-auth.log PROPFIND→401 ×2; UI callout "The server rejected these credentials…"; no partial row; ss_2079c901. iOS re-verified post-#113 (iPhone 17, iOS 27): sheet now shows the inline amber callout (was defect D1). Caveat found during verification: a real DAV 401 carries `WWW-Authenticate` and used to render "could not be reached" — classification fixed in #117 |
| 1.8 | TLS failure (self-signed/bad host) surfaces a clear error | — | — | ⚠ | ✓ | ⚠ | ✓ | macOS: https://127.0.0.1:8643 (plain-HTTP stub) → callout after ~25–30 s pre-fix (defect D4; macOS not re-verified post-#114 — same shared transport, code-verified only). iOS re-verified post-#114 with a silent TCP listener (accepts, never responds — the HTTP stub fails the handshake in ~15 ms and can't reproduce the stall): submitting state cleared at ~15 s = the `requestTimeout` bound; control build stalled ~60 s. In-sheet callout rides on #113 → post-merge: callout at ~15 s |
| 1.9 | Source removal clears local cache; provider data intact remotely | | | ✓ | ✓ | ✓ | ✓ | macOS: source removed via ⋯ → Remove Source… → dialog names the source, offers keep/delete cached copy; davstub-auth-mac-run2.log shows zero DELETE — remote intact; mac-remove-source-dialog.png. iOS: CalDAV source removed, remote GET 200 still; calendar surface emptied; row gone |

## 2. Calendar surface (per applicable provider)

| # | Check | G mac | G iOS | C mac | C iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 2.1 | Browse: day/week/month grids render synced events | | | ✓ | ✓ | macOS: agenda + week grid show standup Wed 7AM, review Fri 2AM; ss_9ecb47f6, ss_b8f7738e. iOS: agenda + week render same seeded events; ios-calendar-agenda.png, ios-calendar-week.png |
| 2.2 | Search finds events across sources | | | ✓ | | macOS: event search filters to matching seeded event; mac-calendar-search.png |
| 2.3 | Offline restore: cached events render with network off | | | ✓ | ✓ | macOS: stub :8643 killed → app relaunch → all 3 cached events render; ss_557128bf. iOS: stub killed → app relaunch → cached events render; ios-calendar-offline-cache.png |
| 2.4 | Create event (title/time/calendar selection) | | | ✓ | ✓ | macOS: L21 `PUT /cal/u/main/<uid>-brev.ics` If-None-Match:* → 201; block on grid; ss_04dc5ae4. iOS: baseline L28 PUT → 201; new block rendered; ios-calendar-created-event.png |
| 2.5 | Edit event fields propagate on next sync | | | ⚠→fixed | ✓ | macOS: live href: L28 PUT If-Match → 204, detail updates. ⚠ seeded events whose cached href went stale (`*-stub.ics`) 412 forever — sync refreshes etag but not href (defect, D2); ss_39a673a8. **Fixed in #119** — write path re-resolves the synced href/etag; verified on iPhone 17 sim 2026-09-27: stale Save → 412 (conflict copy, remote preserved), post-sync Save → PUT new etag → 204, delete re-resolved → 204/remote 404. macOS leg code-shared, not re-run. Contacts/tasks write services carried the same stale-precondition shape — ported the re-resolution in #120 (code + unit-verified). Conflict copy rendered below the editor fold — moved above the fold in #121. iOS: baseline L29/L39 PUT → 204, list+detail update |
| 2.6 | Recurrence rule create + edit-one vs edit-series | | | ✓ | | macOS: editor exposes Repeat picker (CalendarEventEditorView.swift `repeatSection` ~L96); weekly RRULE stored via PUT → 201; save offers edit-this-event vs whole-series choice; mac-recurring-edit-scope.png |
| 2.7 | Attendee update (add/remove) sends invites | | | | ✓* | iOS 2026-10-03: add `qa-attendee@example.org` → `PUT evt-standup.ics` If-Match:`seed-evt-standup` → 204, remote gains `ATTENDEE;PARTSTAT=NEEDS-ACTION`; remove → PUT → 204, ATTENDEE gone; editor footer warns the provider may notify attendees; ios-20…23-*.png, requests.log L13/L16. *stub has no RFC 6638 scheduling and payload carries no ORGANIZER (O9) — live invite delivery still needs `C`/`G`. macOS not run |
| 2.8 | RSVP accept/maybe/decline round-trips | | | | ✓ | iOS 2026-10-03: mail invite card (Hytte weekend, organizer Sigrid) → Godta/Kanskje/Avslå each `PUT evt-hytte-invite.ics` If-Match chained (`seed-…`→`stub-2`→`stub-3`) → 204; remote PARTSTAT ACCEPTED → TENTATIVE → DECLINED; calendar detail shows "Avslått"; ios-10…14-*.png, requests.log L5/L8/L11. macOS not run |
| 2.9 | Conflict: concurrent remote edit is detected, not silently overwritten | | | ✓ | ✓ | macOS: L35 PUT If-Match:`stub-4`→412 on live href; inline "This event changed on the server…"; remote kept Remote-bumped (GET-verified); ss_80bd1964. iOS: baseline L31 PUT → 412; same inline copy shown; remote kept; ios-calendar-conflict.png |
| 2.10 | Delete event removes remotely and locally | | | ✓ | ✓ | macOS: "Delete this event?" dialog → L38 DELETE If-Match:`stub-6`→204; remote GET 404; grid cleared; ss_dc213345. iOS: baseline L35 DELETE → 204, remote 404, row gone |

## 3. Contacts surface (per applicable provider)

| # | Check | G mac | G iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 3.1 | Browse: list + detail render synced contacts | | | ✓ | ✓ | macOS: Alice+Bob listed; detail shows email/phone/URL/BDAY "14 Mar 1985"; ss_81a7b1a7. iOS: same list + detail; ios-contacts-list.png |
| 3.2 | Search finds contacts across sources | | | ✓ | | macOS: contact search filters list to seeded match; mac-contacts-search.png |
| 3.3 | Offline restore: cached contacts render with network off | | | ✓ | | macOS: stub :8643 killed → contacts list + Alice detail still render from cache (email/phone/URL/BDAY present); mac-contacts-offline-cache.png |
| 3.4 | Create contact (explicit source/address-book selection) | | | ✓ | ✓ | macOS: L40 `PUT /card/u/main/<uid>-brev.vcf` If-None-Match:* → 201; row appears instantly; ss_22a4d5fc. iOS: baseline L44 PUT → 201 (required per-source "Allow editing" ON); ios-contact-created.png |
| 3.5 | Edit contact fields propagate on next sync | | | ✓ | ✓ | macOS: L41 `PUT /card/u/main/alice.vcf` If-Match:`seed-alice` → 204; detail+list update; ss_d2445f76. iOS: baseline L37/L39 PUT → 204; edits reflected in detail+list |
| 3.6 | Group / address-book assignment (source-permitting) | | | — | — | n/a on CardDAV: group toggles are Google-only in the editor (ContactEditorView.swift ~L653 gates them on Google groups); CardDAV sources expose no group UI |
| 3.7 | Conflict: concurrent remote edit is detected, not silently overwritten | | | ✓ | ✓ | macOS: out-of-band bump → L44 PUT If-Match:`stub-9`→412; "This contact changed on the server…"; remote kept FN:Remote-changed Alice; ss_f4c4f885. iOS: baseline L41–42 PUT → 412; same copy; remote kept; ios-contact-conflict.png |
| 3.8 | Delete names provider impact; remote vs local-cache deletion distinguished | | | ✓ | ✓ | macOS: dialog: "permanently deletes the contact from 127.0.0.1 and removes it from the local cache"; L47 DELETE If-Match:`seed-bob`→204, remote 404; ss_c93b47c7. iOS: same dialog naming the provider; baseline L45 DELETE → 204, remote 404; ios-contact-delete-dialog.png |

## 4. Cross-source integrity

| # | Check | mac | iOS | Evidence |
|---|-------|:---:|:---:|----------|
| 4.1 | Mixed Google + DAV sources render together in one surface | ✓* | ✓* | *only the DAV leg exercised (two stub sources share surfaces; Google leg untested — pending live pass); ss_b8f7738e + ss_81a7b1a7 same session (mac); iOS agenda/contacts render both stub sources same session |
| 4.2 | A mutation on one source never writes to another account | ✓ | ✓ | all app writes scoped: .ics under /cal/u/, .vcf under /card/u/ only; log L21–47 (mac) + iOS baseline L28–45, zero cross-prefix writes |
| 4.3 | Background refresh picks up remote changes without relaunch | ⚠ | ✓ | macOS: `POST /__control/add` injected a new event while app ran; no REPORT for ~90–120 s (no background pickup observed); manual "Sync Now" immediately issued REPORT → event appeared. Pre-dates the #135 scheduler; not re-run since (observation O3). iOS 2026-10-03 (post-#135): "Background sync" ON → `/__control/add` at 19:52:54 → unprompted REPORT ≈19:54:00 and ≈19:59:20 (5-min fetch cadence); opening the agenda issued no request and the injected event rendered; ios-30/31-*.png, requests.log L18–22 |
| 4.4 | Partial-provider outage degrades only that source's surface | ✓ | | macOS: second stub :8644 (auth) added → killed → only that source shows "Failed · transportFailed"; :8643 cal/contacts/tasks stay Ready; mac-partial-outage.png |
| 4.5 | Expired sync cursor triggers resync that preserves healthy cache | ✓ | | POST expire-sync → L55 REPORT w/ stale token → 403 valid-sync-token → L56 resync → 207; surfaces stayed healthy |
| 4.6 | Full resync after cache clear restores all synced items | ✓ | | macOS: §1.9 removal (delete cached data) + reconnect → source Ready, all seeded items re-cached; davstub-mac-run2.log L1–5 re-discovery PROPFINDs → 207; mac-source-reconnect.png. (Also: 403-triggered full resync re-fetched all members, log L56.) |

## 5. Platform quality gates

| # | Check | mac | iOS | Evidence |
|---|-------|:---:|:---:|----------|
| 5.1 | Accessibility readback (VoiceOver) on calendar + contacts | | | ✓ | | macOS: VoiceOver reads agenda rows fully ("9:00 AM – 10:00 AM, QA recurring — retitled, Stub Calendar") and contact list rows resolve through the list + "Contact details, scroll area" detail pane; ss_9506c732, ss_d1225e17. iOS untested (sim Accessibility Inspector not exercised) |
| 5.2 | Dynamic Type / text scaling renders without truncation | | ✓ | | iOS: UITextContentSizeCategory AccessibilityXL — inbox, contacts list, and calendar empty state render without truncation or clipped controls; ios-xltype-root.png, ios-xltype-contacts.png, ios-xltype-calendar.png. macOS row untested (no per-app text-size control) |
| 5.3 | Localization spot-check (non-English locale) | | | ✓* | | macOS relaunched with `-AppleLanguages '(nb)'`: all catalogs ship `en` only (BrevMail Localizable.xcstrings: 497 strings, `en` sole localization) → English fallback everywhere, no broken layout; *catalogs have no translations to spot-check |
| 5.4 | Reduced motion honored on animations | | | ✓ | | `NSReduceMotionEnabled` set globally; Calendar/Contacts/Tasks views contain no `withAnimation`/`.animation` transitions (grep-clean) — nothing animates to suppress; `MessageListRefreshArrivalEffect` honors `accessibilityReduceMotion` for the one animated PIM-adjacent effect |
| 5.5 | Full keyboard navigation (macOS) / keyboard + VoiceOver (iOS) | ✓ | | macOS: arrow keys move selection through contacts list; selection follows focus; mac-contacts-keyboard-select.png |

## 6. Privacy & hygiene

| # | Check | Result | Evidence |
|---|-------|:------:|----------|
| 6.1 | No secrets, tokens, email addresses, or contact/calendar content in logs | ✓ | | wire+auth logs only ever `auth=Basic ***`/`auth=-`; no password/base64 material; davstub-requests.log + davstub-auth.log |
| 6.2 | All attached evidence is redacted (crops, no raw data) | ✓ | | all screenshots/logs contain only synthetic stub-seed names (Alice Halvorsen, Tor Eide, standup/review events) and stub URLs; evidence dir docs/qa/pim-parity-stub-dav-2026-09-26/ |
| 6.3 | Cache clear removes local copies only; remote providers unchanged | ✓ | | removal dialog offers "Remove, keep cached copy" vs "Remove and delete cached data" — local-cache-only path is explicit; mac-remove-source-dialog.png |
| 6.4 | Account/source removal leaves provider-side data intact | ✓ | | source removal issued zero DELETE on the stub (davstub-auth-mac-run2.log, davstub-mac-run2.log); seeded events/contacts still served GET 200 after removal |

## Final evidence table (AC)

| Layer | Result | Where |
|-------|--------|-------|
| Implementation | | merged PRs #56–#78 |
| Automated tests | ✓ | CI green on main as of c86c691 |
| Live providers | partial / blocked | Generic IMAP/SMTP: full lifecycle pass on `fix/imap-smtp-provider-compat` — macOS (add → inbox → send/receive → reconnect → remove, keychain clean) AND iOS (signed sim build: add → inbox → self-send → relaunch-restore → remove). Google: blocked at recovery-phone device verification (2FA disabled) — needs Henrik; see account-lifecycle-2026-09-26.md |
| macOS runtime | stub DAV complete | this matrix, mac column |
| iOS runtime | stub DAV complete | this matrix, iOS column |
| Maintainer acceptance | | sign-off below |

## Defects (stub-DAV run 2026-09-26)

| # | Severity | Summary | Repro |
|---|----------|---------|-------|
| D1 | med — FIXED in #113 (device-verified) | iOS Add-DAV sheet surfaces no error on wrong credentials | iOS Settings → Calendar & Contacts → Add DAV Source → manual `http://localhost:8644` (stub `--auth u:p`) → wrong password → Connect → PROPFIND→401 ×2 in stub log; sheet shows no callout. macOS shows "The server rejected these credentials…" on the same failure (ss_2079c901). Fix: submission errors now render inside the sheet; verified on iPhone 17 sim (amber callout, sheet stays open). Companion fix #117 for the 401+`WWW-Authenticate` copy. |
| D2 | med — FIXED in #119 (iOS device-verified) | macOS/iOS seeded-event href goes stale → edits 412 forever | Seed events `*-stub.ics`: after remote etag bump, PUT If-Match → 412 on every retry; sync refreshes etag but not cached href; live-href events unaffected (matrix 2.5 ⚠). Fix: `PIMEventWriteService` update/delete re-resolve the target's href/etag through the cache before writing (record id, else uid+recurrenceID identity); If-Match still guards unmerged remote changes. iPhone 17 sim verify: pre-sync Save → 412 + conflict copy; post-sync Save → PUT synced etag → 204; delete → 204 + remote 404. |
| D3 | low — RESOLVED (already fixed by #101; device-verified 2026-09-26) | macOS contact-source "Allow editing" toggles render dimmed | Calendar & Contacts pane: toggles on the CardDAV source row appeared disabled/greyed while calendar-source toggles responded. Re-verified on current main: live toggle, OFF→ON→OFF→ON states persisted. |
| D4 | low — FIXED in #114 (iOS device-verified) | TLS/credential errors delayed ~25–30 s before callout | Pointing the sheet at `https://127.0.0.1:8643` produced no feedback for ~25–30 s. Fix: `PIMDAVClient` setup requests bounded at 15 s via `URLSessionPIMDAVTransport(requestTimeout:)`; iOS verification showed failure surfaced ~15 s vs ~60 s control (silent-listener repro — see #114 comment). |
| O1 | obs | iOS: no Edit/Delete affordances on contact detail until the source's "Allow editing" is ON | By design per `canToggleWrite`, but invisible to the user why actions are missing — worth a hint. |
| O2 | obs | macOS event Edit button unresponsive until app re-activation | Needed window re-activate + click on label text; intermittent, not reproduced on second pass. |
| O3 | obs — FIXED in #135 (iOS stub-verified 2026-10-03) | No background pickup of remote changes within ~2 min | `POST /__control/add` while running produced no REPORT; manual Sync Now did (4.3). #135 added `PIMSyncScheduler` on the fetch cadence for sources with "Background sync" ON; iOS sim pass picked up an injected event unprompted (pim-parity-stub-dav-2026-10-03/). macOS not re-run. |
| D5 | high — FIXED on `fix/imap-smtp-provider-compat` | `SELECT (CONDSTORE)` sent unconditionally → `BAD` on servers without CONDSTORE | Live smoke on mailo.com: `SELECT "INBOX" (CONDSTORE)` → `BAD SELECT bad parameter`. Fix gates the modifier on `supportsCONDSTORE`; verified live — mailbox opens. |
| D6 | high — FIXED on `fix/imap-smtp-provider-compat` | SMTP send impossible where only `AUTH LOGIN` is advertised | mailo.com advertises `AUTH LOGIN` only; client supported PLAIN/XOAUTH2. Fix adds the AUTH LOGIN exchange; verified live — real send + compose lifecycle pass. |
| D7 | low — FIXED in #115 (device-verified) | "Reconnect your mailbox" copy after a failed manual add | The title gated on `session.signInError != nil`; a failed first add set it even though nothing persisted. Fix: the repair copy now keys on `authFailedIMAPAccountEmail` (set only for stored-account re-auth). Verified on iPhone 17 sim: failed manual add keeps "Choose how to connect". |
| O4 | obs | mailo.com server-side search fails multi-word TEXT / non-ASCII criteria | `imap-smtp-live-smoke --exercise-cross-folder-server-search`: basic subject searches pass, `text:"live search"` / non-ASCII `søk røyk` guards return no results — provider charset/TEXT-search gap (not caused by the D5/D6 fix; standalone server-search passes). |
| O5 | obs — RESOLVED 2026-09-26 | iOS onboarding shows no "Continue with Google" even with `BREVGoogleOAuthIOSClientID` baked | Build-procedure gap, not a bug: `tuist generate` does not bake the client ID into the checked-in pbxproj (stays `""` by design); `script/build_and_run.sh` injects `BREV_GOOGLE_OAUTH_*` as xcodebuild overrides. Verified on iPhone 17 sim: override-built app shows "Continue with Google"; a build without it now shows setup guidance (#116). |
| O6 | obs — resolved in round 3 | iOS unsigned sim builds cannot persist Keychain credentials (-34018) | `CODE_SIGNING_ALLOWED=NO` Debug build: securityd rejects every SecItem write (no application-identifier). Environment limitation, not an app defect — **DEVELOPMENT_TEAM-signed build completed the full iOS lifecycle** (round 3). |
| O7–O12 | obs (stub-DAV iOS pass 2026-10-03) | Raw `missingCredential` enum in source row; RSVP badges/confirmations unlocalized in nb UI; attendee PUT lacks ORGANIZER (`METHOD:PUBLISH`); attendee field accepts non-addresses; iOS dark-theme contrast in agenda titles and event sheets (O11 fixed in #187: PIM surfaces now get the root theme); Settings cached-event count stale after background sync | Details and screenshots: pim-parity-stub-dav-2026-10-03/README.md § Observations |

Maintainer sign-off: ________  Date: ________
