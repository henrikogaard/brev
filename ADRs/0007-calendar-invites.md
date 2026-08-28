# ADR-0007: Calendar invitation handling

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik
- **Amended by:** ADR-0039

## Context

Mail with `.ics` attachments using `METHOD:REQUEST` are calendar
invitations (iMIP, RFC 6047). Handling them well is a real UX
differentiator from Apple Mail.

The current implementation already does this *better* than the options I
initially outlined: it uses the provider's server-side API to render ICS
attachments (`calendarEvent(from:)`), send iMIP replies
(`replyToCalendarEvent(attachment:reply:)`), and atomically reply *and*
write to the user's the provider calendar
(`replyToCalendarEventAndUpdateCalendar(event:reply:)`).

The naive options ("parse ICS client-side and send iMIP reply",
"hand off to Calendar.app") are both worse than the inherited flow.

For v2, IMAP backends won't have this server-side support; client-
side iMIP handling becomes necessary.

## Decision

### v1: inherited server-side flow

For the provider accounts, use the existing API endpoints unchanged:

- **Detect:** Message contains an `ics` attachment with iMIP-relevant
  fields. `previous backend`'s existing detection logic is preserved.
- **Render:** Call `MailApiFetcher.calendarEvent(from: attachment)`.
  Server returns parsed event details. No client-side ICS parsing in
  v1.
- **Display:** Inline card at the top of the message body showing
  event title, date, time, location, organizer, attendee list with
  status badges. Designed in `BrevDesign` as
  `CalendarInviteCard`. Accept/Decline/Maybe buttons render below.
- **Respond:** On button tap, call
  `replyToCalendarEventAndUpdateCalendar(event:reply:)`. This sends
  the iMIP REPLY email *and* updates the user's the provider calendar
  server-side. One API call, one user action.
- **Confirm:** Show snackbar/toast confirmation. Update the card's
  status badge to reflect the response.

UI handles the three states (accept/maybe/decline) per the existing
provider `AttendeeState` enum.

The behavior is identical to provider functionally; only the
presentation is rewritten in `BrevDesign` style for both platforms.

### v2: client-side fallback for IMAP backends

When ADR-0001's `BackendCapabilities` lacks `.serverSideCalendarReply`
(IMAPBackend in v2):

- **Parse:** Use a client-side ICS parser (likely
  [iCalSwift](https://github.com/Iru21/iCalSwift) or similar; pick
  during v2 work). Lives in `packages/BrevCalendar/`.
- **Render:** Same `CalendarInviteCard` UI; populate from the locally
  parsed event.
- **Respond:** Construct an iMIP REPLY ICS body and send via SMTP
  (which the IMAPBackend already needs for outgoing mail). The
  organizer's calendar server processes the reply on receipt.
- **Calendar write (optional):** If the user has configured a CalDAV
  account in Brev (separate Settings → Accounts → CalDAV), Brev
  writes the event there using the configured credentials. If not, no
  local calendar write — the iMIP reply alone updates the organizer's
  view of attendance.

### Calendar write target

Brev does not become a full calendar client. The v2 CalDAV
configuration is purely for "where do my accepted invites land?",
not for browsing/managing the calendar inside Brev.

If the user has no CalDAV configured in v2, they can still:

- Accept via iMIP (organizer's calendar updates).
- See the event card in Brev (read-only).
- Use the "Open in Calendar" fallback button (system handoff) to add
  to their macOS/iOS calendar manually.

### `BrevCalendar` package shape

v1 contents:
- `CalendarInviteCard.swift` — the inline card view (shared across
  platforms).
- `CalendarInviteActions.swift` — wraps `MailBackend.replyToCalendar
  Invite(...)` for view layer use.
- No parser, no SMTP composer, no CalDAV client.

v2 additions (when `IMAPBackend` arrives):
- `ICSParser.swift` — client-side iCalendar parser.
- `IMIPReplyComposer.swift` — constructs valid iMIP REPLY messages.
- `CalDAVClient.swift` — minimal CalDAV write client (PUT new event;
  no full sync, no event browsing).

## Rationale

**Why keep the current flow instead of rebuilding.** It works better
than the alternatives. Server-side rendering means no client-side ICS
parser to maintain in v1. Atomic reply + calendar update is impossible
to replicate client-side without a CalDAV client. Strictly better UX
for users on that provider-backed flow.

**Why no full calendar client in Brev.** Scope. Brev is a mail
client. macOS Calendar.app and iOS Calendar are already excellent and
already integrate with the provider's CalDAV server (when users
configure it). Reimplementing calendar inside Brev would double the
project scope for marginal value.

**Why v2 CalDAV is "write-only".** A full bidirectional CalDAV
sync is hard. Accepting an invite to a known calendar requires only
PUT-with-iCal-content; not full sync. This narrow capability gives us
"invites land in your calendar" without a months-long CalDAV
implementation.

**Why split between v1 and v2 cleanly.** The capability gate
(`.serverSideCalendarReply`) makes the v1 code path independent of
v2 work. v2 adds new code; doesn't refactor v1 code.

## Consequences

### Accepted

- v1 calendar feature works only for the provider. The
  `CalendarInviteCard` UI is theoretically shown for other
  invites too, but the action buttons are disabled with a tooltip
  ("Calendar replies require the provider for now — coming with IMAP
  support in v2"). Honest about the limitation.
- The `replyToCalendarEvent(attachment:)` endpoint exists but
  `replyToCalendarEventAndUpdateCalendar(event:)` is the one we use.
  We prefer the atomic variant.
- v2 ICS parsing is a real piece of work (~1-2 weeks). Budgeted into
  IMAP v2 scope.

### Risks

- **Multi-account users with mixed providers.** A user with both an
  the provider account and (in v2) a Gmail-IMAP account sees different
  behavior per account. The UI must clearly indicate which account
  the invite arrived in and which response path will be used.
- **Server-side rendering could change.** If the provider changes the
  `calendarEvent` endpoint's response shape, our card breaks. Risk
  is no different than the broader provider API dependency
  (ADR-0028).

## Amendment (2026-06-28): Create Meeting from Message (#268)

The message context menu's "Create Meeting from Message…" action (previously
hidden as a no-op per the #262 honesty pass) now creates a **one-off local
calendar event** via EventKit, the direct analogue of "Create Task" → Reminders.

This stays inside this ADR's stance that **Brev does not become a calendar
client** — it is write-only, on an explicit user action, with no calendar sync
or browsing:

- `MessageEventDraftBuilder.draft(for:accountID:referenceDate:)` seeds an
  editable `MessageEventDraft` (title = subject, attendees = deduped sender +
  recipients, default 1-hour slot the user adjusts, Brev deep link in the notes).
- `MessageEventSheet` lets the user confirm/edit before anything is written.
  `AppleCalendarEventCreator` requests EventKit calendar access on first use and
  saves an `EKEvent` to the default calendar. EventKit's attendee list is
  read-only via the public API, so attendees are surfaced in the event notes.
- No CalDAV write and no iMIP is involved (those remain the invite-reply path
  above). `NSCalendarsUsageDescription` is added to both apps; `PRIVACY.md`
  discloses the local Calendar write, mirroring the Reminders disclosure.

Verified by `MessageEventDraftBuilder` tests + the updated `MessageCommandPresentation`
matrix (BrevMail).

## References

- ADR-0001: Backend abstraction (capability flags)
- ADR-0028: Roadmap to v2 (IMAP + CalDAV)
- RFC 5546: iTIP — https://datatracker.ietf.org/doc/html/rfc5546
- RFC 6047: iMIP — https://datatracker.ietf.org/doc/html/rfc6047
- RFC 6638: CalDAV Scheduling — https://datatracker.ietf.org/doc/html/rfc6638
