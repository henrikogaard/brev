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

@Suite("Message task payload")
struct MessageTaskPayloadTests {
    @Test("deep links round-trip through Brev message routing")
    func deepLinksRoundTripThroughBrevMessageRouting() throws {
        let header = makeHeader()
        let link = try #require(MessageTaskDeepLinkBuilder.url(
            for: header,
            accountID: "account-1"
        ))

        #expect(link.absoluteString.contains("brev://message?"))
        #expect(NotificationRoutingPolicy.route(from: link) == NotificationMailRoute(
            accountID: "account-1",
            folderID: "inbox",
            messageID: "message-1"
        ))
    }

    @Test("default task draft includes subject sender deep link and optional due date")
    func defaultTaskDraftIncludesMailContext() throws {
        let header = makeHeader()
        let dueDate = Date(timeIntervalSince1970: 1_780_222_400)
        let draft = try #require(MessageTaskDraftBuilder.draft(
            for: header,
            accountID: "account-1",
            dueDate: dueDate
        ))

        #expect(draft.title == "Review launch checklist")
        #expect(draft.notes.contains("From: Alex <alex@example.com>"))
        #expect(draft.notes.contains("Subject: Review launch checklist"))
        #expect(draft.notes.contains("Preview: Please review before Friday."))
        #expect(draft.notes.contains("Brev link: brev://message?"))
        #expect(draft.dueDate == dueDate)
        #expect(draft.target == .appleReminders)
        #expect(draft.isCreateEnabled)
    }

    @Test("blank subjects and edited drafts stay user editable before creation")
    func blankSubjectsAndEditedDraftsStayUserEditable() throws {
        let header = makeHeader(subject: "   ")
        var draft = try #require(MessageTaskDraftBuilder.draft(
            for: header,
            accountID: "account-1"
        ))

        #expect(draft.title == "Email from Alex")

        draft.title = "Follow up with Alex"
        draft.notes = "Edited notes"
        draft.dueDate = Date(timeIntervalSince1970: 1_780_308_800)

        #expect(draft.title == "Follow up with Alex")
        #expect(draft.notes == "Edited notes")
        #expect(draft.dueDate == Date(timeIntervalSince1970: 1_780_308_800))
        #expect(draft.isCreateEnabled)

        draft.title = " "
        #expect(!draft.isCreateEnabled)
    }

    @Test("creation targets are local or system handoff only")
    func creationTargetsAreLocalOrSystemOnly() {
        #expect(MessageTaskCreationTarget.allCases == [.appleReminders, .systemShare])
        #expect(!MessageTaskCreationTarget.allCases.map(\.rawValue).contains("todoist"))
        #expect(!MessageTaskCreationTarget.allCases.map(\.rawValue).contains("asana"))
    }

    private func makeHeader(
        subject: String = "Review launch checklist"
    ) -> MessageHeader {
        MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.com"),
            subject: subject,
            snippet: "Please review before Friday.",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: true
        )
    }
}
