# ADR-0019: Message flag colors and provider-agnostic tagging

- **Status:** Proposed
- **Date:** 2026-05-30
- **Deciders:** Henrik

## Context

The desktop message list offers a flag affordance, and the design
mockups show a colored-flag picker (orange, red, purple, blue, yellow,
green, gray) modeled on Apple Mail's seven-color palette. We need to
decide how a flag *color* is stored and synced so the feature behaves
identically regardless of provider.

The constraint is that "flag color" is not a mail standard. Surveying
the three provider classes Brev targets:

- **IMAP** exposes one boolean system flag (`\Flagged`). Colors are not
  part of the protocol. Arbitrary per-message *keywords* are available
  only when the server advertises `\*` in `PERMANENTFLAGS`. Apple Mail
  encodes its color as a 3-bit value across the keywords
  `$MailFlagBit0`, `$MailFlagBit1`, `$MailFlagBit2`.
- **JMAP** (RFC 8621) models `keywords` as a first-class
  `String → Boolean` map on every Email; custom keywords are standard.
- **provider API** exposes only `flagged: Bool`
  (`ProviderHTTP/.../DTOs.swift` `MessageDTO.flagged`,
  `previous backend/.../Message.swift`). No keyword, label, or color field is
  surfaced anywhere in its message payload.

So the protocol floor across providers is a single boolean, the ceiling
(IMAP/JMAP keywords) is a `String → Bool` set, and **color is a client
concern on every provider** — no server stores it. This is the same
shape the codebase already anticipates: `BackendCapabilities.labels`
exists, and `BackendFeatureSupportKind` already has `localOnly` /
`readOnly` states for exactly this kind of uneven provider support
(ADR-0028 invariant 2: capability-driven UI, never backend type checks).

## Decision

1. Model flag color as a provider-agnostic semantic identity, not a
   rendered color. Add `FlagColor` to `BrevBackend` — a seven-case
   enum matching the Apple-compatible palette. The backend layer imports
   no UI; `BrevDesign`/`BrevThemes` own the mapping from `FlagColor` to
   an actual theme-aware swatch (ADR-0028 invariant 1).

2. Carry the color on the list model: add
   `MessageHeader.flagColor: FlagColor?`. A non-nil color implies the
   message is flagged; clearing the color (`nil`) does not by itself
   clear `isFlagged`.

3. Extend `MailBackend` with a capability-gated operation:
   - `setFlagColor(_:for:)` and its source-scoped variant.
   Default implementations throw `.notSupported(.flagColors)` so
   existing backends keep compiling.

4. Add `BackendCapabilities.flagColors` and a `BackendFeature.flagColors`
   support entry so call sites gate on capability and surface an honest
   per-provider state:
   - **JMAP / IMAP with custom-keyword support** → `supported`. Color
     round-trips as Apple-compatible `$MailFlagBit0..2` keywords.
   - **IMAP without custom keywords** → `readOnly` (read any existing
     Apple flags, cannot write).
   - **the provider** → `localOnly`. The boolean `flagged` still
     round-trips to the provider; the *color identity* lives in Brev's
     local store and syncs across the user's devices through Brev's own
     mechanism, not the mail server.

5. Choose **Apple-compatible keyword encoding** for the on-wire scheme
   (`$MailFlagBit0..2`). This makes colors round-trip into Apple Mail
   and Fastmail, at the cost of capping at seven colors and one color
   per message — which matches the mockup exactly.

6. The exact ordinal-to-color bit mapping in the Apple scheme is
   reverse-engineered, not specified. The `FlagColor` raw value is
   **Brev's own stable persistence key**, deliberately decoupled from
   the Apple bit values. The IMAP/JMAP keyword encoder (future work)
   must carry an explicit mapping table verified against a live Apple
   Mail mailbox before it ships; a wrong table silently mis-maps colors.
   the provider (`localOnly`) does not depend on this mapping.

## Rationale

**Why a semantic enum, not a color or a free-form label.** Keeping the
backend color-agnostic preserves ADR-0028 invariant 1 (no UI types below
the view layer) and lets themes recolor flags. Seven fixed cases match
the mockup and the Apple interop target; a free-form label system is a
larger feature (multi-label per message, label management UI) that this
ADR deliberately does not open.

**Why Apple-compatible keywords over a private `$brev_*` scheme.**
Round-tripping into Apple Mail / Fastmail is worth more to a personal
mail client than unlimited custom labels. The mockup is already Apple's
exact palette, so the cap costs nothing here.

**Why `localOnly` for the provider instead of dropping color there.**
The whole point is identical UX across providers. `localOnly` lets the
color render the same everywhere; the only difference is propagation to
the provider's own webmail, which the support string states plainly.

**Alternatives considered.**

1. Private `$brev_*` keyword scheme — rejected: loses cross-client color
   interop for a multi-label capability we are not building.
2. Store color only where the server supports keywords, none on
   the provider — rejected: breaks identical-UX goal.
3. Treat color as a folder/label (reuse the `labels` capability)
   — rejected: flags and folders are distinct affordances; conflating
   them complicates the list model and the picker.

## Consequences

### Accepted

- Flag color is a first-class, capability-gated, provider-agnostic
  concept. The picker and list rendering branch on `.flagColors` /
  `BackendFeature.flagColors`, never on concrete backend type.
- On the provider today, colors render identically and sync across the
  user's devices via Brev, but do not appear in the provider webmail.
- A future IMAP/JMAP backend round-trips colors with Apple Mail.

### Risks

- **Apple bit-mapping risk:** the reverse-engineered ordinal table can
  be wrong. Mitigation: decouple `FlagColor.rawValue` from the wire
  encoding; require empirical verification before the encoder ships.
- **Local-store divergence risk:** Brev's local color store can drift
  from the provider's boolean flag (e.g. a message unflagged in
  webmail). Mitigation: treat the provider boolean as authoritative for
  *flagged-ness*, and reconcile color to `nil` when `flagged` is false
  on sync.
- **Capability drift risk:** future backends may forget to declare
  `.flagColors`. Mitigation: backend feature-surface tests.

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0028: Roadmap/invariants (invariants 1 and 2)
- ADR-0066 / ADR-0066: JMAP and v2 provider roadmap
- ADR-0018: Folder mutation capabilities (same capability-gating pattern)
- RFC 8621 §4.1.1 (JMAP Email `keywords`)
- RFC 3501 §2.3.2 / §6.4.6 (IMAP keywords, `PERMANENTFLAGS`)
