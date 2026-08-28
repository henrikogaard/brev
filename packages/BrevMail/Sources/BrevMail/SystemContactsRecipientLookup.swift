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

import BrevBackend
import Foundation

#if canImport(Contacts)
import Contacts

/// Caches the local Apple Contacts projection used by compose autocomplete.
actor SystemContactsRecipientLookup {
    static let shared = SystemContactsRecipientLookup()

    private let storeFactory: @Sendable () -> CNContactStore
    private let authorizationStatusProvider: @Sendable () -> CNAuthorizationStatus
    private var cachedContacts: [CachedContact] = []
    private var didLoadContacts = false
    private var lastAuthorizationStatus: CNAuthorizationStatus?
    private var contactsDidChangeObserver: NSObjectProtocol?

    init(
        storeFactory: @escaping @Sendable () -> CNContactStore = { CNContactStore() },
        authorizationStatusProvider: @escaping @Sendable () -> CNAuthorizationStatus = {
            CNContactStore.authorizationStatus(for: .contacts)
        }
    ) {
        self.storeFactory = storeFactory
        self.authorizationStatusProvider = authorizationStatusProvider
    }

    func contacts(matching query: ContactLookupQuery) async -> [ContactLookupResult] {
        installChangeObserverIfNeeded()
        let authorizationStatus = authorizationStatusProvider()
        if authorizationStatus != lastAuthorizationStatus {
            invalidateCache()
            lastAuthorizationStatus = authorizationStatus
        }
        guard ContactsAccessPolicy.isEnabled() else { return [] }
        // Permission requests belong to an explicit settings action. Asking
        // from this path would make ordinary typing trigger a system prompt.
        let canReadContacts: Bool
        #if os(iOS)
        if authorizationStatus == .authorized {
            canReadContacts = true
        } else if #available(iOS 18.0, *) {
            canReadContacts = authorizationStatus == .limited
        } else {
            canReadContacts = false
        }
        #else
        canReadContacts = authorizationStatus == .authorized
        #endif
        guard canReadContacts else { return [] }
        let store = storeFactory()
        if !didLoadContacts {
            cachedContacts = loadContacts(store: store)
            didLoadContacts = true
        }

        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return cachedContacts
            .filter { contact in
                (contact.displayName?.localizedCaseInsensitiveContains(needle) ?? false)
                    || contact.email.localizedCaseInsensitiveContains(needle)
            }
            .prefix(query.limit)
            .map { contact in
                ContactLookupResult(
                    id: "apple-contacts-\(contact.identifier)-\(contact.email.lowercased())",
                    displayName: contact.displayName,
                    email: contact.email,
                    sourceID: query.sourceID
                )
            }
    }

    private func installChangeObserverIfNeeded() {
        guard contactsDidChangeObserver == nil else { return }
        contactsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.invalidateCache() }
        }
    }

    private func invalidateCache() {
        cachedContacts = []
        didLoadContacts = false
    }

    private func loadContacts(store: CNContactStore) -> [CachedContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [CachedContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let displayName = [contact.givenName, contact.middleName, contact.familyName]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " ")
                for emailValue in contact.emailAddresses {
                    let email = String(emailValue.value)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard RecipientAddressValidator.isLikelyEmailAddress(email) else { continue }
                    contacts.append(
                        CachedContact(
                            identifier: contact.identifier,
                            displayName: displayName.isEmpty ? nil : displayName,
                            email: email
                        )
                    )
                }
            }
        } catch {
            return []
        }
        return contacts
    }

    private struct CachedContact: Sendable {
        let identifier: String
        let displayName: String?
        let email: String
    }
}
#else
/// Returns no results on platforms without the Apple Contacts framework.
actor SystemContactsRecipientLookup {
    static let shared = SystemContactsRecipientLookup()

    func contacts(matching _: ContactLookupQuery) async -> [ContactLookupResult] {
        []
    }
}
#endif
