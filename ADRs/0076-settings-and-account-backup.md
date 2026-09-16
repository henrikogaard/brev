# ADR-0076: Versioned settings and account backup

- **Status:** Accepted
- **Date:** 2026-09-16
- **Deciders:** Henrik

## Context

Issue #28 §9 asks for "a versioned backup/restore format with validation,
preview, safe merge/replace choices, and restore tests", keeping
"passwords/tokens outside portable exports by default", and for "durable
local archives distinct from an evictable cache".

What exists (`packages/BrevBackend/Sources/BrevBackend/MailImport.swift`,
`MailFolderExporter.swift`, `packages/BrevSettings/.../ImportExportSection.swift`):

- Import of MBOX and Maildir into a mailbox folder.
- Export of one folder to MBOX or an EML directory.

What a daily driver cannot do today: move to a new Mac and get the same
Brev back. Every preference — rules, Smart Views, signatures, templates,
VIP list, appearance, folder sync overrides, notification settings, related-
mail consent — lives in `UserDefaults` through `SettingsPersistenceStore`,
and account definitions live in the account store with secrets in the
Keychain (`KeychainTokenStore`). None of it is portable. Mail itself is a
rebuildable cache under `Application Support/Brev/{Cache,Gmail,Drafts}`
(ADR-0030, ADR-0050) and can be re-synced from the server.

ADR-0056 syncs *some* preferences through iCloud key-value storage, opt-in;
it is not a backup (no history, no accounts, capped size, Apple-ID-bound).

## Decision

1. **A Brev backup is a versioned directory package**, `Brev Backup
   <date>.brevbackup`, containing:
   - `manifest.json` — `formatVersion` (starts at 1), `createdAt`, app
     version and build, platform, and a SHA-256 per payload file.
   - `settings.json` — every preference `SettingsPersistenceStore` owns,
     exported through one `SettingsBackupCodec` so a key that is added to
     the store without a codec entry fails a unit test.
   - `accounts.json` — account identity and server configuration only:
     `BrevAccount` fields plus `IMAPAccountConfiguration` / Gmail account
     metadata. **Never** passwords, OAuth tokens, refresh tokens, or
     credential IDs that resolve to Keychain items. Restored accounts come
     back in a "sign in to finish restoring" state.
   A directory package needs no compression dependency and can later hold
   mail archives (decision 6) without a format break.

2. **Restore is validate → preview → choose → apply.** `BackupRestorer`
   validates the manifest version and hashes before touching anything, then
   presents a preview: counts per category (accounts, rules, Smart Views,
   signatures, templates, other preferences) and the source app version. The
   user picks **Merge** (keep local entries, add missing ones, backup wins on
   conflicts for scalar preferences) or **Replace** (backup becomes the whole
   state for the categories it contains). Apply is transactional per
   category: a failed category rolls back to the pre-restore snapshot of
   that category and reports; other categories keep their outcome.

3. **Secrets stay out by default and there is no opt-in to include them in
   v1.** A future encrypted variant would need its own ADR (key management,
   passphrase UX, threat model). The manifest carries
   `containsSecrets: false` so a later reader can refuse unknown variants.

4. **Version policy.** `formatVersion` increments only on breaking payload
   changes. Readers accept any version ≤ their own; unknown keys inside
   `settings.json` are preserved on merge and reported in the preview as
   "n settings from a newer Brev were skipped", never silently dropped.

5. **Surface.** Settings › Import / Export gains a third group, "Brev
   backup", with "Back up settings and accounts…" (save panel) and "Restore
   from backup…" (open panel → preview sheet). Both actions are explicit;
   nothing is automatic and nothing leaves the device.

6. **Durable local archives are phase 2, named here so the format is ready.**
   A `mail/` directory inside the package will hold per-account MBOX
   archives produced by the existing `MailFolderExporter`, and restoring
   them means importing through the existing MBOX path into a local
   "On My Mac"-style folder. That local-folder store does not exist yet and
   is the real work of phase 2; it needs its own decision on storage and
   eviction exemption and is not implemented under this ADR.

7. **Privacy.** A backup contains email addresses, server hostnames, rule
   predicates, signature text, and VIP addresses — personal data the user
   already owns. `PRIVACY.md` states what a backup contains, that it is
   written only where the user chooses, and that it never includes
   credentials. No network involvement (ADR-0006 unaffected).

## Rationale

- *Directory package vs. zip/AppleArchive:* Foundation has no zip writer;
  AppleArchive adds a framework and a streaming API for no v1 benefit.
  Finder shows a package as one file, `NSSavePanel` handles it, and
  `manifest.json` hashes give integrity without compression.
- *Codec table vs. dumping the defaults domain:* dumping every key would
  leak transient state (window frames, caches, "last seen" timestamps) and
  make the format hostage to internal key names. A codec per preference
  family keeps the payload intentional and testable.
- *Accounts without secrets vs. Keychain export:* Keychain items are
  device-bound by design; exporting them portably is a second product
  (encryption, passphrase). Re-signing-in after restore is the accepted
  cost, matching Apple Mail's behavior when migrating without Keychain sync.
- *Merge/Replace only vs. per-item picking:* per-item selection is a large UI
  for a rare operation; two clear modes with a preview cover migration and
  disaster recovery.
- *Rejected: extending ADR-0056 iCloud KV sync into "backup".* Different
  guarantees, Apple-ID-bound, 1 MB cap, no accounts.

## Consequences

### Accepted

- New `BrevBackup` module inside `BrevSettings` (codec, writer, validator,
  restorer, preview model) with unit tests for round-trip, tampered hash,
  newer-version payload, merge vs. replace, and per-category rollback.
- `SettingsPersistenceStore` gains `exportBackupSettings()` /
  `applyBackupSettings(_:mode:)`; the completeness test compares the codec's
  key set to the store's known keys.
- Account store gains a metadata-only export and an import that creates
  accounts flagged as needing credentials; `AppSession` surfaces those as
  sign-in prompts through the existing account-error path.
- ImportExportSection UI plus snapshot baselines; `PRIVACY.md`, `CHANGELOG`.

### Risks

- A restored account whose provider setup has changed (e.g. OAuth client
  rotation) still needs the normal re-authentication flow; the backup can
  only bring it to the doorstep. Mitigation: preview says so explicitly.
- Merge semantics for list-like preferences (rules order, Smart View order)
  are the likely source of surprises. Mitigation: merge appends missing
  items after local ones and never reorders local items; Replace exists for
  users who want the backup's order.
- Phase 2 (local archives) may want compression once mail is included; the
  manifest's per-file hash and `formatVersion` leave room for a `mail/`
  payload with its own encoding field without breaking v1 readers.

## References

- ADR-0006 — privacy; ADR-0030 / ADR-0050 — cache is rebuildable;
  ADR-0056 — iCloud KV preference sync (not a backup).
- Issue #28 §9.
- `SettingsPersistenceStore`, `KeychainTokenStore`, `MailImport.swift`,
  `MailFolderExporter.swift`, `ImportExportSection.swift`.
