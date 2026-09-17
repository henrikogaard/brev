# ADR-0079: Native Microsoft 365 mail through Microsoft Graph

- **Status:** Proposed
- **Date:** 2026-09-17
- **Deciders:** Henrik
- **Amends:** ADR-0040, ADR-0066
- **Related:** ADR-0006, ADR-0028, ADR-0065, ADR-0067, ADR-0074

## Context

ADR-0040 accepted native Microsoft 365 as future scope and named Microsoft
Graph as the primary path; ADR-0066 kept it out of the current provider set.
Today a Microsoft account works only as OAuth-over-IMAP/SMTP, which fails for
tenants that disable IMAP (an increasingly common default) and never offers
shared mailboxes, server rules, categories or focused inbox. Issue #28 §7
lists native Microsoft 365 as the largest remaining daily-driver gap for that
audience.

Brev already has one native provider adapter to copy: `packages/BrevGmail`
with `GmailAPIBackend: MailBackend`, an injectable `GmailAPITransport`, a
SQLite account store, a sync reconciler over history deltas, draft staging,
scheduled send, and dynamic `capabilities` computed from probed server state
(`GmailAPIBackend.swift:137-160`). Its OAuth flow (ADR-0065/0067) uses
authorization-code PKCE with a loopback redirect on macOS and a
reversed-client-ID callback on iOS, no client secret, state validation, and a
one-callback receiver.

This ADR is a design decision only. Implementation cannot start until an
Azure app registration exists (client ID, redirect URIs) and a Microsoft 365
developer tenant with at least one shared mailbox is available for live
verification. Nothing in this ADR adds a network call by itself.

## Decision

1. **A new package `packages/BrevGraph` with `GraphMailBackend: MailBackend`.**
   Structure mirrors `BrevGmail`: `GraphAPITransport` (protocol, URLSession
   default, test double), `GraphAPIClient` (typed endpoints), `GraphModels`
   (Codable DTOs kept inside the package; views never see them),
   `SQLiteGraphAccountStore`, `GraphSyncReconciler`, `GraphDraftStaging`.
   `BrevBackend` gains no Microsoft-specific types.

2. **Graph v1.0 only, with these resources.** `me/mailFolders` (+ `delta`),
   `me/mailFolders/{id}/messages/delta` for sync, `me/messages/{id}` with
   `$select` for headers and `/$value` for raw MIME (feeds the existing
   ADR-0045 raw-source seam and body parser), `/attachments` for downloads,
   `me/messages?$search` for server search, `me/sendMail` and
   `me/messages/{id}/send` for sending, `me/mailFolders/inbox/messageRules`
   for server rules, `me/outlook/masterCategories` mapped to labels,
   `users/{shared}/mailFolders` for shared mailboxes, `me/mailboxSettings`
   for automatic replies and time zone. Beta endpoints are not used.

3. **Auth is Microsoft identity platform authorization-code PKCE without
   MSAL.** Reuse the ADR-0065/0067 flow shape: loopback redirect on macOS,
   reversed-client-ID on iOS, PKCE + state, no client secret, tokens in the
   Keychain via the existing credential store. Tenant is `organizations` for
   work accounts and `consumers` for personal Outlook.com, chosen at setup by
   the domain lookup already used for IMAP autodiscovery; `common` is not
   used so the consent screen matches the account type. Scopes are the
   minimum for the features enabled: `Mail.ReadWrite`, `Mail.Send`,
   `MailboxSettings.ReadWrite`, `offline_access`, `User.Read`;
   `Mail.ReadWrite.Shared` and `Mail.Send.Shared` are requested only when the
   user adds a shared mailbox, through incremental consent.

4. **Sync is delta-token based, matching the Gmail history model.** Folder
   list and each synced folder keep a Graph `@odata.deltaLink`; the
   reconciler applies adds/updates/removes to the same header cache and local
   index the IMAP and Gmail backends use, so threading (ADR-0052/0074),
   search fallback, retention and the ADR-0077/0078 features work unchanged.
   `conversationId` maps to `MessageHeader.threadID` and enables
   `.serverSideThreading`. Push (Graph change notifications) is **not** in
   the first slice: it requires a public webhook endpoint Brev does not run;
   polling on the existing fetch schedule plus the ADR-0075 background
   cadence is the delivery model, and the UI must say so as it does for IMAP
   without IDLE.

5. **Capabilities are probed, never assumed.** On connect the backend
   probes `mailboxSettings`, `masterCategories`, rules and shared-mailbox
   access and sets `.providerAPI, .oauthAuth, .serverSideSearch,
   .serverSideThreading, .historyDeltaSync, .labels (categories),
   .serverRules, .autoReply, .sharedMailboxes, .aliases (when
   send-as/send-on-behalf permissions resolve), .folderCreate/Rename/Delete`.
   Views keep branching on these flags (ADR-0028 rule 3). Focused Inbox is
   exposed as a smart view over the `inferenceClassification` property, not
   as a new folder type.

6. **Shared and delegated mailboxes are additional `MailSourceID`s under
   the same account.** A shared mailbox appears as a sibling source in the
   sidebar with its own folders; send-on-behalf/send-as use the alias
   mechanism with the shared address as the identity. This is the first
   backend to exercise `.sharedMailboxes`; the unified inbox and
   cross-source actions already key on `MailSourceID`.

7. **Privacy and disclosure before any code ships.** ADR-0006's network
   table gains rows for `login.microsoftonline.com` (token exchange: code,
   PKCE verifier, client ID, refresh tokens) and `graph.microsoft.com` (mail,
   folder, rule, category, settings and attachment traffic listed above),
   both "off until a Microsoft 365 account is added" and reversible by
   account removal. `PRIVACY.md` gets the matching section. Account setup
   copy states what identifiers leave the device and that the tenant admin
   may need to grant consent.

8. **Setup UX.** The "Microsoft" choice in account setup becomes native
   Graph by default with "Use IMAP/SMTP instead" as an explicit alternative
   for tenants without Graph access; the existing OAuth-over-IMAP path is
   kept, not removed. If a tenant's admin consent is required, the setup
   sheet shows the Microsoft error verbatim with a "Copy request URL" action
   rather than a generic failure.

9. **Out of scope for this ADR:** EWS, Exchange on-premises, Autodiscover
   v2, MAPI (ADR-0040 decision 4 stands), Graph change notifications,
   calendar and contacts through Graph (ADR-0039 read-only scope continues
   to apply; Graph calendar is a later ADR), Teams presence, and Intune/MAM
   policy (ADR-0042).

## Rationale

- *Own package mirroring BrevGmail:* the Gmail adapter proved the shape —
  transport double for tests, DTOs sealed inside the package, dynamic
  capabilities from probes. Copying it keeps `BrevBackend` provider-neutral
  and gives a second data point for what belongs in the shared layer.
- *PKCE without MSAL:* MSAL is a large dependency with its own Keychain
  group, broker and telemetry surface; Brev already has a working native
  PKCE flow and a zero-telemetry rule (AGENTS.md rule 2). The identity
  platform supports plain OAuth 2.0 public clients.
- *Delta over webhooks:* honest about what a desktop client without a
  server can do; ADR-0037 makes the same call for IMAP.
- *`organizations`/`consumers` over `common`:* avoids the "work or school /
  personal" disambiguation screen and mis-consent for personal accounts.

## Consequences

- New protected-path work: package, OAuth client registration handling,
  ADR-0006 rows, PRIVACY.md, setup UI, capability additions if any flag is
  missing (`.sharedMailboxes`, `.serverRules`, `.autoReply` already exist).
- Requires from the maintainer before implementation: an Azure app
  registration (public client, redirect URIs for loopback and the iOS
  reversed client ID), a developer tenant with a shared mailbox, and a
  decision on whether personal Outlook.com is in the first slice.
- Implementation order once unblocked: (1) transport + auth + folder/message
  delta read-only, (2) flags/move/delete/search, (3) send + drafts + aliases,
  (4) rules/categories/auto-reply, (5) shared mailboxes. Each step ships
  behind the probed capabilities so partial support never lies in the UI.
- Live QA needs a recorded matrix like `docs/qa/multi-account-workspace.md`
  covering IMAP-disabled tenant, shared mailbox, and admin-consent-required
  paths.

## References

- ADR-0006: telemetry and privacy
- ADR-0028: architectural invariants
- ADR-0040: native Exchange and Microsoft 365 scope (Graph named primary)
- ADR-0042: enterprise admin policy scope
- ADR-0065, ADR-0067: Google desktop OAuth loopback and client credential
- ADR-0066: current provider scope (amended: Microsoft moves from "future"
  to "designed, awaiting registration")
- ADR-0075: background mail presence (delivery model)
- Issue #28 §7
