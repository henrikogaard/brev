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

@Suite("SecurityKeyMaterialStore")
struct SecurityKeyMaterialStoreTests {
    @Test("keychain store round-trips and deletes payloads")
    func keychainStoreRoundTripsAndDeletesPayloads() async throws {
        let store = SecurityKeychainMaterialStore(
            service: "SecurityKeyMaterialStoreTests-\(UUID().uuidString)"
        )
        let recordID = "record-1"
        let payload = Data("-----BEGIN TEST KEY-----".utf8)

        try await store.setMaterial(payload, for: recordID)
        let restored = try await store.material(for: recordID)
        #expect(restored == payload)

        try await store.deleteMaterial(for: recordID)
        let deleted = try await store.material(for: recordID)
        #expect(deleted == nil)
    }
}
