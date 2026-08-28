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
@testable import BrevMail
import Testing

@Suite("ComposeRecipientAutocomplete")
struct ComposeRecipientAutocompleteTests {
    @Test("short queries do not trigger lookup")
    func shortQueriesDoNotTriggerLookup() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")

        #expect(ComposeRecipientAutocomplete.query(text: "a", sourceID: sourceID) == nil)
        #expect(ComposeRecipientAutocomplete.query(text: " ad ", sourceID: sourceID)?.text == "ad")
    }

    @Test("suggestions remove duplicates existing recipients and invalid emails")
    func suggestionsRemoveDuplicatesExistingRecipientsAndInvalidEmails() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let results = [
            ContactLookupResult(id: "1", displayName: "Ada Lovelace", email: "ada@example.org", sourceID: sourceID),
            ContactLookupResult(id: "2", displayName: "Ada Duplicate", email: "ADA@example.org", sourceID: sourceID),
            ContactLookupResult(id: "3", displayName: "Grace Hopper", email: "grace@example.org", sourceID: sourceID),
            ContactLookupResult(id: "4", displayName: "Broken", email: "not-an-email", sourceID: sourceID)
        ]

        let suggestions = ComposeRecipientAutocomplete.suggestions(
            from: results,
            existingRecipients: ["grace@example.org"]
        )

        #expect(suggestions.map(\.email) == ["ada@example.org"])
        #expect(suggestions.first?.title == "Ada Lovelace")
        #expect(suggestions.first?.subtitle == "ada@example.org")
    }

    @Test("suggestions fall back to email title when display name is missing")
    func suggestionsFallbackToEmailTitle() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let suggestions = ComposeRecipientAutocomplete.suggestions(
            from: [
                ContactLookupResult(id: "1", email: "solo@example.org", sourceID: sourceID)
            ],
            existingRecipients: []
        )

        #expect(suggestions.first?.title == "solo@example.org")
        #expect(suggestions.first?.subtitle == "Contact")
    }

    @Test("suggestions preserve source priority while removing duplicate addresses")
    func suggestionsPreserveSourcePriorityWhileRemovingDuplicateAddresses() {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let suggestions = ComposeRecipientAutocomplete.suggestions(
            from: [
                RecipientAutocompleteCandidate(
                    result: ContactLookupResult(
                        id: "apple-ada",
                        displayName: "Ada Lovelace",
                        email: "ada@example.org",
                        sourceID: sourceID
                    ),
                    source: .appleContacts
                ),
                RecipientAutocompleteCandidate(
                    result: ContactLookupResult(
                        id: "recent-ada",
                        displayName: "Ada Recent",
                        email: "ADA@example.org",
                        sourceID: sourceID
                    ),
                    source: .recentRecipients
                ),
                RecipientAutocompleteCandidate(
                    result: ContactLookupResult(
                        id: "recent-grace",
                        displayName: "Grace Hopper",
                        email: "grace@example.org",
                        sourceID: sourceID
                    ),
                    source: .recentRecipients
                )
            ],
            existingRecipients: []
        )

        #expect(suggestions.map(\.email) == ["ada@example.org", "grace@example.org"])
        #expect(suggestions.map(\.source) == [.appleContacts, .recentRecipients])
        #expect(suggestions.first?.sourceLabel == "Contacts")
        #expect(suggestions.last?.sourceLabel == "Recent")
    }

    @Test("provider lookup failures leave local candidates available")
    @MainActor
    func providerLookupFailuresLeaveLocalCandidatesAvailable() async {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let providerCandidates = await ComposeRecipientAutocomplete.providerCandidates {
            throw TestProviderError.unavailable
        }
        let suggestions = ComposeRecipientAutocomplete.suggestions(
            from: [
                RecipientAutocompleteCandidate(
                    result: ContactLookupResult(
                        id: "recent-grace",
                        displayName: "Grace Hopper",
                        email: "grace@example.org",
                        sourceID: sourceID
                    ),
                    source: .recentRecipients
                )
            ] + providerCandidates,
            existingRecipients: []
        )

        #expect(suggestions.map(\.email) == ["grace@example.org"])
    }

    private enum TestProviderError: Error {
        case unavailable
    }
}
