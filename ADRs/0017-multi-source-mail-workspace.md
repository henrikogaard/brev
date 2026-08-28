# ADR-0017: Multi-source mail workspace

- **Status:** Proposed
- **Date:** 2026-05-29
- **Deciders:** Henrik

## Context

Brev already has two account concepts that point toward a multi-source
mail client:

- `BrevAccount` carries a backend identifier/display name so the view
  layer does not assume every account uses the same provider.
- `Mailbox` represents one mail address/inbox under an account, which
  matters for the provider accounts with several mailboxes and for future
  IMAP/JMAP providers.

The current `BrevMailRootView` still mounts one active `MailBackend`
and one active mailbox at a time. That is sufficient for the first
desktop the provider path, but it cannot support the product shape now
being tracked by issues:

- #26: multiple visible accounts/mailboxes in the sidebar.
- #27: Unified Inbox across accounts/mailboxes.
- #32: Profiles that filter visible mailboxes.
- #8: IMAP-with-OAuth accounts beside the provider accounts.
- #15: future JMAP accounts.

ADR-0028 is the controlling constraint. Views must not import
provider-specific models, must branch on capabilities rather than
backend type, and must not assume one account equals one backend type.
ADR-0066 also matters: macOS uses `ProviderHTTP`, while iOS may use
`retired provider adapter`; the multi-source workspace must sit above those
platform/provider implementations.

## Decision

Introduce a provider-neutral source identity layer in `BrevBackend`.
A **mail source** is the smallest visible mailbox unit in the UI:

```swift
MailSourceID(accountID: BrevAccount.ID, mailboxID: Mailbox.ID)
```

All state that can be ambiguous across accounts or mailboxes must carry
source identity. Folder IDs and message IDs are no longer globally
meaningful once multiple providers are visible; they are meaningful only
inside their source.

### Workspace shape

The app owns a workspace coordinator above individual `MailBackend`
instances:

- one `MailBackend` instance per signed-in account;
- one or more `Mailbox` values per backend;
- one source tree built from accounts, mailboxes, and folders;
- selected folder/message state expressed as source-scoped selections.

`MailBackend` remains the provider boundary. We do not introduce a
"unified backend" that pretends multiple providers are one server.
Instead, the workspace routes each operation to the backend that owns
the selected source.

### Source-scoped selections

Add small value types as needed:

- `MailSourceID` — account/mailbox identity.
- `SourceFolderID` — source plus folder ID.
- `SourceMessageID` — source plus message ID.

These types are plain Swift values, `Sendable`, `Hashable`,
`Identifiable` where useful, and `Codable` where they may be persisted.
They live in `BrevBackend`, not in `BrevMail`, because backends,
settings, profiles, and tests all need the same identity semantics.

### Sidebar model

The sidebar renders a provider-neutral source tree, not a concrete
backend:

```text
Unified Inbox

the provider
  henrik@example.com
    Inbox
    Sent
    Archive
  work@example.com
    Inbox
    Sent

Fastmail
  me@fastmail.com
    Inbox
    Archive
```

For a single account with one mailbox, the UI may collapse this into
the current simple folder list so existing users are not forced through
extra hierarchy.

### Unified Inbox

Unified Inbox is a virtual view over source-scoped Inbox folders. It
merges message headers in the workspace layer and preserves
`SourceMessageID` so opening a message or applying a mutation routes
back to the owning backend.

It is not a `MailBackend` implementation. Backends remain responsible
for their own folders, pagination, message bodies, and mutations.

### Profiles

Profiles are local saved filters over `MailSourceID` values:

```swift
MailProfile(id: UUID, name: String, sourceIDs: [MailSourceID])
```

A source may appear in multiple profiles. Switching profiles filters
the sidebar and virtual views; it does not disconnect accounts, mutate
provider state, or change backend authentication.

Profiles are deliberately local in the first version. Cross-device
profile sync requires a later ADR.

## Rationale

**Why source identity instead of globally namespacing raw strings.**
Backends can and will reuse folder IDs such as `inbox`, and message IDs
may collide across providers. Explicit source-scoped value types make
collisions impossible to ignore in tests and compiler signatures.

**Why not make Unified Inbox a backend.** A fake aggregate backend would
either hide partial failures badly or force every backend into the same
pagination/search model. Keeping aggregation in the workspace layer
lets each provider keep its real capabilities while the UI remains
provider-agnostic.

**Why put identities in `BrevBackend`.** `BrevMail` needs them for
navigation, `BrevSettings` needs them for profiles and sidebar
visibility, and backend tests need them for routing. Putting them in a
view package would invert the dependency direction from ADR-0011.

**Why not implement IMAP/JMAP as part of this ADR.** ADR-0028 and
ADR-0028 keep IMAP/JMAP out of v1 implementation scope. This ADR makes
their later addition possible without view rewrites; it does not choose
IMAP/JMAP libraries or auth flows.

**Why not sync profiles now.** Brev has no hosted settings service, and
ADR-0006's privacy posture favors local-first state. Profiles can be
useful locally without adding a new network surface.

## Consequences

### Accepted

- `BrevMailRootView` will eventually move from one active backend to a
  workspace that can hold several account backends.
- Folder/message navigation must become source-scoped before Unified
  Inbox or Profiles can be reliable.
- Message mutations from virtual views must be grouped by source before
  calling backend APIs.
- Single-account UI needs a collapsed/simple presentation path so this
  architectural flexibility does not add visual noise.
- Tests must include deliberate ID collisions across sources.

### Risks

- **More state in the root mail UI.** A workspace coordinator is more
  complex than one backend reference. Mitigation: introduce small value
  types and policy objects first, then migrate views incrementally.
- **Partial failures in virtual views.** Unified Inbox can succeed for
  one provider and fail for another. Mitigation: model partial failure
  explicitly in the the related feature request implementation rather than hiding it.
- **Premature profile complexity.** Profiles could grow into rules,
  notifications, or sync. Mitigation: first version is only a local
  filter over sources; everything else is out of scope.
- **Public API churn.** `BrevBackend` identities will be public package
  API. Mitigation: keep the initial types small and provider-neutral.

## References

- ADR-0028: Project identity and scope
- ADR-0001: Backend abstraction
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0011: BrevMail package
- ADR-0066: Desktop the provider HTTP backend
- The related feature request: IMAP-with-OAuth backend
- The related feature request: JMAP exploration
- The related feature request: Multi-source mail workspace and sidebar
- The related feature request: Unified Inbox across mailboxes and accounts
- The related feature request: Profiles for mailbox-focused workspaces
