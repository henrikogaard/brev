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
| C | | |
| D | | |

## 1. Source lifecycle

| # | Check | G mac | G iOS | C mac | C iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|----------|
| 1.1 | Incremental consent prompt shows only the scopes the action needs | | | — | — | — | — | |
| 1.2 | Connect → first sync completes without re-prompt | | | | | | | |
| 1.3 | Reconnect after revoke restores the source cleanly | | | | | | | |
| 1.4 | Token refresh survives app restart | | | — | — | — | — | |
| 1.5 | Scope denial leaves the source connectable (no zombie state) | | | — | — | — | — | |
| 1.6 | Generic DAV manual setup (server URL + creds) connects | — | — | | | | | |
| 1.7 | Invalid credentials surface a clear error, no partial source | — | — | | | | | |
| 1.8 | TLS failure (self-signed/bad host) surfaces a clear error | — | — | | | | | |
| 1.9 | Source removal clears local cache; provider data intact remotely | | | | | | | |

## 2. Calendar surface (per applicable provider)

| # | Check | G mac | G iOS | C mac | C iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 2.1 | Browse: day/week/month grids render synced events | | | | | |
| 2.2 | Search finds events across sources | | | | | |
| 2.3 | Offline restore: cached events render with network off | | | | | |
| 2.4 | Create event (title/time/calendar selection) | | | | | |
| 2.5 | Edit event fields propagate on next sync | | | | | |
| 2.6 | Recurrence rule create + edit-one vs edit-series | | | | | |
| 2.7 | Attendee update (add/remove) sends invites | | | | | |
| 2.8 | RSVP accept/maybe/decline round-trips | | | | | |
| 2.9 | Conflict: concurrent remote edit is detected, not silently overwritten | | | | | |
| 2.10 | Delete event removes remotely and locally | | | | | |

## 3. Contacts surface (per applicable provider)

| # | Check | G mac | G iOS | D mac | D iOS | Evidence |
|---|-------|:-----:|:-----:|:-----:|:-----:|----------|
| 3.1 | Browse: list + detail render synced contacts | | | | | |
| 3.2 | Search finds contacts across sources | | | | | |
| 3.3 | Offline restore: cached contacts render with network off | | | | | |
| 3.4 | Create contact (explicit source/address-book selection) | | | | | |
| 3.5 | Edit contact fields propagate on next sync | | | | | |
| 3.6 | Group / address-book assignment (source-permitting) | | | | | |
| 3.7 | Conflict: concurrent remote edit is detected, not silently overwritten | | | | | |
| 3.8 | Delete names provider impact; remote vs local-cache deletion distinguished | | | | | |

## 4. Cross-source integrity

| # | Check | mac | iOS | Evidence |
|---|-------|:---:|:---:|----------|
| 4.1 | Mixed Google + DAV sources render together in one surface | | | |
| 4.2 | A mutation on one source never writes to another account | | | |
| 4.3 | Background refresh picks up remote changes without relaunch | | | |
| 4.4 | Partial-provider outage degrades only that source's surface | | | |
| 4.5 | Expired sync cursor triggers resync that preserves healthy cache | | | |
| 4.6 | Full resync after cache clear restores all synced items | | | |

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
| 6.1 | No secrets, tokens, email addresses, or contact/calendar content in logs | | |
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
