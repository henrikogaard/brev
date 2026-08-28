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

@testable import BrevBackend
import Foundation
import Testing

@Suite("ServerAlias model")
struct ServerAliasTests {
    @Test("alias fields round-trip through Codable")
    func aliasFieldsRoundTripThroughCodable() throws {
        let alias = ServerAlias(
            id: "alias-1",
            email: "work@example.com",
            displayName: "Work",
            isDefault: true
        )
        let data = try JSONEncoder().encode(alias)
        let decoded = try JSONDecoder().decode(ServerAlias.self, from: data)
        #expect(decoded == alias)
        #expect(decoded.isDefault == true)
    }

    @Test("alias without display name decodes correctly")
    func aliasWithoutDisplayName() throws {
        let alias = ServerAlias(id: "alias-2", email: "other@example.com")
        let data = try JSONEncoder().encode(alias)
        let decoded = try JSONDecoder().decode(ServerAlias.self, from: data)
        #expect(decoded.displayName == nil)
    }
}

@Suite("ServerSignature model")
struct ServerSignatureTests {
    @Test("signature fields round-trip through Codable")
    func signatureFieldsRoundTripThroughCodable() throws {
        let sig = ServerSignature(
            id: "sig-1",
            name: "Work Signature",
            body: "<p>Best regards</p>",
            isDefault: true
        )
        let data = try JSONEncoder().encode(sig)
        let decoded = try JSONDecoder().decode(ServerSignature.self, from: data)
        #expect(decoded == sig)
        #expect(decoded.body == "<p>Best regards</p>")
    }
}

@Suite("BackendExtendedCapabilities")
struct BackendExtendedCapabilitiesTests {
    @Test("serverAliases and serverSignatures are distinct bits")
    func serverAliasesAndSignaturesAreDistinctBits() {
        let caps: BackendExtendedCapabilities = [.serverAliases, .serverSignatures]
        #expect(caps.contains(.serverAliases))
        #expect(caps.contains(.serverSignatures))
        #expect(!caps.contains(.serverSignatureTemplates))
    }

    @Test("listAliases throws notSupported on backends without aliases capability")
    func listAliasesThrowsNotSupportedOnBasicBackend() async {
        let backend = MockBackend(capabilities: [.serverSideSearch])
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.listAliases()
        }
    }

    @Test("listServerSignatures throws notSupported on backends without capability")
    func listServerSignaturesThrowsNotSupported() async {
        let backend = MockBackend(capabilities: [.serverSideSearch])
        await #expect(throws: MailBackendError.self) {
            _ = try await backend.listServerSignatures()
        }
    }
}
