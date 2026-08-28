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

@Suite("CalendarInviteResponsePresentation")
struct CalendarInviteResponsePresentationTests {
    @Test("local response displays its exact label and hides actions")
    func localResponseDisplaysExactLabelAndHidesActions() {
        let presentation = CalendarInviteResponsePresentation.resolve(
            header: Self.makeHeader(isAnswered: false),
            localResponse: CalendarInviteLocalResponse(messageID: "m1", response: .tentative)
        )

        #expect(presentation?.label == "Tentative")
        #expect(presentation?.showsActions == false)
    }

    @Test("local responses for another message do not affect this header")
    func localResponseForAnotherMessageDoesNotAffectThisHeader() {
        let presentation = CalendarInviteResponsePresentation.resolve(
            header: Self.makeHeader(isAnswered: false),
            localResponse: CalendarInviteLocalResponse(messageID: "other", response: .declined)
        )

        #expect(presentation?.label == nil)
        #expect(presentation?.showsActions == true)
    }

    @Test("answered headers display responded and hide actions")
    func answeredHeadersDisplayRespondedAndHideActions() {
        let presentation = CalendarInviteResponsePresentation.resolve(
            header: Self.makeHeader(isAnswered: true),
            localResponse: nil
        )

        #expect(presentation?.label == "Responded")
        #expect(presentation?.showsActions == false)
    }

    @Test("unanswered headers show actions with no label")
    func unansweredHeadersShowActionsWithNoLabel() {
        let presentation = CalendarInviteResponsePresentation.resolve(
            header: Self.makeHeader(isAnswered: false),
            localResponse: nil
        )

        #expect(presentation?.label == nil)
        #expect(presentation?.showsActions == true)
    }

    @Test("response confirmations use action-specific copy")
    func responseConfirmationsUseActionSpecificCopy() {
        #expect(CalendarInviteResponsePresentation.confirmationMessage(for: .accepted) == "Invite accepted.")
        #expect(CalendarInviteResponsePresentation.confirmationMessage(for: .tentative) == "Tentative response sent.")
        #expect(CalendarInviteResponsePresentation.confirmationMessage(for: .declined) == "Invite declined.")
        #expect(CalendarInviteResponsePresentation.confirmationMessage(for: .needsAction) == "Invite response updated.")
    }

    @Test("client-side invite sends surface Sent copy warnings")
    func clientSideInviteSendsSurfaceSentCopyWarnings() {
        let status = CalendarInviteResponsePresentation.confirmationStatus(
            for: .accepted,
            sendResult: SendResult(
                sentMessageID: "sent",
                warnings: [.sentCopyAppendFailed]
            )
        )

        #expect(status.message == "Invite accepted, but Brev couldn't save a copy to Sent.")
        #expect(status.tone == .warning)
    }

    @Test("matching active message and response can apply an invite response")
    func matchingActiveMessageAndResponseCanApplyInviteResponse() {
        #expect(CalendarInviteResponsePolicy.canApplyResponse(
            request: CalendarInviteResponseRequest(messageID: "m1", response: .accepted),
            activeRequest: CalendarInviteResponseRequest(messageID: "m1", response: .accepted),
            currentMessageID: "m1"
        ))
    }

    @Test("invite response can start when no response is active")
    func inviteResponseCanStartWhenNoResponseIsActive() {
        #expect(CalendarInviteResponseStartPolicy.canStartResponse(
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("invite response cannot start while another response is active")
    func inviteResponseCannotStartWhileAnotherResponseIsActive() {
        #expect(!CalendarInviteResponseStartPolicy.canStartResponse(
            activeRequest: CalendarInviteResponseRequest(messageID: "m1", response: .accepted),
            isBlocked: false
        ))
    }

    @Test("invite response cannot start while root work is active")
    func inviteResponseCannotStartWhileRootWorkIsActive() {
        #expect(!CalendarInviteResponseStartPolicy.canStartResponse(
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("message response or request changes reject stale invite responses")
    func messageResponseOrRequestChangesRejectStaleInviteResponses() {
        let request = CalendarInviteResponseRequest(messageID: "m1", response: .accepted)

        #expect(!CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: CalendarInviteResponseRequest(messageID: "m2", response: .accepted),
            currentMessageID: "m1"
        ))
        #expect(!CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: CalendarInviteResponseRequest(messageID: "m1", response: .declined),
            currentMessageID: "m1"
        ))
        #expect(!CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: "m2"
        ))
        #expect(!CalendarInviteResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: nil
        ))
    }

    private static func makeHeader(isAnswered: Bool) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            subject: "Friday standup",
            snippet: "Calendar invite attached.",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            isAnswered: isAnswered,
            hasAttachments: true
        )
    }
}
