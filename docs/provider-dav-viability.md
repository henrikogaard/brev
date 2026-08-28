# DAV provider discovery

Status as of 2026-08-27.

`CalDAVDiscovery.discover(for:)` is the local, network-free endpoint builder for
CalDAV and CardDAV. A valid mail domain produces the RFC 6764 well-known URLs on
that domain. Invalid addresses return manual discovery with no endpoints.

Brev has no provider-specific DAV profile or local viability classification.
The well-known URLs are candidates, not proof that the server supports DAV or
accepts the account's credential. Live verification belongs to the explicit
sync operation that uses those endpoints.

`AppSession` installs the CardDAV contact lookup adapter and starts the first
sync only when the backend exposes a CardDAV email address and a current OAuth
bearer token. Password and app-password IMAP accounts do not start CardDAV
sync. A future provider adapter may supply its own verified contact integration
through the same backend extension seam without adding a domain branch to
`CalDAVDiscovery`.
