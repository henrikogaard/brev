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
@testable import BrevSettings
import Foundation
import Testing

@Suite("Smart View conditions")
struct SmartViewConditionTests {
    let work = MailSourceID(accountID: "account", mailboxID: "work")
    let personal = MailSourceID(accountID: "account", mailboxID: "personal")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var header: MessageHeader {
        MessageHeader(id: "message", threadID: "thread", folderID: "inbox",
                      from: .init(name: "Kári", email: "kari@example.com"),
                      cc: [.init(email: "team@example.com")], subject: "Kitchen plans",
                      snippet: "Island depth", date: now.addingTimeInterval(-86400),
                      isRead: true, isFlagged: false, isAnswered: true, hasAttachments: true)
    }

    @Test("any and all groups apply negative and positive conditions")
    func matchGroups() {
        var query = SmartMailbox.SavedQuery(text: "", conditions: [
            .init(field: .from, comparison: .beginsWith, value: "KARI"),
            .init(field: .subject, value: "invoice")
        ], matchMode: .any)
        #expect(query.matches(header))
        query.matchMode = .all
        #expect(!query.matches(header))
        query.conditions?[1] = .init(field: .subject, comparison: .doesNotContain, value: "invoice")
        #expect(query.matches(header))
        #expect(SmartViewCondition(field: .recipients, comparison: .endsWith, value: "example.com").matches(header))
        #expect(!SmartViewCondition(field: .recipients, comparison: .doesNotContain, value: "team").matches(header))
    }

    @Test("mailbox and folder conditions distinguish identical folder IDs")
    func scopedFolders() {
        let condition = SmartViewCondition(field: .folder, comparison: .equals, value: "inbox", sourceID: work)
        #expect(condition.matches(header, sourceID: work))
        #expect(!condition.matches(header, sourceID: personal))
        #expect(!condition.matches(header))
    }

    @Test("date and status conditions use cached fields and calendar days")
    func datesAndFlags() {
        #expect(SmartViewCondition(field: .received, comparison: .inLastDays, value: "2").matches(header, now: now))
        #expect(!SmartViewCondition(field: .received, comparison: .before, date: now.addingTimeInterval(-172_800))
            .matches(header))
        #expect(SmartViewCondition(field: .isRead, comparison: .isTrue).matches(header))
        #expect(SmartViewCondition(field: .isFlagged, comparison: .isFalse).matches(header))
        #expect(SmartViewCondition(field: .isAnswered, comparison: .isTrue).matches(header))
        #expect(SmartViewCondition(field: .hasAttachments, comparison: .isTrue).matches(header))
    }

    @Test("scope exclusions apply outside any-condition groups")
    func excludedRoles() {
        let query = SmartMailbox.SavedQuery(text: "", conditions: [.init(field: .isRead, comparison: .isTrue)],
                                            matchMode: .any, includeTrash: false, includeSent: false)
        #expect(!query.matches(header, folderRole: .trash))
        #expect(!query.matches(header, folderRole: .sent))
        #expect(query.matches(header, folderRole: .inbox))
    }

    @Test("legacy filters and condition groups survive encoding")
    func persistence() throws {
        let legacy = SmartMailbox.SavedQuery(text: "plans", isUnread: false, isStarred: false, folderID: "inbox")
        let converted = SmartMailbox.SavedQuery(text: "", conditions: legacy.editableConditions, matchMode: .all)
        #expect(converted.matches(header) == legacy.searchQuery.matches(header))
        #expect(converted.editableConditions.contains { $0.field == .isFlagged && $0.comparison == .isFalse })
        let decoded = try JSONDecoder().decode(SmartMailbox.SavedQuery.self, from: JSONEncoder().encode(converted))
        #expect(decoded == converted)
        #expect(decoded.matches(header))
    }

    @Test("incomplete and empty groups never match everything by accident")
    func invalidConditions() {
        #expect(!SmartMailbox.SavedQuery(text: "", conditions: [], matchMode: .all).matches(header))
        #expect(!SmartViewCondition(field: .from, value: " ").matches(header))
        #expect(!SmartViewCondition(field: .received, comparison: .inLastDays, value: "0").isValid)
    }
}
