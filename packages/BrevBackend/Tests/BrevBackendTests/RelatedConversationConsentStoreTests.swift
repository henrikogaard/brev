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

@Suite("Related conversation consent store")
struct RelatedConversationConsentStoreTests {
    @Test("automatic lookup defaults off per account")
    func defaultsOffPerAccount() async throws {
        let defaults = try makeDefaults()
        let store = RelatedConversationConsentStore(defaults: defaults)

        #expect(await !store.isRelatedConversationConsented(accountID: "personal"))
        #expect(!store.isAutoLoadEnabled(accountID: "personal"))
    }

    @Test("persistent consent is per account and reversible")
    func persistentConsentIsPerAccountAndReversible() async throws {
        let defaults = try makeDefaults()
        let store = RelatedConversationConsentStore(defaults: defaults)

        store.setAutoLoadEnabled(true, accountID: "personal")

        #expect(await store.isRelatedConversationConsented(accountID: "personal"))
        #expect(await !store.isRelatedConversationConsented(accountID: "work"))
        #expect(RelatedConversationConsentStore(defaults: defaults)
            .isAutoLoadEnabled(accountID: "personal"))

        store.setAutoLoadEnabled(false, accountID: "personal")

        #expect(await !store.isRelatedConversationConsented(accountID: "personal"))
    }

    @Test("session consent authorizes without persisting and revocation clears both")
    func sessionConsentAndRevocation() async throws {
        let defaults = try makeDefaults()
        let store = RelatedConversationConsentStore(defaults: defaults)

        store.grantForSession(accountID: "personal")
        store.setAutoLoadEnabled(true, accountID: "work")

        #expect(await store.isRelatedConversationConsented(accountID: "personal"))
        #expect(!store.isAutoLoadEnabled(accountID: "personal"))

        store.revokeConsent(accountID: "personal")
        store.revokeConsent(accountID: "work")

        #expect(await !store.isRelatedConversationConsented(accountID: "personal"))
        #expect(await !store.isRelatedConversationConsented(accountID: "work"))
    }

    @Test("disabling automatic lookup drops an earlier session grant")
    func disablingAutoLoadClearsSessionGrant() async throws {
        let defaults = try makeDefaults()
        let store = RelatedConversationConsentStore(defaults: defaults)

        store.grantForSession(accountID: "personal")
        store.setAutoLoadEnabled(false, accountID: "personal")

        #expect(await !store.isRelatedConversationConsented(accountID: "personal"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "RelatedConversationConsentStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
