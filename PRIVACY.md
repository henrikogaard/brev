# Privacy

Brev is designed so that **no data about you reaches us, ever.** We
collect no analytics, no crash reports, no usage statistics. The app
contains no telemetry call paths or telemetry SDK artifacts in the
generated app dependency graph.

This document explains the data that *does* leave your device and
where it goes. A fresh App Store or iOS install does not contact
external services until you add an account or explicitly enable an
optional feature. Direct-download macOS builds may check Brev's update
feed according to Settings -> Updates, using Sparkle's signed appcast.
After account sign-in, Brev contacts your mail provider to sync mail.
Everything else is off by default unless called out below.

Brev Nightly is a separate pre-release app (`eu.brevmail.brev.nightly`)
built from `main` every night; it follows exactly the same privacy
posture as Stable — the only difference is which appcast feed it checks.

## What data leaves your device, by default

Only what's needed to sign in, receive, and send mail after you add an
account:

| Data | Where it goes | Why |
|---|---|---|
| Email domain, and sometimes full email address during account setup | Your mail provider's DNS and provider-local autoconfig hosts | To discover IMAP/SMTP (and, where advertised, ManageSieve) server settings after you choose to add an account |
| IMAP account credentials and mail requests | Your selected mail provider's IMAP server | To authenticate, list folders, sync, search, read, view or export original message source, copy, and manage mail after you add an account |
| SMTP submission credentials and message payloads | Your selected mail provider's SMTP submission server | To send mail after you add an account |
| Google OAuth token and Gmail mail requests | `gmail.googleapis.com` | For a Gmail API account: to load Gmail labels, messages, threads, bodies, raw source and attachments; run Gmail search; synchronize mailbox history; save drafts; apply label/read/star/archive/trash actions; and send mail after you add the account |
| Update check | `henrikogaard.github.io` (appcast and release notes), `github.com` / `objects.githubusercontent.com` (DMG download) | Direct-download macOS builds of either release ring only; checks the signed Sparkle appcast using Settings -> Updates cadence |

For standards-first IMAP/SMTP setup, Brev first checks built-in
provider profiles. If discovery is needed, DNS SRV probes use only the
email domain — this includes the `_sieve._tcp` ManageSieve record, so a
server-side-filter endpoint can be pre-filled for your review. The SRV
lookup never connects to the ManageSieve server; an actual ManageSieve
connection stays user-initiated (ADR-0032). Provider-local HTTPS
autoconfig probes may include your full email address; the setup flow
should disclose that before sending the request. Manual server entry
remains available.

Brev does not proxy your mailbox through Brev-operated servers. Your
mail provider's privacy policy governs how they handle the mail data
you access through IMAP/SMTP.

## What data leaves your device only if you opt in

Each is disabled by default. Brev makes none of these calls until
you explicitly enable them in Settings.

### Manual GitHub release check

If you choose **Check GitHub Releases** in Settings -> Updates, Brev
requests Brev's latest public release metadata from `api.github.com`.
The request can expose normal HTTPS metadata such as your IP address,
user agent, and the requested Brev repository to GitHub. Brev does not
run this check automatically when Settings opens.

**How to disable:** Do not choose the manual GitHub release check.
Defaults to off.

### iCloud preference sync

If enabled: Brev mirrors a short, fixed list of local preferences to
Apple's iCloud Key-Value Storage under your own Apple ID so they follow
you between your Mac and iPhone: snoozes and done markers, VIP senders,
manual inbox category choices, pinned messages, blocked senders,
follow-up reminders, signatures, message templates, smart mailbox
definitions, compose preferences, and sidebar smart-folder visibility.
The exact key list is in ADR-0056. Mail content, attachments, account
settings, passwords, tokens, and settings that would turn on other
network features are never included. Apple stores this data subject to
Apple's iCloud terms; Brev has no server and never sees it.

**How to disable:** Settings → Privacy → "Sync preferences with
iCloud". Defaults to off. Turning it off stops reading and writing on
that device; values already in your iCloud account remain there until
overwritten by another device that still syncs.

### Local profiles and pins

Profiles preserve mailbox membership while an account is unavailable. Pins use
account, mailbox, and message identifiers so one mailbox cannot pin another's
message. The source-scoped pin preference follows the existing optional iCloud
preference-sync setting. Legacy pin IDs have no reliable account ownership;
Brev retains those records and asks the user to pin the messages again rather
than assigning them to an arbitrary account. No message bodies are included.

### Local mail notifications

Brev does not register an APNS device token for mail delivery and does not
share a push token with a provider or Brev-operated server. New-mail alerts are
created on the device after IMAP IDLE, polling, Gmail history synchronization,
or an operating-system-granted background refresh observes new mail.

When Brev is closed, delivery is best effort. The operating system may delay or
skip background refresh, so Brev does not promise closed-app mail alerts.
Notification badges, sounds, previews, account overrides, and quiet hours are
local presentation settings.

**How to disable:** Settings → Notifications → "Enable notifications".
Defaults to off.

On macOS, "Keep checking mail in the background" (Settings → Notifications)
keeps Brev running and checking the configured mail servers with no window
open, shows its status in the menu bar, and can optionally register to open
at login. It contacts only the mail servers the added accounts already use;
no new destinations are contacted. Defaults to off.

### Remote HTML assets

If enabled: Brev lets message HTML load remote images, fonts, and
tracking pixels from the hosts referenced by the message. Those hosts
can see your IP address and the time of the request.

Brev blocks remote HTML assets by default. You can load remote content
once for a single message, always allow a sender, always allow a
domain, or enable "Always load remote images" in Settings.

**How to disable:** Settings → Reading → "Always load remote images",
or remove sender/domain allowances from the remote-content policy.
Defaults to blocked.

### List-Unsubscribe actions

If a message includes standard `List-Unsubscribe` headers, Brev can
show an unsubscribe banner. Header detection is local and does not send
any network request.

If you choose an unsubscribe action, Brev asks for confirmation first:
- HTTPS actions open the unsubscribe URL in your browser. If the
  message advertises one-click unsubscribe, the list provider may treat
  opening that URL as an unsubscribe request.
- `mailto:` actions open a draft addressed to the list provider. You
  review and send the message yourself.

**How to disable:** Do not choose the unsubscribe action. Detection
itself is passive and local.

### Server-side filters (ManageSieve)

If enabled: during IMAP account setup you can enter a ManageSieve
server endpoint for your mail provider. Brev does not probe it in the
background. Later, if you choose "Sync to server" in Settings -> Rules,
Brev sends your account credentials and a generated Brev-owned Sieve
script derived from your compatible local rules to that configured
provider endpoint.

Brev writes only its own script name (`brev-rules`) through this path.
Local rules remain the fallback when no ManageSieve endpoint is
configured or when a local rule cannot be translated safely.

**How to disable:** Leave Server-side filters off during account setup,
or do not choose the sync action in Settings -> Rules. Defaults to off.

### Related-mail header discovery

If enabled: when you choose **Load related mail** on a conversation, Brev
asks that account's provider for other messages linked by reply
identifiers (Message-ID, In-Reply-To, References) across every eligible
folder in that mailbox — including folders not currently synced. IMAP
accounts send bounded `UID SEARCH HEADER` queries and fetch only message
metadata (envelope, flags, and References headers). Gmail accounts fetch
the native thread with metadata format only, plus at most one minimal
message lookup to resolve the thread when an older cache record lacks a
stored thread ID.

Only message headers are transferred. Bodies and attachments are never
downloaded by this feature, messages are never marked read, and nothing
is searched across other accounts. A per-account preference in
Settings -> Mailbox View can additionally allow the same lookup
automatically when you open a conversation; it defaults off.

**How to disable:** Do not choose Load related mail, and keep
"Automatically load related mail" off in Settings -> Mailbox View.
Removing the account revokes the consent.

### Apple Reminders task creation

If you choose **Create Task** from a message, Brev shows an editable
task draft first. If you create it in Apple Reminders, the task title,
notes, optional due date, sender, subject, preview text, and Brev
message link are saved to the local Reminders database through Apple's
system API.

Brev does not call Todoist, Asana, or any third-party task API. If you
sync Apple Reminders with iCloud or another account, that sync is
handled by Apple/system account settings, not by Brev.

**How to disable:** Do not choose the Create Task action, or deny
Reminders permission when macOS/iOS asks.

### Apple Calendar event creation

If you choose **Create Meeting from Message**, Brev shows an editable
event draft first. If you create it, the event title, start/end time,
attendees (sender + recipients), notes, and Brev message link are saved
to the local Calendar database through Apple's system API.

Brev does not become a calendar client: it does not sync or browse
calendars, and it does not write the event to any CalDAV server through
this action. If you sync Apple Calendar with iCloud or another account,
that sync is handled by Apple/system account settings, not by Brev.

**How to disable:** Do not choose the Create Meeting action, or deny
Calendar permission when macOS/iOS asks.

### Meeting-time suggestions

If enabled: Brev can suggest meeting times while you compose a message.
The current helper uses only locally stored working-hour and timezone
settings plus availability sources you explicitly enable in Settings.
Suggested times are inserted into the draft as normal editable text.
Brev does not send the draft automatically.

This feature does not contact Apple Calendar, CalDAV, task services, or
AI providers by default. Future calendar-account availability readers
must remain explicitly enabled before their data is consulted. If you
use AI separately to phrase the reply, that is covered by the AI Writer
rules below and requires explicit invocation. (Accepting a calendar
invite is a separate action that *can* write to CalDAV — see "Calendar
invite responses (CalDAV)" below.)

**How to disable:** Settings → Scheduling → "Suggest meeting times".
Defaults to off.

### OAuth account sign-in (Microsoft / Google)

If you add an Outlook/Microsoft or Gmail/Google account, Brev signs you
in using OAuth in a system web session. After you authenticate, Brev
exchanges the resulting authorization code with the provider's token
endpoint (`login.microsoftonline.com` for Microsoft, `oauth2.googleapis.com`
for Google) to obtain access and refresh tokens, and contacts the same
endpoint again when a token needs refreshing. The exchange uses PKCE;
Brev does not claim a confidential native-client secret. The macOS Google
Desktop client requires a Google-generated client credential in token and
refresh exchanges. That value can be recovered from a native app bundle, is
treated as a public identifier, and is not stored with your account data.
Security comes from PKCE, state validation, the exact loopback callback, user
consent, and Keychain-protected user tokens. The iOS client does not receive the
Desktop credential. For Google, Brev also
uses the resulting access token once with Google's OpenID UserInfo endpoint
(`openidconnect.googleapis.com`) to obtain the verified email and stable
account subject. The email in an unsigned token payload is never trusted.
Tokens are stored in the system Keychain, never in plaintext, and are never
sent anywhere except the provider.

On macOS, Google Desktop OAuth returns through an ephemeral HTTP listener bound
only to `127.0.0.1` on a random port. The listener exists only while you are
actively signing in, accepts the single OAuth callback, does not log the
authorization code, and closes immediately afterward. It is not reachable
from another device or network interface. Brev uses
`ASWebAuthenticationSession` for the system web session. On macOS, the system
asks your default browser to handle sign-in and falls back to Safari if needed.
On iOS, Brev passes Google's reversed-client-ID callback scheme to the session
and derives `<reversed-client-ID>:/oauth2redirect` when callback values are
empty. The non-ephemeral session may reuse system browser cookies for SSO, but
Brev cannot read those cookies. Cancelling stops the web session on both
platforms; only macOS also stops the loopback listener.

When you enable Calendar or Contacts on a Google account in
Settings → Calendar & Contacts, Brev runs the same user-initiated Google
authorization again, requesting the additional read-only scope for that
feature. The newly granted token replaces the stored one only when it
belongs to the same Google account and still covers mail access plus the
requested feature scopes; a declined or partial grant changes nothing.
No Google PIM data is synced yet — enablement only extends the grant.

Enabling Editing on a calendar source in Settings → Calendar & Contacts
lets Brev write events to that source: `PUT`/`DELETE` to the collection
URL for CalDAV, `events.insert`/`patch`/`delete` for Google Calendar.
Google sources re-run the authorization first so the `calendar.events`
scope is granted explicitly; a declined sheet leaves the source
read-only. Every mutation carries the stored ETag as an `If-Match`
precondition, so Brev never silently overwrites a newer server-side
change — a conflict asks you to sync first. Turning Editing off is
local-only: the provider grant remains but Brev stops issuing writes.
When an event has attendees, Google mutations send
`sendUpdates=all` so Google notifies invitees; CalDAV servers notify
per their own scheduling support. Brev itself never emails attendees.

Enabling Editing on a contacts source works the same way: CardDAV
sources write vCards with `PUT`/`DELETE` to the contact's
address URL, Google sources call the People API's
`people:createContact`/`updateContact`/`deleteContact`
after re-authorizing with the `contacts` scope. Updates carry the
stored etag precondition, CardDAV edits merge into the stored vCard so
fields Brev does not read are preserved, and Google edits are masked to
the fields Brev owns. Brev never modifies provider-side contact groups
or photos.

For a Gmail API account, Brev then contacts `gmail.googleapis.com` using the
Google access token. Gmail returns stable account-wide message and thread IDs,
label metadata, message content requested by the user or sync policy, and an
account `historyId` used for incremental synchronization. Brev stores a local
Gmail cache under Application Support so downloaded mail can open offline and
so one Gmail message is not duplicated for every label. The cache can contain
headers, bodies, raw source, attachment metadata, labels, and sync cursors, but
never OAuth access or refresh tokens.

Gmail compose drafts and staged attachment bytes are also stored locally in
that database until send/discard cleanup or account removal. They are separate
from the evictable message cache, so clearing downloaded mail or synchronizing
the mailbox does not delete unsent content. Staged attachments have a 25 MiB
aggregate limit per account. This local staging does not add a network call;
saving a Gmail draft still uploads its MIME content to Gmail as requested.

IMAP Send Later retains its scheduling intent locally as draft identifiers,
dates, attempt counts, and recovery reasons. Message content remains in the local
draft staging store. The Outbox keeps interrupted delivery and missing drafts
visible until you cancel or explicitly retry; cancellation retains recoverable
content. Account removal clears scheduling metadata. Time changes and cancellation
add no network request. Sending uses the account's existing SMTP connection.

Submitting Gmail Send Later stores a frozen draft, complete MIME content,
delivery time and attempt state in the same account-owned database. An in-process
poller checks submitted schedules every 30 seconds and uses the existing Gmail
send endpoint when due. It also checks on connection and during permitted app
refresh windows. It cannot deliver while Brev is fully quit. Rate-limit and
authentication failures may wait for retry; uncertain delivery requires explicit
review before another attempt. Canceling retains an editable local draft; account
removal clears the queue. Changing an autosaved draft does not itself schedule mail.

Gmail API access is on only after the user explicitly adds a Google account.
Removing the account clears its Keychain token, Gmail configuration, pending
provider work, and Brev-owned local Gmail cache. The standards-based IMAP/SMTP
fallback remains available as an explicit alternative.

Brev's installed macOS/iOS Gmail implementation uses local foreground,
background-refresh, and periodic Gmail history synchronization. It does not
register a Gmail Pub/Sub watch or send Gmail notifications through a
Brev-operated relay. A future hosted push path would require a separate privacy
and architecture decision before it is enabled.

**How to disable:** Don't add an OAuth-based account, or remove it via
Settings → Accounts. No OAuth network calls occur until you start adding
such an account.

### Provider policy metadata (future enterprise integrations)

If enabled in a future provider-native account backend: Brev may ask your mail
provider for mailbox policy metadata such as shared/delegated mailbox
permissions, Send As / Send on Behalf rights, retention policy names,
sensitivity labels, or admin-disabled feature states. This metadata goes only to
the provider that hosts the mailbox and is used to show supported, read-only, or
policy-disabled controls in Brev.

Generic IMAP/SMTP accounts do not expose this metadata, and this #260 scope work
does not add a new network call. Before any provider policy fetch ships, the
provider hosts, OAuth scopes, exact data sent, cache behavior, and user controls
must be documented here and in ADR-0006.

**How to disable:** Do not add or enable a provider-native enterprise account
integration. Standards-only IMAP/SMTP account setup does not fetch provider
policy metadata.

### Provider-backed workflow state (future provider integrations)

If enabled in a future provider-native account backend: Brev may read or write
workflow state through your mail provider, such as labels/categories, snooze
state, server signatures, server aliases, or shared-mailbox workflow metadata.
Those requests go only to the provider that hosts the mailbox and are used so
the same workflow state can appear on other clients/devices that support it.

Generic IMAP/SMTP accounts keep Brev's local-only fallback for these features.
This #261 scope work adds the local capability matrix and cleanup behavior; it
does not add provider workflow network calls. Before any provider-backed
workflow state sync ships, the concrete provider hosts, OAuth scopes, exact data
read/written, conflict behavior, and local cache behavior must be documented
here and in ADR-0006.

**How to disable:** Use a standards-only IMAP/SMTP account or keep the workflow
surface in local-only mode where Brev offers a choice.

### Contacts sync (CardDAV)

If enabled: for OAuth-based accounts with a built-in CardDAV profile,
Brev can start a CardDAV contacts sync after you add or restore the
account. For manually configured CardDAV sources, sync starts only when
you trigger it. Brev sends your account bearer token or configured
credentials and a CardDAV `REPORT` query to the provider principal URL
to read your address book.

**How to disable:** Don't add an OAuth account with a built-in CardDAV
profile, don't configure a CardDAV source, or remove the account/source.
Password and app-password IMAP accounts do not start CardDAV contact
sync.

### Calendar invite responses (CalDAV)

If enabled: when you accept (or decline) a calendar invitation and you
have configured a CalDAV target, Brev sends your credentials and the
response/event payload via an HTTPS `PUT` to the CalDAV collection URL
you configured. This is the only situation in which the calendar
features write to a remote server, and it never happens without a
configured target and an explicit invite action.

**How to disable:** Don't configure a CalDAV target. Without one,
accepting an invite stays local. Defaults to off.

### Calendar and contacts sources (CalDAV/CardDAV setup)

If enabled: when you connect a calendar or contacts source in Settings,
Brev first tries standards discovery — an unauthenticated HTTPS
`GET` to your address domain's `/.well-known/caldav` or
`/.well-known/carddav` — then validates the credential you entered by
sending it with a `PROPFIND current-user-principal` request to the
discovered or manually entered endpoint. Credentials are only ever sent
to the endpoint you chose: discovery redirects are followed hop-by-hop
and a credential-bearing request is never forwarded to a different host.
Credentials are stored only in Keychain; the source record keeps a
reference, never the secret. Setup traffic happens only during explicit
connect or reconnect — there is no background sync until you enable it
for the source.

When you connect a source or choose "Refresh Collections" on it, Brev
lists the calendars or address books the source exposes: for DAV
sources, the credential plus `PROPFIND` requests for the principal
home-set and a collection listing (names, colors, permissions, sync
hints); for Google sources you enabled on a mail account, the account's
OAuth token plus read-only `calendarList` or `contactGroups`
requests to Google. The results are cached on-device so the list stays
readable offline; hiding a collection is a local choice and never
contacts the provider.

When you choose "Sync Now" on a calendar source or enable its sync,
Brev reads events from the visible calendars only: for CalDAV sources,
the credential plus `REPORT` requests (`sync-collection`, or a
bounded `calendar-query` listing plus `calendar-multiget` fetches on
servers without sync tokens) to the collection URLs; for Google
sources, the account's OAuth token plus paged `events.list` reads.
Events are cached on-device under the source's data directory so they
stay readable offline; the cache stores each event's fields plus the
provider's original payload so provider-specific data survives
refreshes. Sync cursors live separately and are always deleted when the
source is removed. A failed collection keeps its last snapshot — one
unhealthy calendar never empties the others.

When you choose "Sync Now" on a contacts source or enable its sync,
Brev reads contacts from the visible address books only: for CardDAV
sources, the credential plus `REPORT` requests (`sync-collection`,
or an `addressbook-query` listing plus `addressbook-multiget`
fetches on servers without sync tokens); for Google sources, the
account's OAuth token plus a paged `people.connections.list` read.
Contacts are cached on-device under the source's data directory so
they stay readable offline; the cache stores each contact's fields
plus the provider's original payload so provider-specific data
survives refreshes. Photo URLs are stored as references only — Brev
never downloads contact photos during sync. Sync cursors live
separately and are always deleted when the source is removed. A failed
address book keeps its last snapshot — one unhealthy collection never
empties the others.

**How to disable:** Don't connect a calendar or contacts source.
Removing a source deletes its credential, sync cursors and unsent
drafts, and optionally its cached content; it never deletes data on the
provider. Defaults to off.

### Gravatar (sender avatars)

If enabled: Brev sends an SHA-256 hash of each sender's email
address to `gravatar.com` to fetch their avatar if one exists.
The hash is sent over HTTPS. Gravatar is operated by Automattic,
based in the United States.

**Why this is a real privacy event:** the hash identifies a specific
email address. Anyone with a list of email addresses can compute
their hashes, so a hashed lookup table is not anonymous. Automattic
sees which senders you receive email from, by IP, over time.

**How to disable:** Settings → Mailbox View → "Use Gravatar".
Defaults to off.

### BIMI (sender brand logos)

If enabled: Brev performs a DNS TXT lookup at
`default._bimi.<sender-domain>` for each sender. If a BIMI record
exists, Brev fetches the linked SVG logo. This means your DNS
resolver and the logo host can see that you received mail from that
domain.

**How to disable:** Settings → Mailbox View → "Use BIMI logos".
Defaults to off.

### Domain favicons

If enabled: Brev fetches `favicon.ico` (and similar) from sender
domains to display as a fallback avatar. The favicon server sees
your IP address and the time of fetch.

Brev fetches favicons during background sync, not when you open a
message — the sender's server cannot infer the moment you opened
their email.

**How to disable:** Settings → Mailbox View → "Use domain favicons".
Defaults to off.

### AI Writer and mailbox chat

If enabled: when you invoke AI Writer (compose helper), the text of
your draft or selected message is sent to the configured AI
provider.

Manual thread summaries use the same AI consent and destination label.
When you explicitly choose **Summarize Thread** in a loaded conversation,
Brev sends only that bounded thread context and the summary prompt to the
configured AI provider. Brev does not summarize mail in the background,
send notification content to AI, persist summaries as mailbox metadata,
or use summaries for training.

Mailbox chat Q&A uses the same consent and provider routing. When you
explicitly send a question from the AI Sidebar, Brev first runs a
cache-only sender-scoped local search, then sends only your typed question
plus a bounded set of cached matching message headers/snippets to the
configured AI provider. The first version caps this at 12 messages / 48 KiB
of cached context, treats received email content as untrusted prompt input,
and shows the destination label on each assistant answer. Brev does not run
mailbox chat in the background, widen the search to the server implicitly,
persist chat answers as mailbox metadata, or send transcripts to a Brev
service.

**AI provider choice**

AI features are off by default. When AI is enabled, every invocation in
Brev shows a label indicating where the content is being sent. Provider
options are entirely controlled by you: a compatible hosted API, self-hosted
endpoint, or same-device local model. Brev connects directly to the endpoint
you configure; it does not proxy AI requests, sell credits, meter token usage,
or silently select another provider. You'll never be in doubt about the
destination, whether you use compose help, thread summaries, or mailbox chat.

**How to disable:** Settings → AI → "Use AI Writer". Defaults to
off. You can also decline the first-use consent prompt in compose or
mailbox chat.

**BYOK / custom endpoints (OpenAI-compatible and Ollama/local)**

When BYOK is enabled and configured, AI requests go to your configured
endpoint only when you explicitly invoke an AI action. Saving, enabling, or
assigning a provider only updates local settings and Keychain state; it does
not test or contact the endpoint in the background.

- Network location can be a hosted provider such as OpenAI, or a local
  endpoint (for example `http://localhost:11434/v1` for Ollama).
- API keys (for hosted providers) are never sent to Brev; they are stored
  locally in the system Keychain and sent only to the endpoint you configure
  as an authorization header when needed.
- A ChatGPT subscription, browser session, and local developer-CLI credentials
  are never imported or reused as an AI-provider credential. Future provider
  OAuth or local CLI bridges require their own explicit, provider-supported
  flows.
- Local endpoints are still network calls from Brev to the configured
  host, but can avoid public-internet transit when they stay local.
- Brev cannot enforce the retention, training, or logging policy of a
  provider you configure. Review that provider's privacy policy before
  sending message content.
- Use HTTPS for hosted or remote endpoints. Same-device local endpoints such as
  Ollama may use `http://localhost`; another plaintext HTTP endpoint can expose
  message content and API keys on its network.
- BYOK/local providers can be turned off or removed per-account in
  **Settings → AI**.

### API keys and redaction

- BYOK API keys are stored in the OS Keychain (`Keychain` on macOS/iOS),
  never in `UserDefaults`, and never committed to git.
- Provider configuration metadata (names, endpoint URL, model ID, enabled
  state) is stored in local settings, not sent to our servers.
- The settings UI redacts API keys in all status and message output so
  key values are not mirrored into logs or text fields.
- Removing a BYOK/local provider also removes its stored API key from
  Keychain.

## Mail file import and export

Exporting a folder reads original messages from its owning mailbox. Cached
originals are used when available; missing originals may be downloaded from the
mail provider through the existing mail connection. Full-folder export requires
the provider connection to enumerate every page; it does not treat the end of a
partial offline cache as a complete folder. Exports are prepared in a
temporary replacement location and published only after all selected-folder
pages succeed. Brev attempts to remove unpublished temporary output when the
operation exits.

MBOX and EML files contain full messages and attachments. Brev does not add its
saved account passwords, OAuth tokens, or app settings to these files. The files are written to the location
you choose; if that location is managed by iCloud or another file provider, that
provider's own synchronization settings apply.

Import adds messages to the chosen mailbox. A provider-backed import can upload
the imported messages to that provider. Current import availability depends on
the account's importer support.

## Local mail folders

Brev can keep mail in local folders ("On My Mac" / "On My iPhone"), stored as
Maildir files under the app's Application Support directory — outside every
cache root. This data is not a cache: it is never evicted by retention sweeps,
never uploaded, and never sent anywhere. It persists until you delete a local
folder (which permanently removes its messages) or remove the app's data.
Creating, renaming, and deleting local folders and copying or moving mail into
them are macOS-only actions; on iOS local folders are read-only. When you copy
mail from a provider account into a local folder, the full message is read from
that provider and written locally; moving mail additionally deletes it from the
server through the same undoable path as a server-side move. Local folders are
indexed by the same on-device search index as cached mail.

## Keep Offline

Choosing **Keep Offline** in a message list, Unified Inbox, reader or conversation
menu records a device-local pin scoped to the message's account and mailbox. The
same action asks the configured mail backend for the message body; if it needs to
fetch that body, it uses the account's existing IMAP connection or Gmail API with
the account credentials/token and message identifiers. The request goes to your
mail provider. It does not enable remote HTML images or send content to an AI
provider. This fetch is initiated only when you turn Keep Offline on; removing
the pin does not initiate a body fetch or immediately delete cached content.
The prefetch is best-effort, so the pin alone does not prove the body is available
while disconnected.

## Brev backups

Settings › Import / Export can write a `.brevbackup` package — a folder
containing a manifest, your settings, and your account setup (names, email
addresses, and server hostnames/ports) — to a location you choose. Backups
never include passwords, OAuth tokens, Keychain references, or other
credentials; the manifest records `containsSecrets: false` and a SHA-256 hash
of each payload so a restore can detect tampering. Restored accounts are
parked under "Restored accounts — sign in to finish" until you sign in again.
When local folders exist, the backup preview offers to include them as
`mail/*.mbox` payloads (on by default); unlike the settings payload, those
files contain full messages and attachments. The file is written where you
choose; if that location is managed by iCloud or another file provider, that
provider's own synchronization settings apply.

## What data does *not* leave your device, ever

- **Usage analytics, screen-view counts, button-click counts, time-
  in-app.** Brev contains no analytics libraries. Verifiable.
- **Crash reports.** No automatic crash reporting. If you want to
  send a crash report, you choose to do so manually by attaching
  the local log file to a GitHub issue. Apple's system-level crash
  reporting (which you can opt out of in macOS Settings → Privacy
  → Analytics) is outside Brev's control.
- **Your contacts.** When you allow Contacts access, Brev reads local
  macOS/iOS Contacts to display saved photos and suggest recipients while
  composing. It never uploads, creates, edits, or merges Apple Contacts. The
  synthetic demo mailbox never requests or reads Contacts, including when
  access was granted during an earlier real-mailbox run.
- **Recent recipients.** Brev keeps a separate, local-only list of addresses
  learned from already-cached correspondence and successful sends. It is never
  added to Apple Contacts, never uploaded, and can be removed individually or
  cleared from Settings → Compose.
- **Gmail search.** Cached-only queries remain on this device, including when
  disconnected. Auto search previews one local page before sending the query to
  Gmail. Online results arrive in bounded pages and may use full-message reads
  for uncached matches; search does not call the attachment-download endpoint or
  persist newly fetched search-only data. Opening a result may fetch it again.
- **Search coverage.** Explicit online IMAP searches check all server result
  pages, even when there are cached matches. Ordinary queries retrieve headers;
  attachment predicates may retrieve message sources under ADR-0060. Cache-only
  searches and sender context remain local. Broad searches can take longer and
  transfer more headers than the previously truncated results. Search progress
  distinguishes cached results from completed server coverage; interrupted
  searches retain partial results with an incomplete-search notice. Both searches
  with and without attachments disclose possible source downloads.
- **Attachment content indexing.** Off by default and opt-in per account under
  Settings → Folder Sync. When enabled, Brev extracts text locally — on this
  device, with no network call — from attachments already present in the local
  cache, and stores the text in the local SQLite index so message search can
  match it. Indexing never downloads a message or attachment for that purpose;
  uncached content is skipped. Inputs are limited to 25 MB, extracted text is
  truncated at 512 KB, and supported formats are plain text, CSV/Markdown,
  RTF, HTML, and PDF. Office documents are not indexed, and HTML text is
  extracted without loading any remote content the page references. Inline
  attachments are skipped.
  Turning the toggle off — or choosing Remove under Mail Storage — deletes
  every indexed attachment row for that account. Diagnostics record counts,
  byte totals, and durations only: never filenames, subjects, addresses, or
  content. The setting is per-device and is not included in `.brevbackup`
  exports.
- **Search terms, draft contents, attachments.** Stay on your
  device unless you use mail-provider features that require them:
  server-side search, saving drafts, uploading attachments, or
  sending mail. You can also export messages and attachments to a location
  you choose, including a location managed by a file-sync provider.

## Where Brev stores data

- **Account credentials:** macOS or iOS Keychain. Encrypted by the
  system. Never in logs.
- **Mail cache, drafts, settings:** local SQLite/Realm databases in
  the app's container, governed by macOS/iOS file protection.
- **Legacy provider cache snapshots:** quarantined provider adapters may
  keep local JSON cache files in Application Support while they remain
  in the repository as reference code. These caches contain mailbox
  metadata and previously fetched message content only; they do not
  store OAuth secrets, passwords, refresh tokens, or API keys.
- **Avatar cache:** in-memory cache for the current app session plus
  local SQLite cache in the app's Caches directory. You can clear it
  from Settings → Mailbox View → "Clear cached avatars."
- **Logs:** local file at `~/Library/Logs/Brev/brev.log` (macOS)
  or app container (iOS). Never transmitted.

## Your rights under GDPR

- **Right of access / portability:** Brev stores no data about you
  server-side. Your mail data is held by your selected mail provider
  under their policy. Your local data is in the app's container and is
  exported on request to `privacy@brevmail.eu`.
- **Right to erasure:** Uninstall Brev. Your local data is removed.
  Mail on your provider's servers is subject to their policy.
- **Right to rectification:** Settings allows editing all locally-
  stored data. For mail-server data, contact your mail provider.
- **Right to lodge a complaint:** With your national data
  protection authority. In Norway, the Datatilsynet.

## Contact

`privacy@brevmail.eu` for any data subject rights request or
privacy question.

For bug reports that mention privacy, please redact email addresses,
message content, or any other sensitive material before attaching
log files to GitHub issues. The issue tracker is public.

## App Store distribution

When Brev is distributed via the Mac App Store or iOS App Store,
Apple's standard data collection on installations and updates
applies. This is outside Brev's control. See Apple's privacy
documentation.

## Children

Brev does not target users under 16. Brev has no sign-up of its own;
you authenticate against your mail provider, whose terms apply.

## Changes to this policy

This policy is versioned in the Brev source repository. Material
changes will be reflected in CHANGELOG.md and announced in release
notes. The current version of this document lives at
[`brevmail.eu/privacy`](https://brevmail.eu/privacy) and at
[`PRIVACY.md` in the repository](https://github.com/henrikogaard/brev/blob/main/PRIVACY.md).

---

**Data controller:** Henrik Ø. Gaard, Stavanger, Norway.
**Contact:** `privacy@brevmail.eu`.
**Effective from:** the date of the first public Brev release.
