# iOS Password IMAP/SMTP Parity Checklist

Use this checklist when validating that iOS and iPadOS have macOS Brev parity
for standards-first IMAP/SMTP accounts that use a password or app password.
OAuth browser sign-in and the full ADR-0030 folder-wide sync engine are out
of scope for this pass.

Record dated results under `docs/qa/results/`. Do not store credentials,
provider tokens, raw private message bodies, or private attachment contents in
the result file or screenshots.

## Required Environments

| Environment | Required coverage |
| --- | --- |
| iPhone | Current primary iPhone simulator or physical device |
| iPad | Current primary iPad simulator or physical device |
| Account mode | Demo/mock mailbox plus one disposable password/app-password IMAP account when credentials are available |
| Appearance | Light and dark, or record the skipped appearance |
| Dynamic Type | Default plus one accessibility size, or record why skipped |
| Network state | Online plus one offline/restore/error-state pass |

## Password IMAP/SMTP Parity Matrix

| Surface | Expected iOS behavior | Evidence to record |
| --- | --- | --- |
| Account setup entry | Add Mail Account is reachable from first run and Settings → Accounts. Gmail/Outlook OAuth browser sign-in is not offered as an iOS shipping path for this pass. | Visible provider/manual setup entry and OAuth-unavailable/app-password guidance for XOAUTH2 discoveries. |
| Autodiscovery and manual setup | Find settings validates the email locally, uses DNS/provider autoconfig disclosure copy, fills editable IMAP/SMTP fields, and manual defaults remain available. | Sanitized provider/domain, discovered source, and edited server review state. |
| Test connection | Test connection validates IMAP login and SMTP authentication without saving account/configuration/credential material. | Success/failure status copy; no account row created after test-only validation. |
| Add and restore account | Adding a password/app-password account installs the shared `IMAPAccountConnector.standard` backend, persists non-secret config, stores the secret in Keychain, and restores after relaunch. | Account appears after add and after relaunch; failed auth keeps the account retryable. |
| Folder navigation | Source/account sections, Inbox, Sent, Drafts, Archive, Spam/Junk, Trash, custom folders, and counts render where the provider exposes them. | iPhone stack and iPad split-view navigation screenshots with private row text redacted or demo data. |
| Folder actions | Create, rename, delete, and flush actions appear only when capabilities/folder roles allow them and use source-scoped IMAP calls. | Action menu availability and resulting folder refresh. |
| Message list | First page loads, cached first paint works after a transient listing failure, pagination keeps older visited rows, refresh reconciles changed/removed rows, quick filters and sort remain usable. | Sanitized row counts, cache fallback note, refresh/pagination behavior. |
| Search | Server search runs for IMAP-supported criteria; cache-only fallback works over visited cached headers when offline. | Search mode/result count behavior without private query terms. |
| Message reader | Body loading uses cached source reuse when available, remote content remains blocked by default, inline CID images render from local data, and attachments can preview/open/share/save through iOS affordances. | Reader state, remote-content control, attachment action availability. |
| Mailbox actions | Read/unread, flag/unflag, archive, move, delete, permanent delete, junk/not-junk fallback, reply, reply all, forward, unsubscribe, and undo use source-scoped backend calls. | Command availability and post-action row/header state. |
| Compose and send | New, reply, reply all, and forward choose the source-aware sender, support attachments, save/discard drafts, send through SMTP, and surface Sent-copy or remote-Drafts cleanup warnings as non-fatal. | Compose fields, attachment row, send success/warning status. |
| Drafts and scheduled send | Draft staging survives backend recreation; server Drafts cleanup is attempted on discard/send; due scheduled sends retry on reconnect/background refresh instead of being dropped. | Draft save/discard/send behavior and scheduled-send status copy. |
| Settings and diagnostics | Account settings expose capability, mailbox, sync-health, retry sync, conflict review/clear, storage reset, privacy, notification, and account removal controls where applicable. | Settings rows and status panels on iPhone and iPad. |
| Background refresh and IDLE | Foreground, network recovery, scheduled background refresh, and IMAP IDLE use the existing ADR-0029 first-page/cache path without wiring ADR-0030 full sync. | Refresh trigger notes, local notification/new-message signal when available. |
| Notifications | Permission prompt remains explicit, notification previews follow settings, notification actions route back to source-scoped messages, and APNS registration stays opt-in. | Authorization state, preview setting, action routing result. |
| Account removal | Removing or signing out clears account config, Keychain credential, draft staging, header/source/folder caches, pending mutations, conflicts, and related AI assignment state. | Account disappears after removal and does not restore on relaunch. |

## Verification Commands

Run these before marking the password-parity pass locally complete:

```bash
swift test --package-path packages/BrevBackend
swift test --package-path packages/BrevMail
scripts/imap-smtp-local-smoke.sh
tuist generate
tuist build BrevIOS
scripts/lint.sh
scripts/format.sh
scripts/check-adr-required.sh
```

If live disposable credentials are unavailable, record the live account rows as
skipped and include the credential-free smoke result instead.
