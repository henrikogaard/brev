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
        #expect(plan.chips.map(\.label) == ["Keyword: invoices", "Date: last month"])
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
        #expect(plan.chips.map(\.label) == [
            "Keyword: invoices",
            "From: alice@example.com",
        ])
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
        #expect(plan.chips.map(\.label) == ["Keyword: quarterly budget"])
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
