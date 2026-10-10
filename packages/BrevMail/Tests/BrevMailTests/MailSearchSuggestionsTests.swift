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
import Foundation
import Testing

@Suite("MailSearchSuggestions")
struct MailSearchSuggestionsTests {
    private func header(_ id: String, from name: String?, _ email: String, subject: String = "Hello") -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: name, email: email),
            to: [],
            subject: subject,
            snippet: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            isRead: false,
            hasAttachments: false
        )
    }

    private var headers: [MessageHeader] {
        [
            header("1", from: "Marte Solhaug", "marte@example.com", subject: "Budget"),
            header("2", from: "Marte Solhaug", "marte@example.com", subject: "Budget 2"),
            header("3", from: "Ola Nordmann", "ola@example.com"),
            header("4", from: nil, "billing@shop.example"),
        ]
    }

    @Test("an empty field offers recents, quick filters and the most frequent senders")
    func emptyFieldSuggestions() {
        let set = MailSearchSuggestions.make(
            typedText: "",
            tokens: [],
            headers: headers,
            recents: ["invoice", "flights"],
            offersFieldTokens: true
        )
        #expect(set.recents == ["invoice", "flights"])
        #expect(set.quickFilters == [.unread, .flagged, .hasAttachment])
        #expect(set.senders.first?.email == "marte@example.com")
        #expect(set.senders.count == 3)
        #expect(set.fieldTokens.isEmpty)
    }

    @Test("quick filters and senders that are already tokens are not offered again")
    func existingTokensAreNotRepeated() {
        let set = MailSearchSuggestions.make(
            typedText: "",
            tokens: [.unread, .sender(email: "marte@example.com", name: nil)],
            headers: headers,
            recents: [],
            offersFieldTokens: true
        )
        #expect(!set.quickFilters.contains(.unread))
        #expect(set.quickFilters.contains(.flagged))
        #expect(!set.senders.contains { $0.email == "marte@example.com" })
    }

    @Test("typed text matches senders by name or address without regard to case or accents")
    func typedTextMatchesSenders() {
        let byName = MailSearchSuggestions.make(
            typedText: "MARTE",
            tokens: [],
            headers: headers,
            recents: [],
            offersFieldTokens: true
        )
        #expect(byName.senders.map(\.email) == ["marte@example.com"])
        #expect(byName.quickFilters.isEmpty)

        let byAddress = MailSearchSuggestions.make(
            typedText: "shop.exam",
            tokens: [],
            headers: headers,
            recents: [],
            offersFieldTokens: true
        )
        #expect(byAddress.senders.map(\.email) == ["billing@shop.example"])
    }

    @Test("typed text offers the From and Subject field tokens once")
    func typedTextOffersFieldTokens() {
        let set = MailSearchSuggestions.make(
            typedText: "budget",
            tokens: [],
            headers: headers,
            recents: [],
            offersFieldTokens: true
        )
        #expect(set.fieldTokens == [.field(.from), .field(.subject)])

        let scoped = MailSearchSuggestions.make(
            typedText: "budget",
            tokens: [.field(.subject)],
            headers: headers,
            recents: [],
            offersFieldTokens: true
        )
        #expect(scoped.fieldTokens.isEmpty)

        let unavailable = MailSearchSuggestions.make(
            typedText: "budget",
            tokens: [],
            headers: headers,
            recents: [],
            offersFieldTokens: false
        )
        #expect(unavailable.fieldTokens.isEmpty)
    }

    @Test("recents matching the typed text are offered, newest first")
    func typedTextFiltersRecents() {
        let set = MailSearchSuggestions.make(
            typedText: "inv",
            tokens: [],
            headers: [],
            recents: ["flights", "Invoice 42", "invitation"],
            offersFieldTokens: false
        )
        #expect(set.recents == ["Invoice 42", "invitation"])
    }

    @Test("an empty set reports isEmpty so the results stay visible")
    func emptySetIsEmpty() {
        let set = MailSearchSuggestions.make(
            typedText: "zzz",
            tokens: [],
            headers: headers,
            recents: [],
            offersFieldTokens: false
        )
        #expect(set.isEmpty)
    }
}

@Suite("MailRecentSearches")
struct MailRecentSearchesTests {
    @Test("a new search goes first, duplicates move up and the list is capped")
    func addingKeepsNewestFirstAndCaps() {
        var list = ["b", "a"]
        list = MailRecentSearches.adding("A", to: list)
        #expect(list == ["A", "b"])
        for index in 0 ..< 20 {
            list = MailRecentSearches.adding("q\(index)", to: list)
        }
        #expect(list.count == MailRecentSearches.limit)
        #expect(list.first == "q19")
    }

    @Test("blank searches are not remembered")
    func blankIsIgnored() {
        #expect(MailRecentSearches.adding("   ", to: ["a"]) == ["a"])
    }

    @Test("the list persists in the given defaults and can be cleared")
    func persistence() throws {
        let suite = "MailRecentSearchesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MailRecentSearches.load(from: defaults).isEmpty)
        MailRecentSearches.save(["one", "two"], to: defaults)
        #expect(MailRecentSearches.load(from: defaults) == ["one", "two"])
        MailRecentSearches.save([], to: defaults)
        #expect(MailRecentSearches.load(from: defaults).isEmpty)
    }
}
