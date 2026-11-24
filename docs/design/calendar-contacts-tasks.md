# Calendar, Contacts & Tasks

> Consolidates former ADRs `0007`, `0072`, `0084`, and `0089`.

## Scope & Architecture

Brev integrates provider-neutral **Calendar**, **Contacts**, and **Tasks** inside `packages/BrevCalendar/` for connected **Google** (Calendar, People, Tasks) and **standards-based DAV** (CalDAV / CardDAV) sources. All sources are explicit opt-in, cached locally, and rendered via capability flags—never provider type-checks.

- **Mail invitations (iMIP, RFC 6047):** `BrevCalendar` parses `.ics` attachments (`METHOD:REQUEST`, RFC 5545 line-unfolding, UTC/floating/all-day, `ORGANIZER`/`ATTENDEE`) and renders an inline RSVP banner in the reader (Accept / Maybe / Decline gated on `serverSideCalendarReply` or configured CalDAV invite write) plus one-off "Create Meeting from Message" EventKit handoff.
- **Dedicated surfaces:** macOS auxiliary Calendar, Contacts, and Tasks windows; iOS full-screen covers. Read-only browsing works as soon as a source syncs; authoring controls appear only when the user enables **Editing** on a writable source.
- **System calendars:** Device-local Apple EventKit calendars are not browsed inside Brev; EventKit stays scoped to one-off message-to-event creation.

## Sync & Authoring Rules

- **Discovery:** CalDAV/CardDAV supports RFC 6764 `.well-known` discovery and manual URLs with `PROPFIND` principal/collection discovery; Google uses incremental OAuth scopes (`calendar.events`, `contacts`, `tasks`) requested only when enabled.
- **Precondition-safe writes:** Every create/edit/delete carries ETag preconditions (`If-Match` / `If-None-Match`), merges CardDAV vCard edits into stored raw payloads so unknown fields survive intact, and surfaces 412 conflicts clearly for user resolution.
- **Google Drive attachments:** Opt-in `drive.file` picker/save integration lets users attach Drive files or save mail/event attachments to Drive without sending file bytes to the calendar server.

## Bounded Calendar Recurrence Projection

- Recurring `VEVENT` rules (`RRULE`, `RDATE`, `EXDATE`, and `RECURRENCE-ID` exception instances) are expanded deterministically over a **bounded visible query window** rather than materializing unbounded infinite series into storage.
- The event editor currently supports **whole-series** and **this-and-future** edits; single-occurrence exception edits remain planned follow-up work.

## Planned: Offline PIM Write Queue

- Currently, calendar, contact, and task writes go directly to the provider and report an error when offline.
- **Planned design (from former ADR-0084):** Persist pending PIM creates/edits/deletes per source in a local write queue, apply optimistic local cache updates, replay in order on reconnect using existing ETag precondition re-resolution, and surface unrecoverable 412 conflicts cleanly without silently discarding user edits.
