# ADR-0056: Opt-in iCloud key-value sync for local preferences (phase 1)

- **Status:** Accepted
- **Date:** 2026-08-15
- **Deciders:** Henrik
- **Amends:** ADR-0006 (network calls table)

## Context

Brev keeps a growing amount of small, user-owned state on the device
only: snoozes and "done" markers (`LocalMessageWorkflowStateStorage`,
ADR-0043 keeps provider-backed workflow state separate), VIP senders
(`VIPSenderSettings`), manual inbox category overrides
(`InboxCategoryOverrideStore`, ADR-0035), blocked senders, follow-up
reminders, pinned messages, signatures, templates, smart mailboxes, and
a handful of compose and sidebar preferences. All of it lives in
`UserDefaults`.

Henrik runs Brev on a Mac and an iPhone. A message snoozed on one
device stays in the inbox on the other; a VIP added on the phone is not
a VIP on the Mac. Users have asked for the same. Brev has no server of
its own (ADR-0006: "Data Brev itself collects from users: zero"), and a
self-hosted sync server is a v2+ topic that would need its own ADR,
so phase 1 must reuse infrastructure the user already has.

Apple's `NSUbiquitousKeyValueStore` (iCloud Key-Value Storage, "KVS")
is available to every signed-in iCloud user, needs no Brev
infrastructure, is end-to-end tied to the user's Apple ID, and is
sized for exactly this class of data: at most 1 MB total and 1024 keys
per app, with last-writer-wins conflict resolution and best-effort
propagation latency (seconds to minutes).

Constraints from earlier ADRs:

- ADR-0006 / ADR-0005: any new external data flow is off by default,
  requires explicit opt-in, and must be listed in ADR-0006 and
  `PRIVACY.md`.
- ADR-0028 invariants: view code stays behind capability-driven,
  provider-agnostic seams; nothing in the view layer may depend on
  iCloud directly.
- Mail content, credentials, and per-device state must never leave the
  device through this path.

## Decision

1. **Phase-1 preference sync uses iCloud Key-Value Storage, opt-in.**
   A single toggle, "Sync preferences with iCloud", lives in
   Settings → Privacy and defaults to **off**. While it is off Brev
   never reads from or writes to `NSUbiquitousKeyValueStore` and does
   not observe its notifications. The toggle itself is a per-device
   setting (`sync.preferences.iCloudEnabled`) and is never synced.

2. **A `PreferenceSyncStore` protocol is the seam** (in `BrevSettings`).
   Two implementations ship:
   - `LocalOnlyPreferenceSyncStore` — no-op; the default.
   - `ICloudKeyValuePreferenceSyncStore` — mirrors an allowlist of
     `UserDefaults` keys to KVS through a small
     `PreferenceSyncTransport` protocol that `NSUbiquitousKeyValueStore`
     satisfies directly and tests satisfy with an in-memory fake.
   A future self-hosted sync backend implements `PreferenceSyncStore`
   (and can reuse the same allowlist and reconciliation) without
   touching callers. `PreferenceSyncController` picks the active store
   from the toggle and starts/stops it as the toggle changes.

3. **Only an explicit allowlist of keys is synced.** The list is a
   single constant, `PreferenceSyncAllowlist.keys`, and every entry
   must be per-user (not per-device), free of mail content and
   credentials, and small. Phase-1 allowlist:

   | Key | What it holds |
   |---|---|
   | `message.workflowState.v1` | snoozes, done markers, and local notes keyed by account/mailbox/message ID |
   | `vip.senders` | VIP sender list |
   | `list.inboxCategoryOverrides` | manual inbox category overrides |
   | `list.pinnedMessageIDs` | retained legacy unscoped pin IDs |
   | `list.pinnedSourceMessageIDs.v2` | pins scoped to account, mailbox, and message |
   | `blockedSenders.emails` | blocked sender list |
   | `followUp.reminders` | follow-up reminders |
   | `signature.settings` | signatures |
   | `messageTemplates.v1` | message templates |
   | `smartMailbox.mailboxes` | smart mailbox definitions |
   | `compose.messageFormat`, `compose.quotePlacement`, `compose.attachmentReminderEnabled`, `compose.externalRecipientWarningEnabled`, `compose.undoSendDelay` | compose preferences |
   | `folders.showAllMail`, `folders.showArchive`, `folders.showScheduled`, `folders.showSnoozed`, `folders.showSpam`, `folders.showStarred`, `folders.showTrash` | sidebar smart-folder visibility |

   Message and account identifiers inside these values are stable
   across devices because Brev derives IMAP account IDs from the
   normalized email address (`BrevAccount.imapSMTPAccountID`) and uses
   server-assigned message IDs.

   Deliberately **excluded** in phase 1: anything that gates a network
   call or consent (avatar sources, remote content, AI, updates, push,
   CalDAV, encryption, recipient key discovery), per-device state
   (window frames, pane widths, notification sounds/badges, fetch
   interval, appearance/theme selection which may reference custom
   theme files present on one device only), account credentials and
   account/folder sync scope, local rules with automatic execution
   (double execution risk), and per-account flag colors
   (`LocalFlagColorStore` is not wired into a production backend yet;
   add its namespaced keys when it is). Adding a key means editing the
   allowlist and this table.

4. **Key namespacing.** KVS keys are `brev.prefs.v1.<UserDefaults key>`.
   The `v1` segment lets a future format change coexist with older
   builds instead of corrupting them.

5. **Conflict policy: last-writer-wins, as KVS provides.** Brev does
   not add merge logic in phase 1. Concretely:
   - Local change (`UserDefaults.didChangeNotification`) → the store
     diffs allowlisted keys against its last-pushed snapshot and pushes
     changed values, then calls `synchronize()`.
   - Remote change (`NSUbiquitousKeyValueStore.didChangeExternallyNotification`)
     → the store writes the changed allowlisted values into
     `UserDefaults` and posts `PreferenceSync.didApplyRemoteChanges`
     with the affected keys so live views can refresh.
   - First enable on a device: existing cloud values win for keys the
     cloud already has; keys only the device has are pushed. This
     matches Apple's KVS guidance and means the second device adopts
     the first device's state.
   - Remote *absence* never deletes local state (protects against
     iCloud sign-out / account-change resets wiping preferences). Since
     every synced value is written as a whole (an empty list is still a
     value), "cleared" state still propagates.
   - Turning the toggle off stops observation and pushes/pulls; it does
     not delete cloud copies, so other devices keep syncing.
     `ICloudKeyValuePreferenceSyncStore.removeAllRemoteValues()` exists
     for a future "Remove from iCloud" action.

6. **Limits.** KVS allows 1 MB and 1024 keys per app. Brev syncs at most
   ~24 keys. Values are checked before pushing; a single value over
   ~900 KB is skipped and logged rather than triggering a quota
   violation. Quota-violation change notifications are logged.

7. **Entitlement.** Both apps declare
   `com.apple.developer.ubiquity-kvstore-identifier` =
   `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`. The App ID must have
   iCloud → Key-value storage enabled in the developer portal for
   signed builds; unsigned local test builds simply get a KVS store that
   never syncs.

## Rationale

**Why iCloud KVS and not CloudKit, a Brev server, or IMAP-side
storage.** CloudKit is far more capable but is overkill for a few
kilobytes of preferences and adds schema, container, and conflict
machinery. A Brev-hosted server contradicts the zero-server posture and
needs accounts, hosting, and a privacy story of its own. Storing state
in a hidden IMAP folder or as IMAP annotations is provider-dependent
and pollutes the user's mailbox. KVS is zero-infrastructure, already
covered by the user's Apple ID and iCloud terms, and its limits match
the payload.

**Why opt-in even though the data is the user's own preferences.**
ADR-0006 makes every data flow off by default; the user should decide
whether Apple's servers see even a VIP list. Off-by-default also keeps
`scripts/privacy-audit.sh` honest.

**Why an allowlist and not "all `UserDefaults`."** `UserDefaults`
mixes per-user preferences with per-device state, caches, and consent
flags. Syncing consent flags would silently enable network features on
another device. An explicit list is auditable and small.

**Why last-writer-wins without merge.** Merge semantics for each value
type (snooze list, VIP list, template list) would triple the code and
still surprise users in edge cases. Phase 1 accepts that editing the
same preference on two offline devices loses one edit. A future store
can add per-key merge behind the same protocol.

**Why a protocol now.** So the self-hosted option in a later ADR is a
new implementation, not a rewrite of the toggle, controller, and
callers.

## Consequences

### Accepted

- One new external data flow, opt-in, documented in ADR-0006 and
  `PRIVACY.md`.
- New entitlement on both app targets; a developer-portal change is
  needed before signed builds sync.
- Views that load allowlisted state into `@State` refresh on the next
  appearance or on `PreferenceSync.didApplyRemoteChanges`; `@AppStorage`
  consumers refresh automatically.
- Last-writer-wins can drop a concurrent edit.

### Risks

- A synced value type could grow past the KVS quota (long notes,
  thousands of overrides). Mitigation: per-value size guard, logging,
  and the ability to remove a key from the allowlist.
- iCloud availability and latency are outside Brev's control; the
  toggle text says "may take a moment".
- Users may expect mail content or accounts to sync. The toggle
  subtitle and `PRIVACY.md` state the scope.

## References

- ADR-0005 (enforcement), ADR-0006 (network calls table),
  ADR-0028 (invariants), ADR-0012 (BrevSettings), ADR-0035 (inbox
  categories), ADR-0043 (provider-backed workflow state)
- Apple: `NSUbiquitousKeyValueStore` documentation (1 MB / 1024 keys)
