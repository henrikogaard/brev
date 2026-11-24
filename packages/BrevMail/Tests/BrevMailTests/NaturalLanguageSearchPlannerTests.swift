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

@Suite("NaturalLanguageSearchPlanner")
struct NaturalLanguageSearchPlannerTests {
    @Test("folder phrases survive submission and can be removed without losing the keywords")
    func folderPhraseEditing() throws {
        for phrase in ["in Sent", "i Sendt"] {
            let text = "receipt \(phrase) unread"
            let plan = NaturalLanguageSearchPlanner.plan(for: text, execution: .cacheOnly)
            #expect(plan.query.text == "receipt")
            #expect(plan.query.isUnread == true)
            let chip = try #require(plan.chips.first { $0.value == phrase })
            #expect(NaturalLanguageSearchChipEditing.removing(chip, from: text) == "receipt unread")
            let submitted = MailSearchTokens.extract(from: text)
            #expect(submitted.remainingText == "receipt")
            let composed = MailSearchTokens.composedText(freeText: submitted.remainingText, tokens: submitted.tokens)
            #expect(NaturalLanguageSearchPlanner.plan(for: composed, execution: .cacheOnly).chips.contains(chip))
        }
        let literal = NaturalLanguageSearchPlanner.plan(for: "in sentiment analysis", execution: .cacheOnly)
        #expect(literal.query.text == "in sentiment analysis")
        #expect(literal.chips.isEmpty)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test("a folder chip filters mock results and removing it restores all folders")
    func folderChipFiltersMockResults() async throws {
        let sent = Folder(id: "outgoing", name: "Outgoing", role: .sent)
        func header(_ id: String, _ folder: String) -> MessageHeader {
            MessageHeader(id: id, threadID: id, folderID: folder, from: Correspondent(email: "a@example.test"),
                          subject: "receipt", snippet: "", date: .now)
        }
        let mock = MockBackend(messagesByFolder: ["outgoing": [header("a", "outgoing")], "inbox": [header("b", "inbox")]])
        let text = "receipt i sendt"
        let plan = NaturalLanguageSearchPlanner.plan(for: text, execution: .cacheOnly)
        let scoped = try #require(plan.resolvedQuery(in: [sent]))
        #expect(try await mock.search(scoped).map(\.id) == ["a"])
        let chip = try #require(plan.chips.first { $0.kind == .folder })
        let edited = NaturalLanguageSearchChipEditing.removing(chip, from: text)
        let all = try #require(NaturalLanguageSearchPlanner.plan(for: edited, execution: .cacheOnly).resolvedQuery(in: [sent]))
        #expect(try await Set(mock.search(all).map(\.id)) == ["a", "b"])
    }

    @Test("deterministic parser turns last month into a cache search date range")
    func deterministicParserTurnsLastMonthIntoDateRange() throws {
        let now = try date(year: 2026, month: 6, day: 5, hour: 12)

        let plan = NaturalLanguageSearchPlanner.plan(
            for: "invoices from last month",
            folderID: "inbox",
            execution: .cacheOnly,
            now: now,
            calendar: calendar
        )

        #expect(plan.query.text == "invoices")
        #expect(plan.query.folderID == "inbox")
        #expect(plan.query.execution == .cacheOnly)
        let range = try #require(plan.query.dateRange)
        let expectedStart = try date(year: 2026, month: 5, day: 1)
        let expectedEnd = try date(year: 2026, month: 6, day: 1).addingTimeInterval(-0.001)
        #expect(range.lowerBound == expectedStart)
        #expect(range.upperBound == expectedEnd)
        #expect(plan.chips.map(\.label) == ["Date: last month"])
        #expect(plan.requiresAI == false)
    }

    @Test("deterministic parser extracts sender unread and attachment predicates")
    func deterministicParserExtractsSenderUnreadAndAttachmentPredicates() throws {
        let plan = try NaturalLanguageSearchPlanner.plan(
            for: "unread from alice@example.com with attachments",
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(plan.query.text == "")
        #expect(plan.query.from == "alice@example.com")
        #expect(plan.query.isUnread == true)
        #expect(plan.query.hasAttachments == true)
        #expect(plan.chips.map(\.label) == [
            "From: alice@example.com",
            "Unread",
            "Has attachments",
        ])
    }

    @Test("deterministic parser accepts from-colon sender syntax")
    func deterministicParserAcceptsFromColonSenderSyntax() throws {
        let plan = try NaturalLanguageSearchPlanner.plan(
            for: "from: alice@example.com invoices",
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(plan.query.from == "alice@example.com")
        #expect(plan.query.text == "invoices")
        #expect(plan.chips.map(\.label) == ["From: alice@example.com"])
    }

    @Test("ordinary text falls closed to keyword cache search")
    func ordinaryTextFallsClosedToKeywordCacheSearch() throws {
        let plan = try NaturalLanguageSearchPlanner.plan(
            for: "quarterly budget",
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(plan.query == SearchQuery(text: "quarterly budget", execution: .cacheOnly))
        #expect(plan.chips.isEmpty)
        #expect(plan.requiresAI == false)
    }

    @Test("search scope applies on top of natural-language parsing")
    func searchScopeAppliesOnTopOfNaturalLanguageParsing() throws {
        let query = try MessageListSearchQueryPolicy.query(
            text: "alice@example.com last month",
            folderID: "inbox",
            execution: .cacheOnly,
            searchScope: .from,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(query.text == "")
        #expect(query.from == "alice@example.com")
        #expect(query.folderID == "inbox")
        let expectedStart = try date(year: 2026, month: 5, day: 1)
        #expect(query.dateRange?.lowerBound == expectedStart)
    }

    @Test("search scope plan exposes resolved editable chips")
    func searchScopePlanExposesResolvedEditableChips() throws {
        let plan = try MessageListSearchQueryPolicy.plan(
            text: "alice@example.com last month",
            folderID: "inbox",
            execution: .cacheOnly,
            searchScope: .from,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(plan.query.from == "alice@example.com")
        #expect(plan.query.text == "")
        #expect(plan.chips.map(\.label) == ["From: alice@example.com", "Date: last month"])
    }

    @Test("unified inbox search query uses deterministic planner for each source")
    func unifiedInboxSearchQueryUsesDeterministicPlannerForEachSource() throws {
        let query = try UnifiedInboxSearchPolicy.searchQuery(
            text: "unread invoices from last month",
            inboxFolderID: "inbox",
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        #expect(query.text == "invoices")
        #expect(query.folderID == "inbox")
        #expect(query.isUnread == true)
        let expectedStart = try date(year: 2026, month: 5, day: 1)
        #expect(query.dateRange?.lowerBound == expectedStart)
    }

    @Test("chip editing removes selected predicate text")
    func chipEditingRemovesSelectedPredicateText() throws {
        let plan = try NaturalLanguageSearchPlanner.plan(
            for: "unread invoices from alice@example.com with attachments last month",
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5),
            calendar: calendar
        )

        let senderChip = try #require(plan.chips.first { $0.kind == .sender })
        let unreadChip = try #require(plan.chips.first { $0.kind == .unread })
        let attachmentChip = try #require(plan.chips.first { $0.kind == .attachment })

        #expect(NaturalLanguageSearchChipEditing.removing(
            senderChip,
            from: plan.originalText
        ) == "unread invoices with attachments last month")
        #expect(NaturalLanguageSearchChipEditing.removing(
            unreadChip,
            from: plan.originalText
        ) == "invoices from alice@example.com with attachments last month")
        #expect(NaturalLanguageSearchChipEditing.removing(
            attachmentChip,
            from: plan.originalText
        ) == "unread invoices from alice@example.com last month")
    }

    @Test("sender, date and attachment chips filter mock messages and can be removed independently", arguments: [
        "offer from Maya with attachments last week",
        "offer fra Maya med vedlegg forrige uke"
    ])
    func editableBilingualQuery(text: String) async throws {
        let now = try date(year: 2026, month: 6, day: 15)
        let prior = try date(year: 2026, month: 6, day: 10)
        func plan(_ text: String) -> NaturalLanguageSearchPlan {
            NaturalLanguageSearchPlanner.plan(for: text, folderID: "inbox", execution: .cacheOnly,
                                              now: now, calendar: calendar)
        }
        func header(_ id: String, _ name: String, _ date: Date, attached: Bool = true) -> MessageHeader {
            MessageHeader(id: id, threadID: id, folderID: "inbox", from: .init(name: name, email: "\(id)@example.test"),
                          subject: "offer", snippet: "", date: date, hasAttachments: attached)
        }
        let headers = [header("match", "Maya", prior), header("other", "Ola", prior), header("late", "Maya", now),
                       header("no-file", "Maya", prior, attached: false)]
        let backend = MockBackend(messagesByFolder: ["inbox": headers])
        let parsed = plan(text)
        #expect(parsed.query.text == "offer")
        #expect(parsed.query.from?.lowercased() == "maya")
        #expect(parsed.query.hasAttachments == true)
        #expect(parsed.query.dateRange?.contains(prior) == true)
        #expect(try await backend.search(parsed.query).map(\.id) == ["match"])
        for (kind, newMatch) in [(NaturalLanguageSearchChip.Kind.sender, "other"), (.date, "late"), (.attachment, "no-file")] {
            let chip = try #require(parsed.chips.first { $0.kind == kind })
            let edited = plan(NaturalLanguageSearchChipEditing.removing(chip, from: text))
            #expect(try await Set(backend.search(edited.query).map(\.id)) == ["match", newMatch])
        }
        let input = MailSearchTokens.extract(from: text, now: now, calendar: calendar)
        #expect(plan(MailSearchTokens.composedText(freeText: input.remainingText, tokens: input.tokens)).query == parsed.query)
    }

    @Test("search field shows the Norwegian version of its example")
    func localizedPrompt() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let row = try #require(catalog["Search, like “from Maya last week”"] as? [String: Any])
        let nb = (row["localizations"] as? [String: Any])?["nb"] as? [String: Any]
        #expect((nb?["stringUnit"] as? [String: Any])?["value"] as? String == "Søk, for eksempel «fra Maya forrige uke»")
    }

    @Test("date prepositions do not become senders and chip removal preserves ordinary words")
    func datePrepositions() throws {
        let plan = NaturalLanguageSearchPlanner.plan(for: "fra forrige måned salg", execution: .cacheOnly)
        #expect(plan.query.from == nil)
        #expect(plan.query.text == "salg")
        let dateChip = try #require(plan.chips.first)
        #expect(NaturalLanguageSearchChipEditing.removing(dateChip, from: plan.originalText) == "salg")
    }

    @Test("multiword and quoted sender names parse cleanly without leaking surnames into keywords")
    func multiwordSenderNames() throws {
        let unquoted = NaturalLanguageSearchPlanner.plan(for: "from Maya Patel invoice", execution: .cacheOnly)
        #expect(unquoted.query.from == "Maya Patel")
        #expect(unquoted.query.text == "invoice")
        let unquotedChip = try #require(unquoted.chips.first { $0.kind == .sender })
        #expect(NaturalLanguageSearchChipEditing.removing(unquotedChip, from: unquoted.originalText) == "invoice")

        let quoted = NaturalLanguageSearchPlanner.plan(for: #"fra "maya patel" faktura"#, execution: .cacheOnly)
        #expect(quoted.query.from == "maya patel")
        #expect(quoted.query.text == "faktura")
        let quotedChip = try #require(quoted.chips.first { $0.kind == .sender })
        #expect(NaturalLanguageSearchChipEditing.removing(quotedChip, from: quoted.originalText) == "faktura")

        // Round-trip through MailSearchTokens (iOS submit path) preserves quotes on multiword names.
        let extracted = MailSearchTokens.extract(from: #"from "maya patel" invoice"#)
        let composed = MailSearchTokens.composedText(freeText: extracted.remainingText, tokens: extracted.tokens)
        let replanned = NaturalLanguageSearchPlanner.plan(for: composed, execution: .cacheOnly)
        #expect(replanned.query.from == "maya patel")
        #expect(replanned.query.text == "invoice")

        // Capitalized filter phrases are not swallowed by unquoted multiword sender names.
        let enFilter = NaturalLanguageSearchPlanner.plan(for: "from Maya Is Unread", execution: .cacheOnly)
        #expect(enFilter.query.from == "Maya")
        #expect(enFilter.query.isUnread == true)
        #expect(enFilter.query.text.isEmpty)

        let nbFilter = NaturalLanguageSearchPlanner.plan(for: "fra Maya Med Vedlegg", execution: .cacheOnly)
        #expect(nbFilter.query.from == "Maya")
        #expect(nbFilter.query.hasAttachments == true)
        #expect(nbFilter.query.text.isEmpty)

        // Date phrases inside quoted sender names stay part of the sender, not a date filter.
        let quotedDate = NaturalLanguageSearchPlanner.plan(for: #"from "USA TODAY" unread"#, execution: .cacheOnly)
        #expect(quotedDate.query.from == "USA TODAY")
        #expect(quotedDate.query.dateRange == nil)
        #expect(quotedDate.query.isUnread == true)

        // Removing a separate date chip preserves matching words inside a quoted sender name.
        let quotedSenderWithDate = try NaturalLanguageSearchPlanner.plan(
            for: #"from "USA TODAY" today"#,
            execution: .cacheOnly,
            now: date(year: 2026, month: 6, day: 5, hour: 12),
            calendar: calendar
        )
        #expect(quotedSenderWithDate.query.from == "USA TODAY")
        let dateChip = try #require(quotedSenderWithDate.chips.first { $0.kind == .date })
        #expect(
            NaturalLanguageSearchChipEditing.removing(dateChip, from: quotedSenderWithDate.originalText)
                == #"from "USA TODAY""#
        )

        // Padded quoted sender chips remove cleanly.
        let padded = NaturalLanguageSearchPlanner.plan(for: #"from " Maya Patel " invoice"#, execution: .cacheOnly)
        #expect(padded.query.from == "Maya Patel")
        let paddedChip = try #require(padded.chips.first { $0.kind == .sender })
        #expect(NaturalLanguageSearchChipEditing.removing(paddedChip, from: padded.originalText) == "invoice")
    }

    @Test("removing a folder chip skips quoted senders and tolerates extra spaces in the folder clause")
    func folderChipRemovalRespectsQuotedSenders() throws {
        let cases: [(query: String, expectedSender: String, expectedAfterRemoval: String)] = [
            (
                #"receipt from "News in Archive Weekly" in Sent"#,
                "News in Archive Weekly",
                #"receipt from "News in Archive Weekly""#
            ),
            (
                #"receipt from "News in Sent Weekly" in Sent"#,
                "News in Sent Weekly",
                #"receipt from "News in Sent Weekly""#
            ),
            (
                #"receipt from "News in Sent Weekly" in   Sent"#,
                "News in Sent Weekly",
                #"receipt from "News in Sent Weekly""#
            )
        ]
        for testCase in cases {
            let planned = NaturalLanguageSearchPlanner.plan(for: testCase.query, execution: .cacheOnly)
            #expect(planned.query.from == testCase.expectedSender)
            #expect(planned.folderPhrase?.role == .sent)
            let folderChip = try #require(planned.chips.first { $0.kind == .folder })
            let edited = NaturalLanguageSearchChipEditing.removing(folderChip, from: planned.originalText)
            #expect(edited == testCase.expectedAfterRemoval)
            let replanned = NaturalLanguageSearchPlanner.plan(for: edited, execution: .cacheOnly)
            #expect(replanned.query.from == testCase.expectedSender)
            #expect(replanned.folderPhrase == nil)
        }
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}
