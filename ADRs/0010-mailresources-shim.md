# ADR-0010: MailResources compatibility shim

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

ADR-0028 vendors `previous backend/{API,Cache,Models,Utils,ViewModel}/` and
discards `MailResources/`, the target containing localized strings,
asset catalogs, and (notably) provider-branded illustrations like
the provider-hosted AI AI mascot. Brev intentionally defines its own resources via
`BrevDesign` and the themes system (ADR-0002, ADR-0004).

The practical problem this creates: 41 previous backend source files
reference `MailResources` types — 197 `MailResourcesStrings.Localizable.*`
accesses, 163 `MailResourcesAsset.*` accesses, plus
`MailResourcesImages`, `MailResourcesColors`, and `MailResourcesResources.bundle`.
Without something providing those symbols, `previous backend package/` does
not compile, which blocks the rest of the v1 scaffold.

Three options were considered:

1. **previous package `MailResources/` verbatim.** Pull the entire asset catalog,
   strings files, and (via Tuist resource generation) the synthesized
   Swift bindings into Brev. Lowest near-term effort, but ships
   the provider's "provider-hosted AI" branding inside Brev binaries — a brand
   collision we don't want — and contradicts ADR-0028's "Brev defines
   its own resources" boundary.

2. **Strip and refactor in place.** Replace every `MailResourcesStrings.*`
   / `MailResourcesAsset.*` reference in the retired source with a
   Brev equivalent. Cleanest end state, but produces a huge per-file
   diff against provider, making cherry-picks much harder to read and
   apply.

3. **Compatibility shim.** Provide a thin `MailResources` module
   inside `previous backend package/` that exposes the API surface existing
   code expects, with all values returning placeholders (raw keys for
   strings, neutral SF Symbols / gray colors for assets). retired
   files remain byte-identical apart from the
   telemetry-strip breadcrumbs. Real strings and assets are filled in
   by `BrevDesign` and the themes system over time.

## Decision

Implement option 3. A `MailResources` target lives in
`previous backend package/Sources/MailResources/` and is depended on by the
`previous backend` target. It declares:

- `MailResourcesStrings.Localizable` — `@dynamicMemberLookup` returning
  the key string verbatim. Twelve known parametric strings (e.g.
  `snackbarThreadMoved(_:)`) are declared as explicit static methods
  so call-site argument types resolve correctly.
- `MailResourcesAsset` — `@dynamicMemberLookup` returning an
  `MRImageAsset` value with `.image`, `.swiftUIImage`, `.color`,
  `.swiftUIColor` placeholders.
- `MailResourcesImages` — alias of `MailResourcesAsset` for the
  existing call sites that use that name.
- `MailResourcesColors` — alias likewise.
- `MailResourcesResources.bundle` — wrapper exposing `.load(_:)` and
  `.loadCSS(_:)` returning empty strings (the few call sites all
  load static helper CSS that's safe to be empty during scaffold).

The shim is **not** a permanent product. Three intended exits:

- As `BrevDesign` and `BrevThemes` grow real APIs, individual
  retired-previous backend call sites get refactored to route through Brev
  types. Each such migration is a per-call-site PR with PATCHES.md
  entries documenting the divergence.
- When the migration is complete (no previous backend file references
  `MailResources*` anymore), the shim is deleted.
- The shim never gains real string tables or asset bundles. If a
  scaffold-stage build genuinely needs a real string visible to the
  user, it goes into Brev's localization via `BrevDesign`, not into
  the shim.

The shim source file carries a Brev MIT header (not an the provider
one) because no source code is copied into it — it implements the
API surface from scratch using `@dynamicMemberLookup`.

## Rationale

**Why not option 1.** Vendoring `MailResources/` would pull in
provider-branded illustrations (provider-hosted AI AI mascot, accent-color
palettes named for the provider's product line, navbar gradients
matching provider app's identity) into Brev's binary. We'd then need to
strip them anyway to ship Brev. The shim defers and minimizes that
work.

**Why not option 2.** A per-call-site refactor in v1 scaffold ships
hundreds of edits to retired files before we have working app
shells. Cherry-pick legibility is a real, recurring cost (ADR-0028,
ADR-0005). The shim keeps the diff narrow.

**Why `@dynamicMemberLookup` instead of generated stubs.** Resource
generation would ordinarily produce these declarations via Tuist's
pass on asset catalogs and `.strings` files. Replicating that locally
requires either re-vendoring the asset catalog (option 1) or running
SwiftGen on a hand-curated input set. `@dynamicMemberLookup` is one
file, ~80 lines, and any new identifier added in a future cherry-pick
resolves automatically without us regenerating anything.

**Why the shim is inside `previous backend package/`, not a sibling
package.** The shim has no lifetime separate from the retired
previous backend. When previous backend migrates fully to Brev resources, the shim
deletes with it. Keeping it co-located makes the audit trail
unambiguous and prevents accidental dependencies from outside
previous backend.

## Consequences

### Accepted

- All user-visible strings and assets in the v1 scaffold come back as
  raw identifier keys (e.g. the literal string `"actionReply"` shows
  up where provider would have shown localized "Reply"). This is fine
  because no v1 scaffold view actually surfaces these — apps render
  only the "Brev" placeholder until views start landing.
- `BrevDesign` and the upcoming Brev localization layer are the
  long-term home for these strings and assets. The shim is a temporary
  bridge.
- An ADR-required PR will accompany the eventual shim deletion (it's
  a public-API change to a protected path per ADR-0005).

### Risks

- **Hidden runtime bugs.** A retired code path might key off a
  specific string value (`if title == "Reply" {…}`). Such call sites
  would silently miscompare with raw-key fallback strings. Mitigation:
  spot-check during view-layer work; treat any string equality check
  inside previous backend as a refactor candidate.
- **Drift between provider additions and shim coverage.** If provider
  adds a new parametric string, the shim's `@dynamicMemberLookup`
  returns a `String`, but the call site expects a callable. This
  surfaces as a compile error at cherry-pick time and is fixed by
  adding a static method to the shim. Acceptable.

## References

- ADR-0028: Mail client view layer rewrite (Brev defines its own resources)
- ADR-0002: Theme system
- ADR-0004: Build system and project layout
- ADR-0005: Enforcement (protected paths; cherry-pick protocol)
- ADR-0028: Roadmap and invariants (invariant 1: views never see
  the provider types)
- `previous backend package/Sources/MailResources/MailResources.swift`
- `previous backend package/PATCHES.md` (running audit of divergence)
