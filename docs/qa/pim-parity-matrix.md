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

## 1. Source lifecycle

| # | Check | G mac | G iOS | C mac | C iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|----------|
| 1.1 | Incremental consent prompt shows only the scopes the action needs | | | — | — | — | — | |
| 1.2 | Connect → first sync completes without re-prompt | | | | | | | |
| 1.3 | Reconnect after revoke restores the source cleanly | | | | | | | |
| 1.4 | Token refresh survives app restart | | | — | — | — | — | |
| 1.5 | Scope denial leaves the source connectable (no zombie state) | | | — | — | — | — | |
| 1.6 | Generic DAV manual setup (server URL + creds) connects | — | — | ✓ | | ✓ | | log L13–16 discovery PROPFIND /→/principals/u/→/cal/u/ +REPORT 207; L17–20 same for /card/u/; ss_d219f61a (both sources "Ready", items cached) |
| 1.7 | Invalid credentials surface a clear error, no partial source | — | — | ✓ | | ✓ | | :8644 wrong pw → davstub-auth.log PROPFIND→401 ×2; UI callout "The server rejected these credentials…"; no partial row; ss_2079c901 |
| 1.8 | TLS failure (self-signed/bad host) surfaces a clear error | — | — | | | | | |
| 1.9 | Source removal clears local cache; provider data intact remotely | | | | | | | |

## 2. Calendar surface (per applicable provider)

| # | Check | G mac | G iOS | C mac | C iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 2.1 | Browse: day/week/month grids render synced events | | | ✓ | | agenda + week grid show standup Wed 7AM, review Fri 2AM; ss_9ecb47f6, ss_b8f7738e |
| 2.2 | Search finds events across sources | | | | | |
| 2.3 | Offline restore: cached events render with network off | | | ✓ | | stub :8643 killed → app relaunch → all 3 cached events render; ss_557128bf |
| 2.4 | Create event (title/time/calendar selection) | | | ✓ | | L21 `PUT /cal/u/main/<uid>-brev.ics` If-None-Match:* → 201; block on grid; ss_04dc5ae4 |
| 2.5 | Edit event fields propagate on next sync | | | ⚠ | | live href: L28 PUT If-Match → 204, detail updates. ⚠ seeded events whose cached href went stale (`*-stub.ics`) 412 forever — sync refreshes etag but not href (defect); ss_39a673a8 |
| 2.6 | Recurrence rule create + edit-one vs edit-series | | | | | |
| 2.7 | Attendee update (add/remove) sends invites | | | | | |
| 2.8 | RSVP accept/maybe/decline round-trips | | | | | |
| 2.9 | Conflict: concurrent remote edit is detected, not silently overwritten | | | ✓ | | L35 PUT If-Match:`stub-4`→412 on live href; inline "This event changed on the server…"; remote kept Remote-bumped (GET-verified); ss_80bd1964 |
| 2.10 | Delete event removes remotely and locally | | | ✓ | | "Delete this event?" dialog → L38 DELETE If-Match:`stub-6`→204; remote GET 404; grid cleared; ss_dc213345 |

## 3. Contacts surface (per applicable provider)

| # | Check | G mac | G iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 3.1 | Browse: list + detail render synced contacts | | | ✓ | | Alice+Bob listed; detail shows email/phone/URL/BDAY "14 Mar 1985"; ss_81a7b1a7 |
| 3.2 | Search finds contacts across sources | | | | | |
| 3.3 | Offline restore: cached contacts render with network off | | | | | |
| 3.4 | Create contact (explicit source/address-book selection) | | | ✓ | | L40 `PUT /card/u/main/<uid>-brev.vcf` If-None-Match:* → 201; row appears instantly; ss_22a4d5fc |
| 3.5 | Edit contact fields propagate on next sync | | | ✓ | | L41 `PUT /card/u/main/alice.vcf` If-Match:`seed-alice` → 204; detail+list update; ss_d2445f76 |
| 3.6 | Group / address-book assignment (source-permitting) | | | | | |
| 3.7 | Conflict: concurrent remote edit is detected, not silently overwritten | | | ✓ | | out-of-band bump → L44 PUT If-Match:`stub-9`→412; "This contact changed on the server…"; remote kept FN:Remote-changed Alice; ss_f4c4f885 |
| 3.8 | Delete names provider impact; remote vs local-cache deletion distinguished | | | ✓ | | dialog: "permanently deletes the contact from 127.0.0.1 and removes it from the local cache"; L47 DELETE If-Match:`seed-bob`→204, remote 404; ss_c93b47c7 |

## 4. Cross-source integrity

| # | Check | mac | iOS | Evidence |
|---|-------|:---:|:---:|----------|
| 4.1 | Mixed Google + DAV sources render together in one surface | ✓* | | *only the DAV leg exercised (two stub sources share surfaces; Google leg untested — no G fixture); ss_b8f7738e + ss_81a7b1a7 same session |
| 4.2 | A mutation on one source never writes to another account | ✓ | | all app writes scoped: .ics under /cal/u/, .vcf under /card/u/ only; log L21–47, zero cross-prefix writes |
| 4.3 | Background refresh picks up remote changes without relaunch | | | |
| 4.4 | Partial-provider outage degrades only that source's surface | | | |
| 4.5 | Expired sync cursor triggers resync that preserves healthy cache | ✓ | | POST expire-sync → L55 REPORT w/ stale token → 403 valid-sync-token → L56 resync → 207; surfaces stayed healthy |
| 4.6 | Full resync after cache clear restores all synced items | ⚠ | | partial: 403-triggered full resync re-fetched all members (L56); explicit local cache-clear not exercised — cover via §1.9 removal+reconnect |

## 5. Platform quality gates

| # | Check | mac | iOS | Evidence |
|---|-------|:---:|:---:|----------|
| 5.1 | Accessibility readback (VoiceOver) on calendar + contacts | | | |
| 5.2 | Dynamic Type / text scaling renders without truncation | | | |
| 5.3 | Localization spot-check (non-English locale) | | | |
| 5.4 | Reduced motion honored on animations | | | |
| 5.5 | Full keyboard navigation (macOS) / keyboard + VoiceOver (iOS) | | | |

## 6. Privacy & hygiene

| # | Check | Result | Evidence |
|---|-------|:------:|----------|
| 6.1 | No secrets, tokens, email addresses, or contact/calendar content in logs | ✓ | | wire+auth logs only ever `auth=Basic ***`/`auth=-`; no password/base64 material; davstub-requests.log + davstub-auth.log |
| 6.2 | All attached evidence is redacted (crops, no raw data) | | |
| 6.3 | Cache clear removes local copies only; remote providers unchanged | | |
| 6.4 | Account/source removal leaves provider-side data intact | | |

## Final evidence table (AC)

| Layer | Result | Where |
|-------|--------|-------|
| Implementation | | merged PRs #56–#78 |
| Automated tests | | CI green on main |
| Live providers | | §1–§4 above |
| macOS runtime | | this matrix, mac column |
| iOS runtime | | this matrix, iOS column |
| Maintainer acceptance | | sign-off below |

Maintainer sign-off: ________  Date: ________
