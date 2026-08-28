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

/// Local, provider-neutral visibility and default selection for mail
/// sources. This is Brev presentation state: it does not disconnect an
/// account or mutate provider mailbox permissions.
public struct MailboxSourcePreferences: Codable, Equatable, Sendable {
    public var enabledSourceIDs: [MailSourceID]
    public var defaultSourceID: MailSourceID?

    public init(
        enabledSourceIDs: [MailSourceID] = [],
        defaultSourceID: MailSourceID? = nil
    ) {
        self.enabledSourceIDs = enabledSourceIDs
        self.defaultSourceID = defaultSourceID
    }

    public static let defaults = MailboxSourcePreferences()
}

public enum MailboxSourcePreferencesPolicy {
    /// Returns the enabled sources in the same order as `availableSourceIDs`.
    /// Empty persisted state means "all currently available sources".
    public static func enabledSourceIDs(
        availableSourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences
    ) -> [MailSourceID] {
        let available = orderedUnique(availableSourceIDs)
        guard !available.isEmpty else { return [] }

        let storedEnabled = Set(preferences.enabledSourceIDs)
        guard !storedEnabled.isEmpty else { return available }

        let enabled = available.filter { storedEnabled.contains($0) }
        return enabled.isEmpty ? available : enabled
    }

    public static func isEnabled(
        _ sourceID: MailSourceID,
        availableSourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences
    ) -> Bool {
        enabledSourceIDs(
            availableSourceIDs: availableSourceIDs,
            preferences: preferences
        ).contains(sourceID)
    }

    public static func defaultSourceID(
        availableSourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences,
        preferredDefaultSourceID: MailSourceID? = nil
    ) -> MailSourceID? {
        let enabled = enabledSourceIDs(
            availableSourceIDs: availableSourceIDs,
            preferences: preferences
        )
        guard !enabled.isEmpty else { return nil }

        if let saved = preferences.defaultSourceID,
           enabled.contains(saved) {
            return saved
        }
        if let preferredDefaultSourceID,
           enabled.contains(preferredDefaultSourceID) {
            return preferredDefaultSourceID
        }
        return enabled.first
    }

    public static func normalized(
        availableSourceIDs: [MailSourceID],
        enabledSourceIDs proposedEnabledSourceIDs: [MailSourceID],
        defaultSourceID proposedDefaultSourceID: MailSourceID?,
        preferredDefaultSourceID: MailSourceID? = nil
    ) -> MailboxSourcePreferences {
        let available = orderedUnique(availableSourceIDs)
        guard !available.isEmpty else { return .defaults }

        let availableSet = Set(available)
        let enabled = orderedUnique(proposedEnabledSourceIDs)
            .filter { availableSet.contains($0) }
        let resolvedEnabled = enabled.isEmpty ? available : enabled
        let enabledSet = Set(resolvedEnabled)

        let defaultCandidates = [
            proposedDefaultSourceID,
            preferredDefaultSourceID,
            resolvedEnabled.first
        ].compactMap { $0 }
        let resolvedDefault = defaultCandidates.first { enabledSet.contains($0) }

        return MailboxSourcePreferences(
            enabledSourceIDs: resolvedEnabled,
            defaultSourceID: resolvedDefault
        )
    }

    public static func removingAccount(
        _ accountID: BrevAccount.ID,
        from preferences: MailboxSourcePreferences
    ) -> MailboxSourcePreferences {
        MailboxSourcePreferences(
            enabledSourceIDs: preferences.enabledSourceIDs.filter { $0.accountID != accountID },
            defaultSourceID: preferences.defaultSourceID?.accountID == accountID
                ? nil
                : preferences.defaultSourceID
        )
    }

    public static func hasExplicitSelection(
        availableSourceIDs: [MailSourceID],
        preferences: MailboxSourcePreferences
    ) -> Bool {
        let available = Set(availableSourceIDs)
        return preferences.enabledSourceIDs.contains { available.contains($0) }
    }

    private static func orderedUnique(_ sourceIDs: [MailSourceID]) -> [MailSourceID] {
        var seen: Set<MailSourceID> = []
        var result: [MailSourceID] = []
        for sourceID in sourceIDs where seen.insert(sourceID).inserted {
            result.append(sourceID)
        }
        return result
    }
}

public enum MailboxSourcePreferencesStorage {
    public static let storageKey = "mailbox.sourcePreferences"

    public static func load(from defaults: UserDefaults = .standard) -> MailboxSourcePreferences {
        guard let data = defaults.data(forKey: storageKey) else {
            return .defaults
        }
        return decode(data) ?? .defaults
    }

    public static func save(
        _ preferences: MailboxSourcePreferences,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = encode(preferences) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    public static func removeAccount(
        _ accountID: BrevAccount.ID,
        from defaults: UserDefaults = .standard
    ) {
        let next = MailboxSourcePreferencesPolicy.removingAccount(
            accountID,
            from: load(from: defaults)
        )
        save(next, to: defaults)
    }

    public static func decode(_ data: Data) -> MailboxSourcePreferences? {
        try? JSONDecoder().decode(MailboxSourcePreferences.self, from: data)
    }

    public static func encode(_ preferences: MailboxSourcePreferences) -> Data? {
        try? JSONEncoder().encode(preferences)
    }
}
