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

@Suite("SignatureSettings")
struct SignatureSettingsTests {
    @Test("default signature settings are empty")
    func defaultSignatureSettingsAreEmpty() throws {
        let defaults = try Self.makeDefaults()

        let settings = SignatureSettings.load(from: defaults)

        #expect(settings.signatures.isEmpty)
        #expect(settings.defaultSignatureIDsByAccountID.isEmpty)
        #expect(settings.accountIDsWithNoDefaultSignature.isEmpty)
    }

    @Test("saving and loading preserves signatures and defaults")
    func savingAndLoadingPreservesSignaturesAndDefaults() throws {
        let defaults = try Self.makeDefaults()
        var settings = SignatureSettings.defaults
        let signature = settings.addSignature(
            name: "Work",
            body: "Henrik\nBrev",
            isEnabled: true
        )
        settings.setDefaultSignature(signatureID: signature.id, forAccountID: "acct-1")

        settings.save(to: defaults)
        let restored = SignatureSettings.load(from: defaults)

        #expect(restored.signatures.count == 1)
        #expect(restored.signature(forAccountID: "acct-1")?.body == "Henrik\nBrev")
        #expect(restored.defaultSignatureID(forAccountID: "acct-1") == signature.id)
    }

    @Test("disabling a signature preserves the drafted body")
    func disablingSignaturePreservesDraftedBody() throws {
        var settings = SignatureSettings.defaults
        let signature = settings.addSignature(
            name: "Personal",
            body: "Henrik\nBrev",
            isEnabled: true
        )

        settings.setSignatureEnabled(false, id: signature.id)

        #expect(settings.signatures.first?.body == "Henrik\nBrev")
        #expect(settings.signatures.first?.isEnabled == false)
    }

    @Test("resolves account default signature when configured")
    func resolvesAccountDefaultSignatureWhenConfigured() throws {
        var settings = SignatureSettings.defaults
        let first = settings.addSignature(name: "Work", body: "Work sig", isEnabled: true)
        let second = settings.addSignature(name: "Home", body: "Home sig", isEnabled: true)
        settings.setDefaultSignature(signatureID: second.id, forAccountID: "acct-1")
        settings.setDefaultSignature(signatureID: first.id, forAccountID: "acct-2")

        #expect(settings.signature(forAccountID: "acct-1")?.id == second.id)
        #expect(settings.signature(forAccountID: "acct-2")?.id == first.id)
    }

    @Test("falls back to first enabled signature when no account default exists")
    func fallsBackToFirstEnabledSignatureWhenNoAccountDefaultExists() throws {
        var settings = SignatureSettings.defaults
        let disabled = settings.addSignature(name: "Disabled", body: "Disabled", isEnabled: false)
        let enabled = settings.addSignature(name: "Enabled", body: "Enabled", isEnabled: true)

        #expect(settings.signature(forAccountID: "acct-1")?.id == enabled.id)
        #expect(settings.signature(forAccountID: "acct-1")?.id != disabled.id)
    }

    @Test("explicit no signature default is preserved")
    func explicitNoSignatureDefaultIsPreserved() throws {
        let defaults = try Self.makeDefaults()
        var settings = SignatureSettings.defaults
        _ = settings.addSignature(name: "Work", body: "Work sig", isEnabled: true)
        settings.setDefaultSignature(signatureID: nil, forAccountID: "acct-1")

        settings.save(to: defaults)
        let restored = SignatureSettings.load(from: defaults)

        #expect(restored.defaultSignatureID(forAccountID: "acct-1") == nil)
        #expect(restored.signature(forAccountID: "acct-1") == nil)
        #expect(restored.accountIDsWithNoDefaultSignature.contains("acct-1"))
    }

    @Test("choosing a signature clears explicit no signature default")
    func choosingSignatureClearsExplicitNoSignatureDefault() throws {
        var settings = SignatureSettings.defaults
        let signature = settings.addSignature(name: "Work", body: "Work sig", isEnabled: true)
        settings.setDefaultSignature(signatureID: nil, forAccountID: "acct-1")
        settings.setDefaultSignature(signatureID: signature.id, forAccountID: "acct-1")

        #expect(settings.defaultSignatureID(forAccountID: "acct-1") == signature.id)
        #expect(!settings.accountIDsWithNoDefaultSignature.contains("acct-1"))
    }

    @Test("removing a signature clears account defaults")
    func removingSignatureClearsAccountDefaults() throws {
        var settings = SignatureSettings.defaults
        let signature = settings.addSignature(name: "Work", body: "Sig 1", isEnabled: true)
        settings.setDefaultSignature(signatureID: signature.id, forAccountID: "acct-1")

        settings.removeSignature(id: signature.id)

        #expect(settings.signatures.isEmpty)
        #expect(settings.defaultSignatureIDsByAccountID["acct-1"] == nil)
    }

    @Test("signatures can be reordered without losing account defaults")
    func signaturesCanBeReorderedWithoutLosingAccountDefaults() throws {
        var settings = SignatureSettings.defaults
        let first = settings.addSignature(name: "First", body: "Sig 1", isEnabled: true)
        let second = settings.addSignature(name: "Second", body: "Sig 2", isEnabled: true)
        let third = settings.addSignature(name: "Third", body: "Sig 3", isEnabled: true)
        settings.setDefaultSignature(signatureID: second.id, forAccountID: "acct-1")

        settings.moveSignature(id: second.id, direction: .up)
        #expect(settings.signatures.map(\.id) == [second.id, first.id, third.id])
        #expect(settings.defaultSignatureID(forAccountID: "acct-1") == second.id)

        settings.moveSignature(id: second.id, direction: .down)
        settings.moveSignature(id: second.id, direction: .down)
        #expect(settings.signatures.map(\.id) == [first.id, third.id, second.id])
        #expect(settings.defaultSignatureID(forAccountID: "acct-1") == second.id)
    }

    @Test("moving first signature up or last signature down is a no-op")
    func movingAtEdgesIsNoOp() throws {
        var settings = SignatureSettings.defaults
        let first = settings.addSignature(name: "First", body: "Sig 1", isEnabled: true)
        let second = settings.addSignature(name: "Second", body: "Sig 2", isEnabled: true)

        settings.moveSignature(id: first.id, direction: .up)
        settings.moveSignature(id: second.id, direction: .down)

        #expect(settings.signatures.map(\.id) == [first.id, second.id])
    }

    @Test("enabling signature with empty body stays disabled")
    func enablingSignatureWithEmptyBodyStaysDisabled() throws {
        var settings = SignatureSettings.defaults
        let signature = settings.addSignature(name: "Blank", body: "  ", isEnabled: true)

        #expect(settings.signatures.first?.id == signature.id)
        #expect(settings.signatures.first?.isEnabled == false)
    }

    @Test("legacy persisted signature data migrates")
    func legacyPersistedSignatureDataMigrates() throws {
        let defaults = try Self.makeDefaults()
        let legacyJSON = #"""
        {
          "defaultSignature": {
            "body": "Default sig",
            "isEnabled": true
          },
          "accountSignatures": [
            {
              "id": "acct-1",
              "body": "Custom sig",
              "isEnabled": true
            }
          ]
        }
        """#
        defaults.set(Data(legacyJSON.utf8), forKey: SignatureSettings.storageKey)

        let settings = SignatureSettings.load(from: defaults)

        #expect(settings.signatures.count == 2)
        #expect(settings.signature(forAccountID: "acct-1")?.body == "Custom sig")
        #expect(settings.signature(forAccountID: "acct-2")?.body == "Default sig")
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "SignatureSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
