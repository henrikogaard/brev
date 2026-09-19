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

/// Removes Keychain payloads and preferences owned by the retired security
/// family while preserving the current S/MIME catalog. Deletion fails closed:
/// catalog metadata remains available for a later retry if Keychain cleanup
/// cannot complete.
public enum RetiredSecurityMaterialMigration {
    private static let retiredEncryptionToggle = "encryption." + "openPGPEnabled"
    private static let retiredDiscoveryMode = "recipientKeyDiscovery.mode"
    private static let retiredPinPrefix = "brev." + "wkd.pin."
    private static let completionKey = "security." + "retiredMaterialMigration.v1"

    @discardableResult
    public static func run(
        defaults: UserDefaults = .standard,
        materialStore: any SecurityKeyMaterialStore = SecurityKeychainMaterialStore()
    ) async -> Bool {
        // The retired family cannot produce new state, so a completed pass
        // never needs to touch defaults again — the early return keeps every
        // later launch free of the preference read/write + notification pass.
        guard !defaults.bool(forKey: completionKey) else { return true }

        let retiredRecordIDs = SecurityKeyMaterialSettings.retiredRecordIDs(from: defaults)
        do {
            for recordID in retiredRecordIDs {
                try await materialStore.deleteMaterial(for: recordID)
            }
        } catch {
            return false
        }

        // Rewriting the catalog only matters when retired records were
        // stripped; an unchanged payload still posts a did-change
        // notification to every defaults observer.
        if !retiredRecordIDs.isEmpty {
            SecurityKeyMaterialSettings.load(from: defaults).save(to: defaults)
        }
        if defaults.object(forKey: retiredEncryptionToggle) != nil {
            defaults.removeObject(forKey: retiredEncryptionToggle)
        }
        if defaults.object(forKey: retiredDiscoveryMode) != nil {
            defaults.removeObject(forKey: retiredDiscoveryMode)
        }
        // Key enumeration runs once per install — only while the migration
        // is still incomplete — so the whole-dictionary materialization does
        // not repeat every launch.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(retiredPinPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: completionKey)
        return true
    }
}
