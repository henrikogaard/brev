# ADR-0018: Folder mutation capabilities and sidebar context actions

- **Status:** Proposed
- **Date:** 2026-05-30
- **Deciders:** Henrik

## Context

Desktop users expect folder operations from a contextual secondary-click
menu in the mailbox sidebar: create subfolder, rename, delete, and
empty trash/spam. Brev already has message-level context menus and
capability-gated command surfaces, but folder-level mutation support was
incomplete:

- `MailBackend` had no explicit folder mutation contract.
- Backend capability flags did not distinguish folder-create/rename/
  delete/flush support.
- The sidebar had no right-click folder action surface.
- Multi-source desktop routing needed source-scoped folder mutation
  calls to avoid mailbox/account ambiguity.

ADR-0028 invariant 2 requires capability-driven UI. Folder actions
cannot be gated by backend concrete type checks.

## Decision

1. Add folder mutation capabilities to `BackendCapabilities`:
   - `folderCreate`
   - `folderRename`
   - `folderDelete`
   - `folderFlush`
2. Extend `MailBackend` with folder mutation operations:
   - `createFolder(name:parentID:)`
   - `renameFolder(id:name:)`
   - `deleteFolder(id:)`
   - `flushFolder(id:)`
   plus source-scoped variants for multi-source routing.
3. Implement these operations for shipped backends:
   - `MockBackend` (preview/demo/test surface)
   - `ProviderHTTPBackend` (live provider path)
4. Add folder-row context actions in `FolderSidebar`:
   - `New Subfolder...`
   - `Rename Folder...`
   - `Delete Folder`
   - `Empty Trash` / `Delete Junk Mail` (role-specific flush)
   - `Refresh`
5. Gate context actions through capabilities and folder role rules:
   - Create: requires `folderCreate`
   - Rename/Delete: requires custom folder + capability
   - Flush: requires trash/spam role + `folderFlush`
6. Keep destructive actions explicit:
   - Rename/Create prompt alerts
   - Delete/Flush confirmation alerts
   - Root status errors with retry affordance

## Rationale

**Why capability flags instead of backend type checks.**
Capability flags preserve ADR-0028 invariant 2. The same sidebar code
must work for the provider today and other providers later.

**Why add source-scoped methods now.**
Brev already supports multi-source mailbox sections. Folder actions must
target the correct source without relying on mutable active-mailbox
switches or concrete backend assumptions.

**Why include flush as a dedicated operation.**
Emptying trash/junk maps to provider behavior that is not equivalent to
message-by-message delete across all backends. A dedicated contract lets
providers use native endpoints safely.

**Alternatives considered.**

1. Keep folder actions as UI-only stubs:
   rejected because this would advertise unavailable behavior and defer
   protocol alignment.
2. Reuse message delete loops for flush:
   rejected because it is provider-sensitive and can diverge from
   server-native purge semantics.
3. Gate actions by concrete backend type:
   rejected by ADR-0028 invariant 2.

## Consequences

### Accepted

- Folder action affordances are now first-class and capability-gated.
- Backends can independently expose or withhold folder mutation support
  without UI branching by type.
- Multi-source folder action routing is explicit and testable.

### Risks

- **Provider API mismatch risk:** folder-parent addressing may vary by
  provider. Mitigation: backend-level mapping tests and provider-owned
  request DTO translation.
- **Destructive action UX risk:** accidental delete/flush. Mitigation:
  explicit confirmations and role-gated availability.
- **Capability drift risk:** future backends may forget to declare
  folder capabilities. Mitigation: tests and feature-surface checks in
  backend suites.

## References

- ADR-0001: Backend abstraction
- ADR-0005: Enforcement and protected paths
- ADR-0028: Roadmap/invariants (especially invariant 2)
- ADR-0017: Multi-source mail workspace
