# ADR-0003: Sender avatar resolution

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Apple Mail's lack of sender avatars is a major Mac-mail-client
frustration and one of Brev's stated motivations. A modern mail client
shows an avatar next to every message. Done well, it's a real
recognition aid; done naively, it's a privacy disaster.

The problem is harder than it looks:

- No single source covers every sender. Individuals are on Gravatar;
  companies publish BIMI; small businesses publish neither but have a
  favicon; the long tail has nothing.
- Every external lookup is a privacy event. Naive Gravatar/favicon
  queries leak the user's reading patterns and contact graph to third
  parties — a real concern for a GDPR-positioned product.
- Sources have different latencies, hit rates, quality. A cascade
  with caching is required.

## Decision

### Resolution cascade

For each unique sender (keyed by lowercased email address), Brev walks
this cascade and stops at the first hit:

1. **System contacts.** `CNContactStore` lookup. If the sender is in
   the user's macOS or iOS Contacts and has a photo, use it. Highest
   quality — the user chose this photo for this person.
2. **Local avatar cache.** SQLite-backed cache keyed by lowercased
   email plus the avatar preference set that decides source
   eligibility. Hit returns immediately; entries have per-source TTL.
   Including the preference set prevents initials cached while
   external sources are off from masking a later explicit opt-in.
3. **BIMI** *(opt-in, off by default)*. DNS TXT lookup at
   `default._bimi.<sender-domain>`. If present, parse for `l=` (logo
   URL) and fetch the SVG. v1 does not validate the optional VMC/CMC
   certificate (see Risks). Cache TTL: 7 days.
4. **Gravatar** *(opt-in, off by default)*. SHA-256 of lowercased
   email → `https://gravatar.com/avatar/<hash>?d=404&s=128`. The
   `d=404` returns 404 when no avatar exists, letting us fall through.
   Cache TTL: 30 days.
5. **Domain favicon** *(opt-in, off by default)*. Sequential attempts
   on the sender's domain: `apple-touch-icon.png`, `favicon.ico`,
   `www.<domain>/favicon.ico`. First 200 with a valid image wins.
   Public/free-mail provider domains such as `gmail.com` and
   `yahoo.com` are excluded from this fallback. Cache TTL: 30 days.
   Negative cache: 7 days.
6. **Generated initials.** Initials from display name or local-part,
   rendered on a colored circle. Color is `hash(email) %
   avatarPalette.count` from the active theme. Deterministic mapping
   means the same sender always gets the same color across sessions
   and devices.

Steps 1, 2, 6 are local. Steps 3, 4, 5 are network calls, gated by
explicit user opt-in.

### First-run onboarding

On first launch, a privacy panel explains the avatar system and offers
toggles for Gravatar, BIMI, and favicon fetching. All three default
**off**. The user must make an informed choice. The panel explains
plainly what each option does and what data each shares.

This is a deliberate trade-off: defaults-off means new users see
initials-only out of the box, which is less visually impressive than
Gravatar-enabled. We accept this hit to brand-impression in exchange
for the strongest GDPR posture and zero surprise network traffic on
first run. Per ADR-0006, this matches the broader Brev approach: no
external lookups happen until the user says so.

### Cache

Single SQLite table at `~/Library/Caches/Brev/avatars.sqlite`
(macOS) or the iOS Caches directory:

```sql
CREATE TABLE sender_avatar (
    email             TEXT NOT NULL,       -- lowercased
    preference_key    TEXT NOT NULL,       -- avatar source toggles
    source            TEXT NOT NULL,       -- "contacts" | "gravatar" | "bimi" | "favicon" | "initials" | "none"
    image_data        BLOB,                -- PNG/SVG bytes, or NULL for negative cache
    fetched_at        INTEGER NOT NULL,    -- unix timestamp
    expires_at        INTEGER NOT NULL,
    etag              TEXT,                -- for HTTP conditional refresh
    PRIMARY KEY (email, preference_key)
);
```

User-clearable via Settings → Privacy:

- **Clear avatar cache** — wipes all entries.
- **Refresh avatars** — wipes negative cache entries, forces re-
  resolution of senders without avatars.

### Fetch timing

External fetches run **during background sync, not on message open.**
Two reasons:

- Decouples avatar fetch timing from user reading behavior. A sender's
  webserver can't infer "this user just opened my email" from a
  favicon fetch.
- Avatars are ready before the user opens a message — no flash of
  initials replaced by logo.

A background queue throttles concurrent fetches (max 4 parallel) and
respects exponential backoff on failures.

### Privacy controls

Each external source is independently togglable in Settings → Privacy
on both platforms:

- **Use Contacts photos** (default: on, requires Contacts permission)
- **Use Gravatar** (default: off, tooltip explains hash flow to
  Automattic)
- **Use BIMI logos** (default: off, tooltip explains DNS lookup)
- **Use domain favicons** (default: off, tooltip explains favicon
  fetch reveals IP to sender's domain)
- **Initials only** (master toggle, disables 3-5 in one click)

### Avatar shape

Circle, 24pt (compact list rows) or 36pt (expanded list rows / thread
header). For BIMI logos, which arrive as SVG, render at logical size
with no background fill — many BIMI logos are designed for square
display and need padding when circle-cropped. We add 4pt padding inside
the circle and a 0.5pt theme.border ring around the avatar.

## Rationale

**Why defaults-off on Gravatar.** Per Henrik's direction. Gravatar
hashes are technically pseudonymous but a precomputed rainbow table
of common email addresses defeats this trivially. Sending hashes of
every sender's address to Automattic is a real data flow that GDPR
considers personal data processing. Better to make it explicit opt-in.

**Why eager favicon fetch during sync.** Lazy fetch on message open
correlates the favicon request timing with user behavior — the
sender's logs show "this IP fetched favicon at 14:32:17" matching
exactly when their email was opened. Eager fetch during sync breaks
this correlation; the favicon was fetched some time after delivery,
not specifically on open.

**Why no VMC/CMC validation at v1.** Certificate validation adds X.509
parsing, trust chain verification, and OCSP checks for marginal user
benefit. Brev shows logos as a UI aid; actual authentication relies on
the user's MTA (SPF/DKIM/DMARC), not BIMI's logo provenance. Revisit
in v2 if it becomes important.

**Why hash-based avatar coloring instead of random.** Stability across
sessions and devices, no state to sync.

## Consequences

### Accepted

- Defaults-off means brand-impression hit on first run. We document
  this in the welcome screen and trust users to make the right call.
- Cache grows over time. ~5KB per cached avatar × thousands of senders
  = a few hundred MB over years. SQLite handles this. "Clear avatar
  cache" exists in Settings.
- BIMI without VMC validation means a sophisticated attacker who
  successfully forges DMARC could display a spoofed logo. Documented
  in PRIVACY.md as a known limit. The user's real trust signal
  remains MTA authentication checks.
- We do not run a privacy proxy in v1. Users wanting one route through
  their own setup (system proxy, Little Snitch). A hosted proxy is a
  v2+ infrastructure question.

### Risks

- **Favicon scraping leaks reading habits to senders.** Mitigated by
  defaults-off, per-source toggle, and eager-during-sync fetch
  timing. Not eliminated.
- **Gravatar leaks contact graph to Automattic.** Same mitigation;
  also defaults-off.
- **DNS leaks for BIMI.** Smaller leak than HTTP fetch. User's MTA
  already does sender-domain DNS lookups during inbound mail
  processing. Marginal additional exposure.

## Future work

- v2: optional self-hostable avatar proxy doing external fetches on
  the user's behalf, returning privacy-cleaned images. Real
  infrastructure project; not v1.
- v2: explore Apple Business Connect for branded mail on iOS.

## References

- ADR-0028: Project identity and scope
- ADR-0002: Theme system (provides `avatarPalette`)
- ADR-0006: Telemetry and GDPR compliance
- BIMI: https://bimigroup.org/
- Gravatar API: https://docs.gravatar.com/api/avatars/
