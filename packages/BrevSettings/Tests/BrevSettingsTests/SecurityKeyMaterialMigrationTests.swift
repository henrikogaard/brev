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

@testable import BrevSettings
import Foundation
import Testing

@Suite("RetiredSecurityMaterialMigration")
struct SecurityKeyMaterialMigrationTests {
    @Test("migration deletes retired payloads and preserves S/MIME records")
    func migrationDeletesRetiredPayloadsAndPreservesSMIME() async throws {
        let suiteName = "SecurityMigration-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let payload = """
        {
          "records": [
            {"id":"retired","family":"openPGP","label":"Old key","fingerprint":"OLD","algorithm":"RSA","canSign":true,"canEncrypt":true,"hasPrivateMaterial":true,"trust":"trusted","importedAt":0},
            {"id":"smime","family":"smime","label":"Certificate","fingerprint":"CERT","algorithm":"RSA","canSign":true,"canEncrypt":true,"hasPrivateMaterial":true,"trust":"trusted","importedAt":0}
          ],
          "importExport": {"openPGPExportFormat":"asciiArmor","smimeExportFormat":"pkcs12","includePrivateMaterialInExport":false,"allowReplacingExistingMaterialOnImport":false}
        }
        """
        defaults.set(Data(payload.utf8), forKey: SecurityKeyMaterialSettings.Key.storage)
        defaults.set(true, forKey: "encryption.openPGPEnabled")
        defaults.set("webKeyDirectory", forKey: "recipientKeyDiscovery.mode")
        defaults.set("fingerprint", forKey: "brev.wkd.pin.person@example.com")
        let store = MigrationMaterialStore()

        #expect(await RetiredSecurityMaterialMigration.run(defaults: defaults, materialStore: store))
        #expect(await store.deletedRecordIDs == ["retired"])
        #expect(SecurityKeyMaterialSettings.load(from: defaults).records.map(\.id) == ["smime"])
        #expect(defaults.object(forKey: "encryption.openPGPEnabled") == nil)
        #expect(defaults.object(forKey: "recipientKeyDiscovery.mode") == nil)
        #expect(defaults.object(forKey: "brev.wkd.pin.person@example.com") == nil)
    }

    @Test("failed Keychain cleanup leaves migration state available for retry")
    func failedCleanupLeavesStateForRetry() async throws {
        let suiteName = "SecurityMigrationFailure-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let payload = """
        {"records":[{"id":"retired","family":"openPGP","label":"Old key","fingerprint":"OLD","algorithm":"RSA","canSign":true,"canEncrypt":true,"hasPrivateMaterial":true,"trust":"trusted","importedAt":0}],"importExport":{"openPGPExportFormat":"asciiArmor","smimeExportFormat":"pkcs12","includePrivateMaterialInExport":false,"allowReplacingExistingMaterialOnImport":false}}
        """
        let originalData = Data(payload.utf8)
        defaults.set(originalData, forKey: SecurityKeyMaterialSettings.Key.storage)
        defaults.set(true, forKey: "encryption.openPGPEnabled")
        let store = MigrationMaterialStore(shouldFailDeletion: true)

        let result = await RetiredSecurityMaterialMigration.run(defaults: defaults, materialStore: store)
        #expect(!result)
        #expect(defaults.data(forKey: SecurityKeyMaterialSettings.Key.storage) == originalData)
        #expect(defaults.bool(forKey: "encryption.openPGPEnabled"))
    }
}

private actor MigrationMaterialStore: SecurityKeyMaterialStore {
    private(set) var deletedRecordIDs: [String] = []
    private let shouldFailDeletion: Bool

    init(shouldFailDeletion: Bool = false) {
        self.shouldFailDeletion = shouldFailDeletion
    }

    func material(for _: String) async throws -> Data? { nil }
    func setMaterial(_: Data, for _: String) async throws {}
    func deleteMaterial(for recordID: String) async throws {
        if shouldFailDeletion { throw MigrationFailure.expected }
        deletedRecordIDs.append(recordID)
    }
}

private enum MigrationFailure: Error {
    case expected
}
