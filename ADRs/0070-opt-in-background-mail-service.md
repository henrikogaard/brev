# ADR-0070: Opt-in background mail on macOS

- **Status:** Proposed
- **Date:** 2026-09-05
- **Deciders:** Henrik
- **Amends on acceptance:** ADR-0037
- **Tracking:** #28

## Context

Brev's local sync and scheduled-send processing currently depend on the app
process. Closing all windows, fully quitting, sleeping, and disabling background
execution have different effects, which must be visible. The requested mail
client parity work calls for dependable background behavior without silently
introducing a hosted credential relay.

## Decision

1. Add an explicitly enabled, bundled macOS background-mail service registered
   with Apple's `SMAppService`. It is disabled by default and its state is
   visible in Settings, including OS approval required, enabled, and unavailable.
2. Keep one owner of mailbox refresh and due-send delivery. The foreground app
   and service coordinate through an authenticated local connection and durable
   leases so the same message is never sent twice by concurrent processes.
3. Keep credentials in the existing Keychain boundary. The helper uses the same
   signed app-group/access-group identity; no copied password file, token in
   launch arguments, or public listener is permitted.
4. Reuse provider backends, local caches, notification consent, account scope,
   retry backoff, and ambiguous-delivery conflict handling. Do not duplicate
   protocol clients inside the helper.
5. Distinguish closing windows, quitting the UI while background mail remains
   enabled, stopping background mail, sleep, and full system shutdown. The quit
   flow states what will happen to pending scheduled messages.
6. Offer start/stop controls and a direct route to macOS background-item settings.
   Unregistering stops future background work and releases ownership safely.
7. iOS keeps system-granted background refresh and accurate limitations. Reliable
   remote push on iOS requires a separate service/credential/privacy decision;
   this ADR does not authorize a hosted relay or remote APNS gateway.

## Alternatives

- Keep the main UI app running invisibly: simpler packaging, but makes Quit and
  background ownership ambiguous and couples a failed UI to mail delivery.
- Hosted IMAP relay: can support remote push, but adds credential custody,
  infrastructure, recurring operation, and a materially different privacy promise.
- Continue best-effort only everywhere: preserves today's simplicity but does
  not address the requested macOS reliability gap.

## Consequences

The build graph gains a signed helper target and coordinated local execution.
The implementation needs concurrency, restart/crash, registration, upgrade,
revocation, sleep/wake, and ambiguous-send tests plus native OS verification.
Default-off behavior and explicit registration consent preserve the current
privacy posture. A sleeping/offline device still cannot guarantee send timing.
Approval of this ADR is not authorization to register a helper on a user's Mac,
change system permissions, ship a release, or operate a hosted service.

## References

- [ADR-0037](0037-generic-imap-closed-app-notifications.md)
- [ADR-0028](0028-mail-provider-architecture.md)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- `apps/macOS/Project.swift`, `MailFetchScheduler`, `ScheduledSendManaging`
