# Standard mailbox-name localization — 2026-09-30

The mailbox sidebar and the message-list header now show standard folder names
in the app language. Before this change, `FolderAliasPreferencesPolicy` returned
hardcoded English names for the ten standard roles (`Inbox`, `Sent`, `Drafts`,
`Trash`, `Spam`, `Archive`, `Snoozed`, `Scheduled`, `Flagged`, `All Mail`), and
the message-list header used the raw server folder name. A Norwegian interface
therefore mixed English folder labels into an otherwise Norwegian screen.

## Change

- `FolderAliasPreferencesPolicy.standardDisplayName(for:)` resolves all ten
  standard roles through `String(localized:bundle:.module)`; the BrevBackend
  String Catalog carries the `nb` translations (Innboks, Sendt, Utkast, Søppel,
  Søppelpost, Arkiver, Utsatt, Planlagt, Flagget, All e-post).
- The message-list header resolves through
  `MailRootMessageListTitlePolicy.folderTitle` — the same alias → standard name
  → server name path as the sidebar — so the header and the sidebar row never
  disagree about a mailbox.

## Rendered verification

Environment: iPhone 17 Pro simulator (iOS 27), Debug build of `BrevIOS`, mock
backend (`SIMCTL_CHILD_BREV_USE_MOCK=1`), launched with
`-AppleLanguages '(nb)' -AppleLocale nb_NO`, viewed through `serve-sim`.

| Screen | Before | After |
| --- | --- | --- |
| Message-list header | [English "Inbox"](03-message-list-header-before.png) | [Norwegian "Innboks"](02-message-list-header-after.png) |
| Mailbox list | — | [Innboks, Utkast, Sendt, Søppelpost, Søppel, Arkiver](01-mailbox-list.png) |

Custom provider folders keep their server names ("Clients" and its children in
the mailbox list), and provider-native labels (for example Gmail `STARRED`) are
unchanged by design.

## Limits

- Physical-iPhone acceptance is still pending (handoff item 1); simulator
  evidence does not close it.
- The macOS pixel-snapshot suites (`LocalFolderSnapshotTests` light+dark,
  `CalendarGridSnapshotTests`) keep failing on this macOS 27 host and reproduce
  identically on a pristine `origin/main` checkout, so the mismatches are
  pre-existing environment-versus-baseline drift.
