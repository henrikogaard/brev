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

@Suite("MailSearchTokens")
struct MailSearchTokensTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test("predicate tokens compose into the phrases the natural-language planner understands")
    func tokensComposeIntoPlannerPhrases() {
        let text = MailSearchTokens.composedText(
            freeText: "invoices",
            tokens: [.unread, .hasAttachment, .sender(email: "marte@example.com", name: "Marte"), .date(.lastWeek)]
        )
        let plan = NaturalLanguageSearchPlanner.plan(for: text, execution: .cacheOnly, calendar: calendar)

        #expect(plan.query.text == "invoices")
        #expect(plan.query.isUnread == true)
        #expect(plan.query.hasAttachments == true)
        #expect(plan.query.from == "marte@example.com")
        #expect(plan.query.dateRange != nil)
    }

    @Test("a token-only search is still a search")
    func tokenOnlySearchIsActive() {
        #expect(MailSearchTokens.composedText(freeText: "", tokens: [.flagged]) == "flagged")
        #expect(MailSearchTokens.composedText(freeText: "  ", tokens: []).isEmpty)
    }

    @Test("a field token scopes the typed text and adds no phrase")
    func fieldTokenScopesTypedText() {
        let tokens: [MailSearchToken] = [.field(.subject), .unread]
        #expect(MailSearchTokens.composedText(freeText: "budget", tokens: tokens) == "unread budget")
        #expect(MailSearchTokens.searchScope(for: tokens) == .subject)
        #expect(MailSearchTokens.searchScope(for: [.field(.from)]) == .from)
        #expect(MailSearchTokens.searchScope(for: [.unread]) == .all)

        let query = MessageListSearchQueryPolicy.query(
            text: MailSearchTokens.composedText(freeText: "budget", tokens: tokens),
            folderID: "inbox",
            execution: .cacheOnly,
            searchScope: MailSearchTokens.searchScope(for: tokens)
        )
        #expect(query.subject == "budget")
        #expect(query.text.isEmpty)
        #expect(query.isUnread == true)
    }

    @Test("only one field token can be active and duplicates are ignored")
    func onlyOneFieldTokenIsActive() {
        var tokens: [MailSearchToken] = [.field(.from), .unread]
        MailSearchTokens.add(.field(.subject), to: &tokens)
        #expect(tokens == [.unread, .field(.subject)])
        MailSearchTokens.add(.unread, to: &tokens)
        #expect(tokens == [.unread, .field(.subject)])
    }

    @Test("submitting turns typed predicates into tokens and keeps the keywords")
    func extractionTurnsPredicatesIntoTokens() {
        let extraction = MailSearchTokens.extract(
            from: "unread invoices from marte@example.com last week with attachments",
            calendar: calendar
        )
        #expect(extraction.remainingText == "invoices")
        #expect(extraction.tokens.contains(.unread))
        #expect(extraction.tokens.contains(.hasAttachment))
        #expect(extraction.tokens.contains(.date(.lastWeek)))
        #expect(extraction.tokens.contains(.sender(email: "marte@example.com", name: nil)))
        #expect(!extraction.tokens.contains(.flagged))
    }

    @Test("plain keywords are not turned into tokens")
    func plainKeywordsStayText() {
        let extraction = MailSearchTokens.extract(from: "quarterly budget", calendar: calendar)
        #expect(extraction.tokens.isEmpty)
        #expect(extraction.remainingText == "quarterly budget")
    }

    @Test("token titles are unique per token and name their predicate")
    func tokenTitles() {
        #expect(MailSearchToken.unread.title == "Unread")
        #expect(MailSearchToken.flagged.title == "Flagged")
        #expect(MailSearchToken.hasAttachment.title == "Has attachments")
        #expect(MailSearchToken.sender(email: "a@b.no", name: "Ada").title == "From: Ada")
        #expect(MailSearchToken.sender(email: "a@b.no", name: nil).title == "From: a@b.no")
        #expect(MailSearchToken.date(.thisMonth).title == "This month")
        let all: [MailSearchToken] = [.unread, .flagged, .hasAttachment, .field(.from), .field(.subject), .date(.today)]
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test("every date token round-trips through the planner phrase")
    func datePresetsRoundTrip() {
        for preset in MailSearchDatePreset.allCases {
            #expect(MailSearchDatePreset(phrase: preset.phrase) == preset)
            let plan = NaturalLanguageSearchPlanner.plan(for: preset.phrase, execution: .cacheOnly, calendar: calendar)
            #expect(plan.query.dateRange != nil)
        }
    }
}

@Suite("Mailbox search scope")
struct MailSearchMailboxScopeTests {
    @Test("current mailbox keeps the folder, all mailboxes drops it")
    func scopeMapsToQueryFolder() {
        let current = MessageListSearchPlanPolicy.plan(
            text: "invoice",
            sourceID: nil,
            selectedFolderID: "inbox",
            execution: .cacheOnly,
            searchAllFolders: MailSearchMailboxScope.currentMailbox.searchesAllFolders,
            searchScope: .all
        )
        #expect(current.query.folderID == "inbox")

        let all = MessageListSearchPlanPolicy.plan(
            text: "invoice",
            sourceID: nil,
            selectedFolderID: "inbox",
            execution: .cacheOnly,
            searchAllFolders: MailSearchMailboxScope.allMailboxes.searchesAllFolders,
            searchScope: .all
        )
        #expect(all.query.folderID == nil)
        #expect(all.request != current.request)
    }

    @Test("the scope round-trips through the navigation flag")
    func scopeRoundTrips() {
        #expect(MailSearchMailboxScope(searchesAllFolders: true) == .allMailboxes)
        #expect(MailSearchMailboxScope(searchesAllFolders: false) == .currentMailbox)
    }
}
