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

@Suite("MessageOpenReadPolicy")
struct MessageOpenReadPolicyTests {
    @Test("unread headers request a mark-read operation when opened")
    func unreadHeadersRequestMarkReadOperationWhenOpened() {
        let header = Self.makeHeader(id: "unread-1", isRead: false)

        #expect(MessageOpenReadPolicy.operation(for: header) == .markRead(messageID: "unread-1", folderID: "inbox"))
    }

    @Test("already read headers do not request backend work")
    func alreadyReadHeadersDoNotRequestBackendWork() {
        let header = Self.makeHeader(id: "read-1", isRead: true)

        #expect(MessageOpenReadPolicy.operation(for: header) == .none)
    }

    @Test("mark-read can start when no request is active")
    func markReadCanStartWhenNoRequestIsActive() {
        #expect(MessageOpenReadStartPolicy.canStartOpenRead(
            request: MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox"),
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("same mark-read request cannot start twice")
    func sameMarkReadRequestCannotStartTwice() {
        let request = MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox")

        #expect(!MessageOpenReadStartPolicy.canStartOpenRead(
            request: request,
            activeRequest: request,
            isBlocked: false
        ))
    }

    @Test("mark-read cannot start while root work is active")
    func markReadCannotStartWhileRootWorkIsActive() {
        #expect(!MessageOpenReadStartPolicy.canStartOpenRead(
            request: MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox"),
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("changed mark-read request can supersede active work")
    func changedMarkReadRequestCanSupersedeActiveWork() {
        let activeRequest = MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox")

        #expect(MessageOpenReadStartPolicy.canStartOpenRead(
            request: MessageOpenReadRequest(messageID: "unread-2", folderID: "inbox"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
        #expect(MessageOpenReadStartPolicy.canStartOpenRead(
            request: MessageOpenReadRequest(messageID: "unread-1", folderID: "archive"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
    }

    @Test("matching active message can apply mark-read response")
    func matchingActiveMessageCanApplyMarkReadResponse() {
        #expect(MessageOpenReadResponsePolicy.canApplyResponse(
            request: MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox"),
            activeRequest: MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox"),
            currentMessageID: "unread-1"
        ))
    }

    @Test("message or request changes reject stale mark-read response")
    func messageOrRequestChangesRejectStaleMarkReadResponse() {
        let request = MessageOpenReadRequest(messageID: "unread-1", folderID: "inbox")

        #expect(!MessageOpenReadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MessageOpenReadRequest(messageID: "unread-2", folderID: "inbox"),
            currentMessageID: "unread-1"
        ))
        #expect(!MessageOpenReadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MessageOpenReadRequest(messageID: "unread-1", folderID: "archive"),
            currentMessageID: "unread-1"
        ))
        #expect(!MessageOpenReadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: "unread-2"
        ))
        #expect(!MessageOpenReadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: nil
        ))
    }

    private static func makeHeader(id: MessageHeader.ID, isRead: Bool) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead
        )
    }
}
