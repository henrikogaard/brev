# ADR-0092: Opt-in content permissions for isolated mock QA

- **Status:** Accepted
- **Date:** 2026-11-02
- **Deciders:** Henrik (explicitly approved networking and file-picker read access for mock testing)

## Context

ADR-0091's sandbox-only profile protects existing data and denies outbound
connections. It also prevents native WebKit body and attachment-picker
acceptance. These are QA-profile restrictions, not demonstrated shipping bugs.
The maintainer approved both permissions for a separate UUID-only mock run.

## Decision

Add `--isolated-mock-content-qa` to the local build script. It implies all
`--isolated-mock` guards, but selects an explicit `content-qa` bundle marker
and an exact three-key signing profile:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true`
- `com.apple.security.files.user-selected.read-only = true`

The ordinary isolated flag remains sandbox-only. Neither ambient environment
variables nor runtime preferences select the expanded profile. Stamp the
profile into the signed bundle; build verification and startup must require
the matching exact entitlement set. Missing profile markers mean the legacy
strict profile; unknown markers or mismatched permissions fail closed.

All existing UUID, Debug-only, mock-only, private-container, no-App-Group and
no-extension guards remain. Shipping, normal test and release entitlements
are unchanged. Existing signed QA artifacts must not be modified in place.

## Rationale

- An explicit profile preserves the useful no-outbound-network default instead
  of silently adding permissions to every isolated build.
- Requiring both the signed profile marker and exact permissions avoids a
  permissive union of entitlement sets and rejects unintended extra access.
- A separately selected profile is repeatable; manually re-signing a retained
  artifact would undermine its identity and earlier evidence.

## Consequences

### Accepted

- The content-QA app no longer has an OS-level outbound-network prohibition.
  Mock accounts and existing remote-message-content blocking remain enabled;
  this permission is not authorization to contact live providers or load
  external message resources.
- The native picker may grant read access only to explicitly selected files.
  QA uses generated fixture files, not personal documents.
- This authorizes QA setup, not body/attachment, snapshot or release acceptance.

### Risks

Network permission applies to the app, not exclusively to WebKit. Document
the weaker boundary and inspect the actual signature before launch. Preserve
the strict profile and negative tests for mixed profiles, shared groups,
write access, live/release modes and invalid identities. Disk cleanup remains
a separate authorization decision.

## References

- [ADR-0091](0091-isolated-macos-mock-validation.md) — strict default retained.
- [ADR-0006](0006-telemetry-and-privacy.md) — explicit network intent.
- [ADR-0028](0028-mail-provider-architecture.md) — provider-neutral rendering.
- `script/build_and_run.sh` and `IsolatedMockConfiguration` — paired guards.
