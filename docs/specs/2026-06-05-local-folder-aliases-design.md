# Local Folder Aliases Design

## Goal

Let users rename mailbox folders locally without mutating provider folders or
server-side mailbox state. This solves provider names such as `INBOX` showing in
the UI while preserving the backend's exact folder identifiers and names for
sync, moves, imports, exports, and server folder mutation.

## Scope

- Add local aliases keyed by `SourceFolderID`.
- Display aliases in the folder sidebar, folder prompts/confirmations, Move To
  surfaces, notification folder names, and macOS Move commands where source
  identity is available.
- Keep `Folder.name` as the provider truth.
- Add a role-based fallback display name for standard folders so `.inbox`
  renders as `Inbox` even if the provider reports `INBOX`.
- Add context menu actions named `Set Local Name...` and `Clear Local Name`.

## Architecture

Folder alias state lives in `BrevBackend` beside the existing folder visibility
preferences. The model is provider-neutral, source-scoped, codable, and stored
in `UserDefaults`. A policy object resolves display names in this order:

1. non-empty local alias for `SourceFolderID`;
2. standard role display name for known system folders;
3. provider folder name.

The view layer receives `Folder` values unchanged and asks the policy for a
presentation name. Backend APIs continue to receive the original `Folder` and
folder IDs, so no network calls or provider mutations are introduced.

## Interaction

Folder row context menus expose a local alias action for source-scoped folders.
`Set Local Name...` opens a prompt prefilled with the current display name.
Submitting a blank name clears the alias. `Clear Local Name` appears only when
an alias exists. Existing `Rename Folder...` remains server-side and custom
folder-only.

## Verification

- Backend tests cover source scoping, trimming, clearing, role fallback, storage
  round-trip, and account cleanup.
- BrevMail presentation tests cover context menu alias affordances and display
  resolution.
- Focused Swift package tests run for `BrevBackend` and the touched `BrevMail`
  policy tests.
- `git diff --check` verifies whitespace.
