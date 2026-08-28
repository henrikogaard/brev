# ADR-0025: Dense mail chrome Dynamic Type bounds

- **Status:** Proposed
- **Date:** 2026-06-05
- **Deciders:** Henrik

## Context

The iOS/iPadOS accessibility audit in #164 found that compact mail
surfaces became hard to operate at the largest Dynamic Type sizes:

- compact compose kept content reachable, but primary and secondary
  actions could balloon out of the first semantic viewport;
- thread readers could lose subject/participant context before the
  body at accessibility sizes;
- a follow-up simulator pass showed that dense controls such as menu
  rows, search fields, filter/date chrome, message rows, and thread
  headers still became too large even after the first accessibility
  fixes.

Brev has two different kinds of text in mail views:

1. **Reading/editing content**: message bodies, compose body text, and
   user-configurable mailbox text. This text is the user's actual mail
   content and should remain scalable.
2. **Dense chrome**: navigation, metadata, filters, rows, menu actions,
   section headers, and compact thread/detail headers. This text sits in
   constrained controls where unlimited scaling can make the interface
   less usable instead of more accessible.

ADR-0028 still applies: this is view-layer behavior only. It must not
introduce backend type checks, provider assumptions, Realm exposure, new
network calls, or privacy changes.

## Decision

Brev may cap Dynamic Type for dense mail chrome independently from
reading/editing content.

The cap must be expressed through a shared policy in BrevMail, currently
`MailDenseChromeDynamicType`, instead of ad hoc per-view constants:

- `range` is the softer dense-chrome cap for surfaces that can tolerate
  larger control text.
- `compactRange` is the stricter cap for the densest navigational and
  control chrome.

Message body rendering, compose body editing, and user-configurable
mailbox reading text are not governed by this cap. They continue to use
their own content-oriented scaling behavior.

## Rationale

**Alternative: let every mail UI string scale to the largest system
Dynamic Type size.** Rejected for dense chrome. In the audited compact
and split-view layouts, unlimited control scaling pushed core actions
and context out of reach, making the interface less usable at the very
accessibility sizes it was trying to support.

**Alternative: cap the whole mail surface.** Rejected. It would make
actual reading and composing less accessible. The body/content surfaces
are where users need large text most.

**Alternative: build custom large-type layouts for each dense surface
immediately.** Deferred. Some custom layouts may still be worthwhile,
but a shared cap is the smallest consistent v1 stabilization step and
keeps the policy visible for later refinement.

**Alternative: expose a user setting for chrome scaling.** Rejected for
v1. It adds settings complexity before we have evidence that users need
control beyond the existing mailbox text-size preference.

## Consequences

### Accepted

- Dense controls remain closer to normal mail-client density at extreme
  system text sizes.
- Reading and composing content can still scale independently.
- New dense mail chrome should use `MailDenseChromeDynamicType` rather
  than inventing local caps.
- Accessibility verification should check both semantic reachability
  and visual fit for compact iPhone and split-view iPad surfaces.

### Risks

- Users who expect every piece of chrome to scale to the largest system
  size may find some controls smaller than other apps. Mitigation:
  preserve clear labels, traits, hit targets, and scalable body content.
- A shared cap may be too blunt for a future surface. Mitigation:
  add a new named policy value only when a concrete surface proves it
  needs different behavior.
- Visual QA is still required. The cap prevents obvious overflow, but
  it does not replace simulator/device checks at large Dynamic Type.

## References

- ADR-0028 — Roadmap to v2 and architectural invariants
- ADR-0011 — BrevMail package
- The related feature request — iOS/iPadOS accessibility audit
- The related feature request — Compact compose actions at large Dynamic Type
- The related feature request — Reader heading context at largest Dynamic Type
- `packages/BrevMail/Sources/BrevMail/MailDenseChromeDynamicType.swift`
