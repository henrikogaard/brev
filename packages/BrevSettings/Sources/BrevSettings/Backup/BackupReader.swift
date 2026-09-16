/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import Foundation

/// Validated contents of a `.brevbackup` package, shown to the user before
/// restoring (ADR-0076 decision 4). Carries the decoded payloads so
/// `BackupRestorer` never re-reads files that were not verified.
struct BackupPreview {
    /// Package URL the preview was read from.
    let url: URL
    /// Decoded manifest (format version already checked).
    let manifest: BrevBackupManifest
    /// Decoded `settings.json`, if the package carries settings.
    let settings: SettingsBackupPayload?
    /// Decoded `accounts.json`, if the package carries accounts.
    let accounts: AccountsBackupPayload?
    /// Top-level `settings.json` keys this build does not know. In merge
    /// mode "preserved" means the local value is not destroyed — the
    /// unknown payload content itself is not written anywhere.
    let skippedUnknownKeys: Int
    /// Non-secret data stripped during export (e.g. the CalDAV Keychain
    /// credential pointer), surfaced so the user knows what is absent.
    let strippedFields: [String]
    /// Accounts in the backup whose email already matches a signed-in
    /// account; filled in by the caller once known.
    var alreadySignedInAccounts = 0

    /// `settings` re-decoded fields counts for the preview table.
    var accountCount: Int { accounts?.count ?? 0 }
    var rulesCount: Int { settings?.localRules?.rules.count ?? 0 }
    var smartViewCount: Int { settings?.smartMailbox?.mailboxes.count ?? 0 }
    var signatureCount: Int { settings?.signature?.signatures.count ?? 0 }
    var templateCount: Int { settings?.messageTemplate?.templates.count ?? 0 }
    var vipSenderCount: Int { settings?.vipSender?.senders.count ?? 0 }
    /// Number of non-list settings families present in the payload.
    var otherFamiliesCount: Int {
        guard let settings else { return 0 }
        var count = 0
        if settings.appearanceTheme != nil { count += 1 }
        if settings.windowAppearance != nil { count += 1 }
        if settings.appIcon != nil { count += 1 }
        if settings.mailboxView != nil { count += 1 }
        if settings.inboxClassification != nil { count += 1 }
        if settings.avatarPrivacy != nil { count += 1 }
        if settings.browser != nil { count += 1 }
        if settings.compose != nil { count += 1 }
        if settings.remoteContentPolicy != nil { count += 1 }
        if settings.notification != nil { count += 1 }
        if settings.update != nil { count += 1 }
        if settings.folderPreferences != nil { count += 1 }
        if settings.followUp != nil { count += 1 }
        if settings.fetchSchedule != nil { count += 1 }
        if settings.calDAV != nil { count += 1 }
        if settings.encryption != nil { count += 1 }
        if settings.accountMailboxSync != nil { count += 1 }
        if settings.mailboxSource != nil { count += 1 }
        if settings.folderVisibility != nil { count += 1 }
        if settings.preferenceSync != nil { count += 1 }
        if settings.relatedMailAutoLoadAccountIDs != nil { count += 1 }
        return count
    }

    var sourceAppVersion: String { manifest.appVersion }

    /// Returns a copy with `alreadySignedInAccounts` filled in.
    func countingSignedIn(emails: Set<String>) -> BackupPreview {
        var copy = self
        let normalized = Set(emails.map { $0.lowercased() })
        copy.alreadySignedInAccounts = (accounts ?? [])
            .filter { normalized.contains($0.account.emailAddress.lowercased()) }
            .count
        return copy
    }
}

/// Reads and verifies a `.brevbackup` package: directory shape, manifest
/// presence and format version, then every listed payload's SHA-256 and
/// decodability (ADR-0076 decision 4).
enum BackupReader {
    /// - Throws: `BackupError` for any structural or integrity problem.
    static func validate(url: URL) throws -> BackupPreview {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              url.pathExtension == BackupWriter.packageExtension
        else { throw BackupError.notABackup }

        let manifestURL = url.appendingPathComponent(BackupWriter.manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifestData = try? Data(contentsOf: manifestURL)
        else { throw BackupError.missingManifest }

        let manifest: BrevBackupManifest
        do {
            manifest = try BackupWriter.decoder.decode(BrevBackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.corrupted(BackupWriter.manifestName)
        }
        guard manifest.formatVersion <= BrevBackupManifest.currentFormatVersion else {
            throw BackupError.unsupportedVersion(manifest.formatVersion)
        }

        var settings: SettingsBackupPayload?
        var accounts: AccountsBackupPayload?
        for payload in manifest.payloads {
            let payloadURL = url.appendingPathComponent(payload.name)
            guard let data = try? Data(contentsOf: payloadURL),
                  BackupWriter.sha256Hex(data) == payload.sha256
            else { throw BackupError.corrupted(payload.name) }
            switch payload.name {
            case BackupWriter.settingsPayloadName:
                do {
                    settings = try BackupWriter.decoder.decode(SettingsBackupPayload.self, from: data)
                } catch {
                    throw BackupError.corrupted(payload.name)
                }
            case BackupWriter.accountsPayloadName:
                do {
                    accounts = try BackupWriter.decoder.decode(AccountsBackupPayload.self, from: data)
                } catch {
                    throw BackupError.corrupted(payload.name)
                }
            default:
                // Unknown payloads (e.g. a future mail/ archive) verify by
                // hash but are not decoded.
                continue
            }
        }

        return BackupPreview(
            url: url,
            manifest: manifest,
            settings: settings,
            accounts: accounts,
            skippedUnknownKeys: skippedUnknownKeys(in: url),
            strippedFields: strippedFields(in: settings)
        )
    }

    /// Counts `settings.json` top-level keys the codec does not know.
    private static func skippedUnknownKeys(in url: URL) -> Int {
        let settingsURL = url.appendingPathComponent(BackupWriter.settingsPayloadName)
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return 0 }
        return dictionary.keys.filter { !SettingsBackupPayload.knownKeys.contains($0) }.count
    }

    /// Names of fields stripped at export time for privacy, reported so the
    /// preview can mention what the backup does not contain.
    private static func strippedFields(in settings: SettingsBackupPayload?) -> [String] {
        // `notification` and `calDAV` payloads are DTOs whose stripped
        // fields are structural — report them whenever present.
        var fields: [String] = []
        if settings?.notification != nil {
            fields.append("notification.backgroundMailEnabled")
            fields.append("notification.launchAtLoginRequested")
        }
        if settings?.calDAV != nil {
            fields.append("calDAV.credentialAccount")
        }
        return fields
    }
}
