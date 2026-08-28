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

import BrevAvatars
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

#if canImport(Contacts)
import Contacts
#endif

@Suite("ContactsAccessPolicy", .serialized)
struct ContactsAccessPolicyTests {
    @Test("the demo mailbox keeps Contacts off so no permission prompt fires")
    func demoMailboxKeepsContactsOff() throws {
        let defaults = try Self.makeDefaults()

        let isEnabled = ContactsAccessPolicy.isEnabled(
            environment: ["BREV_USE_MOCK": "1"],
            defaults: defaults
        )

        #if DEBUG
        #expect(isEnabled == false)
        #else
        // Release builds have no demo mode to opt into.
        #expect(isEnabled == true)
        #endif
    }

    @Test("a real mailbox leaves Contacts available")
    func realMailboxLeavesContactsAvailable() throws {
        let defaults = try Self.makeDefaults()

        let isEnabled = ContactsAccessPolicy.isEnabled(
            environment: [:],
            defaults: defaults
        )

        #expect(isEnabled == true)
    }

    /// ADR-0055: the avatar resolver starts from `AvatarPreferences.default`
    /// and receives preferences asynchronously, so a gate that has to be
    /// applied races the first screenful of avatar resolutions. This one is
    /// read at the permission check instead.
    @Test("applying the policy reaches avatar resolution's permission gate")
    func applyingPolicyReachesAvatarPermissionGate() {
        let original = AvatarPermissionPolicy.allowsSystemContactsAccess
        defer { AvatarPermissionPolicy.allowsSystemContactsAccess = original }

        AvatarPermissionPolicy.allowsSystemContactsAccess = !ContactsAccessPolicy.isEnabled()
        ContactsAccessPolicy.applyProcessWidePolicy()

        #expect(AvatarPermissionPolicy.allowsSystemContactsAccess == ContactsAccessPolicy.isEnabled())
    }

    @Test("entering the demo mailbox disables Contacts after a normal app launch")
    func enteringDemoMailboxDisablesContactsAfterNormalLaunch() throws {
        let defaults = try Self.makeDefaults()
        let original = AvatarPermissionPolicy.allowsSystemContactsAccess
        defer {
            ContactsAccessPolicy.applyProcessWidePolicy(environment: [:], defaults: defaults)
            AvatarPermissionPolicy.allowsSystemContactsAccess = original
        }

        ContactsAccessPolicy.applyProcessWidePolicy(environment: [:], defaults: defaults)
        #expect(ContactsAccessPolicy.isEnabled(environment: [:], defaults: defaults))

        ContactsAccessPolicy.disableForDemoMailbox()

        #expect(!ContactsAccessPolicy.isEnabled(environment: [:], defaults: defaults))
        #expect(!AvatarPermissionPolicy.allowsSystemContactsAccess)
    }

    #if canImport(Contacts)
    @Test("autocomplete does not request Contacts access while authorization is undecided")
    func autocompleteDoesNotRequestContactsAccessWhileAuthorizationIsUndecided() async {
        let defaults = UserDefaults.standard
        let recorder = ContactStoreFactoryRecorder()
        defer {
            ContactsAccessPolicy.applyProcessWidePolicy(environment: [:], defaults: defaults)
        }
        ContactsAccessPolicy.disableForDemoMailbox()
        let lookup = SystemContactsRecipientLookup(
            storeFactory: { recorder.makeStore() },
            authorizationStatusProvider: { .notDetermined }
        )

        let results = await lookup.contacts(
            matching: ContactLookupQuery(
                text: "alex",
                sourceID: MailSourceID(accountID: "demo", mailboxID: "demo")
            )
        )

        #expect(results.isEmpty)
        #expect(recorder.callCount == 0)
    }
    #endif

    @Test("leaving the demo mailbox restores the normal launch policy")
    func leavingDemoMailboxRestoresNormalLaunchPolicy() throws {
        let defaults = try Self.makeDefaults()
        let original = AvatarPermissionPolicy.allowsSystemContactsAccess
        defer {
            ContactsAccessPolicy.applyProcessWidePolicy(environment: [:], defaults: defaults)
            AvatarPermissionPolicy.allowsSystemContactsAccess = original
        }

        ContactsAccessPolicy.disableForDemoMailbox()
        ContactsAccessPolicy.applyProcessWidePolicy(environment: [:], defaults: defaults)

        #expect(ContactsAccessPolicy.isEnabled(environment: [:], defaults: defaults))
        #expect(AvatarPermissionPolicy.allowsSystemContactsAccess)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "ContactsAccessPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

#if canImport(Contacts)
private final class ContactStoreFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func makeStore() -> CNContactStore {
        lock.withLock { calls += 1 }
        return CNContactStore()
    }
}
#endif
