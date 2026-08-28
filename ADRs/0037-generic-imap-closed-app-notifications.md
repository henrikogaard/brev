# ADR-0037: Generic IMAP closed-app notification posture

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amended by:** ADR-0037

> ADR-0037 removes the provider-push exception in item 3. The local-only,
> best-effort closed-app posture remains current.

## Context

The related feature request asks whether Brev should provide new-mail notifications for
generic IMAP/SMTP accounts when the app is fully quit. Provider-native push
and macOS APNS registration previously existed under ADR-0037, but ADR-0037
retired those paths. Generic IMAP/SMTP accounts do not have a provider push
gateway under Brev's control.

The options are:

- Run a Brev-hosted IMAP IDLE relay that stores or proxies credentials,
  keeps mailbox connections open, and sends APNS.
- Rely on OS-granted background refresh windows, local polling, and IMAP
  IDLE while the app is running.
- Add a macOS login/background helper that keeps the client running
  outside the main app lifecycle.
- Be explicit in Settings and privacy copy about what works while Brev
  is running versus closed.

ADR-0006 and ADR-0028 make a relay a high bar: it would introduce new
infrastructure, long-lived mailbox connections outside the user's
device, and new privacy/security disclosure requirements.

## Decision

1. **Brev will not run a hosted generic-IMAP push relay for v1.** Generic
   IMAP/SMTP accounts remain device-local: polling, IMAP IDLE, cache
   refresh, and notification previews happen on the user's device.

2. **Closed-app generic IMAP notifications are best-effort only.** iOS
   may get system-granted `BGAppRefreshTask` windows. macOS may use local
   background refresh while the app remains installed/runnable, but Brev
   does not promise APNS-style closed-app push for ordinary IMAP accounts.

3. **Provider push is unavailable in the current release.** Brev does not
   register APNS tokens for mail delivery. Any future provider-push adapter
   requires a new ADR and capability-driven integration.

4. **The limitation must be visible.** Notification settings and
   `PRIVACY.md` must distinguish live local alerts from best-effort generic
   background refresh.

5. **A helper or relay requires a later ADR.** A future macOS helper or
   hosted relay would need new threat modeling, privacy documentation,
   credential handling, user controls, and packaging/release work before
   implementation.

## Consequences

- Brev is honest about generic IMAP behavior instead of implying that
  all accounts receive closed-app push.
- No new network service, telemetry, credential relay, or APNS gateway is
  introduced by this decision.
- Competitor parity remains incomplete for generic IMAP accounts when the
  app is fully quit; a future provider-specific integration would require a
  new decision and capability-driven implementation.

## References

- ADR-0006 (telemetry and privacy)
- ADR-0028 (roadmap and invariants)
- ADR-0037 (notification delivery and push architecture)
- ADR-0037 (macOS remote push registration)
- ADR-0028 (standards-first IMAP/SMTP roadmap)
- The related feature request (generic IMAP closed-app notifications)
