# ADR-0059: Malformed domain-derived DAV endpoint handling

- **Status:** Proposed
- **Date:** 2026-08-24
- **Deciders:** Henrik

## Context

CalDAV and CardDAV discovery derives HTTPS endpoints from the account email
address or a caller-provided domain. `URL` accepts some syntactically unusual
host strings, while other malformed values cannot form a URL at all. Treating
URL construction as infallible can therefore either crash account setup or
surface an endpoint that is not a valid DNS domain. Discovery is local and
must not make a network request merely because an account was entered.

The existing `CalDAVDiscovery.Result` already models unavailable endpoints as
optional configurations, and manual discovery is an established setup
fallback. `probeURLs(for:)` is a synchronous URL-construction helper whose
empty-array result can represent that no probes are available.

This decision covers the domain-validation seam in `BrevCalendar`; it does not
expand CalDAV/CardDAV into a calendar client or change provider authentication.
It complements ADR-0007's narrow CalDAV write scope, ADR-0028's
standards-first direction, and ADR-0046's generic DAV discovery.

## Decision

1. Validate the extracted or supplied domain before constructing any DAV URL.
   A valid domain has non-empty DNS labels, labels no longer than 63 bytes,
   total length no longer than 253 bytes, alphanumeric label boundaries, and
   only alphanumeric characters or hyphens inside labels. A single trailing
   dot is accepted for a fully qualified domain name.
2. If an account-derived domain is empty or semantically invalid, return a
   `CalDAVDiscovery.Result` with `discoveryMethod == .manual` and both DAV
   configurations set to `nil`.
3. If a supplied probe domain is empty or semantically invalid, return an empty
   probe list. Neither discovery path performs a network call for invalid
   input.
4. Preserve the existing built-in provider and well-known endpoint behavior
   for valid domains, including their public return types and URL shapes.
5. Keep validation private to `CalDAVDiscovery`; do not change a public
   `BrevCalendar` signature to make endpoint construction throwing or optional.

## Rationale

Returning an unavailable endpoint through existing optional and empty-result
seams keeps setup usable: the user can correct the account or enter a manual
configuration rather than seeing a crash or waiting on a doomed request.
Validation is performed before the the provider built-in branch so malformed
domains cannot bypass the same safety rule.

The alternatives were rejected as follows:

- Force-unwrapping `URL` values is unsafe because Foundation can reject
  malformed hosts, and it turns ordinary setup input into a process crash.
- Returning a placeholder URL would make an invalid endpoint appear usable and
  could send credentials or calendar data to the wrong host.
- Throwing or changing `CalDAVConfiguration.builtInProvider`, `discover`, or
  `probeURLs` would widen a public API solely to report a setup-validation
  outcome that the current optional/manual seams already express.
- Attempting discovery over the network before validation would violate the
  local, user-initiated discovery boundary and add no value for invalid input.

## Consequences

### Accepted

- Invalid domains such as an empty value, `example..com`, `-bad.com`, or a
  domain containing whitespace produce no usable DAV endpoint and no crash.
- Callers must treat `.manual`, `nil` configurations, and an empty probe list
  as unavailable-endpoint states and provide the existing manual setup path.
- Valid domains retain the same provider selection and URL paths as before.

### Risks

- Domain syntax validation is intentionally conservative. A provider using a
  non-standard host spelling may require manual configuration even if a server
  would accept it; the user can still supply a manually verified target.
- This is syntax validation, not live reachability or CalDAV capability
  verification. Those remain separate, explicit checks after setup.

## References

- ADR-0007: Calendar invitation handling
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0046: Capability-driven AI routing and generic DAV discovery
- RFC 1034: Domain names — concepts and facilities
- RFC 1123: Requirements for Internet hosts
- `packages/BrevCalendar/Sources/BrevCalendar/CalDAVConfiguration.swift`
- `packages/BrevCalendar/Tests/BrevCalendarTests/CalDAVConfigurationTests.swift`
