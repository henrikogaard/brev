# ADR-0055: The demo mailbox never accesses system Contacts

- **Status:** Accepted
- **Date:** 2026-08-13
- **Deciders:** Henrik
- **Amends:** ADR-0003, ADR-0006

## Context

Brev's demo mode (`BREV_USE_MOCK=1`, or the Developer Settings toggle)
seeds a mailbox of invented senders so the UI can be exercised without a
real account. It is the mode every local UI verification runs in.

Opening that mailbox raises the macOS Contacts permission prompt. The
prompt comes from `SystemContactPhotoProvider.canReadContacts()` in
`BrevAvatars`, which calls `CNContactStore.requestAccess(for:)` whenever
the authorization status is `.notDetermined`. The message list renders
avatars for every visible sender on first paint, so the prompt appears
seconds after launch, on every fresh install or after any TCC reset.

The senders are fictional. A Contacts match is impossible by
construction, so the prompt cannot improve anything the tester sees — it
can only interrupt them, and it trains whoever is testing to dismiss a
privacy prompt reflexively.

The obvious fix — force `AvatarPreferences.useContacts` off in demo mode
— was tried first and does not hold. `AvatarResolver.shared` is a lazily
created singleton constructed with `AvatarPreferences.default`, which has
`useContacts: true`. Preferences arrive later, through an `await
updatePreferences(...)` from the view layer's bootstrap. Avatar
resolution for the first screenful of messages is enqueued on the same
actor from a different task, so nothing orders the bootstrap ahead of it.
In practice the resolver serviced several resolutions with the default
preferences and prompted before the gate landed.

Any fix that depends on *when* a preference is applied has this race. The
gate has to sit at the permission check itself, where ordering cannot
matter.

## Decision

`BrevAvatars` gains a process-wide switch, `AvatarPermissionPolicy
.allowsSystemContactsAccess`, read before any contact-photo provider is
called and again at `SystemContactPhotoProvider`. When it is off, avatar
resolution neither requests permission nor reads Contacts access granted
during an earlier run.

Both app targets set it synchronously in `BrevApp.init()`, from
`DeveloperSettings.isDemoModeRequested(...)`. `init()` returns before any
scene body is evaluated, so the switch is in place before a view can
exist to resolve an avatar. It is a plain `nonisolated(unsafe) static
var` rather than actor state precisely so that reading it cannot suspend
and cannot be reordered.

The normal sign-in screen can also enter the demo mailbox without a demo
launch flag. `AppSession.signInWithDemo()` therefore disables Contacts
synchronously before awaiting or installing the demo backend. This closes
the path where app initialization allowed Contacts because the process
started in normal mode.

The view-layer gate added alongside this — `ContactsAccessPolicy` in
`BrevMail`, which forces `useContacts` off and short-circuits compose
recipient autocomplete — stays. Together, the two gates keep demo mode
from asking for or reading Contacts through either consumer.

## Consequences

- Demo mode never accesses system Contacts and raises no Contacts prompt,
  deterministically, regardless of launch path or task ordering.
- `BrevAvatars` carries one piece of process-wide mutable state. The app writes
  it at launch and at demo-session boundaries; resolution paths only read it.
- The switch governs all Contacts access. A future surface that wants
  Contacts on demand must remain unavailable while the demo mailbox is the
  active session rather than routing around this decision.
- ADR-0006's network-calls table is untouched: Contacts is local, and
  nothing here adds or removes an external call.

## Alternatives considered

**Force `useContacts` off in the bootstrap only.** Already shipped and
already shown insufficient — see Context. Kept as the second layer, not
relied on as the first.

**Never call `requestAccess` at all, in every mode.** Cleaner in the
abstract: an app arguably should not prompt for Contacts as a side effect
of opening a mailbox. But it silently breaks contact avatars for every
real user until some other surface asks, and there is no such surface
today. That is a product change, not a testing fix, and belongs in its
own ADR alongside the Settings affordance it needs.

**Give demo mode its own `UserDefaults` suite** so `avatar.useContacts`
can be false there without touching real runs. Fixes the preference value
but not the race, since the resolver still starts from
`AvatarPreferences.default`.
