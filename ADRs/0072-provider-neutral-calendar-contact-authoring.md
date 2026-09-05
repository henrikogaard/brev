# ADR-0072: Provider-neutral calendar and contact authoring

- **Status:** Proposed
- **Date:** 2026-09-05
- **Deciders:** Henrik
- **Supersedes on acceptance:** ADR-0039's read-only authoring boundary
- **Tracking:** #28, #3, #4 through #11

## Context

The requested alternative to mature mail clients includes useful calendar and
contact workflows. Brev currently handles mail invites, selected CalDAV writes,
and contact autocomplete. Existing issues already describe the larger Google
and DAV implementation and should be reused rather than duplicated.

## Decision

1. Extend BrevCalendar's plain domain model into capability-driven calendar and
   contact services. Sources retain account/provider identity; views do not
   depend on Google, Graph, CalDAV, or CardDAV response types.
2. Implement cached agenda/day/week/month browsing, event detail, create/edit/
   delete, invitations/RSVP, recurrence, and conflict-aware updates. Show whether
   a source is writable and whether a change is pending or synchronized.
3. Implement cached contact browsing/search, create/edit/delete, groups where
   supported, and explicit duplicate/merge choices. Do not silently merge two
   providers' records merely because an email address matches.
4. Use Google Calendar and People APIs for Google sources and CalDAV/CardDAV
   for standards sources. Reuse shared editors and local persistence/replay
   behavior; provider adapters translate recurrence and version/ETag semantics.
5. Account setup asks separately for calendar and contacts access. Reading and
   authoring scopes are chosen for the selected features and documented before
   network calls are introduced. Existing mail sign-in is not implicit consent
   for contacts/calendar access.
6. Add mail actions for creating an event from a message, opening the related
   event, and creating/updating a contact. Keep original mail context intact.
7. Integrate existing task/meeting issues #12 and #13 after the foundational
   services. A standalone notes/chat suite is not required by this ADR.
8. Deliver meaningful slices: source setup and sync, browsing, then authoring
   and mail integration. Empty providers or unwired demonstration screens do
   not count as implemented functionality.

## Alternatives

System-app handoff remains useful but cannot provide one cross-provider workflow.
Read-only browsing is smaller but leaves the requested editing gap. Provider-
specific screens would duplicate UX and create inconsistent semantics.

## Consequences

This reopens the previous read-only scope only after acceptance. Public domain
APIs, local sync/conflict handling, new OAuth scopes and network documentation
are required. Recurrence exceptions, time zones, all-day events, invite ownership,
contact field preservation, offline edits and permissions need contract tests.
Google/DAV live parity and device QA remain acceptance work, not inferred from
unit tests. Actual account grants and message/invitation transmission still
require the normal user-authorized product flow.

## References

- [ADR-0039](0039-read-only-calendar-contacts-scope.md)
- [ADR-0028](0028-mail-provider-architecture.md)
- [Google Calendar scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Google API scopes](https://developers.google.com/identity/protocols/oauth2/scopes)
- Existing issues #3 through #13
