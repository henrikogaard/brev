# PR #47 phone layout verification

2026-09-19, iPhone 18 Pro / iOS 27 simulator, explicit mock mail only.
These are rendered app captures, not design mockups.

| Screen | Evidence |
| --- | --- |
| [Inbox](inbox.jpg) | One-row search; readable sender, two-line subject and preview; Compose at the bottom. |
| [Mailboxes](mailboxes.jpg) | Named navigation, one Settings entry, reduced indentation, trailing folder disclosure. |
| [Reader](reader.jpg) | Message opens from Inbox; AI and message menus have distinct icons. |

Interaction checks: mailbox selection, message opening, searching for GitHub,
and opening/closing Compose. The automation required explicit touch-down/up;
the ordinary tap helper reported success without activating controls. Reader
runtime accessibility snapshots did not settle, so reader-menu/Back, VoiceOver,
large accessibility sizes and iPad QA remain unverified. No sending or real-account
operations were performed.

Automated coverage: app-hosted search sizing regression (red at 319pt, green at
44pt), focused presentation/navigation tests, and four light/dark component
snapshots in `PhoneMailboxSnapshotTests`. Earlier unrelated snapshot mismatches
remain recorded in WORKLOG.md and the PR; these captures do not clear them.
