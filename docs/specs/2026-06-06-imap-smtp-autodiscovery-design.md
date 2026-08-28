# IMAP/SMTP Autodiscovery Design

## Goal

Add account-setup autodiscovery for standards-first IMAP/SMTP without
resetting the existing Brev product behavior. The first slice provides a
backend-neutral configuration contract that UI and future network probes can
use safely.

## Scope

- Replace the OAuth-only discovery model with provider-neutral account
  settings that can describe password/app-password and XOAUTH2 accounts.
- Preserve the existing `IMAPConfiguration` and `SMTPConfiguration` value
  types while the new account setup UI is built.
- Add deterministic discovery from built-in provider profiles.
- Add privacy-aware probe planning for DNS SRV and provider-local HTTPS
  autoconfig URLs.
- Add a Thunderbird/Mozilla `config-v1.1.xml` parser for IMAP and SMTP
  server settings.
- Add an async resolver contract that runs the ordered strategy through
  injected HTTPS and SRV loaders, so tests stay deterministic and the UI can
  wire live networking later.

## Non-Goals

- No live DNS or URLSession probing in this slice.
- No Exchange Autodiscover XML implementation in this slice.
- No account-setup UI in this slice.
- No credential validation or mailbox login in this slice.

## Architecture

`BrevBackend` owns the discovery data model because it is provider-neutral
and needed by both macOS and iOS. A new `MailAccountAutodiscovery` type
returns a `MailAccountDiscoveryResult` containing incoming and outgoing
server settings, source metadata, and whether the result still needs manual
review.

Discovery is layered:

1. Built-in provider profile lookup for common domains.
2. RFC 6186 SRV query plan for `_imaps`, `_imap`, `_submission`, and
   `_submissions`.
3. HTTPS autoconfig probe plan for provider-hosted Thunderbird-style XML.
4. Manual fallback suggestions using `imap.<domain>` and `smtp.<domain>`.

Live networking remains outside the pure model. UI code runs the resolver
after the user explicitly starts account setup; injected loaders keep DNS and
HTTPS behavior deterministic in tests.

The resolver is the future account-setup entry point: it checks built-in
profiles first, then checks DNS SRV. The SRV queries are started together so
missing service records do not serialize DNS timeouts. A complete SRV result
avoids the provider-local HTTPS autoconfig probes that disclose the full email
address.
When DNS is incomplete, the resolver may continue to provider-local
autoconfig XML. If discovery still has only one side, manual fallback fills the
missing IMAP or SMTP settings before the setup UI presents editable fields.

When a provider autoconfig response lists multiple secure servers for the same
side, discovery prefers a currently provisionable password/app-password entry
over OAuth2 or encrypted-password alternatives until those auth flows exist.

SRV records with a root target are treated as an explicit unavailable-service
marker and are ignored instead of becoming empty editable hostnames.

## Privacy

Autodiscovery starts only after a user enters an email address and chooses to
continue account setup. DNS SRV probes use the domain only. Thunderbird-style
HTTPS URLs can include the full email address; the probe plan marks those
requests so the UI can disclose that before sending them, and the resolver
does not send them when DNS SRV already returned complete server settings.

## Testing

Swift Testing coverage starts with:

- Built-in Gmail/Outlook/Fastmail/iCloud/Yahoo profile lookup.
- Domain normalization and fallback suggestions.
- Probe planning that distinguishes domain-only DNS probes from HTTPS probes
  that include the full email address.
- Thunderbird autoconfig XML parsing for IMAP and SMTP settings.
- Codable and default-value checks for the IMAP/SMTP configuration value types.
