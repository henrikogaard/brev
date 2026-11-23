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
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

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

        // Padded quoted sender chips remove cleanly.
        let padded = NaturalLanguageSearchPlanner.plan(for: #"from " Maya Patel " invoice"#, execution: .cacheOnly)
        #expect(padded.query.from == "Maya Patel")
        let paddedChip = try #require(padded.chips.first { $0.kind == .sender })
        #expect(NaturalLanguageSearchChipEditing.removing(paddedChip, from: padded.originalText) == "invoice")
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
