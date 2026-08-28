# ADR-0046: Capability-driven AI routing and generic DAV discovery

- **Status:** Proposed
- **Date:** 2026-06-30
- **Deciders:** Henrik

## Context

IMAP/SMTP neutralization removed hardcoded the provider behavior from account
provisioning and restore flows, but two remaining derivations were still present:

- AI routing included an explicit backend-identifier gate for the built-in
  provider-hosted AI path.
- Calendar discovery/viability used a hardcoded the provider built-in branch.
- Privacy transparency surfaced a previous package-specific avatar endpoint string.

These behaviors are not suitable for the broader “provider-neutral” direction.

## Decision

- Make AI provider resolution capability-driven only:
  if the active backend reports AI support, `AIProviderResolver` uses provider-hosted AI as
  the built-in provider independent of account backend identifier.
- Make CalDAV/CardDAV discovery generic by default:
  no provider-specific constructors (`.builtInProvider`) and no built-in the provider
  domain branch; discovery uses well-known URL construction for all domains.
- Make privacy dashboard avatar network text configurable via a constructor argument
  in `PrivacyDashboardView`, with default label `"Gravatar"` instead of a
  hardcoded previous package host.

## Rationale

Capability-driven routing keeps AI behavior aligned with ADR-0001 (backend
capabilities, not backend-type checks). Removing hardcoded the provider discovery
paths prevents accidental product coupling and keeps calendar sync behavior uniform
across providers until provider-specific discovery plug-ins are introduced.

## Consequences

- Other, non-AI-capable accounts resolve to standard disabled/unsupported
  behavior instead of relying on backend string matching.
- the provider/other existing accounts that still advertise AI support continue to
  surface provider-hosted AI by capability.
- CalDAV/CardDAV behavior now requires standard `.well-known`/verification flows for
  all providers; the provider no longer receives privileged built-ins.
- A follow-up task remains to document and execute broader dependency hygiene in
  `Tuist/Package.swift` so only explicit dependencies required by retired
  `previous backend` remain as exceptions.

## References

- ADR-0001: Backend abstraction
- ADR-0007: Calendar invites and DAV concerns
- ADR-0008: AI Writer architecture
- ADR-0005: Protected paths and ADR-gate
- ADR-0066: Legacy backend metadata migration seam
