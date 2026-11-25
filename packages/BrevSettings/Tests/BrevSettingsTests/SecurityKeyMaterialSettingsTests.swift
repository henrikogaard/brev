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

@Suite("SecurityKeyMaterialSettings")
struct SecurityKeyMaterialSettingsTests {
    @Test("settings default to local-only safe import and export preferences")
    func defaultsUseSafeImportExportPreferences() {
        let defaults = SecurityKeyMaterialSettings.defaults

        #expect(defaults.records.isEmpty)
        #expect(defaults.importExport.smimeExportFormat == .pkcs12)
        #expect(defaults.importExport.includePrivateMaterialInExport == false)
        #expect(defaults.importExport.allowReplacingExistingMaterialOnImport == false)
    }

    @Test("records persist and trusted capability counts are derived")
    func recordsPersistAndTrustedCountsAreDerived() throws {
        let userDefaults = try Self.makeDefaults()
        let importedAt = Date(timeIntervalSince1970: 1_717_222_000)
        let trusted = SecurityKeyMaterialSettings.Record(
            id: "smime-trusted",
            family: .smime,
            label: "Signing identity",
            emailAddress: "work@example.com",
            fingerprint: "AA11BB22",
            algorithm: "RSA-2048",
            canSign: true,
            canEncrypt: true,
            hasPrivateMaterial: true,
            trust: .trusted,
            importedAt: importedAt
        )
        let untrusted = SecurityKeyMaterialSettings.Record(
            id: "smime-untrusted",
            family: .smime,
            label: "S/MIME Cert",
            emailAddress: "work@example.com",
            fingerprint: "CC33DD44",
            algorithm: "RSA-2048",
            canSign: true,
            canEncrypt: false,
            hasPrivateMaterial: false,
            trust: .untrusted,
            importedAt: importedAt
        )
        var settings = SecurityKeyMaterialSettings.defaults
        settings.upsert(trusted)
        settings.upsert(untrusted)
        settings.save(to: userDefaults)

        let restored = SecurityKeyMaterialSettings.load(from: userDefaults)

        #expect(restored.records.count == 2)
        #expect(restored.records.allSatisfy { $0.family == .smime })
        #expect(restored.trustedSigningRecordCount == 1)
        #expect(restored.trustedEncryptionRecordCount == 1)
    }

    @Test("bulk destructive actions require typed confirmation")
    func bulkDestructiveActionsRequireTypedConfirmation() {
        let removeOne = SecurityKeyMaterialConfirmationPolicy.confirmation(
            for: .removeSelectedItem,
            subjectLabel: "Work key"
        )
        let wipeAll = SecurityKeyMaterialConfirmationPolicy.confirmation(for: .removeAllMaterial)

        #expect(removeOne.requiresTypedConfirmation == false)
        #expect(removeOne.isSatisfied(by: nil))
        #expect(wipeAll.requiresTypedConfirmation)
        #expect(!wipeAll.isSatisfied(by: nil))
        #expect(!wipeAll.isSatisfied(by: "delete"))
        #expect(wipeAll.isSatisfied(by: "DELETE"))
    }

    @Test("bulk delete executor refuses empty or wrong confirmation input without deleting keys")
    func bulkDeleteExecutorRefusesEmptyOrWrongInput() {
        let record1 = SecurityKeyMaterialSettings.Record(
            id: "smime-1",
            family: .smime,
            label: "Signing identity",
            emailAddress: "work@example.com",
            fingerprint: "AA11",
            algorithm: "RSA",
            canSign: true,
            canEncrypt: true,
            hasPrivateMaterial: true,
            trust: .trusted,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let record2 = SecurityKeyMaterialSettings.Record(
            id: "smime-2",
            family: .smime,
            label: "Recipient cert",
            emailAddress: "peer@example.com",
            fingerprint: "BB22",
            algorithm: "RSA",
            canSign: false,
            canEncrypt: true,
            hasPrivateMaterial: false,
            trust: .trusted,
            importedAt: Date(timeIntervalSince1970: 1)
        )
        var settings = SecurityKeyMaterialSettings(records: [record1, record2], importExport: .defaults)

        // Empty or mismatched confirmation MUST NOT delete any records.
        #expect(
            SecurityKeyMaterialConfirmationPolicy.apply(
                action: .removeAllSMIME,
                recordID: nil,
                confirmationInput: "",
                to: &settings
            ) == nil
        )
        #expect(settings.records.count == 2)

        #expect(
            SecurityKeyMaterialConfirmationPolicy.apply(
                action: .removeAllMaterial,
                recordID: nil,
                confirmationInput: "delete",
                to: &settings
            ) == nil
        )
        #expect(settings.records.count == 2)

        // Single-record removal uses normal confirmation without typed phrase.
        let singleRemoved = SecurityKeyMaterialConfirmationPolicy.apply(
            action: .removeSelectedItem,
            recordID: "smime-2",
            confirmationInput: "",
            to: &settings
        )
        #expect(singleRemoved == ["smime-2"])
        #expect(settings.records.map(\.id) == ["smime-1"])

        // Exact "DELETE" proceeds with bulk removal.
        let bulkRemoved = SecurityKeyMaterialConfirmationPolicy.apply(
            action: .removeAllSMIME,
            recordID: nil,
            confirmationInput: "DELETE",
            to: &settings
        )
        #expect(bulkRemoved == ["smime-1"])
        #expect(settings.records.isEmpty)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suite = "SecurityKeyMaterialSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
