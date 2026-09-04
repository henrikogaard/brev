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

import BrevBackend
import Foundation

public extension Notification.Name {
    /// Posted when the mailbox sync settings change in a way that affects
    /// the local cache footprint — most importantly the offline-retention
    /// policy. The mail view observes this to prune cached message bodies
    /// that now fall outside the retention window. Decouples the (multiple)
    /// settings surfaces that can change retention from the single place
    /// that owns a backend handle to enforce it.
    static let brevMailboxSyncSettingsDidChange = Notification.Name(
        "eu.brevmail.settings.mailboxSync.changed"
    )
}

public struct AccountMailboxRoleMapping: Codable, Equatable, Sendable {
    public var accountID: String
    public var draftsFolderID: String?
    public var sentFolderID: String?
    public var junkFolderID: String?
    public var trashFolderID: String?
    public var archiveFolderID: String?
}

public enum FolderSyncScope: String, CaseIterable, Sendable, Codable, Identifiable {
    case allFolders
    case subscribedOnly

    public var id: String { rawValue }
}

public enum OfflineRetentionPolicy: String, CaseIterable, Sendable, Codable, Identifiable {
    // Ordered longest-to-shortest retention so the settings picker
    // (`ForEach(allCases)`) reads top-down from "keep everything" to the
    // tightest window. The `rawValue`s of the original four cases are kept
    // stable so previously-saved preferences and exported settings blobs
    // still decode (the new cases only add to the set).
    case keepAll
    case keep1Year
    case keep6Months
    case keep90Days
    case keep30Days
    case keep14Days
    case keep7Days
    case headersOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keepAll: return String(localized: "Everything", bundle: .module)
        case .keep1Year: return String(localized: "1 year", bundle: .module)
        case .keep6Months: return String(localized: "6 months", bundle: .module)
        case .keep90Days: return String(localized: "90 days", bundle: .module)
        case .keep30Days: return String(localized: "30 days", bundle: .module)
        case .keep14Days: return String(localized: "14 days", bundle: .module)
        case .keep7Days: return String(localized: "7 days", bundle: .module)
        case .headersOnly: return String(localized: "Headers only", bundle: .module)
        }
    }

    public var description: String {
        switch self {
        case .keepAll:
            return String(localized: "Keep all synced messages available locally.", bundle: .module)
        case .keep1Year:
            return String(localized: "Keep full message content for the latest year.", bundle: .module)
        case .keep6Months:
            return String(localized: "Keep full message content for the latest 6 months.", bundle: .module)
        case .keep90Days:
            return String(localized: "Keep full message content for the latest 90 days.", bundle: .module)
        case .keep30Days:
            return String(localized: "Keep full message content for the latest 30 days.", bundle: .module)
        case .keep14Days:
            return String(localized: "Keep full message content for the latest 14 days.", bundle: .module)
        case .keep7Days:
            return String(localized: "Keep full message content for the latest 7 days.", bundle: .module)
        case .headersOnly:
            return String(localized: "Keep headers only; load body content on demand.", bundle: .module)
        }
    }

    /// Number of days of full message bodies to keep locally, or `nil` when
    /// no age-based cutoff applies. `nil` for both `.keepAll` (keep
    /// everything) and `.headersOnly` (keep no bodies regardless of age —
    /// distinguish those two via `keepsBodies`).
    public var retentionDays: Int? {
        switch self {
        case .keep7Days: return 7
        case .keep14Days: return 14
        case .keep30Days: return 30
        case .keep90Days: return 90
        case .keep6Months: return 180
        case .keep1Year: return 365
        case .keepAll, .headersOnly: return nil
        }
    }

    /// Whether message bodies are cached at all. `.headersOnly` drops every
    /// body; every other policy keeps bodies (subject to `retentionDays`).
    public var keepsBodies: Bool {
        self != .headersOnly
    }
}

public struct FolderSyncOverride: Codable, Equatable, Sendable {
    public var retentionPolicy: OfflineRetentionPolicy?

    public init(retentionPolicy: OfflineRetentionPolicy? = nil) {
        self.retentionPolicy = retentionPolicy
    }
}

public struct AccountMailboxSyncSettings: Equatable, Sendable {
    enum Key {
        static let roleMappings = "account.mailboxRoleMappings"
        static let folderSyncScope = "account.folderSyncScope"
        static let includeSharedFolders = "account.includeSharedFolders"
        static let includeArchiveFolders = "account.includeArchiveFolders"
        static let offlineRetentionPolicy = "account.offlineRetentionPolicy"
        static let folderOverrides = "account.folderOverrides"
        static let sourceFolderOverrides = "account.sourceFolderOverrides"
    }

    public var roleMappingsByAccountID: [String: AccountMailboxRoleMapping]
    public var folderSyncScope: FolderSyncScope
    public var includeSharedFolders: Bool
    public var includeArchiveFolders: Bool
    public var offlineRetentionPolicy: OfflineRetentionPolicy
    public var folderOverrides: [String: FolderSyncOverride]
    /// Overrides keyed by the complete account, mailbox, and folder identity.
    public var sourceFolderOverrides: [SourceFolderID: FolderSyncOverride]

    public init(
        roleMappingsByAccountID: [String: AccountMailboxRoleMapping],
        folderSyncScope: FolderSyncScope,
        includeSharedFolders: Bool,
        includeArchiveFolders: Bool,
        offlineRetentionPolicy: OfflineRetentionPolicy,
        folderOverrides: [String: FolderSyncOverride] = [:],
        sourceFolderOverrides: [SourceFolderID: FolderSyncOverride] = [:]
    ) {
        self.roleMappingsByAccountID = roleMappingsByAccountID
        self.folderSyncScope = folderSyncScope
        self.includeSharedFolders = includeSharedFolders
        self.includeArchiveFolders = includeArchiveFolders
        self.offlineRetentionPolicy = offlineRetentionPolicy
        self.folderOverrides = folderOverrides
        self.sourceFolderOverrides = sourceFolderOverrides
    }

    public static let defaults = AccountMailboxSyncSettings(
        roleMappingsByAccountID: [:],
        folderSyncScope: .allFolders,
        includeSharedFolders: true,
        includeArchiveFolders: true,
        offlineRetentionPolicy: .keep90Days,
        folderOverrides: [:]
    )

    public static func load(from defaults: UserDefaults = .standard) -> AccountMailboxSyncSettings {
        AccountMailboxSyncSettings(
            roleMappingsByAccountID: roleMappings(from: defaults),
            folderSyncScope: enumValue(
                FolderSyncScope.self,
                for: Key.folderSyncScope,
                defaultValue: Self.defaults.folderSyncScope,
                defaults: defaults
            ),
            includeSharedFolders: bool(
                for: Key.includeSharedFolders,
                defaultValue: Self.defaults.includeSharedFolders,
                defaults: defaults
            ),
            includeArchiveFolders: bool(
                for: Key.includeArchiveFolders,
                defaultValue: Self.defaults.includeArchiveFolders,
                defaults: defaults
            ),
            offlineRetentionPolicy: enumValue(
                OfflineRetentionPolicy.self,
                for: Key.offlineRetentionPolicy,
                defaultValue: Self.defaults.offlineRetentionPolicy,
                defaults: defaults
            ),
            folderOverrides: folderOverrides(from: defaults),
            sourceFolderOverrides: defaults.data(forKey: Key.sourceFolderOverrides).flatMap {
                try? JSONDecoder().decode([SourceFolderID: FolderSyncOverride].self, from: $0)
            } ?? [:]
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(sourceFolderOverrides) {
            defaults.set(data, forKey: Key.sourceFolderOverrides)
        }
        defaults.set(folderSyncScope.rawValue, forKey: Key.folderSyncScope)
        defaults.set(includeSharedFolders, forKey: Key.includeSharedFolders)
        defaults.set(includeArchiveFolders, forKey: Key.includeArchiveFolders)
        defaults.set(offlineRetentionPolicy.rawValue, forKey: Key.offlineRetentionPolicy)

        if let data = try? JSONEncoder().encode(roleMappingsByAccountID) {
            defaults.set(data, forKey: Key.roleMappings)
        } else {
            defaults.removeObject(forKey: Key.roleMappings)
        }

        if let data = try? JSONEncoder().encode(folderOverrides) {
            defaults.set(data, forKey: Key.folderOverrides)
        } else {
            defaults.removeObject(forKey: Key.folderOverrides)
        }
    }

    public mutating func setRoleMapping(_ mapping: AccountMailboxRoleMapping) {
        roleMappingsByAccountID[mapping.accountID] = mapping
    }

    public mutating func removeRoleMapping(accountID: String) {
        roleMappingsByAccountID.removeValue(forKey: accountID)
    }

    public func roleMapping(for accountID: String) -> AccountMailboxRoleMapping {
        roleMappingsByAccountID[accountID] ?? AccountMailboxRoleMapping(accountID: accountID)
    }

    /// Resolves a folder policy without applying another mailbox's override.
    public func policy(for folderID: String, sourceID: MailSourceID? = nil) -> OfflineRetentionPolicy {
        override(for: folderID, sourceID: sourceID)?.retentionPolicy ?? offlineRetentionPolicy
    }

    /// Returns an explicit source override, falling back to legacy folder preferences.
    public func override(for folderID: String, sourceID: MailSourceID? = nil) -> FolderSyncOverride? {
        if let sourceID,
           let scoped = sourceFolderOverrides[SourceFolderID(sourceID: sourceID, folderID: folderID)] {
            return scoped
        }
        return folderOverrides[folderID]
    }

    public mutating func setRetentionPolicy(
        _ policy: OfflineRetentionPolicy?,
        forFolderID folderID: String,
        sourceID: MailSourceID? = nil
    ) {
        if let sourceID {
            // Preserve an explicit Default choice even if a legacy override exists.
            sourceFolderOverrides[SourceFolderID(sourceID: sourceID, folderID: folderID)] =
                FolderSyncOverride(retentionPolicy: policy)
            return
        }
        var override = folderOverrides[folderID] ?? FolderSyncOverride()
        override.retentionPolicy = policy
        setOverride(override, forFolderID: folderID)
    }

    private mutating func setOverride(
        _ override: FolderSyncOverride,
        forFolderID folderID: String
    ) {
        if override.retentionPolicy == nil {
            folderOverrides.removeValue(forKey: folderID)
        } else {
            folderOverrides[folderID] = override
        }
    }

    private static func folderOverrides(from defaults: UserDefaults) -> [String: FolderSyncOverride] {
        guard let data = defaults.data(forKey: Key.folderOverrides),
              let overrides = try? JSONDecoder().decode([String: FolderSyncOverride].self, from: data) else {
            return Self.defaults.folderOverrides
        }
        return overrides
    }

    private static func roleMappings(from defaults: UserDefaults) -> [String: AccountMailboxRoleMapping] {
        guard let data = defaults.data(forKey: Key.roleMappings),
              let mappings = try? JSONDecoder().decode([String: AccountMailboxRoleMapping].self, from: data) else {
            return Self.defaults.roleMappingsByAccountID
        }
        return mappings
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let raw = defaults.string(forKey: key),
              let value = Value(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}
