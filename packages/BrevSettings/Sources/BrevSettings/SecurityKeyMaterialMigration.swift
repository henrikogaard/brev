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

    @discardableResult
    public static func run(
        defaults: UserDefaults = .standard,
        materialStore: any SecurityKeyMaterialStore = SecurityKeychainMaterialStore()
    ) async -> Bool {
        let retiredRecordIDs = SecurityKeyMaterialSettings.retiredRecordIDs(from: defaults)
        do {
            for recordID in retiredRecordIDs {
                try await materialStore.deleteMaterial(for: recordID)
            }
        } catch {
            return false
        }

        SecurityKeyMaterialSettings.load(from: defaults).save(to: defaults)
        defaults.removeObject(forKey: retiredEncryptionToggle)
        defaults.removeObject(forKey: retiredDiscoveryMode)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(retiredPinPrefix) {
            defaults.removeObject(forKey: key)
        }
        return true
    }
}
