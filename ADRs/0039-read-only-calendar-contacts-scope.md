# ADR-0039: Read-only calendar and contacts scope

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amends:** ADR-0007, ADR-0028

## Context

ADR-0007 kept Brev from becoming a full calendar client: it handled
mail-based invites, optional CalDAV writes for accepted invites, and
system handoff. ADR-0028 moved the launch backend to standards-first
IMAP/SMTP and kept calendar handling tied to client-side iMIP plus DAV
where configured.

The related feature request reopens the broader scope because Outlook and eM Client
include calendar and contacts, while Apple Mail benefits from the
bundled Calendar and Contacts apps. Brev already has several pieces:
invite rendering/reply, CalDAV write-target work, CardDAV-backed
compose autocomplete, local system Contacts avatar lookup, and DAV
viability checks. What it lacks is any browsable calendar or contacts
surface.

## Decision

Brev remains mail-first, but read-only calendar and contacts browsing is
in scope after live CalDAV/CardDAV integration is proven.

1. **Current v1 surfaces remain mail workflow surfaces.** Calendar
   invites, iMIP replies, accepted-invite CalDAV writes, and CardDAV
   compose autocomplete are part of mail.

2. **Read-only browsing is accepted as future scope.** After #121 proves
   live CalDAV/CardDAV sync and provider OAuth viability, Brev may add
   browsable calendar and contacts views: day/week/month inspection,
   read-only event detail, read-only people/group lists, and scoped
   calendar/contact search results.

3. **Full PIM authoring remains out of scope.** Arbitrary event
   creation/editing, free/busy scheduling, meeting invitation sending,
   contact creation/editing/merging, and contact administration stay with
   dedicated Calendar and Contacts apps unless a future ADR explicitly
   reopens that boundary.

4. **Settings must explain the boundary.** Brev exposes a Calendar &
   Contacts settings/status section that states what exists now, what is
   planned after #121, and what is deliberately out of scope.

5. **Provider semantics stay capability-driven.** Future browsing/search
   uses provider-neutral models and backend extension services. Views
   must not assume that CalDAV, CardDAV, Exchange, Gmail, and local
   Contacts expose the same fields or mutability.

## Rationale

Read-only browsing fills the strongest competitive gap without turning
Brev into a full personal-information-manager suite. It lets users
inspect calendar and contact context from a mail workflow, while
avoiding the much larger authoring/scheduling/admin scope that Outlook
and eM Client own.

Sequencing this after #121 prevents a decorative UI that cannot be
trusted with real provider data. It also keeps ADR-0006 intact: DAV
traffic remains tied to explicit account setup, contacts setup, or
user-visible sync choices.

## Consequences

- The related feature request is resolved as "read-only PIM browsing accepted, full PIM
  editing rejected."
- The existing CalDAV settings remain about accepted invite writes; they
  are not silently promoted into full calendar sync UI.
- Calendar/contact browsing and unified PIM search should be tracked as
  follow-up implementation under #121 or a later dedicated issue once DAV
  live integration is in review.
- Settings now has a shipped Calendar & Contacts section so users and
  maintainers can see the scope boundary without reading ADRs.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0007: Calendar invitation handling
- ADR-0028: Standards-first IMAP/SMTP roadmap
- The related feature request: CalDAV/CardDAV live integration and provider OAuth viability
- The related feature request: Browsable calendar and contacts management
